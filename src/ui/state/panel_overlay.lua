-- 弹层/结算的纯查询面（自 panel_interrupt 拆出,#162 后模块超变异点阈值）：
-- 无副作用,不触 host bridge。打断动作(closer 注册/提示/interrupt)住 panel_interrupt。
local panel_overlay = {}

local SETTLEMENT_TYPES = {
  { flag = "popup_active", name = "弹窗" },
  { flag = "market_active", name = "黑市" },
  { flag = "choice_active", name = "机会" },
  { flag = "move_active", name = "移动" },
}

function panel_overlay.settlement_type(ui)
  if ui == nil then
    return nil
  end
  for _, settlement in ipairs(SETTLEMENT_TYPES) do
    if ui[settlement.flag] == true then
      return settlement.name
    end
  end
  return nil
end

-- 基础屏取消按钮口径的遮挡判定:choice_active 豁免——followup 自己的选择屏正是
-- 取消按钮要退出的对象,不算对它的遮挡;弹窗/黑市/移动照常算。
function panel_overlay.settlement_type_excluding_choice(ui)
  if ui == nil then
    return nil
  end
  for _, settlement in ipairs(SETTLEMENT_TYPES) do
    if settlement.flag ~= "choice_active" and ui[settlement.flag] == true then
      return settlement.name
    end
  end
  return nil
end

function panel_overlay.is_settling(state)
  local ui = state and state.ui
  return panel_overlay.settlement_type(ui) ~= nil
end

-- 真弹层判定(#162):弹窗/黑市/机会是覆盖弹层;移动(move_active)与
-- input_blocked 是阶段位,不算弹层。道具槽全时段可点门只看这里。
local _OVERLAY_FLAGS = { "popup_active", "market_active", "choice_active" }

function panel_overlay.is_overlay_visible(ui)
  if ui == nil then
    return false
  end
  for _, flag in ipairs(_OVERLAY_FLAGS) do
    if ui[flag] == true then
      return true
    end
  end
  return false
end

return panel_overlay

