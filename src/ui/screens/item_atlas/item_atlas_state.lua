-- 图鉴屏的面板态与目录/翻页纯逻辑:catalog 单一持有者。
-- 门面(../item_atlas.lua)只做行为编排与注册,测试目录注入也走这里。
local _default_catalog = require("src.config.content.item_atlas")
local number_utils = require("src.foundation.number")
local item_atlas_nodes = require("src.ui.schema.item_atlas")

local atlas_state = {}

local PAGE_SIZE = item_atlas_nodes.page_size
local _catalog = _default_catalog

function atlas_state.ensure(state)
  assert(state ~= nil, "missing state")
  local ui = assert(state.ui, "missing state.ui")
  ui.item_atlas = ui.item_atlas or {
    open = false,
    page_index = 1,
    selected_item_id = nil,
  }
  return ui.item_atlas
end

function atlas_state.clamp_page(page_index)
  local page = number_utils.to_integer(page_index)
  if page == nil then
    return 1
  end
  return number_utils.clamp(page, 1, number_utils.page_count(#_catalog, PAGE_SIZE))
end

function atlas_state.item_at(atlas, slot_index)
  local slot = number_utils.to_integer(slot_index) or 1
  return _catalog[(atlas.page_index - 1) * PAGE_SIZE + slot]
end

function atlas_state.catalog()
  return _catalog
end

function atlas_state.set_catalog(catalog)
  _catalog = catalog or _default_catalog
  return _catalog
end

return atlas_state

