-- 道具目标选择阶段独立超时。借用 DeadlineService 的 target_select scope；
-- item_phase_ask 二次确认屏激活（pending_confirmation）后注册 deadline，
-- 到点调 deadlines.resolve_target_select。
local timing = require("src.config.gameplay.timing")
local deadlines = require("src.turn.deadlines")
local pending_confirmation = require("src.state.pending_confirmation")
local NumberUtils = require("src.foundation.number")
local choice_owner = require("src.turn.choice.owner")
local afk_signal = require("src.turn.policies.afk_signal")

local M = {}

local function _resolve_target_select_timeout()
  local timeouts = timing.scope_timeouts
  if type(timeouts) == "table" and NumberUtils.is_numeric(timeouts.target_select) and timeouts.target_select > 0 then
    return timeouts.target_select
  end
  return 15
end

local function _is_target_select_active(state)
  return pending_confirmation.is_source_active(state, pending_confirmation.SOURCE_ITEM_PHASE_ASK)
end

local function _pending_choice(game)
  return game and game.turn and game.turn.pending_choice or nil
end

local function _resolve_target_owner(game, choice)
  if choice_owner.has_dangling_owner(game, choice) then
    return nil
  end
  return choice_owner.resolve_player(game, choice)
end

local function _notify_target_timeout(game, state, choice)
  local owner_player = _resolve_target_owner(game, choice)
  if afk_signal.is_timeout_eligible(owner_player) then
    afk_signal.on_timeout_fallback(game, state, owner_player.id, "target_select")
  end
end

-- 窗口该不该注册 target deadline：确认屏激活且当前 choice 可归属（无 turn 的
-- 裸结构兼容既有超时契约，choice 缺失按「无归属窗口」处理，不注册）。
local function _should_arm_target_deadline(game, state, choice_id)
  if not _is_target_select_active(state) then
    return false
  end
  if choice_id == nil and game ~= nil and game.turn ~= nil then
    return false
  end
  return true
end

-- 只结算仍归属同一 choice 的到期窗口：deadline 是在 choice 存活期注册的，
-- 其他路径清窗/换窗后 item_phase_ask 状态可能残留，不得误判为 AFK 或重复推进。
local function _resolve_target_deadline(game, state, choice_id)
  local active_choice = _pending_choice(game)
  if active_choice ~= nil then
    if active_choice.id == choice_id then
      state._target_select_timeout_choice_id = choice_id
      _notify_target_timeout(game, state, active_choice)
      deadlines.resolve_target_select(game, state, { choice = active_choice }, "tick_timeout")
    end
    return
  end
  if game == nil or game.turn == nil then
    state._target_select_timeout_choice_id = choice_id
    deadlines.resolve_target_select(game, state, { choice = nil }, "tick_timeout")
  end
end

-- 当前 choice 已有活跃 deadline 或已消费超时：是则本轮无需重新注册。
local function _has_target_deadline_for_choice(state, choice_id)
  if deadlines.is_active(state, "target_select") then
    return state._target_select_deadline_choice_id == choice_id
  end
  return choice_id ~= nil and state._target_select_timeout_choice_id == choice_id
end

-- 换窗后旧 deadline 作废：取消并清掉已消费标记，重新注册。
local function _cancel_stale_target_deadline(state)
  if deadlines.is_active(state, "target_select") then
    deadlines.cancel(state, "target_select")
    state._target_select_timeout_choice_id = nil
  end
end

local function _choice_id(game)
  local choice = _pending_choice(game)
  if choice ~= nil then
    return choice.id
  end
  return nil
end

function M.step(game, state, dt)
  if type(state) ~= "table" then
    return
  end
  local choice_id = _choice_id(game)
  if not _should_arm_target_deadline(game, state, choice_id) then
    _cancel_stale_target_deadline(state)
    state._target_select_deadline_choice_id = nil
    state._target_select_timeout_choice_id = nil
    return
  end

  if _has_target_deadline_for_choice(state, choice_id) then
    return
  end

  _cancel_stale_target_deadline(state)
  state._target_select_deadline_choice_id = choice_id
  deadlines.start(state, "target_select", {
    timeout_seconds = _resolve_target_select_timeout(),
    priority = 80,
    on_timeout = function()
      _resolve_target_deadline(game, state, choice_id)
    end,
  })
end

return M

