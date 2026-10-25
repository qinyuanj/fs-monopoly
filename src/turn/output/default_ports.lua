local agent = require("src.computer.agent")
local control = require("src.player.control")

local default_ports = {}

local function _build_missing_port(current, builder)
  if type(current) == "table" then
    return current
  end
  return builder()
end

local function _build_auto_play_port()
  return {
    is_computer_controlled = function(_, player)
      return control.is_computer_controlled(player)
    end,
    pick_target_player = function(game, player, item_id, candidates)
      return agent.pick_target_player(game, player, item_id, candidates)
    end,
    pick_remote_dice_value = function(game, player, dice_count)
      return agent.pick_remote_dice_value(game, player, dice_count)
    end,
    pick_roadblock_target = function(game, player, _candidates)
      return agent.pick_roadblock_target(game, player)
    end,
    auto_action_for_choice = function(game, choice)
      return agent.auto_action_for_choice(game, choice)
    end,
  }
end

local function _install_defaults(target)
  target.auto_play_port = _build_missing_port(target.auto_play_port, _build_auto_play_port)
  return target
end

function default_ports.resolve_game_opts(opts)
  return _install_defaults(opts or {})
end

function default_ports.install(game)
  if type(game) ~= "table" then
    return game
  end
  return _install_defaults(game)
end

return default_ports

