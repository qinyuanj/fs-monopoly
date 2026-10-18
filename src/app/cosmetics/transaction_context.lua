local default_catalog = require("src.config.content.skins")
local logger = require("src.foundation.log")

local context = {}

local state = {
  catalog = default_catalog,
  archive_adapter = nil,
  equip_adapter = nil,
  unequip_adapter = nil,
  transaction_result_applier = nil,
}

local function _price_before(price_a, price_b)
  if price_a == nil then
    return false
  end
  if price_b == nil then
    return true
  end
  return price_a < price_b
end

-- 目录排序真源（#495 裁定）：price 递增为主键（最便宜的皮肤在槽位1），order
-- 字段为同价 tie-break，源下标兜底保证全等键稳定；price 缺失的皮肤排最后。
local function _sorted_by_price(source)
  local decorated = {}
  for index, skin in ipairs(source) do
    decorated[#decorated + 1] = { skin = skin, source_index = index }
  end
  table.sort(decorated, function(a, b)
    local price_a = a.skin.price
    local price_b = b.skin.price
    if price_a ~= price_b then
      return _price_before(price_a, price_b)
    end
    local order_a, order_b = a.skin.order or 0, b.skin.order or 0
    if order_a ~= order_b then
      return order_a < order_b
    end
    return a.source_index < b.source_index
  end)
  local sorted = {}
  for index, entry in ipairs(decorated) do
    sorted[index] = entry.skin
  end
  return sorted
end

function context.catalog()
  return _sorted_by_price(state.catalog)
end

function context.has_equip_adapter()
  return type(state.equip_adapter) == "function"
end

function context.has_unequip_adapter()
  return type(state.unequip_adapter) == "function"
end

function context.archive_call(method, role_id, product_id)
  local adapter = state.archive_adapter
  if type(adapter) ~= "table" or type(adapter[method]) ~= "function" then
    return nil
  end
  local ok, result = pcall(adapter[method], role_id, product_id)
  if ok then
    return result
  end
  return nil
end

function context.call_equip_adapter(role_id, skin)
  if not context.has_equip_adapter() then
    return false
  end
  local ok, result = pcall(state.equip_adapter, role_id, skin)
  return ok and result == true
end

function context.call_unequip_adapter(role_id)
  if not context.has_unequip_adapter() then
    return
  end
  local ok, err = pcall(state.unequip_adapter, role_id)
  if ok then
    return
  end
  logger.warn(
    "skin_panel: unequip callback failed",
    "role_id=" .. tostring(role_id),
    tostring(err)
  )
end

local function _configure_callback(field, callback, message)
  assert(callback == nil or type(callback) == "function", message)
  state[field] = callback
end

function context.configure_equip(callback)
  _configure_callback("equip_adapter", callback, "invalid skin equip callback")
end

function context.configure_unequip(callback)
  _configure_callback("unequip_adapter", callback, "invalid skin unequip callback")
end

function context.configure_transaction_result_applier(callback)
  _configure_callback("transaction_result_applier", callback, "invalid skin transaction result applier")
end

function context.call_transaction_result_applier(root_state, result)
  local applier = state.transaction_result_applier
  if type(applier) ~= "function" then
    return
  end
  local ok, err = pcall(applier, root_state, result)
  if not ok then
    logger.warn(
      "skin_panel: transaction result applier failed",
      tostring(err)
    )
  end
end

function context.configure_archive(archive)
  assert(archive == nil or type(archive) == "table", "invalid skin archive")
  state.archive_adapter = archive
end

function context.configure_catalog_for_tests(new_catalog)
  state.catalog = new_catalog or default_catalog
end

function context.reset_for_tests()
  state.catalog = default_catalog
  state.archive_adapter = nil
  state.equip_adapter = nil
  state.unequip_adapter = nil
  state.transaction_result_applier = nil
end

return context

