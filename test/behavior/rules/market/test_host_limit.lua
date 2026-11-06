require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
-- 限购买满(#231):经真实选择解析与真实付费网关回调驱动,宿主只替身到 Role 与事件注册。
local support = require("test.support.shared_support")
local market_cfg = require("src.config.content.market")
local market_catalog = require("src.config.content.market_catalog")
local market_service = require("src.rules.market")
local market_feedback = require("src.rules.market.choice").feedback
local choice_resolver = require("src.rules.choice.resolver")
local inventory = require("src.rules.items.inventory")
local runtime_ports = require("src.foundation.ports.runtime_ports")

local PAID_PRODUCT_ID = 2012
local OTHER_PAID_PRODUCT_ID = 2004
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

local function _option(game, player, product_id)
  local spec = market_service.choice.build(player, game, { active_tab = "item", page_index = 1 })
  for _, option in ipairs(spec.options) do
    if option.id == product_id then
      return option
    end
  end
  error("missing market option: " .. tostring(product_id))
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

describe("TestMarketHostLimit", function()
  it("test_item_stays_buyable_until_the_limit_then_is_marked_and_blocked", function()
    local game = support.new_game()
    local player = game:current_player()
    _with_host(game, function(host)
      _buy_times(game, host, player, PAID_PRODUCT_ID, LIMIT - 1)
      _empty_inventory(player)
      local before = _option(game, player, PAID_PRODUCT_ID)
      luassert.is_true(before.can_buy, "9th purchase must leave the item buyable")
      luassert.is_not_true(before.host_limit_reached, "9 purchases are below the limit")

      _buy_times(game, host, player, PAID_PRODUCT_ID, 1)
      _empty_inventory(player)
      local after = _option(game, player, PAID_PRODUCT_ID)
      luassert.is_false(after.can_buy, "10th purchase must make the item unbuyable")
      luassert.is_true(after.host_limit_reached, "10th purchase must mark the option")

      local other = _option(game, player, OTHER_PAID_PRODUCT_ID)
      luassert.is_true(other.can_buy, "other products keep their own count")
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
      luassert.is.equal("host_limit_reached", failures[1].reason, "failure reason")
      luassert.is_truthy(failures[1].body:find("本局已买满", 1, true), "failure tip text")
    end)
  end)

  it("test_one_players_limit_does_not_touch_the_other_player", function()
    local game = support.new_game()
    local buyer, other = game.players[1], game.players[2]
    _with_host(game, function(host)
      _buy_times(game, host, buyer, PAID_PRODUCT_ID, LIMIT)
      local option = _option(game, other, PAID_PRODUCT_ID)
      luassert.is_true(option.can_buy, "other player's same product stays buyable")
      luassert.is_not_true(option.host_limit_reached, "other player's option is not marked")
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
      luassert.is_not_true(option.host_limit_reached, "a new game has no maxed items")
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
      local refreshed
      for _, option in ipairs(game.turn.pending_choice.options) do
        if option.id == PAID_PRODUCT_ID then
          refreshed = option
        end
      end
      luassert.is_true(refreshed.host_limit_reached, "host already charged, so the failed grant still counts")
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
      local rt = require("src.host.paid_purchase_gateway")._runtime(game)
      local queue = rt.pending_by_role_id[player.id]
      queue[#queue + 1] = {
        player_id = player.id,
        product_id = PAID_PRODUCT_ID,
        entry = market_catalog.entry_by_id(PAID_PRODUCT_ID),
        goods_id = _goods_id(PAID_PRODUCT_ID),
      }

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

      _host_callback(host, player, PAID_PRODUCT_ID)

      luassert.is.equal(0, inventory.count(player), "no pending record means no card is granted")
      local option = _option(game, player, PAID_PRODUCT_ID)
      luassert.is_true(option.host_limit_reached, "the host counted it, so the mirror counts it too")
    end)
  end)

  it("test_gold_item_has_no_limit", function()
    local game = support.new_game()
    local player = game:current_player()
    game:set_player_cash(player, 5000 * (LIMIT + 2))
    _with_host(game, function()
      for _ = 1, LIMIT + 1 do
        _empty_inventory(player)
        _click_buy(game, player, GOLD_PRODUCT_ID)
      end
      _empty_inventory(player)
      local option = _option(game, player, GOLD_PRODUCT_ID)
      luassert.is_true(option.can_buy, "gold items stay unlimited")
      luassert.is_not_true(option.host_limit_reached, "gold items are never maxed")
    end)
  end)
end)
