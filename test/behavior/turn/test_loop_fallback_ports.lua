local check = require("luassert")
local gameplay_loop = require("src.turn.loop.init")
local choice_auto_policy = require("src.turn.policies.choice_auto")
local turn_default_ports = require("src.turn.output.default_ports")

describe("TestLoopFallbackPorts", function()

it("test_installs_complete_no_op_port_contracts", function()
  local game = {
    players = { { id = 1 } },
    turn = { current_player_index = 1 },
    dirty = {},
  }

  gameplay_loop._M_test.ensure_fallback_ports(game)

  check.same(type(game.auto_play_port.is_computer_controlled), "function")
  check.same(type(game.auto_play_port.auto_action_for_choice), "function")
  check.same(type(game.auto_play_port.pick_target_player), "function")
  check.same(type(game.auto_play_port.pick_remote_dice_value), "function")
  check.same(type(game.auto_play_port.pick_roadblock_target), "function")
  check.is_nil(game.bankruptcy_port, "回合兜底不再装破产端口(#208)")

  local ok, action = pcall(choice_auto_policy.decide, game, nil, {
    id = "choice_1",
    options = { { id = "first" } },
  }, {
    allow_first_option_fallback = true,
  })

  check.is_true(ok)
  check.same(action and action.type, "choice_select")
  check.same(action and action.option_id, "first")
end)

it("test_installs_missing_ports_onto_an_existing_game_table_in_place", function()
  local game = { players = {} }

  local installed = turn_default_ports.install(game)

  check.same(installed, game, "install 应就地返回同一张 game 表")
  check.same(type(game.auto_play_port.is_computer_controlled), "function")
  check.same(type(game.auto_play_port.auto_action_for_choice), "function")
  check.is_nil(game.bankruptcy_port, "回合输出默认端口不再构建破产端口(#208)")
end)

it("test_keeps_ports_the_caller_already_provided", function()
  local auto_play_port = { is_computer_controlled = function() return true end }
  local game = { auto_play_port = auto_play_port }

  turn_default_ports.install(game)

  check.same(game.auto_play_port, auto_play_port, "已注入的 auto_play_port 不应被顶掉")
end)

it("test_passes_non_table_arguments_through_untouched", function()
  check.same(turn_default_ports.install(nil), nil)
  check.same(turn_default_ports.install(false), false)
  check.same(turn_default_ports.install("not_a_game"), "not_a_game")
end)


end)
