local tiles_cfg = require("src.config.content.tiles")
local contiguous_count = require("src.ui.view.contiguous_count")
local tile_rent = require("src.ui.view.tile_rent")

local board_slice = {}
local cached_board_tiles = {}

local _tiles_by_id = {}

for _, cfg in ipairs(tiles_cfg) do
  _tiles_by_id[cfg.id] = cfg
end

local _tile_state_out = {}
local _tile_state_entries = {}
local _count_by_owner = {}
local _rent_by_owner = {}

local function _clear_table(t)
  for k in pairs(t) do t[k] = nil end
end

local function _owner_count_for_tile(owner_id, board, tile_id)
  _count_by_owner[owner_id] = _count_by_owner[owner_id] or contiguous_count.build_for_owner(board, owner_id)
  local count = _count_by_owner[owner_id][tile_id]
  return (count and count > 0) and count or nil
end

local function _owner_rent_for_tile(owner_id, board, tile_id)
  _rent_by_owner[owner_id] = _rent_by_owner[owner_id] or contiguous_count.build_rent_for_owner(board, owner_id, function(tile)
    return tile_rent.for_level(tile, tile and tile.level or 0)
  end)
  local rent = _rent_by_owner[owner_id][tile_id]
  return (rent and rent > 0) and rent or nil
end

local function _update_tile_entry(tile_id, raw, board)
  _tile_state_entries[tile_id] = _tile_state_entries[tile_id] or {}
  local entry = _tile_state_entries[tile_id]
  entry.owner_id = raw.owner_id
  entry.level = raw.level
  entry.contiguous_count = nil
  entry.contiguous_rent = nil
  if raw.owner_id then
    entry.contiguous_count = _owner_count_for_tile(raw.owner_id, board, tile_id)
    entry.contiguous_rent = _owner_rent_for_tile(raw.owner_id, board, tile_id)
  end
  _tile_state_out[tile_id] = entry
end

local function _fill_tile_states(board)
  local lookup = board.tile_lookup or {}
  _clear_table(_tile_state_out)
  _clear_table(_count_by_owner)
  _clear_table(_rent_by_owner)
  for tile_id, raw in pairs(lookup) do _update_tile_entry(tile_id, raw, board) end
end

local function _project_tile_states(game)
  local board = game and game.board or nil
  if not board then return _tile_state_out end
  _fill_tile_states(board)
  return _tile_state_out
end

local _cached_board_path_ref = nil

local function _build_board_tiles(board_path)
  if _cached_board_path_ref == board_path and #cached_board_tiles > 0 then
    return cached_board_tiles
  end
  _cached_board_path_ref = board_path
  local out = {}
  assert(type(board_path) == "table", "missing board path")
  for i, tile in ipairs(board_path) do
    local tile_id = tile and tile.id
    local cfg = _tiles_by_id[tile_id]
    assert(cfg ~= nil, "missing tile cfg: " .. tostring(tile_id))
    out[i] = {
      id = tile_id,
      name = cfg.name,
      type = cfg.type,
      price = cfg.price,
      row = cfg.row,
      col = cfg.col,
    }
  end
  return out
end

local function _build_overlays(env)
  assert(env ~= nil and env.game ~= nil and env.game.board ~= nil and env.game.board.get_overlays ~= nil,
    "missing board overlays")
  return env.game.board:get_overlays()
end

function board_slice.tile_count()
  return #cached_board_tiles
end

local function _populate_board(target, board_tiles, game, env, turn)
  target.tiles = board_tiles
  target.tile_states = _project_tile_states(game)
  target.overlays = _build_overlays(env)
  target.players = game.players
  target.phase = turn.phase
  target.move_anim = turn.move_anim
  target.action_anim = turn.action_anim
  target.move_followup_pending = turn.move_followup_pending == true
  target.turn_start_prompt_seq = turn.turn_start_prompt_seq or 0
  target.turn_start_prompt_player_id = turn.turn_start_prompt_player_id
  target.tile_count = #board_tiles
  return target
end

function board_slice.update(board, game, env, turn)
  local board_path = assert(game and game.board and game.board.path, "missing game.board.path")
  local board_tiles = _build_board_tiles(board_path)
  cached_board_tiles = board_tiles
  return _populate_board(board or {}, board_tiles, game, env, turn)
end

function board_slice.build(game, env, turn)
  return board_slice.update(nil, game, env, turn)
end

return board_slice

