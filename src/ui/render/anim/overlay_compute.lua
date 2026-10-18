local host_types = require("src.foundation.host_types")
local unit_position = require("src.ui.render.support.unit_position")

local compute = {}

-- vec 是宿主 Vector3，type() 返回的是宿主类名而不是 "table"（#266），不能拿
-- type(vec) == "table" 把门——那样真机上每个分量都取成 nil。
local function _resolve_vector_value(vec, key, index)
  local value = host_types.field(vec, key)
  if value ~= nil then
    return value
  end
  return host_types.field(vec, index)
end

local _ZERO_VEC = host_types.vec3(0.0, 0.0, 0.0)

local function _zero_vector()
  return _ZERO_VEC
end

local function _validate_tile_query(state, tile_index)
  assert(state ~= nil, "missing state")
  assert(tile_index ~= nil, "missing tile_index")
  local scene = assert(state.board_scene, "missing board_scene")
  local tiles = assert(scene.tiles, "missing scene.tiles")
  return scene, tiles
end

local function _read_position_from_table(tbl, index)
  if type(tbl) ~= "table" then
    return nil
  end
  return unit_position.read_unit_position(tbl[index])
end

function compute.resolve_tile_pos(state, tile_index)
  local scene, tiles = _validate_tile_query(state, tile_index)
  local tile_pos = _read_position_from_table(tiles, tile_index)
  if tile_pos ~= nil then
    return tile_pos
  end

  local building_pos = _read_position_from_table(scene.buildings, tile_index)
  if building_pos ~= nil then
    return building_pos
  end

  return _zero_vector()
end

local function _native_add(a, b)
  return a + b
end

local function _try_native_vector_add(pos, offset)
  return pcall(_native_add, pos, offset)
end

local function _resolve_vector_components(vec)
  local x = _resolve_vector_value(vec, "x", 1) or 0
  local y = _resolve_vector_value(vec, "y", 2) or 0
  local z = _resolve_vector_value(vec, "z", 3) or 0
  return x, y, z
end

local function _create_offset_vector(pos_x, pos_y, pos_z, offset_x, offset_y, offset_z)
  if math and math.Vector3 then
    return math.Vector3(pos_x + offset_x, pos_y + offset_y, pos_z + offset_z)
  end
  return nil
end

local function _offset_pos(pos, offset)
  local ok, result = _try_native_vector_add(pos, offset)
  if ok then
    return result
  end
  local pos_x, pos_y, pos_z = _resolve_vector_components(pos)
  local offset_x, offset_y, offset_z = _resolve_vector_components(offset)
  local vector = _create_offset_vector(pos_x, pos_y, pos_z, offset_x, offset_y, offset_z)
  if vector then
    return vector
  end
  return pos
end

local _y_offset_cache = {}
local function _y_offset_vector(y_offset)
  local key = y_offset or 1.0
  local cached = _y_offset_cache[key]
  if cached then
    return cached
  end
  cached = math.Vector3(0.0, key, 0.0)
  _y_offset_cache[key] = cached
  return cached
end

function compute.overlay_pos_for_tile(state, tile_index, y_offset)
  return _offset_pos(compute.resolve_tile_pos(state, tile_index), _y_offset_vector(y_offset))
end

function compute.overlay_pos_for_player(state, player_id, y_offset)
  assert(state ~= nil, "missing state")
  assert(player_id ~= nil, "missing player_id")
  local game = assert(state.game, "missing state.game")
  local player = assert(game:find_player_by_id(player_id), "missing player: " .. tostring(player_id))
  return _offset_pos(compute.resolve_tile_pos(state, player.position), _y_offset_vector(y_offset))
end

return compute

