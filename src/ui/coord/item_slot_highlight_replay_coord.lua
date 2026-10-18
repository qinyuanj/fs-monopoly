local replay = require("src.ui.state.item_slot_highlight_replay")
local events = require("src.ui.coord.item_slots_events")
local logger = require("src.foundation.log")

-- 把 ui.state 算出的高亮计划投递成宿主动画(#594)。判定住在 ui.state,
-- 这里只负责副作用与失败容忍:宿主发送失败留诊断、不回滚记忆、不自动重试,
-- 否则一次宿主抖动会把玩家的槽位交互也一起卡住。
local M = {}

local _PLANS = {
  [replay.PLAN_REPLAY] = true,
  [replay.PLAN_RESET] = true,
  [replay.PLAN_NONE] = true,
}

local function _emit(plan, slot_pickable)
  if plan == replay.PLAN_RESET then
    events.emit_global_reset_animation()
    return
  end
  events.emit_pickable_slot_animation(slot_pickable)
end

-- 返回 true 表示这一轮投递完整送达;false 表示宿主报错已记诊断。
function M.deliver(plan, slot_pickable)
  assert(_PLANS[plan] == true, "unknown highlight plan: " .. tostring(plan))
  if plan == replay.PLAN_NONE then
    return true
  end
  assert(type(slot_pickable) == "table", "missing slot snapshot for plan: " .. tostring(plan))
  local ok, err = pcall(_emit, plan, slot_pickable)
  if not ok then
    logger.warn("item slot highlight replay send failed:", tostring(err))
    return false
  end
  return true
end

return M

