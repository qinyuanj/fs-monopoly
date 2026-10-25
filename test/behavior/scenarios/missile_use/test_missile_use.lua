require("test.bootstrap").install_package_paths()
-- luacheck: ignore 143 (busted injects the verified luassert object)
local luassert = assert
local support = require("test.support.shared_support")
local config_reset = require("test.support.config_reset")
local inventory = require("src.rules.items.inventory")
local item_ids = require("src.config.gameplay.item_ids")
local use_flow = require("src.rules.items.use_flow")
local choice_resolver = require("src.rules.choice.resolver")
local move_followup = require("src.turn.phases.move_followup")

local function new_strike(cash)
  local game = support.new_game()
  local user, target = game.players[1], game.players[2]
  user.inventory:clear()
  game:set_player_cash(user, cash)
  game:set_player_cash(target, 20000)
  game:update_player_position(user, 4)
  game:update_player_position(target, 4)
  user.inventory:add({ id = item_ids.missile })
  user.inventory:add({ id = item_ids.missile })
  user.inventory:add({ id = item_ids.mine })
  return game, user, target
end

local function select_target(game, user, target)
  local begin = use_flow.begin_item_use(game, user.id, item_ids.missile, { phase = "post_action" })
  luassert.is.equal("waiting_choice", begin.status)
  luassert.is_false(begin.item_consumed)
  local choice = support.open_choice(game, begin.choice_spec)
  return use_flow.resolve_item_use_choice(game, choice, {
    type = "choice_select", choice_id = choice.id, player_id = user.id, option_id = target.id,
  })
end

describe("missile use with a co-located user (#118)", function()
  before_each(function() config_reset.reset_all() end)

  it("finishes a strike even when the user's hospital bill causes bankruptcy", function()
    local game, user, target = new_strike(500)

    local result = select_target(game, user, target)

    luassert.is_true(result.ok)
    luassert.is_true(result.item_consumed)
    luassert.is_true(user.eliminated)
    luassert.is.equal(0, inventory.count(user))
    luassert.is_false(target.eliminated)
    luassert.is.equal(15000, game:player_cash(target))
    luassert.is.equal(game.board:find_first_by_type("hospital"), target.position)
    luassert.is.equal(2, game:detention_remaining(target))
  end)

  it("consumes exactly one missile and charges both co-located survivors", function()
    local game, user, target = new_strike(20000)

    local result = select_target(game, user, target)

    luassert.is_true(result.ok)
    luassert.is_true(result.item_consumed)
    luassert.is.equal(1, support.count_item(user, item_ids.missile))
    luassert.is.equal(1, support.count_item(user, item_ids.mine))
    luassert.is.equal(15000, game:player_cash(user))
    luassert.is.equal(15000, game:player_cash(target))
    luassert.is.equal(2, game:detention_remaining(user))
  end)

  it("also settles a computer-controlled strike before self-bankruptcy", function()
    local game, user, target = new_strike(500)

    local result = use_flow.begin_item_use(game, user.id, item_ids.missile, {
      phase = "post_action", is_computer_controlled = true, target_id = target.id,
    })

    luassert.is_true(result.ok)
    luassert.is_true(result.item_consumed)
    luassert.is_true(user.eliminated)
    luassert.is.equal(15000, game:player_cash(target))
  end)

  it("consumes once before the animated strike's deferred hospital bill", function()
    local game, user, target = new_strike(500)
    game.anim_gate_port.wait_action_anim = true

    local result = select_target(game, user, target)

    luassert.is_true(result.ok)
    luassert.is_true(result.item_consumed)
    luassert.is_false(user.eliminated)
    luassert.is.equal(1, support.count_item(user, item_ids.missile))
    luassert.is.equal(20000, game:player_cash(target))
    move_followup.run({ game = game }, result.after_action_anim.next_args)
    luassert.is_true(user.eliminated)
    luassert.is.equal(15000, game:player_cash(target))
    luassert.is.equal(0, inventory.count(user))
  end)

  it("retains the missile when its target choice is cancelled", function()
    local game, user = new_strike(20000)
    local begin = use_flow.begin_item_use(game, user.id, item_ids.missile, { phase = "post_action" })
    local choice = support.open_choice(game, begin.choice_spec)

    choice_resolver.resolve(game, choice, { type = "choice_cancel", choice_id = choice.id })

    luassert.is.equal(2, support.count_item(user, item_ids.missile))
    luassert.is.equal(20000, game:player_cash(user))
  end)

  it("retains the missile when the selected player is no longer a valid target", function()
    local game, user, target = new_strike(20000)
    local begin = use_flow.begin_item_use(game, user.id, item_ids.missile, { phase = "post_action" })
    local choice = support.open_choice(game, begin.choice_spec)
    game:set_player_deity(target, "angel", 3)

    local result = use_flow.resolve_item_use_choice(game, choice, {
      choice_id = choice.id, option_id = target.id,
    })

    luassert.is_false(result.ok)
    luassert.is_false(result.item_consumed)
    luassert.is.equal(2, support.count_item(user, item_ids.missile))
    luassert.is.equal(20000, game:player_cash(user))
    luassert.is.equal(20000, game:player_cash(target))
  end)
end)
