local runtime_constants = require("src.config.gameplay.runtime_constants")
local handlers = require("src.ui.render.anim.handlers")
local board_feedback = require("src.ui.render.board_feedback.service")
local dice_nodes = require("src.ui.schema.dice")

local defaults = {}

local function _timing_or(value, fallback)
  if value ~= nil then
    return value
  end
  return fallback
end

local function _timing()
  return require("src.config.gameplay.timing")
end

function defaults.roll_spin_seconds()
  return _timing_or(_timing().dice_spin_seconds, 1.0)
end

function defaults.roll_face_hold_seconds()
  return _timing_or(_timing().dice_face_hold_seconds, 1.0)
end

local function _ensure_move_effect_direction(anim)
  if anim.direction or anim.steps then
    return anim
  end
  local patched = {}
  for key, value in pairs(anim) do
    patched[key] = value
  end
  patched.direction = runtime_constants.v3_left
  return patched
end

local function _void_delegate(method_name)
  return function(state, anim, duration, opts)
    handlers[method_name](state, anim, duration, opts)
    return duration
  end
end

local function _return_delegate(method_name)
  return function(state, anim, duration, opts)
    return handlers[method_name](state, anim, duration, opts)
  end
end

function defaults.register()
  local registry = require("src.ui.render.anim.registry")
  if registry.resolve("roll") then
    return
  end
  registry.register("roll", function(state, anim, _, opts)
    local roll_spin_seconds = defaults.roll_spin_seconds()
    local roll_face_hold_seconds = defaults.roll_face_hold_seconds()
    handlers.play_roll_dice_screen(state, anim, roll_spin_seconds, roll_face_hold_seconds, {
      runtime = opts and opts.runtime,
      ui_events = opts and opts.ui_events,
      schedule = opts and opts.schedule,
      dice_screen_nodes = dice_nodes,
    })
    return roll_spin_seconds + roll_face_hold_seconds
  end)
  registry.register("roadblock", _void_delegate("play_overlay"))
  registry.register("mine", _void_delegate("play_overlay"))
  registry.register("move_effect", function(state, anim)
    return handlers.play_move_effect(state, _ensure_move_effect_direction(anim))
  end)
  registry.register("teleport_effect", _return_delegate("play_teleport_effect"))
  registry.register("forced_relocation", _return_delegate("play_forced_relocation"))
  registry.register("mine_trigger", _return_delegate("play_mine_trigger"))
  registry.register("roadblock_trigger", _return_delegate("play_roadblock_trigger"))
  registry.register("upgrade_land", function(state, anim, duration, opts)
    board_feedback.play_tile_cue(state, "upgrade_land_smoke", anim.tile_index, {
      player_id = anim.player_id,
      duration = duration,
      use_building_tile_position = true,
    }, opts and opts.runtime_bundle)
    return duration
  end)
  registry.register("cash_receive", function(state, anim, duration, opts)
    board_feedback.play_player_cue(state, "cash_burst", anim.player_id, {
      duration = duration,
      amount = anim.amount,
    }, opts and opts.runtime_bundle)
    return duration
  end)
  registry.register("missile", _void_delegate("play_missile"))
  registry.register("monster", _void_delegate("play_monster"))
  registry.register("clear_obstacles", _void_delegate("play_clear_obstacles"))
end

return defaults

