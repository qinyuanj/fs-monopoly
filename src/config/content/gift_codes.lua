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

return gift_codes
