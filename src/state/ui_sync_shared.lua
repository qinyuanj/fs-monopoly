local shared = {}
local _cached_env = {}

local function _turn_countdown_only(dirty)
  return dirty ~= nil and dirty.turn_countdown == true
end

local function _has_other_dirty(dirty)
  return dirty.players or dirty.board_tiles or dirty.turn or dirty.market or dirty.ui
end

local function _has_inventory_dirty(dirty)
  return dirty.inventory == true
end

function shared.is_only_turn_countdown(dirty)
  if not _turn_countdown_only(dirty) then
    return false
  end
  if _has_other_dirty(dirty) then
    return false
  end
  return not _has_inventory_dirty(dirty)
end

local function _game_field(game, key)
  return game and game[key] or nil
end

local function _winner_name(game, winner)
  return game and (game.winner_names or (winner and winner.name)) or nil
end

function shared.build_ui_env(state, game)
  local winner = _game_field(game, "winner")
  local winner_name = _winner_name(game, winner)
  _cached_env.game = game
  _cached_env.ui_state = state
  _cached_env.last_turn = _game_field(game, "last_turn")
  _cached_env.finished = _game_field(game, "finished")
  _cached_env.winner_name = winner_name
  return _cached_env
end

return shared

