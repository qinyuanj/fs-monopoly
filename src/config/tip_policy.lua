local event_kinds = require("src.config.gameplay.event_kinds")

local M = {}

M[event_kinds.dice_roll] = { tip = false }
M[event_kinds.rent_paid] = { tip = true }
M[event_kinds.tax_paid] = { tip = true }
M[event_kinds.medical_fee] = { tip = true }
M[event_kinds.hospital_stay] = { tip = true }
M[event_kinds.mountain_stay] = { tip = true }
M[event_kinds.land_purchase] = { tip = true }
M[event_kinds.land_upgrade] = { tip = true }
M[event_kinds.transit] = { tip = false }
M[event_kinds.move_completed] = { tip = false }
M[event_kinds.roadblock_placed] = { tip = false }
M[event_kinds.roadblock_triggered] = { tip = false }
M[event_kinds.mine_placed] = { tip = false }
M[event_kinds.bankruptcy] = { tip = false }
M[event_kinds.victory] = { tip = false }
-- 遥控骰子（#103）:全场可见提示谁用了遥控骰子、设定了多少点。
M[event_kinds.remote_dice] = { tip = true }
-- AI 遥控骰子的目标格（#109）:一次用卡只弹一条提示,目标格只进行动日志。
M[event_kinds.remote_dice_target] = { tip = false }
-- 骰子加倍明细（#103）:只进行动日志(骰面 × 倍率 = 步数),提示归 item_used 的使用播报。
M[event_kinds.dice_multiplier_breakdown] = { tip = false }

M[event_kinds.rent_multiplier_breakdown] = { tip = true }
M[event_kinds.afk_auto_enabled] = { tip = true }
-- 电脑/托管玩家到达黑市未购买:不弹 tip,但进行动日志——托管席位要能看出自己被跳过。
M[event_kinds.market_auto_skipped] = { tip = false }

M[event_kinds.choice_picked] = { log = false }
M[event_kinds.choice_skipped] = { log = false }
M[event_kinds.turn_start] = { log = false }
M[event_kinds.turn_end] = { log = false }

return M

