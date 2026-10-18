local property_query = {}

function property_query.safe_tile_state(game, tile)
  if not (game and tile and tile.type == "land") then
    return { owner_id = nil, level = 0 }
  end
  return { owner_id = tile.owner_id, level = tile.level or 0 }
end

local function _state_for(game, tile, state_fn)
  local state = property_query.safe_tile_state(game, tile)
  if state_fn then
    state = state_fn(game, tile)
  end
  return state
end

function property_query.resolve_rent_owner(game, tile, state_fn)
  local state = _state_for(game, tile, state_fn)

  local owner = nil
  if state.owner_id then
    owner = game:find_player_by_id(state.owner_id)
  end
  if not owner or owner.eliminated then
    game:set_tile_owner(tile, nil)
    return nil, state, nil
  end
  if game:player_is_in_mountain(owner) then
    return nil, state, { reason = "mountain", owner = owner }
  end
  return owner, state, nil
end

return property_query

