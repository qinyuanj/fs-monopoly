-- Pure status resolution for the 3D player-status overlay: given a game/player,
-- decide which status key is active and the remaining-turn count to display.
-- Transient-state detection lives in status_signals; this module maps those
-- signals plus location/deity state onto a status key. Kept free of
-- scene/cache/specs dependencies so it stays unit-testable in isolation (the
-- scene-sync side lives in src.ui.render.status3d.status).
local signals = require("src.ui.render.status3d.status_signals")

local M = {}

local _deity_status_map = {
  poor = "poor",
  rich = "rich",
  angel = "angel",
}

local _location_effect_status = {
  hospital = "hospital",
  mountain = "mountain",
}

local function _location_effect_active(game, player, status)
  if (status.stay_turns or 0) > 0 or status.pending_location_effect ~= nil then
    return true
  end
  return signals.is_player_detained_this_turn(game, player)
end

local function _tile_location_status(board, position)
  if not board or not board.get_tile then
    return nil
  end
  local tile = board:get_tile(position)
  local tile_type = tile and tile.type or nil
  return _location_effect_status[tile_type]
end

local function _resolve_location_status(game, player, status)
  if not _location_effect_active(game, player, status) then
    return nil
  end
  local expected = _tile_location_status(game.board, player.position)
  if not expected then
    return nil
  end
  local pending = status.pending_location_effect
  if pending ~= nil and pending ~= expected then
    return nil
  end
  return expected
end

local function _resolve_deity_status(status)
  local deity = status.deity
  if not deity then
    return nil
  end
  if (deity.remaining or 0) <= 0 then
    return nil
  end
  return _deity_status_map[deity.type]
end

local function _resolve_stay_turns_remaining(game, player)
  local stay_turns = player.status and player.status.stay_turns or 0
  -- 扣留剩余回合 uses the 含当前回合 (inclusive) convention. During the player's
  -- own frozen turn the stay_turns counter has already decremented at turn start, so the
  -- inclusive remaining is +1 - the same number the detention tip shows, and never 0 while
  -- detained. Between turns (and at landing) the raw counter already is the inclusive value.
  if signals.is_player_detained_this_turn(game, player) then
    return stay_turns + 1
  end
  return stay_turns
end

local function _resolve_deity_remaining(player)
  local deity = player.status and player.status.deity
  if not deity then
    return 0
  end
  local remaining = deity.remaining or 0
  local cap = player.deity_duration_turns
  if cap then
    return math.min(remaining, cap)
  end
  return remaining
end

local function _resolve_secondary_status_key(game, player, status, has_roadblock)
  local location = _resolve_location_status(game, player, status)
  if location then
    return location
  end
  if has_roadblock then
    return "roadblock"
  end
  return _resolve_deity_status(status)
end

local function _last_turn(game)
  return game and game.last_turn or nil
end

local function _pending_roadblock(game, player, has_roadblock)
  return has_roadblock and signals.has_pending_roadblock_trigger(game, player)
end

function M.resolve_player_status_key(game, player)
  if player == nil or player.eliminated == true then
    return nil
  end
  local status = player.status or {}
  local has_roadblock = signals.check_roadblock_status(_last_turn(game), player)
  if _pending_roadblock(game, player, has_roadblock) then
    return "roadblock"
  end
  return _resolve_secondary_status_key(game, player, status, has_roadblock)
end

function M.resolve_remaining_value(game, player, remaining_field)
  if remaining_field == "stay_turns" then
    return _resolve_stay_turns_remaining(game, player)
  end
  if remaining_field == "deity_remaining" then
    return _resolve_deity_remaining(player)
  end
  return 0
end

return M

--[[ mutate4lua-manifest
version=4
projectHash=c2ec2712f2984ac7
scope.0.id=chunk:src/ui/render/status3d/status_resolve.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=131
scope.0.semanticHash=0076fb3f96d7315d
scope.1.id=function:_location_effect_active
scope.1.kind=function
scope.1.startLine=22
scope.1.endLine=27
scope.1.semanticHash=acede092a4ea2b26
scope.2.id=function:_tile_location_status
scope.2.kind=function
scope.2.startLine=29
scope.2.endLine=36
scope.2.semanticHash=e4b73fb2a5334d23
scope.3.id=function:_resolve_location_status
scope.3.kind=function
scope.3.startLine=38
scope.3.endLine=51
scope.3.semanticHash=888721223ed4e366
scope.4.id=function:_resolve_deity_status
scope.4.kind=function
scope.4.startLine=53
scope.4.endLine=62
scope.4.semanticHash=713210529ec0f893
scope.5.id=function:_resolve_stay_turns_remaining
scope.5.kind=function
scope.5.startLine=64
scope.5.endLine=74
scope.5.semanticHash=d79faf8728e2014d
scope.6.id=function:_resolve_deity_remaining
scope.6.kind=function
scope.6.startLine=76
scope.6.endLine=87
scope.6.semanticHash=159ff5c3b210d1b3
scope.7.id=function:_resolve_secondary_status_key
scope.7.kind=function
scope.7.startLine=89
scope.7.endLine=98
scope.7.semanticHash=bee64cebe69e5e27
scope.8.id=function:_last_turn
scope.8.kind=function
scope.8.startLine=100
scope.8.endLine=102
scope.8.semanticHash=616a2ca60599c94f
scope.9.id=function:_pending_roadblock
scope.9.kind=function
scope.9.startLine=104
scope.9.endLine=106
scope.9.semanticHash=2769313fd47f7bbb
scope.10.id=function:M.resolve_player_status_key
scope.10.kind=function
scope.10.startLine=108
scope.10.endLine=118
scope.10.semanticHash=015fe2a5bb6738a7
scope.11.id=function:M.resolve_remaining_value
scope.11.kind=function
scope.11.startLine=120
scope.11.endLine=128
scope.11.semanticHash=b778d5b7533a7a6b
]]
