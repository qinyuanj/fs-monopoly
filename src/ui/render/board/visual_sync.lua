local tile_sync = require("src.ui.render.board.visual_sync_tile")
local overlay_sync = require("src.ui.render.board.visual_sync_overlay")
local batch_sync = require("src.ui.render.board.visual_sync_batch")

local visual_sync = {}

visual_sync.sync_tile_visual = tile_sync.sync_tile_visual
visual_sync.sync_overlay_visual = overlay_sync.sync_overlay_visual
visual_sync.sync_many = batch_sync.sync_many

return visual_sync

