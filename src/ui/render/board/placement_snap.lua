local placement_geometry = require("src.ui.render.board.placement_geometry")
local runtime_state = require("src.ui.state.runtime")
local move_anim_debug = require("src.ui.render.move_anim.debug")
local move_anim = require("src.ui.render.move_anim")
local player_resolve = require("src.ui.render.board.player_resolve")

local M = {}

local _should_debug_log = move_anim_debug.enabled
local _debug_log = move_anim_debug.debug_log

local _resolve_player_id = player_resolve.resolve_player_id
local _resolve_active_player_base = player_resolve.resolve_active_player_base

local _stop_opts = {}

local function _stop_player_motion(pid, unit, stop_synthetic_ai)
  _stop_opts.stop_synthetic_ai = stop_synthetic_ai == true
  return move_anim.stop_player_presentation(pid, unit, _stop_opts)
end

local _follow_opts = {}

local function _publish_follow_target(state, pid, target_pos, source)
  _follow_opts.source = source
  _follow_opts.seq = nil
  runtime_state.set_follow_target_position(state, pid, target_pos, _follow_opts)
end

local function _place_player_unit(pid, unit, target_pos)
  assert(unit.set_position ~= nil, "missing unit.set_position: " .. tostring(pid))
  unit.set_position(target_pos)
end

-- Elimination kills the role in the host (bankruptcy calls role.die()/role.lose()),
-- which removes its avatar and leaves the ctrl unit dead: any host call on that unit
-- fails with "Internal error". Only Lua-side move state is ours to clear here.
local function _hide_eliminated_player(state, player, i)
  local pid = _resolve_player_id(player, i)
  move_anim.clear_player_token(state.board_scene, pid, "board_sync_eliminated")
end

local function _stop_and_log_player_motion(state, pid, unit)
  move_anim.clear_player_token(state.board_scene, pid, "board_sync_place_players")
  return _stop_player_motion(pid, unit, true)
end

local function _log_stop_and_snap(pid, idx, stop_result, target_pos)
  if not _should_debug_log() then return end
  _debug_log(
    "board_refresh_stop_and_snap",
    "player_id=" .. tostring(pid),
    "position=" .. tostring(idx),
    "motion_stop=" .. tostring(stop_result.motion_stop_path or "none"),
    "ai_stop=" .. tostring(stop_result.ai_stop_path or "none"),
    "anim_stop=" .. tostring(stop_result.anim_stop_path or "none"),
    "target_pos=" .. tostring(target_pos)
  )
end

local function _place_single_player(state, player, i, occupants, spacing, min_player_y)
  local idx, base, pid = _resolve_active_player_base(state, player, i)
  assert(state.player_units ~= nil, "missing player_units")
  local unit = assert(state.player_units[pid], "missing player unit: " .. tostring(pid))
  local base_y = assert(base.y, "missing base.y: " .. tostring(idx))
  local y_offset = placement_geometry.calc_y_offset(base_y, min_player_y)
  local list = occupants[idx]
  local slot, count = placement_geometry.resolve_occupant_slot(list, pid)
  local ox, oz = placement_geometry.calc_slot_offset(slot, count, spacing)
  local target_pos = placement_geometry.resolve_target_position(base, y_offset, ox, oz)
  local stop_result = _stop_and_log_player_motion(state, pid, unit)
  _log_stop_and_snap(pid, idx, stop_result, target_pos)
  _place_player_unit(pid, unit, target_pos)
  _publish_follow_target(state, pid, target_pos, "board_sync_snap")
end

function M.place_players(state, players, occupants, spacing, min_player_y)
  for i, player in ipairs(players) do
    assert(player ~= nil, "missing player: " .. tostring(i))
    if not player.eliminated then
      _place_single_player(state, player, i, occupants, spacing, min_player_y)
    else
      _hide_eliminated_player(state, player, i)
    end
  end
end

-- Exported for testing
M.resolve_min_player_y = placement_geometry.resolve_min_player_y
return M

--[[ mutate4lua-manifest
version=4
projectHash=5de252a2604aaa09
scope.0.id=chunk:src/ui/render/board/placement_snap.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=94
scope.0.semanticHash=a0cf9a8a3ec47965
scope.1.id=function:_stop_player_motion
scope.1.kind=function
scope.1.startLine=17
scope.1.endLine=20
scope.1.semanticHash=b4f71c848a722661
scope.2.id=function:_publish_follow_target
scope.2.kind=function
scope.2.startLine=24
scope.2.endLine=28
scope.2.semanticHash=667b6483f8d820a5
scope.3.id=function:_place_player_unit
scope.3.kind=function
scope.3.startLine=30
scope.3.endLine=33
scope.3.semanticHash=77c2bd90e0c1935c
scope.4.id=function:_hide_eliminated_player
scope.4.kind=function
scope.4.startLine=38
scope.4.endLine=41
scope.4.semanticHash=faff9c85a55ae0eb
scope.5.id=function:_stop_and_log_player_motion
scope.5.kind=function
scope.5.startLine=43
scope.5.endLine=46
scope.5.semanticHash=ea96fd4888d9ae9a
scope.6.id=function:_log_stop_and_snap
scope.6.kind=function
scope.6.startLine=48
scope.6.endLine=59
scope.6.semanticHash=33fa32e7d76b9f5b
scope.7.id=function:_place_single_player
scope.7.kind=function
scope.7.startLine=61
scope.7.endLine=75
scope.7.semanticHash=bd17e3a3abf9501b
scope.8.id=function:M.place_players
scope.8.kind=function
scope.8.startLine=77
scope.8.endLine=86
scope.8.semanticHash=39d1ba2e25b31474
]]
