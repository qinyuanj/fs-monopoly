-- Mutation-closure pins for src/rules/chance/handlers.lua.
-- Targets the boundary/branch survivors not already covered by chance_spec,
-- chance_asset_handlers_spec, and chance_cash_others_contract_spec:
--   * adjust_chance_delta deity cross-cases (rich only doubles gains, poor
--     only doubles payments) and the gain/payment sign split,
--   * handle_bankruptcy_if_non_positive's `> 0` boundary,
--   * _apply_to_all_players eliminated-skip and _dispatch_payment angel-skip,
--   * pay_others mountain-skip and payer-bankruptcy break,
--   * collect_from_others liquid cap, mountain-skip, and the
--     total_collected > 0 anim guard.
-- Routed by architect (agent_context/rules-mutation-bootstrap-debt.md).
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local default_map = require("src.config.content.default_map")
local chance_handlers = require("src.rules.chance.handlers")
local asset_handlers = require("src.rules.chance.handlers")._asset
local movement = require("src.rules.movement")
local event_feed = require("src.rules.ports.event_feed")
local monopoly_event = require("src.foundation.events")
local achievement_progress = require("src.rules.ports.achievement_progress")
local config_reset = require("test.support.config_reset")

local _assert_eq = support.assert_eq
local _with_patches = support.with_patches

local function _game(players)
  return support.new_game({ map = default_map, players = players or { "P1", "P2" } })
end

local function _balance(game, player)
  return game:player_cash(player)
end

describe("TestChanceHandlersClosure", function()
before_each(function()
  config_reset.reset_all()
end)

-- adjust_chance_delta deity cross-cases ----------------------------------

it("test_add_cash_rich_doubles_a_gain", function()
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  g:set_player_deity(p, "rich", 3)
  local before = _balance(g, p)
  h.add_cash(g, p, { effect = "add_cash", amount = 1000, target = "self" })
  _assert_eq(_balance(g, p) - before, 2000, "rich deity doubles a positive delta")
end)

it("test_add_cash_rich_doubles_even_a_single_coin_gain", function()
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  g:set_player_deity(p, "rich", 3)
  local before = _balance(g, p)
  h.add_cash(g, p, { effect = "add_cash", amount = 1, target = "self" })
  _assert_eq(_balance(g, p) - before, 2, "a gain of one coin is still > 0 and must double")
end)

it("test_add_cash_poor_does_not_double_a_gain", function()
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  g:set_player_deity(p, "poor", 3)
  local before = _balance(g, p)
  h.add_cash(g, p, { effect = "add_cash", amount = 1000, target = "self" })
  _assert_eq(_balance(g, p) - before, 1000, "poor deity must not touch gains")
end)

it("test_add_cash_target_all_skips_eliminated_players", function()
  local g = _game({ "P1", "P2", "P3" })
  local h = chance_handlers.build()
  g.players[2].eliminated = true
  local before2 = _balance(g, g.players[2])
  local before3 = _balance(g, g.players[3])
  h.add_cash(g, g.players[1], { effect = "add_cash", amount = 1000, target = "all" })
  _assert_eq(_balance(g, g.players[2]) - before2, 0, "eliminated player is not credited")
  _assert_eq(_balance(g, g.players[3]) - before3, 1000, "live player is credited")
end)

it("test_pay_cash_poor_doubles_a_payment", function()
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  g:set_player_cash(p, 99999)
  g:set_player_deity(p, "poor", 3)
  local before = _balance(g, p)
  h.pay_cash(g, p, { effect = "pay_cash", amount = 1000, target = "self" })
  _assert_eq(_balance(g, p) - before, -2000, "poor deity doubles a negative delta")
end)

it("test_pay_cash_rich_does_not_double_a_payment", function()
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  g:set_player_cash(p, 99999)
  g:set_player_deity(p, "rich", 3)
  local before = _balance(g, p)
  h.pay_cash(g, p, { effect = "pay_cash", amount = 1000, target = "self" })
  _assert_eq(_balance(g, p) - before, -1000, "rich deity must not touch payments")
end)

-- _dispatch_payment angel-skip (target=all) ------------------------------

it("test_pay_cash_target_all_skips_an_angel_player_only_for_a_negative_card", function()
  local g = _game({ "P1", "P2", "P3" })
  local h = chance_handlers.build()
  for _, p in ipairs(g.players) do g:set_player_cash(p, 99999) end
  g:set_player_deity(g.players[2], "angel", 3)
  local before2 = _balance(g, g.players[2])
  local before3 = _balance(g, g.players[3])
  h.pay_cash(g, g.players[1], { effect = "pay_cash", amount = 1000, target = "all", negative = true })
  _assert_eq(_balance(g, g.players[2]) - before2, 0, "angel blocks a negative chance charge")
  _assert_eq(_balance(g, g.players[3]) - before3, -1000, "non-angel player still pays")
end)

it("test_pay_cash_target_all_still_charges_an_angel_player_for_a_non_negative_card", function()
  local g = _game()
  local h = chance_handlers.build()
  for _, p in ipairs(g.players) do g:set_player_cash(p, 99999) end
  g:set_player_deity(g.players[2], "angel", 3)
  local before2 = _balance(g, g.players[2])
  h.pay_cash(g, g.players[1], { effect = "pay_cash", amount = 1000, target = "all", negative = false })
  _assert_eq(_balance(g, g.players[2]) - before2, -1000, "angel only protects against negative cards")
end)

-- handle_bankruptcy_if_non_positive boundary -----------------------------

it("test_a_payment_that_lands_on_exactly_zero_eliminates_the_player", function()
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  g:set_player_cash(p, 1000)
  h.pay_cash(g, p, { effect = "pay_cash", amount = 1000, target = "self" })
  _assert_eq(_balance(g, p), 0, "balance reaches zero")
  _assert_eq(p.eliminated, true, "zero balance is non-positive -> eliminated")
end)

it("test_a_payment_that_leaves_a_positive_balance_does_not_eliminate", function()
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  g:set_player_cash(p, 1001)
  h.pay_cash(g, p, { effect = "pay_cash", amount = 1000, target = "self" })
  _assert_eq(_balance(g, p), 1, "one coin remains")
  _assert_eq(p.eliminated or false, false, "positive balance survives")
end)

-- pay_others branches ----------------------------------------------------

it("test_pay_others_does_not_pay_a_recipient_who_is_in_the_mountain", function()
  local g = _game()
  local h = chance_handlers.build()
  local payer, other = g.players[1], g.players[2]
  g:set_player_cash(payer, 99999)
  local mountain = g.board:find_first_by_type("mountain")
  g:player_relocate(other, { destination_index = mountain, move_dir_mode = "clear" })
  local before = _balance(g, other)
  h.pay_others(g, payer, { effect = "pay_others", amount = 3000, target = "self" })
  _assert_eq(_balance(g, other) - before, 0, "a recipient in the mountain receives nothing")
end)

it("test_pay_others_stops_distributing_once_the_payer_goes_bankrupt", function()
  local g = _game({ "P1", "P2", "P3", "P4" })
  local h = chance_handlers.build()
  local payer = g.players[1]
  g:set_player_cash(payer, 3000) -- only enough for one recipient
  local before = {}
  for i = 2, 4 do before[i] = _balance(g, g.players[i]) end
  h.pay_others(g, payer, { effect = "pay_others", amount = 3000, target = "self" })
  _assert_eq(payer.eliminated, true, "payer goes bankrupt after the first payment")
  _assert_eq(_balance(g, g.players[2]) - before[2], 3000, "first recipient is paid")
  _assert_eq(_balance(g, g.players[3]) - before[3], 0, "distribution breaks before the second recipient")
  _assert_eq(_balance(g, g.players[4]) - before[4], 0, "distribution breaks before the third recipient")
end)

it("test_pay_others_queues_no_cash_receive_anim_for_payer_or_recipients", function()
  local g = _game({ "P1", "P2", "P3" })
  local h = chance_handlers.build()
  local payer = g.players[1]
  g:set_player_cash(payer, 99999)
  g.anim_gate_port = { wait_action_anim = true, wait_move_anim = false }
  h.pay_others(g, payer, { effect = "pay_others", amount = 3000, target = "self" })
  local kinds = {}
  if g.turn.action_anim ~= nil then
    kinds[1] = g.turn.action_anim.kind
  end
  for _, anim in ipairs(g.turn.action_anim_queue or {}) do
    kinds[#kinds + 1] = anim.kind
  end
  _assert_eq(table.concat(kinds, ","), "", "pay_others suppresses every per-transfer cash_receive anim")
end)

-- collect_from_others branches -------------------------------------------

it("test_collect_from_others_caps_the_actor_s_gain_at_the_target_s_liquidity", function()
  local g = _game()
  local h = chance_handlers.build()
  local actor, other = g.players[1], g.players[2]
  g:set_player_cash(other, 500)
  local actor_before = _balance(g, actor)
  h.collect_from_others(g, actor, { effect = "collect_from_others", amount = 3000, target = "self" })
  _assert_eq(_balance(g, actor) - actor_before, 500, "actor only receives what the target can liquidate")
  _assert_eq(other.eliminated, true, "the target is still charged the full fee and goes bankrupt")
end)

it("test_collect_from_others_collects_nothing_while_the_collector_is_in_the_mountain", function()
  local g = _game()
  local h = chance_handlers.build()
  local actor, other = g.players[1], g.players[2]
  g:set_player_cash(other, 99999)
  local mountain = g.board:find_first_by_type("mountain")
  g:player_relocate(actor, { destination_index = mountain, move_dir_mode = "clear" })
  local before = _balance(g, other)
  h.collect_from_others(g, actor, { effect = "collect_from_others", amount = 3000, target = "self" })
  _assert_eq(_balance(g, other) - before, 0, "a collector in the mountain collects nothing")
end)

it("test_collect_from_others_queues_no_summary_anim_when_nothing_is_collected", function()
  local g = _game()
  local h = chance_handlers.build()
  local actor, other = g.players[1], g.players[2]
  g:set_player_cash(other, 99999)
  local mountain = g.board:find_first_by_type("mountain")
  g:player_relocate(actor, { destination_index = mountain, move_dir_mode = "clear" })
  g.anim_gate_port = { wait_action_anim = true, wait_move_anim = false }
  h.collect_from_others(g, actor, { effect = "collect_from_others", amount = 3000, target = "self" })
  _assert_eq(g.turn.action_anim, nil, "total_collected == 0 must not queue a cash_receive anim")
end)

-- collect_from_others total_collected > 0 boundary -----------------------

it("test_collect_from_others_queues_the_summary_anim_when_exactly_one_coin_is_collected", function()
  local g = _game()
  local h = chance_handlers.build()
  g.anim_gate_port = { wait_action_anim = true, wait_move_anim = false }
  local actor, other = g.players[1], g.players[2]
  g:set_player_cash(other, 1) -- liquidity caps the collection at exactly 1
  h.collect_from_others(g, actor, { effect = "collect_from_others", amount = 3000, target = "self" })
  luassert.is_not_nil(g.turn.action_anim, "total_collected == 1 is > 0 and must queue a cash_receive anim")
  _assert_eq(g.turn.action_anim.kind, "cash_receive", "summary anim is a cash_receive")
  _assert_eq(g.turn.action_anim.amount, 1, "summary anim carries the collected total")
end)

-- move_steps chance_move anim source -------------------------------------

it("test_move_forward_tags_the_move_anim_payload_with_the_chance_move_source", function()
  local g = _game()
  g.anim_gate_port = { wait_action_anim = true, wait_move_anim = true }
  local h = chance_handlers.build()
  local p = g.players[1]
  h.move_forward(g, p, { effect = "move_forward", steps = 3 })
  luassert.is_not_nil(g.turn.move_anim, "open move_anim gate routes the move onto the move_anim channel")
  _assert_eq(g.turn.move_anim.source, "chance_move", "chance moves identify their anim source")
end)

-- move_backward move_opts + allow_optional -------------------------------

it("test_move_backward_drives_movement_with_the_relative_backward_facing_and_market_skip", function()
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  local captured
  _with_patches({
    { target = movement, key = "move", value = function(_, _, steps, opts)
        captured = { steps = steps, opts = opts }
        return { visited = {}, steps = steps }
      end },
  }, function()
    h.move_backward(g, p, { effect = "move_backward", steps = 2 }, { arrival_direction = "down" })
  end)
  _assert_eq(captured.opts.facing_mode, "relative_backward", "backward moves use relative_backward facing")
  _assert_eq(captured.opts.skip_market_check, true, "backward moves skip the market check")
  _assert_eq(captured.opts.direction, "down", "an arrival_direction context seeds the move direction")
end)

it("test_move_steps_default_to_zero_when_missing", function()
  -- #293:`card.steps or 0` 的 `0`→`1` 变异只在 steps 缺失时可分(0 是 truthy,
  -- 显式 0 与变异同值)。
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  local forwards, backwards = 0, 0
  _with_patches({
    { target = movement, key = "move", value = function(_, _, steps, opts)
        if opts ~= nil and opts.facing_mode == "relative_backward" then
          backwards = steps
        else
          forwards = steps
        end
        return { visited = {}, steps = steps }
      end },
  }, function()
    h.move_forward(g, p, { effect = "move_forward" })
    h.move_backward(g, p, { effect = "move_backward" }, nil)
  end)
  _assert_eq(forwards, 0, "forward without steps should move zero")
  _assert_eq(backwards, 0, "backward without steps should move zero")
end)

it("test_move_backward_tolerates_a_nil_context_without_indexing_it", function()
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  local ok = pcall(function()
    _with_patches({
      { target = movement, key = "move", value = function(_, _, steps)
          return { visited = {}, steps = steps }
        end },
    }, function()
      h.move_backward(g, p, { effect = "move_backward", steps = 1 }, nil)
    end)
  end)
  luassert.truthy(ok, "the context guard must short-circuit before indexing a nil context")
end)

it("test_move_backward_marks_its_move_result_as_optional", function()
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  g:update_player_position(p, g.board:index_of_tile_id(32))
  g:set_player_status(p, "move_dir", "down")
  local out = h.move_backward(g, p, { effect = "move_backward", steps = 2 }, {})
  luassert.truthy(out and out.move_result, "move_backward returns a move result")
  _assert_eq(out.move_result.allow_optional, true, "backward landings are optional")
end)

-- forced_move teleport classification ------------------------------------

it("test_forced_move_into_the_mountain_queues_a_forced_relocation_anim", function()
  local g = _game()
  g.anim_gate_port = { wait_action_anim = true, wait_move_anim = false }
  local h = chance_handlers.build()
  local p = g.players[1]
  local mountain = g.board:get_tile(g.board:find_first_by_type("mountain"))
  h.forced_move(g, p, { effect = "forced_move", destination_tile_id = mountain.id }, {})
  luassert.is_not_nil(g.turn.action_anim, "forced_move queues an anim")
  _assert_eq(g.turn.action_anim.kind, "forced_relocation",
    "a mountain destination is a teleport tile and uses forced_relocation")
end)

it("test_forced_move_asserts_missing_destination_with_message", function()
  -- #293:forced_move 的 destination 断言消息未测。
  local g = _game()
  local h = chance_handlers.build()
  local ok, err = pcall(h.forced_move, g, g.players[1], { effect = "forced_move" }, {})
  luassert.truthy(ok == false, "forced_move without destination should assert")
  luassert.truthy(tostring(err):find("forced_move requires destination_tile_id", 1, true) ~= nil,
    "assert should carry its message: " .. tostring(err))
end)

it("test_forced_move_relocates_with_forced_move_mode", function()
  -- #293:relocate opts 的 move_dir_mode "forced_move" 字面值(→ nil 变异)未测。
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  local mountain = g.board:get_tile(g.board:find_first_by_type("mountain"))
  local seen_opts
  local saved_relocate = g.player_relocate
  g.player_relocate = function(_, player, opts)
    seen_opts = opts
    return saved_relocate(g, player, opts)
  end
  h.forced_move(g, p, { effect = "forced_move", destination_tile_id = mountain.id }, {})
  g.player_relocate = saved_relocate
  luassert.truthy(seen_opts ~= nil and seen_opts.move_dir_mode == "forced_move",
    "forced_move should relocate with the forced_move facing mode")
end)

-- emit_event event_feed publication guard --------------------------------

it("test_emit_event_publishes_a_chance_card_feed_entry_when_the_payload_carries_text", function()
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  local published = {}
  _with_patches({
    { target = event_feed, key = "publish", value = function(_, entry)
        published[#published + 1] = entry
      end },
  }, function()
    h.add_cash(g, p, { effect = "add_cash", amount = 100, target = "self" })
  end)
  _assert_eq(#published, 1, "a string-text payload publishes exactly one feed entry")
  _assert_eq(published[1].kind, "chance_card", "the feed entry is tagged as a chance card")
  luassert.truthy(type(published[1].text) == "string" and #published[1].text > 0,
    "the published entry carries the payload text")
end)

it("test_pay_cash_event_text_carries_the_paid_amount", function()
  -- #293:_apply_payment 的事件文案用 abs_value(delta)(→ nil 变异)拼金币数,文案未测。
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  g:set_player_cash(p, 99999)
  local published = {}
  _with_patches({
    { target = event_feed, key = "publish", value = function(_, entry)
        published[#published + 1] = entry
      end },
  }, function()
    h.pay_cash(g, p, { effect = "pay_cash", amount = 500, target = "self" })
  end)
  _assert_eq(#published, 1, "pay_cash publishes exactly one feed entry")
  luassert.truthy(published[1].text:find("500", 1, true) ~= nil,
    "pay_cash event text should carry the paid amount; got " .. published[1].text)
end)

it("test_add_cash_with_zero_amount_records_no_cash_received_progress", function()
  -- #293:L41 record_cash_received 的 `amount > 0`(→ `>=` 变异)在 amount=0
  -- 时会误记成就进度,零额加钱路径未测。
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  local recorded = {}
  _with_patches({
    { target = achievement_progress, key = "cash_received", value = function(...)
        recorded[#recorded + 1] = ...
        return true
      end },
  }, function()
    h.add_cash(g, p, { effect = "add_cash", amount = 0, target = "self" })
  end)
  _assert_eq(#recorded, 0, "a zero-amount gain must not record cash_received progress")
end)

it("test_add_cash_with_single_coin_records_cash_received_progress", function()
  -- #293:L41 record_cash_received 的 `amount > 0`(→ `> 1` 变异)在 amount=1
  -- 时会漏记成就进度,单币加钱路径未测。
  local g = _game()
  local h = chance_handlers.build()
  local p = g.players[1]
  local recorded = {}
  _with_patches({
    { target = achievement_progress, key = "cash_received", value = function(...)
        recorded[#recorded + 1] = ...
        return true
      end },
  }, function()
    h.add_cash(g, p, { effect = "add_cash", amount = 1, target = "self" })
  end)
  _assert_eq(#recorded, 1, "a one-coin gain must record cash_received progress")
end)

-- Asset-handler boundary pins, exercised through the injected common port so
-- the destroy/discard arithmetic can be observed without a full game.
end)

describe("TestChanceAssetHandlerClosure", function()
before_each(function()
  config_reset.reset_all()
end)

local function _events_common(deps_extra)
  local events = {}
  local common = {
    emit_event = function(_, _, payload) events[#events + 1] = payload end,
    dependencies = function()
      local deps = { monopoly_event = monopoly_event }
      for k, v in pairs(deps_extra or {}) do deps[k] = v end
      return deps
    end,
  }
  local handlers = {}
  asset_handlers.register(handlers, common)
  return handlers, events
end

-- destroy_buildings_on_path: (t.level or 0) > 0 boundary ------------------

it("test_destroy_buildings_on_path_destroys_level_1_land_and_spares_level_nil_land", function()
  local handlers, events = _events_common()
  local destroyed = {}
  local game = {
    board = {
      get_tile = function(_, idx)
        if idx == 1 then return { type = "land", level = 1, name = "Lvl1" } end
        if idx == 2 then return { type = "land", name = "NoLevel" } end -- level is nil
        return { type = "chance", name = "Chance" }
      end,
    },
    set_tile_level = function(_, tile, level) destroyed[tile.name] = level end,
  }
  handlers.destroy_buildings_on_path(game, {}, {}, { visited = { 1, 2, 3 } })
  _assert_eq(#events, 1, "only the level-1 tile crosses the > 0 threshold")
  _assert_eq(events[1].tile.name, "Lvl1", "the destroyed tile is the one with a building")
  _assert_eq(destroyed["Lvl1"], 0, "the level-1 tile is razed to 0")
  _assert_eq(destroyed["NoLevel"], nil, "a nil-level tile defaults to 0 and is left untouched")
end)

-- discard_items: count==0 drops the whole inventory ----------------------

local function _inventory_deps(item_ids)
  return {
    inventory = {
      count = function() return #item_ids end,
      remove_nth_occupied = function(_, idx) return { id = table.remove(item_ids, idx) } end,
      item_name = function(id) return "Item" .. tostring(id) end,
    },
  }
end

local function _rng_game()
  return { rng = { next_int = function(_, lo) return lo end } }
end

it("test_discard_items_with_count_0_drops_every_item_the_player_holds", function()
  local item_ids = { 10, 20 }
  local handlers, events = _events_common(_inventory_deps(item_ids))
  handlers.discard_items(_rng_game(), { name = "P" }, { effect = "discard_items", count = 0 })
  _assert_eq(#item_ids, 0, "count==0 resolves to the full inventory size and drains it")
  _assert_eq(#events, 1, "one summary event is emitted")
  luassert.truthy(events[1].text:find("2 张", 1, true), "the summary reports two discarded items")
end)

it("test_discard_items_lists_the_dropped_names_only_when_at_least_one_item_is_dropped", function()
  local item_ids = { 10 }
  local handlers, events = _events_common(_inventory_deps(item_ids))
  handlers.discard_items(_rng_game(), { name = "P" }, { effect = "discard_items", count = 1 })
  luassert.truthy(events[1].text:find(": ", 1, true), "dropping one item appends the name list")
end)

it("test_discard_items_omits_the_name_list_when_nothing_is_dropped", function()
  local item_ids = {}
  local handlers, events = _events_common(_inventory_deps(item_ids))
  handlers.discard_items(_rng_game(), { name = "P" }, { effect = "discard_items", count = 2 })
  _assert_eq(events[1].text:find(": ", 1, true), nil, "an empty drop must not append a name list separator")
end)


end)
