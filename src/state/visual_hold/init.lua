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

