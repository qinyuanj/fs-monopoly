local gameplay_loop = require("src.turn.loop")
local turn_dispatch = require("src.turn.actions.action_dispatcher")
local presentation_ports = require("src.ui.ports")
local runtime_deps = require("src.ui.coord.deps")
local camera_sync = require("src.ui.ports.ui_sync")._camera
local tick_clock = require("src.turn.loop.tick_clock")
local frame_timer = require("src.host.frame_timer")
local leaderboard_settlement = require("src.app.host_integrations.leaderboard_settlement")

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

--[[ mutate4lua-manifest
version=4
projectHash=59e6673016386482
scope.0.id=chunk:src/app/gameplay_start.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=107
scope.0.semanticHash=f5084f32f7690a31
scope.1.id=function:_start_tick_loop
scope.1.kind=function
scope.1.startLine=12
scope.1.endLine=19
scope.1.semanticHash=82b76e649725920b
scope.2.id=function:<anonymous>
scope.2.kind=function
scope.2.startLine=15
scope.2.endLine=18
scope.2.semanticHash=c8228a9a5b1f1f75
scope.3.id=function:_ensure_tick_loop
scope.3.kind=function
scope.3.startLine=21
scope.3.endLine=25
scope.3.semanticHash=84224c00ece9936d
scope.4.id=function:_build_gameplay_loop_ports
scope.4.kind=function
scope.4.startLine=27
scope.4.endLine=29
scope.4.semanticHash=04a3b0c01baa0aa1
scope.5.id=function:_build_turn_action_port
scope.5.kind=function
scope.5.startLine=31
scope.5.endLine=40
scope.5.semanticHash=1c75fbef84503dfc
scope.6.id=function:<anonymous>#2
scope.6.kind=function
scope.6.startLine=33
scope.6.endLine=35
scope.6.semanticHash=360776c78d632b1f
scope.7.id=function:<anonymous>#3
scope.7.kind=function
scope.7.startLine=36
scope.7.endLine=38
scope.7.semanticHash=aba9250a8c6b104f
scope.8.id=function:_is_fresh_first_turn
scope.8.kind=function
scope.8.startLine=44
scope.8.endLine=48
scope.8.semanticHash=f97e94577bb683e3
scope.9.id=function:_should_prime_first_turn
scope.9.kind=function
scope.9.startLine=50
scope.9.endLine=56
scope.9.semanticHash=02b75238ec9ba9a0
scope.10.id=function:_prime_first_turn
scope.10.kind=function
scope.10.startLine=58
scope.10.endLine=64
scope.10.semanticHash=345330de81832c6b
scope.11.id=function:M.start
scope.11.kind=function
scope.11.startLine=68
scope.11.endLine=95
scope.11.semanticHash=b66bae4391f69439
scope.12.id=function:M.stop
scope.12.kind=function
scope.12.startLine=97
scope.12.endLine=104
scope.12.semanticHash=eb3e97d6717a8b3a
]]
