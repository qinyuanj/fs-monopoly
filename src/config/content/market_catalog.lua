local market_cfg = require("src.config.content.market")

local market_catalog = {}

local _entries_by_id
local _entries_by_id_len

local function _product_id(entry)
  return entry and entry.product_id or nil
end

local function _catalog_unchanged(cfg_len)
  return _entries_by_id ~= nil and _entries_by_id_len == cfg_len
end

local function _assert_unique(first_index, product_id, index)
  assert(
    first_index == nil,
    "duplicate market product_id: "
      .. tostring(product_id)
      .. " (first_index="
      .. tostring(first_index)
      .. ", duplicate_index="
      .. tostring(index)
      .. ")"
  )
end

local function _ensure_entries_by_id()
  local cfg_len = #market_cfg
  if _catalog_unchanged(cfg_len) then
    return _entries_by_id
  end
  _entries_by_id_len = cfg_len
  _entries_by_id = {}
  local first_index_by_id = {}
  for index, entry in ipairs(market_cfg) do
    local product_id = _product_id(entry)
    if product_id ~= nil then
      local first_index = first_index_by_id[product_id]
      _assert_unique(first_index, product_id, index)
      first_index_by_id[product_id] = index
      _entries_by_id[product_id] = entry
    end
  end
  return _entries_by_id
end

function market_catalog.entries()
  return market_cfg
end

function market_catalog.entry_by_id(product_id)
  return _ensure_entries_by_id()[product_id]
end

return market_catalog

