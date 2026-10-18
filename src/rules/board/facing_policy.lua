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

--[[ mutate4lua-manifest
version=4
projectHash=41fa279aa3b4d315
scope.0.id=chunk:src/rules/board/facing_policy.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=143
scope.0.semanticHash=6573f975f00e77bc
scope.1.id=function:_player_move_dir
scope.1.kind=function
scope.1.startLine=24
scope.1.endLine=27
scope.1.semanticHash=93c839897afe61e5
scope.2.id=function:_set_move_dir
scope.2.kind=function
scope.2.startLine=29
scope.2.endLine=36
scope.2.semanticHash=42c742c5b151733b
scope.3.id=function:_require_sync_context
scope.3.kind=function
scope.3.startLine=38
scope.3.endLine=42
scope.3.semanticHash=5fe2c6e4f2dda52c
scope.4.id=function:_validate_sync_args
scope.4.kind=function
scope.4.startLine=44
scope.4.endLine=49
scope.4.semanticHash=ef6341df2abe82b3
scope.5.id=function:_sync_clear_mode
scope.5.kind=function
scope.5.startLine=51
scope.5.endLine=54
scope.5.semanticHash=c776f76ae325c079
scope.6.id=function:_resolve_tile_move_dir
scope.6.kind=function
scope.6.startLine=56
scope.6.endLine=60
scope.6.semanticHash=a79fde3dfa7150e8
scope.7.id=function:_sync_forced_move_mode
scope.7.kind=function
scope.7.startLine=62
scope.7.endLine=71
scope.7.semanticHash=d530b413e79bd461
scope.8.id=function:facing_policy.sync_move_dir_after_position_change
scope.8.kind=function
scope.8.startLine=73
scope.8.endLine=84
scope.8.semanticHash=fb21e001f6efb1d5
scope.9.id=function:_has_skip_entry_context
scope.9.kind=function
scope.9.startLine=86
scope.9.endLine=89
scope.9.semanticHash=191f210b289e7fa4
scope.10.id=function:_skip_flag_set
scope.10.kind=function
scope.10.startLine=91
scope.10.endLine=94
scope.10.semanticHash=918a9221cfb35ccc
scope.11.id=function:_is_entry_tile
scope.11.kind=function
scope.11.startLine=96
scope.11.endLine=99
scope.11.semanticHash=20210900405ab08b
scope.12.id=function:facing_policy.should_skip_inner_entry
scope.12.kind=function
scope.12.startLine=101
scope.12.endLine=109
scope.12.semanticHash=81f607c67fb28abe
scope.13.id=function:_resume_forward_facing
scope.13.kind=function
scope.13.startLine=111
scope.13.endLine=114
scope.13.semanticHash=a6ae24b9cc2ff6c2
scope.14.id=function:_relative_facing
scope.14.kind=function
scope.14.startLine=116
scope.14.endLine=121
scope.14.semanticHash=211bb7acdc800ab2
scope.15.id=function:facing_policy.resolve_initial_facing
scope.15.kind=function
scope.15.startLine=123
scope.15.endLine=136
scope.15.semanticHash=22f067f35014d1d8
]]
