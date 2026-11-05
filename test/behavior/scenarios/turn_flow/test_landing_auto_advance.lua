require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local function _assert_identity(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local support = require("test.support.shared_support")
local item_ids = require("src.config.gameplay.item_ids")
local inventory = require("src.rules.items.inventory")
local TurnScheduler = require("src.turn.scheduler")
local phase_registry = require("src.turn.phases.registry")

local function _new_manual_game()
  return support.new_game({ ai = {}, auto_all = false })
end

local function _run_landing_turn(game, player, move_result)
  local phases = phase_registry.build_default_phases()
  phases.start = function()
    return "landing", { player = player, move_result = move_result or {} }
  end
  game.turn_runtime = TurnScheduler:new(game, phases)
  game.turn_runtime:run_turn()
end

local function _fill_inventory(player)
  while not inventory.is_full(player) do
    inventory.add(player, { id = item_ids.free_rent })
  end
end

describe("TestLandingAutoAdvance", function()

local function _test_full_inventory_market_landing_skips_choice_and_continues_to_inter_turn_wait()
  local game = _new_manual_game()
  local player = game.players[1]
  local market_index = assert(support.first_tile_by_type(game.board, "market"))

  _fill_inventory(player)
  game:update_player_position(player, market_index)

  _run_landing_turn(game, player)

  luassert.is_nil(game.turn.pending_choice)
  _assert_identity(game.turn.phase, "inter_turn_wait")
  luassert.is_true(game.turn.inter_turn_wait_active)
end

local function _test_market_landing_with_free_slot_opens_market_choice()
  local game = _new_manual_game()
  local player = game.players[1]
  local market_index = assert(support.first_tile_by_type(game.board, "market"))

  game:update_player_position(player, market_index)

  _run_landing_turn(game, player)

  _assert_identity(game.turn.pending_choice and game.turn.pending_choice.kind, "market_buy")
end

local function _test_free_rent_card_on_enemy_land_is_consumed_without_waiting_for_choice()
  local game = _new_manual_game()
  local player = game.players[1]
  local owner = game.players[2]
  local land_index, land_tile = support.first_land_tile(game.board)
  local player_cash = game:player_cash(player)
  local owner_cash = game:player_cash(owner)

  game:set_tile_owner(land_tile, owner.id)
  game:set_player_property(owner, land_tile.id, true)
  inventory.add(player, { id = item_ids.free_rent })
  game:update_player_position(player, land_index)

  _run_landing_turn(game, player)

  luassert.is_nil(game.turn.pending_choice)
  _assert_identity(game.turn.phase, "inter_turn_wait")
  _assert_identity(support.count_item(player, item_ids.free_rent), 0)
  _assert_identity(game:player_cash(player), player_cash)
  _assert_identity(game:player_cash(owner), owner_cash)
end

local function _test_declining_strong_card_uses_free_rent_and_does_not_open_second_choice()
  local game = _new_manual_game()
  local player = game.players[1]
  local owner = game.players[2]
  local land_index, land_tile = support.first_land_tile(game.board)
  local player_cash = game:player_cash(player)
  local owner_cash = game:player_cash(owner)

  game:set_tile_owner(land_tile, owner.id)
  game:set_player_property(owner, land_tile.id, true)
  inventory.add(player, { id = item_ids.strong })
  inventory.add(player, { id = item_ids.free_rent })
  game:update_player_position(player, land_index)

  _run_landing_turn(game, player)

  local strong_choice = assert(game.turn.pending_choice, "strong card prompt should open first")
  _assert_identity(strong_choice.kind, "rent_card_prompt")
  _assert_identity(strong_choice.meta.card_kind, "strong")

  game:dispatch_action({
    type = "choice_cancel",
    choice_id = strong_choice.id,
    actor_role_id = player.id,
  })

  luassert.is_nil(game.turn.pending_choice)
  _assert_identity(game.turn.phase, "inter_turn_wait")
  _assert_identity(support.count_item(player, item_ids.strong), 1)
  _assert_identity(support.count_item(player, item_ids.free_rent), 0)
  _assert_identity(game:player_cash(player), player_cash)
  _assert_identity(game:player_cash(owner), owner_cash)
end

local function _test_accepting_strong_card_prompt_executes_the_selected_card()
  local game = _new_manual_game()
  local player = game.players[1]
  local owner = game.players[2]
  local land_index, land_tile = support.first_land_tile(game.board)

  game:set_tile_owner(land_tile, owner.id)
  game:set_player_property(owner, land_tile.id, true)
  inventory.add(player, { id = item_ids.strong })
  game:update_player_position(player, land_index)

  _run_landing_turn(game, player)

  local strong_choice = assert(game.turn.pending_choice, "strong card prompt should open first")
  _assert_identity(strong_choice.meta.card_kind, "strong")

  game:dispatch_action({
    type = "choice_select",
    choice_id = strong_choice.id,
    option_id = "use",
    actor_role_id = player.id,
  })

  luassert.is_nil(game.turn.pending_choice)
  _assert_identity(support.count_item(player, item_ids.strong), 0, "接受提示应消耗强征卡")
  _assert_identity(support.tile_state(game, land_tile).owner_id, player.id, "强征应把地块转到出牌者名下")
end

local function _test_unknown_rent_card_kind_falls_through_to_paying_rent()
  local game = _new_manual_game()
  local player = game.players[1]
  local owner = game.players[2]
  local land_index, land_tile = support.first_land_tile(game.board)

  game:set_tile_owner(land_tile, owner.id)
  game:set_player_property(owner, land_tile.id, true)
  inventory.add(player, { id = item_ids.strong })
  game:update_player_position(player, land_index)

  _run_landing_turn(game, player)

  local strong_choice = assert(game.turn.pending_choice, "strong card prompt should open first")
  -- 把 card_kind 改成登记表里没有的值:选择器应落到「不执行任何卡」的分支,
  -- 再顺着无卡兜底走到正常付租。
  strong_choice.meta.card_kind = "spec_unknown_card"
  local player_cash = game:player_cash(player)
  local owner_cash = game:player_cash(owner)

  game:dispatch_action({
    type = "choice_select",
    choice_id = strong_choice.id,
    option_id = "use",
    actor_role_id = player.id,
  })

  luassert.is_nil(game.turn.pending_choice)
  _assert_identity(support.count_item(player, item_ids.strong), 1, "未知卡种不应消耗手牌")
  _assert_identity(support.tile_state(game, land_tile).owner_id, owner.id, "未知卡种不应转移地权")
  luassert.is_true(game:player_cash(player) < player_cash, "未知卡种应回落到正常付租")
  luassert.is_true(game:player_cash(owner) > owner_cash, "地主应收到租金")
end


it("test_full_inventory_market_landing_skips_choice_and_continues_to_inter_turn_wait", _test_full_inventory_market_landing_skips_choice_and_continues_to_inter_turn_wait)
it("test_market_landing_with_free_slot_opens_market_choice", _test_market_landing_with_free_slot_opens_market_choice)
it("test_free_rent_card_on_enemy_land_is_consumed_without_waiting_for_choice", _test_free_rent_card_on_enemy_land_is_consumed_without_waiting_for_choice)
it("test_declining_strong_card_uses_free_rent_and_does_not_open_second_choice", _test_declining_strong_card_uses_free_rent_and_does_not_open_second_choice)
it("test_accepting_strong_card_prompt_executes_the_selected_card", _test_accepting_strong_card_prompt_executes_the_selected_card)
it("test_unknown_rent_card_kind_falls_through_to_paying_rent", _test_unknown_rent_card_kind_falls_through_to_paying_rent)
end)
