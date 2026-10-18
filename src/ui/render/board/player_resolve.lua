local M = {}

function M.resolve_player_id(player, i)
  return assert(player.id, "missing player id: " .. tostring(i))
end

function M.resolve_active_player_base(state, player, i)
  local idx = assert(player.position, "missing player position: " .. tostring(i))
  assert(state.tile_positions ~= nil, "missing tile_positions")
  local base = assert(state.tile_positions[idx], "missing tile_position: " .. tostring(idx))
  local pid = M.resolve_player_id(player, i)
  return idx, base, pid
end

return M

