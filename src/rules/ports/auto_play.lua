local auto_play = {}
local contract_helper = require("src.rules.ports.contract_helper")

function auto_play.is_computer_controlled(game, player)
  return contract_helper.call_required_method(game, "auto_play_port", "auto_play_port", "is_computer_controlled", game, player) == true
end

function auto_play.pick_target_player(game, player, item_id, candidates)
  return contract_helper.call_required_method(game, "auto_play_port", "auto_play_port", "pick_target_player", game, player, item_id, candidates)
end

function auto_play.pick_remote_dice_value(game, player, dice_count)
  return contract_helper.call_required_method(game, "auto_play_port", "auto_play_port", "pick_remote_dice_value", game, player, dice_count)
end

function auto_play.pick_roadblock_target(game, player, candidates)
  return contract_helper.call_required_method(game, "auto_play_port", "auto_play_port", "pick_roadblock_target", game, player, candidates)
end

function auto_play.auto_action_for_choice(game, choice)
  return contract_helper.call_required_method(game, "auto_play_port", "auto_play_port", "auto_action_for_choice", game, choice)
end

return auto_play

