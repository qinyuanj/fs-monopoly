local gameplay_loop = require("src.turn.loop")
local turn_dispatch = require("src.turn.actions.action_dispatcher")
local presentation_ports = require("src.ui.ports")
local runtime_deps = require("src.ui.coord.deps")
local camera_sync = require("src.ui.ports.ui_sync")._camera
local tick_clock = require("src.turn.loop.tick_clock")
local frame_timer = require("src.host.frame_timer")
local leaderboard_settlement = require("src.app.host_integrations.leaderboard_settlement")
local cosmetics_transaction = require("src.app.cosmetics.transaction")

local M = {}

local function _start_tick_loop(state, current_game_ref, interval)
  local tick_interval = interval or 1
  local fallback_tick_seconds = tick_clock.resolve_fallback_tick_seconds(tick_interval)
  return frame_timer.repeat_every(tick_interval, function()
    local tick_seconds = tick_clock.resolve_tick_seconds(state, fallback_tick_seconds)
    gameplay_loop.tick(current_game_ref[1], state, tick_seconds)
  end)
end

local function _ensure_tick_loop(state, current_game_ref)
  if state.tick_handle == nil then
    state.tick_handle = _start_tick_loop(state, current_game_ref)
  end
end

local function _build_gameplay_loop_ports()
  return presentation_ports.build()
end

local function _build_turn_action_port()
  return {
    dispatch_action = function(game, state, action, opts)
      return turn_dispatch.dispatch_action(game, state, action, opts)
    end,
    should_block_action = function(state, action_or_type)
      return turn_dispatch.should_block_action(state, action_or_type)
    end,
  }
end

-- A turn is "fresh" only before any turn has run, at the start phase, with
-- nothing awaiting the player.
local function _is_fresh_first_turn(turn)
  return turn.turn_count == 0
    and turn.phase == "start"
    and turn.pending_choice == nil
end

local function _should_prime_first_turn(game)
  local turn = game and game.turn or nil
  if turn == nil then
    return false
  end
  return _is_fresh_first_turn(turn)
end

local function _prime_first_turn(game)
  if not _should_prime_first_turn(game) then
    return false
  end
  game:advance_turn()
  return true
end

-- ADR 0074:开局即读皮肤存档并恢复穿戴;AI 无宿主 role、无存档,跳过。
local function _restore_skins(state, game)
  for _, player in ipairs(game and game.players or {}) do
    if not player.is_ai then
      cosmetics_transaction.restore_role(state, player.id)
    end
  end
end

-- 行为测试公共接缝：test_gameplay_start 验证只有无待决选择的首次 start 才推进回合。
M.prime_first_turn = _prime_first_turn

function M.start(state, current_game_ref)
  assert(state ~= nil, "missing state")
  assert(type(current_game_ref) == "table", "missing current_game_ref")
  if current_game_ref[1] then
    _ensure_tick_loop(state, current_game_ref)
    return current_game_ref[1]
  end

  state.turn_action_port = _build_turn_action_port()
  state.gameplay_loop_ports = _build_gameplay_loop_ports()
  state.presentation_runtime = runtime_deps.build({ camera_sync = camera_sync })
  -- 新局开局前清滤波基线,防止跨局同 role_id 首帧被误去重(#454)。
  camera_sync.reset_baseline()
  local current_game = gameplay_loop.new_game(state)
  current_game_ref[1] = current_game
  -- 排行榜退出监听挂在每名真人玩家的宿主 role 上,开局即注册,中途离开
  -- 标记 quit_reason,终局 settle 据此跳过其富豪榜资产累计。
  leaderboard_settlement.watch_game(current_game)
  _restore_skins(state, current_game)
  -- set_game 必须先于首回合起跑：它会 reset wait_callback_runtime,若首回合已挂起
  -- landing_visual 等待(begin_wait + 0.2s 定时器),reset 会抹掉 pending seq,定时器
  -- 回来时对不上就永远不 mark_ready,整局死锁在 wait_landing_visual。
  gameplay_loop.set_game(state, current_game)
  _prime_first_turn(current_game)

  _ensure_tick_loop(state, current_game_ref)

  return current_game
end

function M.stop(state)
  assert(state ~= nil, "missing state")
  if state.tick_handle == nil then
    return
  end
  frame_timer.stop(state.tick_handle)
  state.tick_handle = nil
end

return M

