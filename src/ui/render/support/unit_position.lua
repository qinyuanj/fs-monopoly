local host_types = require("src.foundation.host_types")

local unit_position = {}

local function _access_get_position(unit)
  return unit.get_position
end

local function _resolve_get_position(unit)
  if unit == nil then
    return nil
  end
  local ok, getter = pcall(_access_get_position, unit)
  if not ok or type(getter) ~= "function" then
    return nil
  end
  return getter
end

function unit_position.read_unit_position(unit)
  local getter = _resolve_get_position(unit)
  if getter == nil then
    return nil
  end
  local ok, pos = pcall(getter)
  if not ok then
    return nil
  end
  return pos
end

local function _read_indexed_position(units, index)
  if units == nil or index == nil then
    return nil
  end
  return unit_position.read_unit_position(units[index])
end

function unit_position.read_scene_tile_position(scene, tile_index)
  return _read_indexed_position(scene and scene.tiles or nil, tile_index)
end

function unit_position.read_scene_building_position(scene, tile_index)
  return _read_indexed_position(scene and scene.buildings or nil, tile_index)
end

-- 棋盘地面高度的唯一读法:角色站位下限与覆盖物离地高度都从这里取,
-- 保证两者以同一个地面为基准(地板是平的,地块锚点 y 不齐,见 overlay_compute)。
-- 宿主 Vector3 的 type() 不是 "table"(#266),分量按字段名取,取不到再按下标取。
function unit_position.read_scene_ground_y(scene)
  local pos = unit_position.read_unit_position(assert(scene.ground, "missing board_scene.ground"))
  assert(pos ~= nil, "missing ground position")
  local y = host_types.field(pos, "y")
  if y == nil then
    y = host_types.field(pos, 2)
  end
  return assert(y, "missing ground position y")
end

return unit_position
