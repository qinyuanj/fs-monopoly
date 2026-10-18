local optional_action_choice = {}

function optional_action_choice.is_optional_action_choice(choice)
  local kind = choice and choice.kind or nil
  return kind == "item_phase_passive" or kind == "landing_optional_effect"
end

function optional_action_choice.is_cancelable_optional_action_choice(choice)
  return optional_action_choice.is_optional_action_choice(choice) and choice.allow_cancel ~= false
end

local function _is_cancelable_item_phase_passive(choice)
  if not optional_action_choice.is_cancelable_optional_action_choice(choice) then
    return false
  end
  return choice.kind == "item_phase_passive"
end

-- A pre_action item phase passive choice is opened at turn start, before the roll.
-- Unlike post_action/landing optional phases (which resolve through the 结束 button),
-- skipping it belongs on the 行动 button so 行动 precedes the roll even while a
-- pre-action card is still in the bag. Item target selection (passive_origin) is a
-- usage follow-up with its own base-cancel exit and is excluded here.
function optional_action_choice.is_pre_action_item_phase_passive(choice)
  if not _is_cancelable_item_phase_passive(choice) then
    return false
  end
  local meta = choice.meta
  return type(meta) == "table" and meta.phase == "pre_action" and meta.passive_origin ~= true
end

-- Item target selection is a follow-up of item usage (道具使用后续选择): rules
-- marks every followup choice_spec with meta.passive_origin
-- (src/rules/choice_handlers/item_phase_handlers._decorate_phase_followup); the
-- kind varies per card (item_target_player / remote_dice_value / roadblock_target
-- / demolish_target), so the marker, not the kind, is the truth source. The base
-- screen keeps its cancel button up as the exit back to the item phase window.
function optional_action_choice.is_item_target_selection_choice(choice)
  local meta = choice and choice.meta
  return type(meta) == "table" and meta.passive_origin == true
end

-- 基础屏取消按钮唯一口径：渲染显隐(panel_action_controls)与意图构造(route_base)
-- 都只问这个谓词，两边永不脱节。只有道具使用后续选择拥有基础屏取消出口
-- （取消 → rules 侧 followup_cancel → reopen_or_finish 重开道具窗、卡不消耗）；
-- escrow / 预消耗 followup 由 rules 写 allow_cancel=false 关掉出口。
function optional_action_choice.is_base_cancel_choice(choice)
  return optional_action_choice.is_item_target_selection_choice(choice)
    and choice.allow_cancel ~= false
end

return optional_action_choice

