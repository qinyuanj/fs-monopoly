-- archive_key:宿主自定义玩家存档(Int)的归属 key,1 已拥有 / 0 未拥有;
-- equipped_archive_key 存当前穿戴的 product_id,0 为未穿(ADR 0074)。
-- 号码以宿主编辑器配置为准,上线后不可挪用。
local skins = {
  { order = 1, product_id = 5005, name = "奶龙", creature_key = "nailong", unlock = "purchase", currency = "金豆", price = 68, archive_key = 1054 },
  { order = 2, product_id = 5006, name = "水豚嘟嘟", creature_key = "capybara_dudu", unlock = "purchase", currency = "金豆", price = 98, archive_key = 1053 },
  { order = 5, product_id = 5003, name = "海绵宝宝", creature_key = "spongebob", unlock = "purchase", currency = "金豆", price = 198, archive_key = 1055 },
  { order = 6, product_id = 5004, name = "派大星", creature_key = "patrick_star", unlock = "purchase", currency = "金豆", price = 198, archive_key = 1052 },
}

skins.equipped_archive_key = 1051

return skins
