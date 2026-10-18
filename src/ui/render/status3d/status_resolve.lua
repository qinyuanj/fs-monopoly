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

