local prefab = require("Data.Prefab")
local overlay_runtime = require("src.ui.render.anim.overlay_runtime")
local overlay_compute = require("src.ui.render.anim.overlay_compute")
local shared = require("src.ui.render.board.visual_sync_shared")

local visual_sync_overlay = {}

local roadblock_scale = math and math.Vector3 and math.Vector3(4.0, 4.0, 4.0) or {
  x = 4.0,
  y = 4.0,
  z = 4.0,
}

-- #339 真机标定:y_offset 缺省 1.0 会被地板埋没,2.0 是探针肉眼验证的可见高度;
-- 地雷 scale 1x 不像路障 4x 能顶出地板,sync 生成必须显式抬升。
local mine_y_offset = 2.0

local _trigger_kind_for_overlay = {
  roadblock = "roadblock_trigger",
  mine = "mine_trigger",
}

local function _matches_trigger(entry, target_kind, tile_index)
  return entry ~= nil and entry.kind == target_kind and entry.tile_index == tile_index
end

local function _match_in_anim_queue(queue, target_kind, tile_index)
  if type(queue) ~= "table" then
    return false
  end
  for _, entry in ipairs(queue) do
    if _matches_trigger(entry, target_kind, tile_index) then
      return true
    end
  end
  return false
end

local function _resolve_turn(state)
  local game = state and state.game or nil
  return game and game.turn or nil
end

local function _has_pending_trigger_anim(state, overlay_kind, tile_index)
  local turn = _resolve_turn(state)
  if not turn then
    return false
  end
  -- overlay_kind 恒为 roadblock/mine(_sync_overlay_kind 只喂这两种),映射恒命中,
  -- target_kind 空守卫是死防御(#262 删除)。
  local target_kind = _trigger_kind_for_overlay[overlay_kind]
  if _matches_trigger(turn.action_anim, target_kind, tile_index) then
    return true
  end
  return _match_in_anim_queue(turn.action_anim_queue, target_kind, tile_index)
end

local function _spawn_roadblock_overlay(state, idx)
  return overlay_runtime.spawn_overlay(
    assert(shared.resolve_scene(state), "missing board_scene"),
    "roadblock",
    idx,
    nil,
    prefab.unit and prefab.unit["路障"] or nil,
    overlay_compute.overlay_pos_for_tile(state, idx),
    roadblock_scale,
    shared.deps(state)
  )
end

local function _spawn_mine_overlay(state, idx)
  return overlay_runtime.spawn_overlay(
    assert(shared.resolve_scene(state), "missing board_scene"),
    "mine",
    idx,
    prefab.group["地雷A"],
    prefab.unit and prefab.unit["地雷A"] or nil,
    overlay_compute.overlay_pos_for_tile(state, idx, mine_y_offset),
    nil,
    shared.deps(state)
  )
end

local _spawn_overlay_for_kind = {
  roadblock = _spawn_roadblock_overlay,
  mine = _spawn_mine_overlay,
}

local function _sync_overlay_kind(state, scene, board_index, overlay_kind, present)
  if present then
    _spawn_overlay_for_kind[overlay_kind](state, board_index)
  elseif not _has_pending_trigger_anim(state, overlay_kind, board_index) then
    overlay_runtime.clear_overlay(scene, overlay_kind, board_index, shared.deps(state))
  end
end

function visual_sync_overlay.sync_overlay_visual(state, board_index)
  if board_index == nil then
    return false
  end
  local board = shared.resolve_board(state)
  local scene = shared.resolve_scene(state)
  if not (board and scene) then
    return false
  end

  local has_roadblock = board:has_roadblock(board_index)
  local has_mine = board:has_mine(board_index)

  _sync_overlay_kind(state, scene, board_index, "roadblock", has_roadblock)
  _sync_overlay_kind(state, scene, board_index, "mine", has_mine)

  return true
end

return visual_sync_overlay

