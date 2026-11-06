require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
-- 限购买满(#231):经真实选择解析与真实付费网关回调驱动,宿主替身到 Role 与事件注册;
-- 买满提示只观察 feedback 的失败原因与文案。
local support = require("test.support.shared_support")
local market_cfg = require("src.config.content.market")
local market_catalog = require("src.config.content.market_catalog")
local market_service = require("src.rules.market")
local market_feedback = require("src.rules.market.choice").feedback
local market_query = require("src.rules.market.query")
local choice_resolver = require("src.rules.choice.resolver")
local inventory = require("src.rules.items.inventory")
local paid_purchase_port = require("src.rules.ports.paid_purchase")
local runtime_ports = require("src.foundation.ports.runtime_ports")

local PAID_PRODUCT_ID = 2012
local OTHER_PAID_PRODUCT_ID = 2004
local SECOND_PAGE_PRODUCT_ID = 2017
local GOLD_PRODUCT_ID = 2003
local LIMIT = 10

local function _goods_id(product_id)
  return "goods_" .. tostring(product_id)
end

local function _goods_list()
  local list = {}
  for _, entry in ipairs(market_cfg) do
    list[#list + 1] = { name = entry.name, goods_id = _goods_id(entry.product_id) }
  end
  return list
end

-- 每名玩家一个 Role 替身:记录打开购买页(显示时长 > 1 秒)的商品,收屏调用不算。
local function _new_host(game)
  local host = { roles = {}, handlers = {}, opened = {} }
  for _, player in ipairs(game.players) do
    host.roles[player.id] = {
      get_roleid = function() return player.id end,
      show_goods_purchase_panel = function(goods_id, show_time)
        if show_time > 1 then
          host.opened[#host.opened + 1] = goods_id
        end
      end,
      set_goods_panel_visible = function() end,
    }
  end
  return host
end

local function _with_host(game, fn)
  local host = _new_host(game)
  support.with_patches({
    { key = "GameAPI", value = {
      random_int = function(min, max) return min <= max and min or max end,
      get_goods_list = _goods_list,
    } },
    { target = runtime_ports, key = "resolve_role", value = function(role_id) return host.roles[role_id] end },
    { key = "EVENT", value = { SPEC_ROLE_PURCHASE_GOODS = "SPEC_ROLE_PURCHASE_GOODS" } },
    { key = "RegisterTriggerEvent", value = function(args, callback) host.handlers[args[2]] = callback end },
  }, function()
    market_service.purchase.setup_for_game(game)
    fn(host)
  end)
end

local function _open_market(game, player)
  local spec = market_service.choice.build(player, game, { active_tab = "item", page_index = 1 })
  spec.id = 2310
  game.turn.pending_choice = spec
  return spec
end

local function _find_option(options, product_id)
  for _, option in ipairs(options) do
    if option.id == product_id then
      return option
    end
  end
  error("missing market option: " .. tostring(product_id))
end

local function _option(game, player, product_id)
  local spec = market_service.choice.build(player, game, { active_tab = "item", page_index = 1 })
  return _find_option(spec.options, product_id)
end

local function _click_buy(game, player, product_id)
  local spec = _open_market(game, player)
  return choice_resolver.resolve(game, spec, {
    type = "choice_select",
    choice_id = spec.id,
    option_id = product_id,
    actor_role_id = player.id,
  })
end

local function _host_callback(host, player, product_id)
  host.handlers[player.id](nil, nil, { role = host.roles[player.id], goods_id = _goods_id(product_id) })
end

local function _empty_inventory(player)
  while inventory.count(player) > 0 do
    inventory.remove_nth_occupied(player, 1)
  end
end

local function _buy_times(game, host, player, product_id, times)
  for _ = 1, times do
    _empty_inventory(player)
    _click_buy(game, player, product_id)
    _host_callback(host, player, product_id)
  end
end

local function _fill_inventory(player)
  while not inventory.is_full(player) do
    inventory.add(player, { id = 2001 })
  end
end

local function _capture_buy_failed(fn)
  local captured = {}
  support.with_patches({
    { target = market_feedback, key = "emit_buy_failed", value = function(_, _, reason, body)
      captured[#captured + 1] = { reason = reason, body = body }
    end },
  }, fn)
  return captured
end

describe("TestMarketPurchaseLimit", function()
  it("test_item_stays_buyable_until_the_limit_then_is_marked_and_blocked", function()
    local game = support.new_game()
    local player = game:current_player()
    _with_host(game, function(host)
      _buy_times(game, host, player, PAID_PRODUCT_ID, LIMIT - 1)
      _empty_inventory(player)
      local before = _option(game, player, PAID_PRODUCT_ID)
      luassert.is_true(before.can_buy, "9th purchase must leave the item buyable")
      luassert.is_true(before.can_buy_with_free_slot, "9th purchase keeps the confirm button")
      luassert.is_not_true(before.purchase_limit_reached, "9 purchases are below the limit")

      _buy_times(game, host, player, PAID_PRODUCT_ID, 1)
      _empty_inventory(player)
      local after = _option(game, player, PAID_PRODUCT_ID)
      luassert.is_false(after.can_buy, "10th purchase must make the item unbuyable")
      luassert.is_false(after.can_buy_with_free_slot, "a maxed paid item hides the confirm button")
      luassert.is_true(after.purchase_limit_reached, "10th purchase must mark the option")

      local other = _option(game, player, OTHER_PAID_PRODUCT_ID)
      luassert.is_true(other.can_buy, "other products keep their own count")
    end)
  end)

  it("test_paid_item_maxes_out_only_when_the_last_host_callback_arrives", function()
    local game = support.new_game()
    local player = game:current_player()
    _with_host(game, function(host)
      _buy_times(game, host, player, PAID_PRODUCT_ID, LIMIT - 1)
      _empty_inventory(player)
      _click_buy(game, player, PAID_PRODUCT_ID)
      local pending = _option(game, player, PAID_PRODUCT_ID)
      luassert.is_not_true(pending.purchase_limit_reached, "the 10th order is not counted before its callback")
      luassert.is_true(pending.can_buy_with_free_slot, "the button stays until the callback arrives")

      _host_callback(host, player, PAID_PRODUCT_ID)
      _empty_inventory(player)
      local maxed = _option(game, player, PAID_PRODUCT_ID)
      luassert.is_true(maxed.purchase_limit_reached, "the callback marks the item maxed")
      luassert.is_false(maxed.can_buy_with_free_slot, "the callback hides the button")
    end)
  end)

  it("test_click_after_limit_never_opens_the_host_page_and_tells_the_player", function()
    local game = support.new_game()
    local player = game:current_player()
    _with_host(game, function(host)
      _buy_times(game, host, player, PAID_PRODUCT_ID, LIMIT)
      _empty_inventory(player)
      local opened_before = #host.opened

      local result
      local failures = _capture_buy_failed(function()
        result = _click_buy(game, player, PAID_PRODUCT_ID)
      end)

      luassert.is.equal(opened_before, #host.opened, "maxed item must not open the host purchase page")
      luassert.is_true(result and result.stay, "a maxed click keeps the market open")
      luassert.is.equal(1, #failures, "a maxed click reports one failure")
      luassert.is.equal("purchase_limit_reached", failures[1].reason, "failure reason")
      luassert.is.equal("本局已买满", failures[1].body, "failure tip text")
    end)
  end)

  it("test_one_players_limit_does_not_touch_the_other_player", function()
    local game = support.new_game()
    local buyer, other = game.players[1], game.players[2]
    _with_host(game, function(host)
      _buy_times(game, host, buyer, PAID_PRODUCT_ID, LIMIT)
      local option = _option(game, other, PAID_PRODUCT_ID)
      luassert.is_true(option.can_buy, "other player's same product stays buyable")
      luassert.is_not_true(option.purchase_limit_reached, "other player's option is not marked")
    end)
  end)

  it("test_a_new_game_starts_from_zero", function()
    local first = support.new_game()
    _with_host(first, function(host)
      _buy_times(first, host, first:current_player(), PAID_PRODUCT_ID, LIMIT)
    end)

    local second = support.new_game()
    _with_host(second, function()
      local option = _option(second, second:current_player(), PAID_PRODUCT_ID)
      luassert.is_true(option.can_buy, "a new game must reset the count")
      luassert.is_not_true(option.purchase_limit_reached, "a new game has no maxed items")
    end)
  end)

  it("test_callback_with_failed_card_grant_still_counts_and_refreshes_the_screen", function()
    local game = support.new_game()
    local player = game:current_player()
    _with_host(game, function(host)
      _buy_times(game, host, player, PAID_PRODUCT_ID, LIMIT - 1)
      _empty_inventory(player)
      _click_buy(game, player, PAID_PRODUCT_ID)
      _fill_inventory(player)
      game:consume_dirty()

      _host_callback(host, player, PAID_PRODUCT_ID)

      local dirty = game:consume_dirty()
      luassert.is_true(dirty.market, "grant failure must still refresh the open market screen")
      local refreshed = _find_option(game.turn.pending_choice.options, PAID_PRODUCT_ID)
      luassert.is_true(refreshed.purchase_limit_reached, "host already charged, so the failed grant still counts")
    end)
  end)

  it("test_callback_arriving_after_the_limit_still_grants_the_card", function()
    local game = support.new_game()
    local player = game:current_player()
    _with_host(game, function(host)
      _buy_times(game, host, player, PAID_PRODUCT_ID, LIMIT - 1)
      _empty_inventory(player)
      _click_buy(game, player, PAID_PRODUCT_ID)
      -- 第二条待到账记录:同商品两笔在途,第 11 次回调落在买满之后。
      paid_purchase_port.start(game, player, market_catalog.entry_by_id(PAID_PRODUCT_ID))

      _host_callback(host, player, PAID_PRODUCT_ID)
      _empty_inventory(player)
      _host_callback(host, player, PAID_PRODUCT_ID)

      luassert.is.equal(1, inventory.count(player), "paid callback past the limit must not be rejected")
    end)
  end)

  it("test_callback_without_a_pending_record_still_counts_when_goods_are_known", function()
    local game = support.new_game()
    local player = game:current_player()
    _with_host(game, function(host)
      _buy_times(game, host, player, PAID_PRODUCT_ID, LIMIT - 1)
      _empty_inventory(player)
      _open_market(game, player)
      game:consume_dirty()

      _host_callback(host, player, PAID_PRODUCT_ID)

      luassert.is.equal(0, inventory.count(player), "no pending record means no card is granted")
      luassert.is_true(game:consume_dirty().market, "the count changed, so the open screen must refresh")
      local refreshed = _find_option(game.turn.pending_choice.options, PAID_PRODUCT_ID)
      luassert.is_true(refreshed.purchase_limit_reached, "the host counted it, so the mirror counts it too")
    end)
  end)

  it("test_untracked_callback_for_a_non_market_product_is_skipped_without_crashing", function()
    local game = support.new_game()
    local player = game:current_player()
    _with_host(game, function(host)
      local skin_entry = { product_id = 5001, kind = "skin", name = "流放卡", on_purchase = function() end }
      paid_purchase_port.start(game, player, skin_entry)
      _host_callback(host, player, PAID_PRODUCT_ID)

      luassert.has_no.errors(function()
        _host_callback(host, player, PAID_PRODUCT_ID)
      end, nil, "skins share the gateway, so a repeated callback must not reach the market count")
    end)
  end)

  it("test_maxed_mark_stays_with_the_item_on_its_real_page", function()
    local game = support.new_game()
    local player = game:current_player()
    local entry = market_catalog.entry_by_id(SECOND_PAGE_PRODUCT_ID)
    _with_host(game, function(host)
      for _ = 1, LIMIT do
        _empty_inventory(player)
        paid_purchase_port.start(game, player, entry)
        _host_callback(host, player, SECOND_PAGE_PRODUCT_ID)
      end

      local first = market_service.choice.build(player, game, { active_tab = "item", page_index = 1 })
      for _, option in ipairs(first.options) do
        luassert.is_not_true(option.purchase_limit_reached, option.label .. " on page 1 is not maxed")
      end
      local second = market_service.choice.build(player, game, { active_tab = "item", page_index = 2 })
      luassert.is_true(_find_option(second.options, SECOND_PAGE_PRODUCT_ID).purchase_limit_reached,
        "the mark must be on the maxed item's own page")
    end)
  end)

  it("test_gold_item_is_marked_and_blocked_after_the_limit", function()
    local game = support.new_game()
    local player = game:current_player()
    game:set_player_cash(player, 5000 * (LIMIT + 2))
    _with_host(game, function()
      for _ = 1, LIMIT do
        _empty_inventory(player)
        _click_buy(game, player, GOLD_PRODUCT_ID)
        luassert.is.equal(1, inventory.count(player), "every gold purchase must grant the card")
      end
      _empty_inventory(player)
      local option = _option(game, player, GOLD_PRODUCT_ID)
      luassert.is_true(option.purchase_limit_reached, "10th gold purchase must mark the option")
      luassert.is_false(option.can_buy, "maxed gold item is unbuyable")
      luassert.is_false(option.can_buy_with_free_slot, "a free slot does not help a maxed item")

      local cash_before = game:player_cash(player)
      local failures = _capture_buy_failed(function()
        _click_buy(game, player, GOLD_PRODUCT_ID)
      end)
      luassert.is.equal("purchase_limit_reached", failures[1].reason, "failure reason")
      luassert.is.equal("本局已买满", failures[1].body, "failure text")
      luassert.is.equal(0, inventory.count(player), "11th purchase must not grant the card")
      luassert.is.equal(cash_before, game:player_cash(player), "11th purchase must not charge")
    end)
  end)

  it("test_failed_gold_purchases_do_not_count", function()
    local game = support.new_game()
    local player = game:current_player()
    _with_host(game, function()
      game:set_player_cash(player, 0)
      for _ = 1, LIMIT do
        _click_buy(game, player, GOLD_PRODUCT_ID)
      end
      game:set_player_cash(player, 5000 * 2)
      _fill_inventory(player)
      for _ = 1, LIMIT do
        _click_buy(game, player, GOLD_PRODUCT_ID)
      end
      _empty_inventory(player)
      luassert.is_not_true(_option(game, player, GOLD_PRODUCT_ID).purchase_limit_reached,
        "failed purchases must not use up the limit")
      _click_buy(game, player, GOLD_PRODUCT_ID)
      luassert.is.equal(1, inventory.count(player), "the player can still buy after failed attempts")
    end)
  end)

  it("test_gold_card_from_another_source_does_not_count", function()
    local game = support.new_game()
    local player = game:current_player()
    game:set_player_cash(player, 5000 * 2)
    _with_host(game, function()
      for _ = 1, LIMIT do
        _empty_inventory(player)
        inventory.give(player, GOLD_PRODUCT_ID, { game = game })
      end
      _empty_inventory(player)
      luassert.is_not_true(_option(game, player, GOLD_PRODUCT_ID).purchase_limit_reached,
        "only market purchases count")
    end)
  end)

  it("test_gold_limit_is_per_player_and_resets_in_a_new_game", function()
    local game = support.new_game()
    local player = game.players[1]
    local other = game.players[2]
    game:set_player_cash(player, 5000 * LIMIT)
    game:set_player_cash(other, 5000)
    _with_host(game, function()
      for _ = 1, LIMIT do
        _empty_inventory(player)
        _click_buy(game, player, GOLD_PRODUCT_ID)
      end
      luassert.is_true(_option(game, player, GOLD_PRODUCT_ID).purchase_limit_reached, "buyer is maxed")
      luassert.is_not_true(_option(game, other, GOLD_PRODUCT_ID).purchase_limit_reached,
        "other player's option is not marked")
    end)

    local next_game = support.new_game()
    local next_player = next_game.players[1]
    next_game:set_player_cash(next_player, 5000)
    _with_host(next_game, function()
      luassert.is_not_true(_option(next_game, next_player, GOLD_PRODUCT_ID).purchase_limit_reached,
        "a new game has no maxed items")
    end)
  end)

  it("test_full_inventory_blocks_can_buy_but_not_can_buy_with_free_slot", function()
    local game = support.new_game()
    local player = game:current_player()
    game:set_player_cash(player, 5000)
    _with_host(game, function()
      _fill_inventory(player)
      for _, product_id in ipairs({ GOLD_PRODUCT_ID, PAID_PRODUCT_ID }) do
        local option = _option(game, player, product_id)
        luassert.is_false(option.can_buy, "a full inventory blocks the purchase")
        luassert.is_true(option.can_buy_with_free_slot, "freeing a slot is all it takes")
      end
    end)
  end)

  it("test_maxed_item_with_a_full_inventory_counts_as_maxed", function()
    local game = support.new_game()
    local player = game:current_player()
    game:set_player_cash(player, 5000 * (LIMIT + 1))
    _with_host(game, function()
      for _ = 1, LIMIT do
        _empty_inventory(player)
        _click_buy(game, player, GOLD_PRODUCT_ID)
      end
      _fill_inventory(player)
      local option = _option(game, player, GOLD_PRODUCT_ID)
      luassert.is_true(option.purchase_limit_reached, "the item is maxed")
      luassert.is_false(option.can_buy_with_free_slot, "maxed wins over slots-full: no button")
    end)
  end)

  it("test_insufficient_gold_fails_both_buy_flags", function()
    local game = support.new_game()
    local player = game:current_player()
    game:set_player_cash(player, 0)
    _with_host(game, function()
      local option = _option(game, player, GOLD_PRODUCT_ID)
      luassert.is_false(option.can_buy, "cannot afford")
      luassert.is_false(option.can_buy_with_free_slot, "a free slot does not help without gold")
    end)
  end)

  it("test_auto_purchase_candidates_skip_a_maxed_gold_item", function()
    local game = support.new_game()
    local player = game:current_player()
    game:set_player_cash(player, 5000 * (LIMIT + 1))
    _with_host(game, function()
      for _ = 1, LIMIT do
        _empty_inventory(player)
        _click_buy(game, player, GOLD_PRODUCT_ID)
      end
      _empty_inventory(player)
      for _, entry in ipairs(market_query.eligibility.list_available(player, game)) do
        luassert.is_not.equal(GOLD_PRODUCT_ID, entry.product_id, "maxed gold item is not a candidate")
      end
    end)
  end)
end)
