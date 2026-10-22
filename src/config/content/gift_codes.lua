-- 礼包码码表(#195 / ADR 0075)。每个码:
--   id         短整数,上线后不可复用(兑换记录只存 id,改 code 文本不影响已兑换记录)
--   code       玩家输入的兑换码;比对前去首尾空格、不区分大小写
--   rewards    礼包码奖励的皮肤 product_id 列表(须在 skins.lua 且配了 archive_key)
--   expires_at 可选,墙钟秒;墙钟超过即过期,墙钟取不到不判过期
-- 码表随客户端明文分发(ADR 0075 接受此风险)。加载期校验见 gift_code_catalog。
local gift_codes = {
  codes = {},
}

-- 兑换记录的 Str 玩家存档 key,存已兑换码 id 的逗号分隔列表。
-- 占位号码:真实号码以宿主编辑器配置为准,由 #200 人工登记后替换。
gift_codes.redeem_record_archive_key = 1056

-- 兑换结果提示文本(按兑换门面的状态取用);granted 的 %s 为本次发放的皮肤名,顿号分隔。
gift_codes.messages = {
  granted = "兑换成功，获得：%s",
  all_owned = "奖励皮肤已全部拥有",
  invalid_code = "兑换码无效",
  expired = "兑换码已过期",
  already_redeemed = "已兑换过该兑换码",
  archive_unavailable = "存档未开启，暂时无法兑换",
  write_failed = "兑换失败，请稍后重试",
}

return gift_codes
