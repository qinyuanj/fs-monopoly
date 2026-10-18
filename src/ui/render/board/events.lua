local visual_sync = require("src.ui.render.board.visual_sync")

local M = {}

local function _sync_single_tile(state, tile_id)
  if tile_id == nil then
    return false
  end
  return visual_sync.sync_many(state, {
    tile_ids = { tile_id },
  })
end

function M.on_tile_upgraded(state, tile_id, _)
  return _sync_single_tile(state, tile_id)
end

function M.on_tile_owner_changed(state, tile_id, _)
  return _sync_single_tile(state, tile_id)
end

M.sync_many = visual_sync.sync_many

return M

