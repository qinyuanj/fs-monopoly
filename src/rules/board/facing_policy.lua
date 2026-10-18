local facing_policy = {}
local market_default_move_dir = "right"

local valid_modes = {
  fresh_forward = true,
  resume_forward = true,
  relative_forward = true,
  relative_backward = true,
}

local valid_sync_modes = {
  clear = true,
  preserve = true,
  forced_move = true,
}

-- tile types that clear move_dir on relocation; market forces a fixed direction
local _tile_type_move_dir = {
  hospital = false,
  mountain = false,
  market = market_default_move_dir,
}

local function _player_move_dir(player)
  local status = player and player.status or nil
  return status and status.move_dir or nil
end

local function _set_move_dir(game, player, value)
  assert(game ~= nil and type(game.set_player_status) == "function", "missing game.set_player_status")
  if _player_move_dir(player) == value then
    return false
  end
  game:set_player_status(player, "move_dir", value)
  return true
end

local function _require_sync_context(game, player, current_index)
  assert(game ~= nil, "missing game")
  assert(player ~= nil, "missing player")
  assert(current_index ~= nil, "missing current_index")
end

local function _validate_sync_args(game, player, current_index, mode)
  _require_sync_context(game, player, current_index)
  mode = mode or "preserve"
  assert(valid_sync_modes[mode] == true, "invalid move_dir sync mode: " .. tostring(mode))
  return mode
end

local function _sync_clear_mode(game, player)
  _set_move_dir(game, player, nil)
  return game:set_player_status(player, "skip_next_inner_entry", false)
end

local function _resolve_tile_move_dir(game, current_index)
  local board = assert(game.board, "missing game.board")
  local tile = assert(board:get_tile(current_index), "missing tile: " .. tostring(current_index))
  return _tile_type_move_dir[tile.type]
end

local function _sync_forced_move_mode(game, player, current_index)
  local override = _resolve_tile_move_dir(game, current_index)
  if override == false then
    return _set_move_dir(game, player, nil)
  end
  if override then
    return _set_move_dir(game, player, override)
  end
  return _set_move_dir(game, player, _player_move_dir(player))
end

function facing_policy.sync_move_dir_after_position_change(game, player, current_index, mode)
  -- Centralize move_dir updates for teleports/relocations so special handlers
  -- don't each re-encode board-facing rules.
  mode = _validate_sync_args(game, player, current_index, mode)
  if mode == "clear" then
    return _sync_clear_mode(game, player)
  end
  if mode == "preserve" then
    return _set_move_dir(game, player, _player_move_dir(player))
  end
  return _sync_forced_move_mode(game, player, current_index)
end

local function _has_skip_entry_context(board, player)
  return board ~= nil and board.map ~= nil and board.map.entry_points ~= nil
    and player ~= nil and player.position ~= nil
end

local function _skip_flag_set(player)
  local status = player.status or nil
  return status ~= nil and status.skip_next_inner_entry == true
end

local function _is_entry_tile(board, player)
  local tile = board:get_tile(player.position)
  return tile ~= nil and board.map.entry_points[tile.id] ~= nil
end

function facing_policy.should_skip_inner_entry(board, player)
  if not _has_skip_entry_context(board, player) then
    return false
  end
  if not _skip_flag_set(player) then
    return false
  end
  return _is_entry_tile(board, player)
end

local function _resume_forward_facing(opts)
  assert(opts.direction ~= nil, "resume_forward requires opts.direction")
  return opts.direction
end

local function _relative_facing(player, opts)
  if opts.direction ~= nil then
    return opts.direction
  end
  return _player_move_dir(player)
end

function facing_policy.resolve_initial_facing(mode, player, opts)
  opts = opts or {}
  assert(valid_modes[mode] == true, "invalid facing mode: " .. tostring(mode))

  if mode == "fresh_forward" then
    return nil
  end

  if mode == "resume_forward" then
    return _resume_forward_facing(opts)
  end

  return _relative_facing(player, opts)
end

return facing_policy

