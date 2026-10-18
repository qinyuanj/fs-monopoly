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

return unit_position

