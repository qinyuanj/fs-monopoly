-- 礼包码码表(#195 / #203 / ADR 0075)。礼包码是一人一码的补偿码,每个码:
--   id         短整数,上线后不可复用(兑换记录只存 id);停用的 id 列进 retired_ids
--   code_hash  规范化后(去空白与连字符、转大写)码的 SHA-256,64 位小写十六进制;
--              码表不存明文 code,出现即加载报错
--   rewards    礼包码奖励的皮肤 product_id 列表(须在 skins.lua 且配了 archive_key)
--   expires_at 可选,墙钟秒;墙钟超过即过期,墙钟取不到不判过期
--   note       工单号或补偿原因,不写玩家昵称
-- 新码一律用 `lua5.4 tools/cli.lua gift-code new` 生成:它只在 codes 列表末尾
-- 追加一条,明文码只在终端打印一次。「id → 玩家、明文码、发放日期」记在仓外。
-- 加载期校验见 gift_code_catalog。
local gift_codes = {
  codes = {
    { id = 2, code_hash = "602f521bc1c37fe7b2c7447cfe8b743fac9f5a4cf7630ff3b7ac9227d93e623b", rewards = { 5005 }, expires_at = 1808295571, note = "#200 真机验收测试码(取代停用的 id 1 TEST2026)" },
  },
  -- 停用 id,永不再分配:1 = 旧明文测试码 TEST2026(#203 停用)。
  retired_ids = { 1 },
}

-- 兑换记录的 Str 玩家存档 key,存已兑换码 id 的逗号分隔列表。
-- 号码以宿主编辑器配置为准:编辑器存档「礼包码兑换记录」(Str)即 1056(#200 已核实)。
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
