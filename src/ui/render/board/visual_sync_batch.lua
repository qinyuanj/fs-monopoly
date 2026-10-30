local shared = require("src.ui.render.board.visual_sync_shared")
local tables = require("src.foundation.tables")
local tile_sync = require("src.ui.render.board.visual_sync_tile")
local overlay_sync = require("src.ui.render.board.visual_sync_overlay")

local visual_sync_batch = {}

local function _append_unique(raw_list, out, seen)
  for _, value in ipairs(raw_list) do
    if value ~= nil and not seen[value] then
      seen[value] = true
      out[#out + 1] = value
    end
  end
end

local function _dedupe_into(raw_list, out, seen)
  tables.clear(out)
  tables.clear(seen)
  if type(raw_list) == "table" then
    _append_unique(raw_list, out, seen)
  end
  return out
end

local _norm_tiles = {}
local _norm_tiles_seen = {}
local _norm_overlays = {}
local _norm_overlays_seen = {}
local _norm_owners = {}
local _norm_owners_seen = {}
local _normalized = { tile_ids = _norm_tiles, overlay_indices = _norm_overlays, affected_owner_ids = _norm_owners }

local function _normalize_payload(payload)
  payload = payload or {}
  _normalized.tile_ids = _dedupe_into(payload.tile_ids, _norm_tiles, _norm_tiles_seen)
  _normalized.overlay_indices = _dedupe_into(payload.overlay_indices, _norm_overlays, _norm_overlays_seen)
  _normalized.affected_owner_ids = _dedupe_into(payload.affected_owner_ids, _norm_owners, _norm_owners_seen)
  return _normalized
end

local _expand_owner_set = {}
local _expand_tile_ids = {}

local function _build_owner_set(owner_ids)
  tables.clear(_expand_owner_set)
  for _, owner_id in ipairs(owner_ids) do
    _expand_owner_set[owner_id] = true
  end
  return _expand_owner_set
end

local function _is_owned_land_tile(tile, owner_set)
  return tile and tile.type == "land" and tile.owner_id and owner_set[tile.owner_id]
end

local function _collect_owned_land_tiles(path, owner_set, out)
  for _, tile in ipairs(path) do
    if _is_owned_land_tile(tile, owner_set) then
      out[#out + 1] = tile.id
    end
  end
  return out
end

local function _expand_affected_tiles(state, owner_ids)
  tables.clear(_expand_tile_ids)
  -- owner_ids 恒为 table(_normalize_payload 经 _dedupe_into 归一),`not owner_ids`
  -- 是死防御——or->and 变异体在空表下殊途同归不可杀(#262 删除)。
  if #owner_ids == 0 then
    return _expand_tile_ids
  end
  local board = shared.resolve_board(state)
  if not (board and type(board.path) == "table") then
    return _expand_tile_ids
  end
  local owner_set = _build_owner_set(owner_ids)
  return _collect_owned_land_tiles(board.path, owner_set, _expand_tile_ids)
end

local _sync_seen = {}

local function _sync_tile_dedup(state, tile_ids)
  local handled = false
  for _, tile_id in ipairs(tile_ids) do
    if tile_id ~= nil and not _sync_seen[tile_id] then
      _sync_seen[tile_id] = true
      if tile_sync.sync_tile_visual(state, tile_id) then handled = true end
    end
  end
  return handled
end

local function _sync_overlays(state, indices)
  local handled = false
  for _, board_index in ipairs(indices) do
    if overlay_sync.sync_overlay_visual(state, board_index) then
      handled = true
    end
  end
  return handled
end

function visual_sync_batch.sync_many(state, payload)
  local normalized = _normalize_payload(payload)
  tables.clear(_sync_seen)
  local handled = _sync_tile_dedup(state, normalized.tile_ids)
  if _sync_tile_dedup(state, _expand_affected_tiles(state, normalized.affected_owner_ids)) then
    handled = true
  end
  if _sync_overlays(state, normalized.overlay_indices) then
    handled = true
  end
  return handled
end

return visual_sync_batch

