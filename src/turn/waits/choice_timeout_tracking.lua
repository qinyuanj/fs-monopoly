-- 选择超时簿记(#602 拆分):deadline 作用域同步/重置与 owner 缺失清算,
-- 自 choice_timeout.lua 移出,引擎只留 tick 决策主线。
local choice_owner = require("src.turn.choice.owner")
local choice_scope = require("src.turn.deadlines.choice_scope")
local deadlines = require("src.turn.deadlines")

local M = {}

local function _owner_eliminated(owner_player)
  return owner_player ~= nil and owner_player.eliminated == true
end

local function _resolve_force_skip_reason(game, active_choice)
  if choice_owner.has_dangling_owner(game, active_choice) then
    return "owner_dangling"
  end
  if _owner_eliminated(choice_owner.resolve_player(game, active_choice)) then
    return "owner_eliminated"
  end
  return nil
end

-- owner 悬空/被淘汰的窗口不进倒计时:立即 force_skip 清算,不走自动代答。悬空
-- owner 若带「兜底当前回合玩家」的 actor 去派发,只会被 actor 校验拦截,窗口
-- 永不消失、blocked warn 每轮超时刷屏。
function M.maybe_force_skip_owner_missing(game, state, active_choice, output_ports)
  local reason = _resolve_force_skip_reason(game, active_choice)
  if reason ~= nil then
    output_ports.set_pending_choice_elapsed(state, 0)
    deadlines.force_skip(game, state, active_choice, reason)
    return true
  end
  return false
end

local function _cancel_choice_deadlines(state)
  deadlines.cancel(state, "choice")
  deadlines.cancel(state, "market_buy")
end

function M.reset_tracking(state, output_ports)
  output_ports.set_pending_choice_elapsed(state, 0)
  output_ports.set_pending_choice_id(state, nil)
  _cancel_choice_deadlines(state)
end

local function _sync_choice_identity(state, output_ports, active_choice, previous_choice_id)
  if previous_choice_id ~= active_choice.id then
    output_ports.set_pending_choice_elapsed(state, 0)
    output_ports.set_pending_choice_id(state, active_choice.id)
    _cancel_choice_deadlines(state)
  end
end

local function _other_choice_scope(scope)
  return scope == "choice" and "market_buy" or "choice"
end

local function _cancel_other_scope(state, scope)
  local other_scope = _other_choice_scope(scope)
  if deadlines.is_active(state, other_scope) then
    deadlines.cancel(state, other_scope)
  end
end

local function _start_scope_once(state, scope, timeout)
  if not deadlines.is_active(state, scope) then
    deadlines.start(state, scope, {
      timeout_seconds = timeout,
      priority = 100,
    })
  end
end

local function _sync_deadline_scope(state, active_choice, timeout)
  local scope = choice_scope.for_choice(active_choice)
  _cancel_other_scope(state, scope)
  _start_scope_once(state, scope, timeout)
end

function M.sync_tracking(state, output_ports, active_choice, previous_choice_id, timeout)
  _sync_choice_identity(state, output_ports, active_choice, previous_choice_id)
  _sync_deadline_scope(state, active_choice, timeout)
end

return M

