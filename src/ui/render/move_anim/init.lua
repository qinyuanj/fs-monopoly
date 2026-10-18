local playback = require("src.ui.render.move_anim.playback")
local stop = require("src.ui.render.move_anim.stop")

local move_anim = {}

move_anim.step_duration             = playback.step_duration
move_anim.one_step                  = playback.one_step
move_anim.play_sequence             = function(board_scene, anim_ctx)
  return playback.play_sequence(board_scene, anim_ctx, move_anim)
end
move_anim.play_teleport             = stop.play_teleport
move_anim.snap_player_to_index      = stop.snap_player_to_index
move_anim.prepare_player_for_snap   = stop.prepare_player_for_snap
move_anim.stop_player_presentation  = stop.stop_player_presentation
move_anim.clear_player_token        = stop.clear_player_token
move_anim.has_active_stop_context   = stop.has_active_stop_context

return move_anim

