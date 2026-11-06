-- 单局限购计数(ADR 0080、0081):按玩家、按商品记本局已购次数。
-- 付费商品是宿主限购的局内镜像:宿主回调不带数量,每到一次记 1 件,靠编辑器
-- 「单次限购 = 1」成立。金币商品在扣款发卡成功后记 1 件。
-- 计数挂在 game 上,新一局的 game 自然从 0 开始。
local purchase_limit = {}

local COUNTS_FIELD = "_market_purchase_counts"

local function _count_key(player, entry)
  return tostring(player.id) .. ":" .. tostring(entry.product_id)
end

local function _purchase_count(game, player, entry)
  local counts = game[COUNTS_FIELD]
  return counts and counts[_count_key(player, entry)] or 0
end

function purchase_limit.record_purchase(game, player, entry)
  local counts = game[COUNTS_FIELD]
  if not counts then
    counts = {}
    game[COUNTS_FIELD] = counts
  end
  counts[_count_key(player, entry)] = _purchase_count(game, player, entry) + 1
end

function purchase_limit.is_reached(game, player, entry)
  local limit = entry.purchase_limit
  return limit ~= nil and _purchase_count(game, player, entry) >= limit
end

return purchase_limit
