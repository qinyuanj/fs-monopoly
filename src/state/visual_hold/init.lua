local runtime_state = require("src.state.runtime")
local deferred_dirty = require("src.state.visual_hold.deferred_dirty")
local release_scheduler = require("src.state.visual_hold.release_scheduler")
local event_log = require("src.state.event_log")
local dirty_tracker = require("src.state.dirty_tracker")
local Scope = require("src.foundation.scope")

local landing_visual_hold = {}

local post_release_hook = nil

local function _ensure_hold(state)
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  local hold = turn_runtime.landing_visual_hold
  if type(hold) ~= "table" then
    hold = {
      active = false,
      release_pending = false,
      flushing = false,
      frozen_ui_model = nil,
      deferred_dirty = deferred_dirty.new_bucket(),
      release_callbacks = {},
    }
    turn_runtime.landing_visual_hold = hold
  end
  release_scheduler.ensure_buffers(hold)
  return hold
end

local _mark_turn_dirty = dirty_tracker.mark_turn

local function _ensure_event_log_for_game(game)
  if type(game) ~= "table" then
    return nil
  end
  game.state = game.state or {}
  game.state.event_log = game.state.event_log or event_log.new()
  return game.state.event_log
end

local function _reset_deferred_buffers(hold)
  deferred_dirty.reset(hold)
  release_scheduler.reset(hold)
end

-- hold 激活期间累积的资源(release_callbacks、deferred_dirty bucket、
-- frozen_ui_model、event_log buffer)注册进 Scope;release/reset_state/
-- clear_game 统一经 _destroy_hold_scope 销毁,destroy 幂等保证清理恰好一次。
-- release 与 clear_game 的待决回放路径在销毁前先 replay(replay 内 flush
-- buffer),故此处的 pop_buffer 只对无回放的路径实际生效,既有差异保持不变。
local function _ensure_active_scope(hold)
  if hold.scope ~= nil then
    return hold.scope
  end
  local scope = Scope.new()
  hold.scope = scope
  scope:defer(function()
    hold.frozen_ui_model = nil
  end)
  scope:defer(function()
    _reset_deferred_buffers(hold)
  end)
  scope:defer(function()
    event_log.pop_buffer(hold)
  end)
  return scope
end

local function _destroy_hold_scope(hold)
  local scope = hold.scope
  hold.scope = nil
  if scope ~= nil then
    scope:destroy()
  end
end

local function _game_turn(game)
  return game and game.turn or nil
end

local function _game_turn_bool(field)
  return function(game)
    local turn = _game_turn(game)
    return turn and turn[field] == true or false
  end
end

local _game_turn_active = _game_turn_bool("landing_visual_hold_active")
local _game_turn_release_pending = _game_turn_bool("landing_visual_release_pending")

local function _project_hold_to_game(game, hold)
  local turn = _game_turn(game)
  if turn == nil then
    return
  end
  turn.landing_visual_hold_active = hold.active == true
  turn.landing_visual_release_pending = hold.release_pending == true
end

local function _hold_is_state_source(hold)
  return hold.source == "state"
end

local function _set_hold_state(state, active, release_pending, source)
  runtime_state.set_landing_visual_hold_active(state, active)
  runtime_state.set_landing_visual_release_pending(state, release_pending)
  runtime_state.set_landing_visual_hold_source(state, source)
  local hold = _ensure_hold(state)
  if active == true then
    _ensure_active_scope(hold)
  end
  return hold
end

-- Re-entrant start on an already-active hold: refresh the flags, but only log a
-- buffer event if the hold was not already marked active.
local function _refresh_active_hold(game, state)
  if type(state) ~= "table" then
    return
  end
  local hold = _ensure_hold(state)
  local was_active = hold.active == true
  hold = _set_hold_state(state, true, false, "state")
  _project_hold_to_game(game, hold)
  if was_active ~= true then
    _ensure_event_log_for_game(game)
    event_log.push_buffer(game.state.event_log, hold)
  end
end

local function _begin_hold(game, state)
  if type(state) == "table" then
    local hold = _set_hold_state(state, true, false, "state")
    _project_hold_to_game(game, hold)
    _ensure_event_log_for_game(game)
    event_log.push_buffer(game.state.event_log, hold)
  else
    game.turn.landing_visual_hold_active = true
    game.turn.landing_visual_release_pending = false
  end
end

function landing_visual_hold.start(game, opts)
  local _ = opts
  if not (game and game.turn) then
    return false
  end
  local state = game.landing_visual_hold_state
  if landing_visual_hold.is_active_game(game) == true then
    _refresh_active_hold(game, state)
    return false
  end
  _begin_hold(game, state)
  _mark_turn_dirty(game)
  return true
end

-- 行为测试公共接缝：test_phase_transitions 在落地等待场景建立 hold，观察回合恢复。
landing_visual_hold.hold_state_for_game = landing_visual_hold.start

local function _hold_field_or_game_fallback(game, field, fallback)
  local state = game and game.landing_visual_hold_state or nil
  if type(state) == "table" then
    local hold = _ensure_hold(state)
    if _hold_is_state_source(hold) then
      return hold[field] == true
    end
  end
  return fallback(game)
end

function landing_visual_hold.is_active_game(game)
  return _hold_field_or_game_fallback(game, "active", _game_turn_active)
end

function landing_visual_hold.is_release_pending_game(game)
  return _hold_field_or_game_fallback(game, "release_pending", _game_turn_release_pending)
end

function landing_visual_hold.mark_release_pending(game)
  if not (game and game.turn) then
    return false
  end
  if landing_visual_hold.is_active_game(game) ~= true then
    return false
  end
  local state = game.landing_visual_hold_state
  if type(state) == "table" then
    local hold = _set_hold_state(state, true, true, "state")
    _project_hold_to_game(game, hold)
  else
    game.turn.landing_visual_release_pending = true
  end
  _mark_turn_dirty(game)
  return true
end

local function _hold_changed(game)
  return landing_visual_hold.is_active_game(game) == true
    or landing_visual_hold.is_release_pending_game(game) == true
end

local function _merge_deferred_dirty(game, hold)
  if game and game.dirty then
    deferred_dirty.merge_into(game.dirty, hold.deferred_dirty)
  end
end

local function _run_post_release_hook()
  if type(post_release_hook) == "function" then
    post_release_hook()
  end
end

-- 待决释放的统一收尾:回放 deferred 回调(merge dirty → flush 内 replay)、
-- 销毁 hold scope、跑 post_release hook、标 ui dirty。release 与 clear_game
-- 的待决分支共用,保证两条路径的收尾语义一致(#440)。
local function _flush_pending_release(game, state, hold)
  _merge_deferred_dirty(game, hold)
  landing_visual_hold.with_flushing(state, function()
    release_scheduler.replay(hold)
  end)
  _destroy_hold_scope(hold)
  _run_post_release_hook()
  runtime_state.set_ui_dirty(state, true)
end

-- hold 已存在时的清除(CRAP 门禁 #452):release_pending 两段握手走
-- _flush_pending_release 回放(#440),否则直接销毁 scope,再投影回 game。
local function _clear_hold_state(game, state)
  local hold = _ensure_hold(state)
  local replay_pending = hold.release_pending == true
  _set_hold_state(state, false, false, "state")
  if replay_pending then
    _flush_pending_release(game, state, hold)
  else
    _destroy_hold_scope(hold)
  end
  _project_hold_to_game(game, hold)
end

-- state 缺失(旧态残留)时的兜底:直接清 turn 侧两枚标志。
local function _clear_turn_flags(game)
  game.turn.landing_visual_hold_active = false
  game.turn.landing_visual_release_pending = false
end

-- release_pending 已置位时,defer 的回调属于两段握手已确认的释放:走
-- _flush_pending_release 回放,不得静默丢弃(#440)。teardown 一律走
-- _destroy_hold_scope,堵住 #419 引入的跨回合 scope/回调泄漏。
function landing_visual_hold.clear_game(game)
  if not (game and game.turn) then
    return false
  end
  local changed = _hold_changed(game)
  local state = game.landing_visual_hold_state
  if type(state) == "table" then
    _clear_hold_state(game, state)
  else
    _clear_turn_flags(game)
  end
  if changed then
    _mark_turn_dirty(game)
  end
  return changed
end

landing_visual_hold.is_active_state = runtime_state.get_landing_visual_hold_active

function landing_visual_hold.is_flushing_state(state)
  local hold = _ensure_hold(state)
  return hold.flushing == true
end

-- hold 从非激活转激活时补一条 buffer 事件。
local function _push_activation_buffer(game, hold, was_active)
  if hold.active == true and was_active ~= true then
    _ensure_event_log_for_game(game)
    event_log.push_buffer(game.state.event_log, hold)
  end
end

function landing_visual_hold.sync_state_from_game(state, game)
  local hold = _ensure_hold(state)
  local was_active = hold.active == true
  if _hold_is_state_source(hold) then
    _project_hold_to_game(game, hold)
    _push_activation_buffer(game, hold, was_active)
    return hold
  end
  runtime_state.set_landing_visual_hold_active(state, _game_turn_active(game))
  runtime_state.set_landing_visual_release_pending(state, _game_turn_release_pending(game))
  runtime_state.set_landing_visual_hold_source(state, "game")
  if hold.active == true then
    _ensure_active_scope(hold)
  end
  _push_activation_buffer(game, hold, was_active)
  return hold
end

function landing_visual_hold.should_defer(state, game)
  if state == nil then
    return false
  end
  if game ~= nil then
    landing_visual_hold.sync_state_from_game(state, game)
  end
  return landing_visual_hold.is_active_state(state) and not landing_visual_hold.is_flushing_state(state)
end

function landing_visual_hold.capture_frozen_ui_model(state)
  local hold = _ensure_hold(state)
  if hold.frozen_ui_model ~= nil then
    return hold.frozen_ui_model
  end
  hold.frozen_ui_model = runtime_state.get_ui_model(state)
  return hold.frozen_ui_model
end

function landing_visual_hold.freeze_active_ui(state)
  local hold = _ensure_hold(state)
  if hold.active ~= true then
    return nil
  end
  return landing_visual_hold.capture_frozen_ui_model(state)
end

function landing_visual_hold.defer_dirty(state, dirty)
  local hold = _ensure_hold(state)
  return deferred_dirty.defer(hold, dirty)
end

function landing_visual_hold.register_release_callback(state, key, fn, opts)
  local hold = _ensure_hold(state)
  return release_scheduler.register(hold, key, fn, opts)
end

function landing_visual_hold.run_or_defer(state, game, key, fn, opts)
  if landing_visual_hold.should_defer(state, game) then
    landing_visual_hold.register_release_callback(state, key, fn, opts)
    return true
  end
  return fn()
end

local function _defer_replay(state, bucket, replay, ...)
  return release_scheduler.register_deferred_replay(_ensure_hold(state), bucket, replay, ...)
end

-- 行为测试公共接缝：test_visual_hold 经这些入口观测 release 的载荷保真与回放顺序。
-- 生产回放统一经 run_or_defer；保留类型化入口以覆盖同一 release 调度行为。
function landing_visual_hold.defer_popup(state, payload, opts, replay)
  return _defer_replay(state, "popup", replay, payload, opts)
end

function landing_visual_hold.defer_runtime_event(state, _, payload, replay)
  return _defer_replay(state, "runtime_event", replay, payload)
end

function landing_visual_hold.defer_board_visual_sync(state, payload, replay)
  return _defer_replay(state, "board_visual_sync", replay, payload)
end

function landing_visual_hold.defer_tile_update(state, tile_id, level, replay)
  return _defer_replay(state, "tile_update", replay, tile_id, level)
end

function landing_visual_hold.defer_owner_change(state, tile_id, owner_id, replay)
  return _defer_replay(state, "owner_change", replay, tile_id, owner_id)
end

function landing_visual_hold.defer_bankruptcy_clear(state, game, player, owned_tile_ids, replay)
  return _defer_replay(state, "bankruptcy_clear", replay, game, player, owned_tile_ids)
end

function landing_visual_hold.with_flushing(state, fn)
  local hold = _ensure_hold(state)
  local previous = hold.flushing == true
  hold.flushing = true
  local ok, result_or_err = xpcall(fn, debug and debug.traceback or function(err)
    return err
  end)
  hold.flushing = previous
  if not ok then
    error(result_or_err)
  end
  return result_or_err
end

function landing_visual_hold.set_post_release_hook(fn)
  post_release_hook = fn
end

-- release 前置守卫:game 缺失但 state 仍持有 turn 时,整局视为已清空。
-- 返回二元结果 (took_early_path, clear_result),与 clear_game 的返回值
-- (false 或 changed 布尔,永不 nil)解耦。
local function _clear_when_game_missing(state, game)
  if game == nil and state and state.turn then
    return true, landing_visual_hold.clear_game(state)
  end
  return false
end

local function _sync_when_game_present(state, game)
  if state and game then
    landing_visual_hold.sync_state_from_game(state, game)
  end
end

function landing_visual_hold.release(state, game)
  local early, clear_result = _clear_when_game_missing(state, game)
  if early then
    return clear_result
  end
  _sync_when_game_present(state, game)
  local hold = _ensure_hold(state)
  if hold.release_pending ~= true then
    return false
  end

  hold.release_pending = false
  hold.active = false

  _flush_pending_release(game, state, hold)
  landing_visual_hold.clear_game(game)
  return true
end

function landing_visual_hold.reset_state(state)
  local hold = _ensure_hold(state)
  hold.active = false
  hold.release_pending = false
  hold.flushing = false
  hold.source = nil
  _destroy_hold_scope(hold)
  return hold
end

return landing_visual_hold

--[[ mutate4lua-manifest
version=4
projectHash=9efe35c4a579f1e1
scope.0.id=chunk:src/state/visual_hold/init.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=441
scope.0.semanticHash=6255a31c343d8c1c
scope.1.id=function:_ensure_hold
scope.1.kind=function
scope.1.startLine=12
scope.1.endLine=28
scope.1.semanticHash=ce066c35aed86eb8
scope.2.id=function:_ensure_event_log_for_game
scope.2.kind=function
scope.2.startLine=32
scope.2.endLine=39
scope.2.semanticHash=d1fda453a2aabfbb
scope.3.id=function:_reset_deferred_buffers
scope.3.kind=function
scope.3.startLine=41
scope.3.endLine=44
scope.3.semanticHash=adba1684a6ff705f
scope.4.id=function:_ensure_active_scope
scope.4.kind=function
scope.4.startLine=51
scope.4.endLine=67
scope.4.semanticHash=2178fb979ca55964
scope.5.id=function:<anonymous>
scope.5.kind=function
scope.5.startLine=57
scope.5.endLine=59
scope.5.semanticHash=de73855b9bd40abb
scope.6.id=function:<anonymous>#2
scope.6.kind=function
scope.6.startLine=60
scope.6.endLine=62
scope.6.semanticHash=600a75ce96a391b3
scope.7.id=function:<anonymous>#3
scope.7.kind=function
scope.7.startLine=63
scope.7.endLine=65
scope.7.semanticHash=600a75ce96a391b3
scope.8.id=function:_destroy_hold_scope
scope.8.kind=function
scope.8.startLine=69
scope.8.endLine=75
scope.8.semanticHash=52b645ba51864605
scope.9.id=function:_game_turn
scope.9.kind=function
scope.9.startLine=77
scope.9.endLine=79
scope.9.semanticHash=616a2ca60599c94f
scope.10.id=function:_game_turn_bool
scope.10.kind=function
scope.10.startLine=81
scope.10.endLine=86
scope.10.semanticHash=d94980177626dfc8
scope.11.id=function:<anonymous>#4
scope.11.kind=function
scope.11.startLine=82
scope.11.endLine=85
scope.11.semanticHash=133ad1ac963179e7
scope.12.id=function:_project_hold_to_game
scope.12.kind=function
scope.12.startLine=91
scope.12.endLine=98
scope.12.semanticHash=d2841e0eb2430ed2
scope.13.id=function:_hold_is_state_source
scope.13.kind=function
scope.13.startLine=100
scope.13.endLine=102
scope.13.semanticHash=a8b64c56e64509d5
scope.14.id=function:_set_hold_state
scope.14.kind=function
scope.14.startLine=104
scope.14.endLine=113
scope.14.semanticHash=15b6f640c99d8267
scope.15.id=function:_refresh_active_hold
scope.15.kind=function
scope.15.startLine=117
scope.15.endLine=129
scope.15.semanticHash=6422111a57de0ce1
scope.16.id=function:_begin_hold
scope.16.kind=function
scope.16.startLine=131
scope.16.endLine=141
scope.16.semanticHash=3c051005223588cb
scope.17.id=function:landing_visual_hold.start
scope.17.kind=function
scope.17.startLine=143
scope.17.endLine=156
scope.17.semanticHash=2b69b1d7f19da2eb
scope.18.id=function:_hold_field_or_game_fallback
scope.18.kind=function
scope.18.startLine=160
scope.18.endLine=169
scope.18.semanticHash=5c86a70703ff49e2
scope.19.id=function:landing_visual_hold.is_active_game
scope.19.kind=function
scope.19.startLine=171
scope.19.endLine=173
scope.19.semanticHash=2a83785a68b42a92
scope.20.id=function:landing_visual_hold.is_release_pending_game
scope.20.kind=function
scope.20.startLine=175
scope.20.endLine=177
scope.20.semanticHash=2a83785a68b42a92
scope.21.id=function:landing_visual_hold.mark_release_pending
scope.21.kind=function
scope.21.startLine=179
scope.21.endLine=195
scope.21.semanticHash=d833d40100dc0c26
scope.22.id=function:_hold_changed
scope.22.kind=function
scope.22.startLine=197
scope.22.endLine=200
scope.22.semanticHash=c0e23ff088e9a278
scope.23.id=function:_merge_deferred_dirty
scope.23.kind=function
scope.23.startLine=202
scope.23.endLine=206
scope.23.semanticHash=6bd5a72f137e0b0e
scope.24.id=function:_run_post_release_hook
scope.24.kind=function
scope.24.startLine=208
scope.24.endLine=212
scope.24.semanticHash=e3961c5e397f559b
scope.25.id=function:_flush_pending_release
scope.25.kind=function
scope.25.startLine=217
scope.25.endLine=225
scope.25.semanticHash=40abafd6ce0c0a81
scope.26.id=function:<anonymous>#5
scope.26.kind=function
scope.26.startLine=219
scope.26.endLine=221
scope.26.semanticHash=600a75ce96a391b3
scope.27.id=function:_clear_hold_state
scope.27.kind=function
scope.27.startLine=229
scope.27.endLine=239
scope.27.semanticHash=6d8f9cb6c34dd701
scope.28.id=function:_clear_turn_flags
scope.28.kind=function
scope.28.startLine=242
scope.28.endLine=245
scope.28.semanticHash=89e9fcc23b326957
scope.29.id=function:landing_visual_hold.clear_game
scope.29.kind=function
scope.29.startLine=250
scope.29.endLine=265
scope.29.semanticHash=7e57438c854c7c87
scope.30.id=function:landing_visual_hold.is_flushing_state
scope.30.kind=function
scope.30.startLine=269
scope.30.endLine=272
scope.30.semanticHash=6b29dbed50bd63ec
scope.31.id=function:_push_activation_buffer
scope.31.kind=function
scope.31.startLine=275
scope.31.endLine=280
scope.31.semanticHash=978bae2208bb7af7
scope.32.id=function:landing_visual_hold.sync_state_from_game
scope.32.kind=function
scope.32.startLine=282
scope.32.endLine=298
scope.32.semanticHash=e85100af90b38422
scope.33.id=function:landing_visual_hold.should_defer
scope.33.kind=function
scope.33.startLine=300
scope.33.endLine=308
scope.33.semanticHash=5c12b038d503e3c8
scope.34.id=function:landing_visual_hold.capture_frozen_ui_model
scope.34.kind=function
scope.34.startLine=310
scope.34.endLine=317
scope.34.semanticHash=781e874bc500b034
scope.35.id=function:landing_visual_hold.freeze_active_ui
scope.35.kind=function
scope.35.startLine=319
scope.35.endLine=325
scope.35.semanticHash=398e2b6f9f39e9ac
scope.36.id=function:landing_visual_hold.defer_dirty
scope.36.kind=function
scope.36.startLine=327
scope.36.endLine=330
scope.36.semanticHash=9777cac48bf200bb
scope.37.id=function:landing_visual_hold.register_release_callback
scope.37.kind=function
scope.37.startLine=332
scope.37.endLine=335
scope.37.semanticHash=08af0cda342221db
scope.38.id=function:landing_visual_hold.run_or_defer
scope.38.kind=function
scope.38.startLine=337
scope.38.endLine=343
scope.38.semanticHash=eb0c8eff2bd5ca7f
scope.39.id=function:_defer_replay
scope.39.kind=function
scope.39.startLine=345
scope.39.endLine=347
scope.39.semanticHash=d529984ae3706989
scope.40.id=function:landing_visual_hold.defer_popup
scope.40.kind=function
scope.40.startLine=349
scope.40.endLine=351
scope.40.semanticHash=406bfcaa2a0f654b
scope.41.id=function:landing_visual_hold.defer_runtime_event
scope.41.kind=function
scope.41.startLine=353
scope.41.endLine=355
scope.41.semanticHash=4a72f6236b5f062e
scope.42.id=function:landing_visual_hold.defer_board_visual_sync
scope.42.kind=function
scope.42.startLine=357
scope.42.endLine=359
scope.42.semanticHash=7c75d9437e0a07d7
scope.43.id=function:landing_visual_hold.defer_tile_update
scope.43.kind=function
scope.43.startLine=361
scope.43.endLine=363
scope.43.semanticHash=406bfcaa2a0f654b
scope.44.id=function:landing_visual_hold.defer_owner_change
scope.44.kind=function
scope.44.startLine=365
scope.44.endLine=367
scope.44.semanticHash=406bfcaa2a0f654b
scope.45.id=function:landing_visual_hold.defer_bankruptcy_clear
scope.45.kind=function
scope.45.startLine=369
scope.45.endLine=371
scope.45.semanticHash=3636edac36ec76d7
scope.46.id=function:landing_visual_hold.with_flushing
scope.46.kind=function
scope.46.startLine=373
scope.46.endLine=385
scope.46.semanticHash=f64a97e1178ae452
scope.47.id=function:<anonymous>#6
scope.47.kind=function
scope.47.startLine=377
scope.47.endLine=379
scope.47.semanticHash=eba5730cfa182143
scope.48.id=function:landing_visual_hold.set_post_release_hook
scope.48.kind=function
scope.48.startLine=387
scope.48.endLine=389
scope.48.semanticHash=139af97e09c42e84
scope.49.id=function:_clear_when_game_missing
scope.49.kind=function
scope.49.startLine=394
scope.49.endLine=399
scope.49.semanticHash=2f7bd3c903332c5f
scope.50.id=function:_sync_when_game_present
scope.50.kind=function
scope.50.startLine=401
scope.50.endLine=405
scope.50.semanticHash=e4fd79c27c74ec9b
scope.51.id=function:landing_visual_hold.release
scope.51.kind=function
scope.51.startLine=407
scope.51.endLine=424
scope.51.semanticHash=7a47ecaeb2bfab70
scope.52.id=function:landing_visual_hold.reset_state
scope.52.kind=function
scope.52.startLine=426
scope.52.endLine=434
scope.52.semanticHash=943ed09e5aa636f1
scope.53.id=function:landing_visual_hold.merge_dirty
scope.53.kind=function
scope.53.startLine=436
scope.53.endLine=438
scope.53.semanticHash=aba9250a8c6b104f
]]
