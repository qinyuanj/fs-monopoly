-- 道具槽拒绝反馈的契约单源：文案、时长、去重键。
-- 裁定与发射都只有一处(src/turn/actions/item_slot_click + item_slot_denial_tip),
-- 展示层不再自备一套——早先 UI 侧 idle 提示与 turn 侧拒绝提示各写一半、靠去重
-- 前缀隐式握手,两套判定不一致就掉进「两边都不提示」的夹缝。
-- 文案按拒因细分(#205 四类 + #216 通用兜底):阶段不合法 / 余额不足 / 无目标 /
-- 同组已用各有独立文案;设计不可达的拒因(出现即快照语义被破坏,见 ADR 0038)
-- 走通用诚实文案。
local M = {}

M.PHASE_DENIED_TEXT = "现阶段该卡无法使用"
M.INSUFFICIENT_FUNDS_TEXT = "你的现金不足，该卡当前无法使用"
M.NO_TARGET_TEXT = "没有合适的目标，该卡当前无法使用"
M.EFFECT_GROUP_USED_TEXT = "本回合已使用过同类效果的卡，该卡当前无法使用"
M.GENERIC_DENIED_TEXT = "该卡当前无法使用"
M.DURATION = 2.0

-- 拒因 → 文案。前两条是裁定自己产出的拒因（不是你的回合 / 没有道具窗），
-- 其余来自 rules 的 availability.can_offer_in_phase 第二返回值。
M.TEXT_BY_REASON = {
  not_current_turn = M.PHASE_DENIED_TEXT,
  no_item_window = M.PHASE_DENIED_TEXT,
  offer_in_phases_not_allowed = M.PHASE_DENIED_TEXT,
  insufficient_funds = M.INSUFFICIENT_FUNDS_TEXT,
  special_condition_failed = M.NO_TARGET_TEXT,
  effect_group_used = M.EFFECT_GROUP_USED_TEXT,
}

function M.text_for_reason(reason)
  return M.TEXT_BY_REASON[reason] or M.GENERIC_DENIED_TEXT
end

-- 去重键带上「谁点的」与「为什么」：只带 item_id 时,甲的提示会把乙同卡的提示
-- 吞掉(跨玩家静默),同卡换了拒因也会被上一条吞掉(提示不更新)。
function M.dedupe_key(actor_role_id, item_id, reason)
  return table.concat({
    "item_slot_denied",
    tostring(actor_role_id),
    tostring(item_id),
    tostring(reason),
  }, ":")
end

return M

