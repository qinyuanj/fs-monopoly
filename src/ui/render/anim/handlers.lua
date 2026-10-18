local dice = require("src.ui.render.anim.dice")
local units = require("src.ui.render.anim.units")

local handlers = {}

function handlers.play_roll_dice_screen(state, anim, duration, hold_seconds, opts)
  dice.play_roll_dice_screen(anim, duration, hold_seconds, opts)
end

handlers.play_overlay = units.play_overlay
handlers.play_missile = units.play_missile
handlers.play_monster = units.play_monster
handlers.play_clear_obstacles = units.play_clear_obstacles
handlers.play_move_effect = units.play_move_effect
handlers.play_teleport_effect = units.play_teleport_effect
handlers.play_forced_relocation = units.play_forced_relocation
handlers.play_mine_trigger = units.play_mine_trigger
handlers.play_roadblock_trigger = units.play_roadblock_trigger
handlers.build_tip = units.build_tip
handlers.clear_overlay = units.clear_overlay

return handlers

