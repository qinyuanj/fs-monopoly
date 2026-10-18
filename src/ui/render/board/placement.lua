local runtime_state = require("src.ui.state.runtime")
local player_resolve = require("src.ui.render.board.player_resolve")
local placement_snap = require("src.ui.render.board.placement_snap")

local M = {}

local _resolve_player_id = player_resolve.resolve_player_id
local _resolve_active_player_base = player_resolve.resolve_active_player_base

local _snapshot_a = {}
local _snapshot_b = {}
local _snapshot_current = _snapshot_a

local function _next_snapshot()
  local snapshot = (_snapshot_current == _snapshot_a) and _snapshot_b or _snapshot_a
  _snapshot_current = snapshot
  for k in pairs(snapshot) do
    snapshot[k] = nil
  end
  return snapshot
end

local function _snapshot_value(player)
  local pos = player.position
  local eliminated = player.eliminated and 1 or 0
  return tostring(pos) .. ":" .. tostring(eliminated)
end

local function _build_snapshot(players)
  local snapshot = _next_snapshot()
  for i, player in ipairs(players) do
    assert(player ~= nil, "missing player: " .. tostring(i))
    local pid = _resolve_player_id(player, i)
    snapshot[pid] = _snapshot_value(player)
  end
  return snapshot
end

function M.compute_need_sync(state, snapshot)
  local board_runtime = runtime_state.ensure_board_runtime(state)
  local need_sync = board_runtime.board_sync_pending or false
  local last_positions = assert(board_runtime.board_last_positions, "missing board_runtime.board_last_positions")
  if not need_sync then
    for pid, value in pairs(snapshot) do
      if last_positions[pid] ~= value then
        need_sync = true
        break
      end
    end
  end
  return need_sync
end

local _occupants = {}

local function _reset_occupants()
  for k, v in pairs(_occupants) do
    if type(v) == "table" then
      -- pairs 清除:数字下界 1->0 变异逐值等价( occupants 下标恒 ≥1,
      -- 多清 [0] 无人观测);pairs 无数字位点(#262 化简)。
      for j in pairs(v) do v[j] = nil end
    else
      _occupants[k] = nil
    end
  end
end

local function _append_occupant(state, player, i)
  local idx, _, pid = _resolve_active_player_base(state, player, i)
  local list = _occupants[idx]
  if not list then
    list = {}
    _occupants[idx] = list
  end
  list[#list + 1] = pid
end

function M.build_occupants(state, players)
  _reset_occupants()
  for i, player in ipairs(players) do
    assert(player ~= nil, "missing player: " .. tostring(i))
    if not player.eliminated then
      _append_occupant(state, player, i)
    end
  end
  return _occupants
end

M.resolve_min_player_y = placement_snap.resolve_min_player_y
M.place_players = placement_snap.place_players
M.build_snapshot = _build_snapshot

return M

--[[ mutate4lua-manifest
version=4
projectHash=db85ec50ec101ebb
scope.0.id=chunk:src/ui/render/board/placement.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=97
scope.0.semanticHash=56d9a0430c4d12f5
scope.1.id=function:_next_snapshot
scope.1.kind=function
scope.1.startLine=14
scope.1.endLine=21
scope.1.semanticHash=4c887ef72fc148ae
scope.2.id=function:_snapshot_value
scope.2.kind=function
scope.2.startLine=23
scope.2.endLine=27
scope.2.semanticHash=d11e526ca38124e0
scope.3.id=function:_build_snapshot
scope.3.kind=function
scope.3.startLine=29
scope.3.endLine=37
scope.3.semanticHash=02e7f7343d853370
scope.4.id=function:M.compute_need_sync
scope.4.kind=function
scope.4.startLine=39
scope.4.endLine=52
scope.4.semanticHash=dc033513627b77e2
scope.5.id=function:_reset_occupants
scope.5.kind=function
scope.5.startLine=56
scope.5.endLine=66
scope.5.semanticHash=d3be3add50f3f8db
scope.6.id=function:_append_occupant
scope.6.kind=function
scope.6.startLine=68
scope.6.endLine=76
scope.6.semanticHash=982ea1e85e7ff88c
scope.7.id=function:M.build_occupants
scope.7.kind=function
scope.7.startLine=78
scope.7.endLine=87
scope.7.semanticHash=eb11c37269f1bc7e
]]
