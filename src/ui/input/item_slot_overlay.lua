-- 道具槽点击的遮挡门：单一 seam。
--
-- 「点击者的屏幕上是否盖着弹层」是纯展示语义,turn 层看不见,所以这一条判断必须
-- 留在展示层——但只留这一条,别的都归 turn 裁定。
--
-- 关键是**逐席位**判定:模态画布本来就是逐席位切的(choice_helpers.switch_modal_canvas
-- 只给 can_operate 的席位切模态屏,旁观者留在基础屏;popup.switch_popup_canvas 同理,
-- 非操作者回落旁观画布),所以对手开着选择屏/黑市/弹窗时,我的屏幕是干净的,
-- 我的点击理应照常拿到裁定反馈。早先这里读的是全场共享的 popup_active /
-- market_active / choice_active 布尔,于是任何人开弹层都会把所有人的槽位点击一起
-- 静默——四人局里几乎总有人在模态里,这条比它要防的误触更伤。
--
-- 例外:broadcast 弹窗(modal_state.open_popup 的 payload.broadcast)是真的全场盖住。
local panel_interrupt = require("src.ui.state.panel_interrupt")
local modal_state = require("src.ui.state.modal")
local role_id_utils = require("src.foundation.identity")

local M = {}

-- 广播弹窗(open_popup 的 payload.broadcast)为全场盖住。
local function _broadcast_popup_covering(ui)
  return ui.popup_active == true and ui.popup_broadcast == true
end

-- 操作者或点击者身份未知时保守当作盖住,不放行来路不明的点击。
local function _unknown_actor_covered(operator_role_id, actor_role_id)
  return operator_role_id == nil or actor_role_id == nil
end

function M.blocks_click(state, actor_role_id)
  local ui = state and state.ui
  if not panel_interrupt.is_overlay_visible(ui) then
    return false
  end
  if _broadcast_popup_covering(ui) then
    return true
  end
  local operator_role_id = modal_state.operator_role_id(state)
  if _unknown_actor_covered(operator_role_id, actor_role_id) then
    return true
  end
  return role_id_utils.equals(operator_role_id, actor_role_id)
end

return M

