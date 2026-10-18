local dirty_tracker = require("src.state.dirty_tracker")
local logger = require("src.foundation.log")

local game_state_tiles = {}

local function _bump_land_rent_version(self)
  self._land_rent_version = (self._land_rent_version or 0) + 1
end

local function _mark_board(self)
  dirty_tracker.mark(self.dirty, "board_tiles")
end

-- Returns the port only when it can actually sync; nil means "no visual feedback wired".
local function _resolve_board_visual_feedback_port(self)
  local board_visual_feedback_port = self.board_visual_feedback_port
  if type(board_visual_feedback_port) == "table" and type(board_visual_feedback_port.sync_many) == "function" then
    return board_visual_feedback_port
  end
  return nil
end

-- #551:同步失败留痕按「game 实例 × 失败类别」去重——坏装配下 tile 高频路径
-- 不刷屏,且 sink 不跨 game 泄漏。handled==false(no-op port / 无事可同步)是
-- headless 合法日常,不在此留痕。
local function _warn_sync_failure_once(self, key, ...)
  local sink = self._board_visual_sync_warned
  if sink == nil then
    sink = {}
    self._board_visual_sync_warned = sink
  end
  logger.log_once(sink, "warn", key, ...)
end

local function _sync_board_visual(self, payload)
  if not self then
    return false
  end
  local board_visual_feedback_port = _resolve_board_visual_feedback_port(self)
  if board_visual_feedback_port == nil then
    _warn_sync_failure_once(self, "no_port",
      "[board_state] visual sync dropped: board_visual_feedback_port not wired")
    return false
  end
  local ok, result = pcall(board_visual_feedback_port.sync_many, self, payload)
  if not ok then
    _warn_sync_failure_once(self, "sync_error",
      "[board_state] visual sync dropped: sync_many threw: " .. tostring(result))
    return false
  end
  return result == true
end

local function _notifier_of(self)
  return self and self.tile_owner_notifier or nil
end

local function _notify_owner_changed(notifier, tile_id, owner_id)
  if notifier and type(notifier.notify_owner_changed) == "function" then
    notifier:notify_owner_changed(tile_id, owner_id)
    return true
  end
  return false
end

local function _on_owner_changed(notifier, tile_id, owner_id)
  if notifier and type(notifier.on_tile_owner_changed) == "function" then
    notifier:on_tile_owner_changed(tile_id, owner_id)
    return true
  end
  return false
end

local function _notify_tile_owner_changed(self, tile_id, owner_id)
  local notifier = _notifier_of(self)
  if _notify_owner_changed(notifier, tile_id, owner_id) then
    return true
  end
  return _on_owner_changed(notifier, tile_id, owner_id)
end

local function _update_tile(self, tile, updates)
  assert(tile ~= nil and tile.type == "land", "invalid tile for update")
  for key, value in pairs(updates) do
    tile[key] = value
  end
  _mark_board(self)
end

local function _collect_affected_owner_ids(...)
  local out = {}
  local seen = {}
  for i = 1, select("#", ...) do
    local owner_id = select(i, ...)
    if owner_id ~= nil and not seen[owner_id] then
      seen[owner_id] = true
      out[#out + 1] = owner_id
    end
  end
  return out
end

function game_state_tiles.set_tile_owner(self, tile, owner_id)
  assert(tile ~= nil and tile.type == "land", "invalid tile for owner")
  local previous_owner_id = tile.owner_id
  _bump_land_rent_version(self)
  _update_tile(self, tile, { owner_id = owner_id })
  _notify_tile_owner_changed(self, tile.id, owner_id)
  _sync_board_visual(self, {
    tile_ids = { tile.id },
    affected_owner_ids = _collect_affected_owner_ids(previous_owner_id, owner_id),
  })
end

function game_state_tiles.set_tile_level(self, tile, level)
  _bump_land_rent_version(self)
  _update_tile(self, tile, { level = level })
  if tile and tile.id ~= nil then
    _sync_board_visual(self, {
      tile_ids = { tile.id },
      affected_owner_ids = _collect_affected_owner_ids(tile.owner_id),
    })
  end
end

function game_state_tiles.reset_tile(self, tile)
  assert(tile ~= nil and tile.type == "land", "invalid tile for reset")
  local previous_owner_id = tile.owner_id
  _bump_land_rent_version(self)
  tile.owner_id = nil
  tile.level = 0
  _mark_board(self)
  _notify_tile_owner_changed(self, tile.id, nil)
  _sync_board_visual(self, {
    tile_ids = { tile.id },
    affected_owner_ids = _collect_affected_owner_ids(previous_owner_id),
  })
end

local function _delegate_overlay(self, board_method, index, ...)
  assert(self ~= nil and self.board ~= nil, "missing board")
  self.board[board_method](self.board, index, ...)
  _mark_board(self)
  _sync_board_visual(self, { overlay_indices = { index } })
end

function game_state_tiles.place_roadblock(self, index)
  _delegate_overlay(self, "place_roadblock", index)
end

function game_state_tiles.clear_roadblock(self, index)
  _delegate_overlay(self, "clear_roadblock", index)
end

function game_state_tiles.place_mine(self, index, data)
  _delegate_overlay(self, "place_mine", index, data)
end

function game_state_tiles.clear_mine(self, index)
  _delegate_overlay(self, "clear_mine", index)
end

function game_state_tiles.clear_all_overlays(self, index)
  _delegate_overlay(self, "clear_all", index)
end

return game_state_tiles

