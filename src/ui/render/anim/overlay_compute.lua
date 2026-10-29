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

local function _resolve_xz(vec)
  return _resolve_vector_value(vec, "x", 1) or 0, _resolve_vector_value(vec, "z", 3) or 0
end

-- 覆盖物离地高度(相对 board_scene.ground 的 y)。地板是平的,格子模型原点却不齐:
-- 真机实测普通格锚点 y=0.116,起点等特殊格 1.575~2.238,角色在所有格都站在 1.747。
-- 以锚点为基准时特殊格上的地雷飘到角色头顶,所以只取锚点的 x/z,高度一律从地面起算。
-- 数值 = #339 在普通格(锚点 0.116、地面 1.457)标定的世界高度 - 地面 y:
-- 地雷/清障机器人 0.116+2.0,路障/导弹 0.116+1.0,普通格观感保持不变。
local _height_above_ground = {
  mine = 0.659,
  robot = 0.659,
  roadblock = -0.341,
  missile = -0.341,
}

function compute.overlay_pos_for_tile(state, kind, tile_index)
  local height = assert(_height_above_ground[kind], "unknown overlay kind: " .. tostring(kind))
  local x, z = _resolve_xz(compute.resolve_tile_pos(state, tile_index))
  return host_types.vec3(x, unit_position.read_scene_ground_y(state.board_scene) + height, z)
end

function compute.overlay_pos_for_player(state, kind, player_id)
  assert(state ~= nil, "missing state")
  assert(player_id ~= nil, "missing player_id")
  local game = assert(state.game, "missing state.game")
  local player = assert(game:find_player_by_id(player_id), "missing player: " .. tostring(player_id))
  return compute.overlay_pos_for_tile(state, kind, player.position)
end

return compute

