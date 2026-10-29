local prefab = require("Data.Prefab")
local logger = require("src.foundation.log")
local compute = require("src.ui.render.anim.overlay_compute")
local runtime = require("src.ui.render.anim.overlay_runtime")
local robot = require("src.ui.render.anim.unit_overlay_robot")

local host_types = require("src.foundation.host_types")

local overlay = {}
local roadblock_scale = host_types.vec3(4.0, 4.0, 4.0)

local _deps = robot.resolve_presentation_runtime

local function _play_roadblock(state, tile_index)
  local unit_id = prefab.unit and prefab.unit["路障"] or nil
  runtime.spawn_overlay(
    assert(state.board_scene, "missing board_scene"),
    "roadblock",
    tile_index,
    nil,
    unit_id,
    compute.overlay_pos_for_tile(state, "roadblock", tile_index),
    roadblock_scale,
    _deps(state)
  )
end

local function _play_mine(state, tile_index)
  local group_id = prefab.group["地雷A"]
  local unit_id = prefab.unit and prefab.unit["地雷A"] or nil
  if not group_id and not unit_id then
    logger.warn("[Eggy]", "地雷A prefab 缺失，已跳过生成")
    return
  end
  runtime.spawn_overlay(assert(state.board_scene, "missing board_scene"), "mine", tile_index, group_id, unit_id,
    compute.overlay_pos_for_tile(state, "mine", tile_index), nil, _deps(state))
end

function overlay.clear_overlay(state, kind, tile_index)
  assert(state ~= nil, "missing state")
  assert(kind ~= nil, "missing kind")
  assert(tile_index ~= nil, "missing tile_index")
  runtime.clear_overlay(assert(state.board_scene, "missing board_scene"), kind, tile_index, _deps(state))
end

function overlay.play_overlay(state, anim, duration, opts)
  local tile_index = assert(anim.tile_index, "missing tile_index")
  if anim.kind == "roadblock" then
    return _play_roadblock(state, tile_index)
  end
  if anim.kind == "mine" then
    return _play_mine(state, tile_index)
  end
end

function overlay.play_missile(state, anim, duration, opts)
  local clear_overlay = assert(opts and opts.clear_overlay, "missing clear_overlay")
  local tile_index = assert(anim.tile_index, "missing missile tile_index")
  robot.clear_obstacle(state, clear_overlay, tile_index)
  local unit_id = prefab.unit and prefab.unit["导弹"] or nil
  local group_id = prefab.group["导弹"]
  runtime.spawn_transient(group_id, unit_id, compute.overlay_pos_for_tile(state, "missile", tile_index), duration, _deps(state))
end

overlay.play_clear_obstacles = robot.play_clear_obstacles

return overlay

