-- 倒计时解析树(#602 拆分,自 ui_sync.lua 移出,行为保持):拘留/选择/弹层
-- 各分支的剩余秒数判定。写回与打脏仍归 ui_sync.update_countdown。
local tick_ui_gate = require("src.turn.waits.ui_gate")
local choice_route_policy = require("src.config.choice.route_policy")
local runtime_state = require("src.state.runtime")
local DeadlineService = require("src.turn.deadlines")

local M = {}

local _ceil = math.ceil

local _log_prefix = "[Eggy]"

local function _resolve_detained_countdown(turn)
  local remaining = (turn.detained_wait_seconds or 0) - (turn.detained_wait_elapsed or 0)
  if remaining < 0 then
    remaining = 0
  end
  return true, _ceil(remaining)
end

-- 无屏 route（道具窗口 / 内联选项）本来就不点亮 choice_active，缺屏是常态，别打日志。
-- 这里只读显式 route_key（pending choice 由 intent_dispatcher 统一写入）：缺 route 的
-- 回落是 base_inline，同样无屏，不必为了判定去走会打 warn 的 policy.resolve。
local function _should_log_missing_choice_screen(gate, pending_choice)
  if gate.choice_active == true or gate.market_active == true then
    return false
  end
  local route_key = choice_route_policy.resolve_explicit_route(pending_choice)
  if route_key == nil then
    return false
  end
  return not choice_route_policy.is_screenless_route(route_key)
end

local function _resolve_pending_choice_countdown(state, gate, timeout, pending_choice)
  local pending_choice_elapsed = runtime_state.get_pending_choice_elapsed(state)
  if pending_choice_elapsed < 0 then
    pending_choice_elapsed = 0
  end
  if _should_log_missing_choice_screen(gate, pending_choice) then
    runtime_state.log_once(
      state,
      "info",
      "countdown_runtime_choice_without_ui_" .. tostring(pending_choice.id),
      _log_prefix,
      "countdown driven by runtime pending choice without ui choice screen",
      "choice_id=" .. tostring(pending_choice.id),
      "kind=" .. tostring(pending_choice.kind)
    )
  end
  local remaining = timeout - pending_choice_elapsed
  if remaining < 0 then
    remaining = 0
  end
  return true, _ceil(remaining)
end

local function _resolve_popup_countdown(game, state)
  -- modal 超时时长直接由 ui_gate 解析。
  local popup_timeout = tick_ui_gate.resolve_modal_timeout_seconds(state)
  if popup_timeout <= 0 then
    return false, 0
  end
  local remaining = popup_timeout - runtime_state.get_modal_elapsed(state)
  if remaining < 0 then
    remaining = 0
  end
  return true, _ceil(remaining)
end

local function _resolve_action_button_countdown(state, timeout)
  local remaining = timeout - (state.action_button_elapsed or 0)
  if remaining < 0 then
    remaining = 0
  end
  return true, _ceil(remaining)
end

local function _resolve_pending_choice(turn, state)
  return turn.pending_choice or runtime_state.get_pending_choice(state)
end

local function _resolve_modal_countdown(game, state, timeout, gate)
  if gate.popup_active == true then
    return _resolve_popup_countdown(game, state)
  end
  if state.action_button_active then
    return _resolve_action_button_countdown(state, timeout)
  end
  return false, 0
end

function M.resolve_state(game, state, turn, timeout, gate)
  local pending_choice = _resolve_pending_choice(turn, state)
  if turn.detained_wait_active then
    return _resolve_detained_countdown(turn)
  end
  if timeout <= 0 then
    return false, 0
  end
  if pending_choice ~= nil then
    return _resolve_pending_choice_countdown(state, gate, timeout, pending_choice)
  end
  return _resolve_modal_countdown(game, state, timeout, gate)
end

function M.resolve_deadline(state)
  local primary = DeadlineService.peek(state, "primary")
  if primary == nil then
    return nil, nil, nil
  end
  return true, _ceil(primary.remaining_seconds or 0), primary.level
end

return M

