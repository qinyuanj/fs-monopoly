local land_adjacency = require("src.state.land_adjacency")
local property_query = require("src.rules.board.property_query")
local pricing = require("src.rules.land.pricing")
local rent_math = require("src.rules.land.rent_math")

local resolver = {}

-- 版本号一变(买地/加盖改了租金基数)整张缓存作废。
local function _ensure_rent_cache(game)
  local version = game._land_rent_version or 0
  local cache = game._land_rent_cache
  if not cache or cache.version ~= version then
    cache = {
      version = version,
      by_owner = {},
    }
    game._land_rent_cache = cache
  end
  return cache
end

local function _ensure_owner_bucket(cache, owner_id)
  local owner_cache = cache.by_owner[owner_id]
  if not owner_cache then
    owner_cache = { tile_sum = {}, tile_count = {}, tile_rents = {} }
    cache.by_owner[owner_id] = owner_cache
  end
  return owner_cache
end

local function _get_owner_cache(game, owner_id)
  return _ensure_owner_bucket(_ensure_rent_cache(game), owner_id)
end

resolver.safe_tile_state = property_query.safe_tile_state
resolver.resolve_rent_owner = property_query.resolve_rent_owner

local function _compute_and_cache(game, board, land_neighbors, owner_cache, start_tile, owner_id)
  local rent_sum, component, rents = rent_math.compute_contiguous_rent(
    start_tile.id,
    owner_id,
    land_neighbors,
    function(tile_id)
      local tile = board:get_tile_by_id(tile_id)
      assert(tile ~= nil, "missing tile: " .. tostring(tile_id))
      if tile.type ~= "land" then
        return nil
      end

      local state = resolver.safe_tile_state(game, tile)
      return state.owner_id, pricing.rent_for_level(tile, state.level)
    end
  )

  -- rent_math 总是返回 component 表(至少含起始地块),无需 nil 兜底。
  local count = #component
  for _, tile_id in ipairs(component) do
    owner_cache.tile_sum[tile_id] = rent_sum
    owner_cache.tile_count[tile_id] = count
    owner_cache.tile_rents[tile_id] = rents
  end
  return rent_sum, count, component, rents
end

-- 棋盘完整性(map.neighbors 齐全)由 land_adjacency.ensure_complete 断言,这里只挡住 nil board。
local function _require_land_neighbors(board)
  assert(board ~= nil, "missing board")
  return land_adjacency.ensure_complete(board)
end

local function _require_land_start_tile(board, index)
  local start_tile = assert(board:get_tile(index), "missing start tile: " .. tostring(index))
  assert(start_tile.type == "land", "invalid start tile: " .. tostring(index))
  return start_tile
end

local function _resolve_component(game, board, index, owner_id)
  local land_neighbors = _require_land_neighbors(board)

  local start_tile = _require_land_start_tile(board, index)
  local start_state = resolver.safe_tile_state(game, start_tile)
  if start_state.owner_id ~= owner_id then
    return start_tile, 0, 0, nil
  end

  local owner_cache = _get_owner_cache(game, owner_id)
  -- tile_sum / tile_count / tile_rents 由 _compute_and_cache 在同一轮里写满,
  -- 三者要么同时在要么同时不在,因此只需探测其中一个。
  local cached_sum = owner_cache.tile_sum[start_tile.id]
  if cached_sum then
    return start_tile,
      cached_sum,
      owner_cache.tile_count[start_tile.id],
      nil,
      owner_cache.tile_rents[start_tile.id]
  end

  local rent_sum, count, component, rents =
    _compute_and_cache(game, board, land_neighbors, owner_cache, start_tile, owner_id)
  return start_tile, rent_sum, count, component, rents
end

function resolver.contiguous_rent(game, board, index, owner_id)
  local _, rent_sum = _resolve_component(game, board, index, owner_id)
  return rent_sum
end

function resolver.contiguous_count(game, board, index, owner_id)
  local _, _, count = _resolve_component(game, board, index, owner_id)
  return count
end

function resolver.contiguous_breakdown(game, board, index, owner_id)
  local start_tile, rent_sum, count, _, rents = _resolve_component(game, board, index, owner_id)
  if count == 0 then
    return { count = 0, single_rent = 0, total_rent = 0, rents = {} }
  end
  local start_state = resolver.safe_tile_state(game, start_tile)
  local single_rent = pricing.rent_for_level(start_tile, start_state.level)
  return {
    count = count,
    single_rent = single_rent,
    total_rent = rent_sum,
    rents = rents or {},
  }
end

return resolver

