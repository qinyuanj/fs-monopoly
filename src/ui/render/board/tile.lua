local tiles_cfg = require("src.config.content.tiles")
local number_utils = require("src.foundation.number")
local tile_rent = require("src.ui.view.tile_rent")
local player_colors = require("src.ui.view.player_colors")

local tiles_by_id = {}
for _, cfg in ipairs(tiles_cfg) do
  tiles_by_id[cfg.id] = cfg
end

local tile_renderer = {}

local function _set_billboard_text(node, text)
  if node and node.set_billboard_text then
    node.set_billboard_text(text)
    return true
  end
  return false
end

local function _assert_land_node_present(is_land, node_name)
  if is_land then
    assert(false, "missing " .. node_name .. " node")
  end
end

local function _render_name(unit, cfg, is_land)
  local name_node = unit.get_child_by_name("name")
  if _set_billboard_text(name_node, cfg.name) then
    return
  end
  _assert_land_node_present(is_land, "name")
end

local function _display_rent(cfg, level, contiguous_rent)
  if contiguous_rent and contiguous_rent > 0 then
    return contiguous_rent
  end
  return tile_rent.for_level(cfg, level)
end

local function _render_price(unit, cfg, is_land, owner_name, level, contiguous_rent)
  local price_node = unit.get_child_by_name("price")
  local text
  if owner_name then
    local rent = _display_rent(cfg, level, contiguous_rent)
    if rent and rent > 0 then
      text = owner_name .. "\n租 " .. number_utils.format_integer_part(rent)
    else
      text = owner_name
    end
  else
    text = "售 " .. number_utils.format_integer_part(cfg.price)
  end
  if _set_billboard_text(price_node, text) then
    return
  end
  _assert_land_node_present(is_land, "price")
end

local function _render_color(unit, owner_id, is_land)
  local color_node = unit.get_child_by_name("color")
  if color_node and color_node.set_paint_area_color then
    local color = player_colors.resolve_owner_color(owner_id)
    color_node.set_paint_area_color(1, color)
    return
  end
  _assert_land_node_present(is_land, "color")
end

local function _resolve_tile_cfg(unit, tile_id)
  local cfg = tiles_by_id[tile_id]
  assert(cfg ~= nil, "missing tile cfg: " .. tostring(tile_id))
  assert(unit ~= nil and unit.get_child_by_name ~= nil, "invalid tile unit")
  return cfg
end

local function _assert_tile_fields(cfg, tile_id, is_land)
  assert(cfg.name ~= nil, "missing tile name: " .. tostring(tile_id))
  if is_land then
    assert(cfg.price ~= nil, "missing tile price: " .. tostring(tile_id))
  end
end

function tile_renderer.render_tile(unit, tile_id, owner_id, owner_name, level, contiguous_rent)
  local cfg = _resolve_tile_cfg(unit, tile_id)
  local is_land = cfg.type == "land"
  _assert_tile_fields(cfg, tile_id, is_land)
  _render_name(unit, cfg, is_land)
  _render_price(unit, cfg, is_land, owner_name, level, contiguous_rent)
  _render_color(unit, owner_id, is_land)
end

return tile_renderer

