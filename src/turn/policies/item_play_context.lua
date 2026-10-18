local auto_play_port = require("src.rules.ports.auto_play")
local control = require("src.player.control")

local item_auto_play_context = {}

local function _is_computer_controlled(player)
  return player and control.is_computer_controlled(player) == true or false
end

function item_auto_play_context.build(game, player, context)
  local ctx = context or {}
  local is_computer_controlled = _is_computer_controlled(player)
  ctx.is_computer_controlled = is_computer_controlled

  if not is_computer_controlled then
    return ctx
  end

  if type(ctx.select_target_player) ~= "function" then
    ctx.select_target_player = function(item_id, candidates)
      return auto_play_port.pick_target_player(game, player, item_id, candidates)
    end
  end

  if type(ctx.select_remote_dice) ~= "function" then
    ctx.select_remote_dice = function(dice_count)
      return auto_play_port.pick_remote_dice_value(game, player, dice_count)
    end
  end

  return ctx
end

return item_auto_play_context

