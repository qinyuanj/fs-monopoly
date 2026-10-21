-- paid-entry pin — src/app/cosmetics/transaction_purchase.lua 拼给
-- paid_purchase_port.start 的付费入场（paid entry）私有契约钉子。
--
-- 这条断言直测付费入场表的内部形状（entry.kind / product_id / currency /
-- price 与 on_purchase 履约回调），是子模块与 paid_purchase_port 之间的私有
-- 契约，没有门面级可观察替身。为降低门面 spec 的连带面（#241），从
-- test_cosmetics_transaction.lua 等价迁出，独立成本 pin spec。
-- 这里是内部契约的钉子而非门面行为规约：门面级可观察行为仍住门面 spec。
--
require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local with_patches = support.with_patches

local transaction = require("src.app.cosmetics.transaction")
local paid_purchase_port = require("src.rules.ports.paid_purchase")

local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end

local function _catalog()
  return {
    { product_id = "skin_1", name = "皮肤一", unlock = "purchase", currency = "金豆", price = 198 },
    { product_id = "skin_2", name = "皮肤二", unlock = "purchase", currency = "金豆", price = 198 },
  }
end

local function _state(player)
  player = player or { id = 1 }
  return {
    ui = {},
    game = {
      find_player_by_id = function(_, role_id)
        if tostring(role_id) == tostring(player.id) then
          return player
        end
        return nil
      end,
    },
  }, player
end

local function _archive(owned, equipped)
  local store = {
    owned = owned or {},
    equipped = equipped or {},
    marked = {},
  }
  return {
    store = store,
    -- ADR 0074:存档可写才放行购买;替身恒可写。
    can_persist = function()
      return true
    end,
    load_owned = function(role_id)
      return store.owned[tostring(role_id)]
    end,
    mark_owned = function(role_id, product_id)
      store.owned[tostring(role_id)] = store.owned[tostring(role_id)] or {}
      store.owned[tostring(role_id)][#store.owned[tostring(role_id)] + 1] = product_id
      store.marked[#store.marked + 1] = product_id
      return true
    end,
    load_equipped = function(role_id)
      return store.equipped[tostring(role_id)]
    end,
    save_equipped = function(role_id, product_id)
      store.equipped[tostring(role_id)] = product_id
    end,
  }
end

describe("TestCosmeticsTransactionPaidEntryPin", function()
  before_each(function()
    transaction.reset_for_tests()
    transaction.configure_catalog_for_tests(_catalog())
    transaction.configure_archive(_archive())
  end)
  after_each(function()
    transaction.reset_for_tests()
    paid_purchase_port.reset_for_tests()
    support.restore_runtime_services()
  end)

it("test_locked_purchase_starts_paid_entry_and_completion_fulfills_original_product", function()
  local state, player = _state()
  local archive = _archive()
  local equipped = {}
  local captured = nil
  transaction.configure_archive(archive)
  transaction.configure_equip(function(_, skin)
    equipped[#equipped + 1] = skin.product_id
    return true
  end)

  transaction.handle_skin_transaction(state, 1, { type = "open" })

  with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function(game, start_player, entry)
        captured = { game = game, player = start_player, entry = entry }
        return true
      end,
    },
  }, function()
    local result = transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
    luassert.truthy(result.accepted == true, "purchase start should be accepted")
    luassert.truthy(result.pending_purchase == true, "locked purchase should create pending purchase")
  end)

  _assert_eq(captured and captured.game, state.game, "paid entry should use state game")
  _assert_eq(captured and captured.player, player, "paid entry should use resolved player")
  _assert_eq(captured and captured.entry.kind, "skin", "paid entry should be tagged as skin")
  _assert_eq(captured and captured.entry.product_id, "skin_1", "paid entry should keep product id")
  _assert_eq(captured and captured.entry.currency, "金豆", "paid entry should keep currency")
  _assert_eq(captured and captured.entry.price, 198, "paid entry should keep price")

  state.ui.skin_panel.page_index = 2
  _assert_eq(captured.entry.on_purchase(), true, "host callback should fulfill through transaction seam")
  _assert_eq(state.ui.skin_panel.owned_by_role["1"]["skin_1"], true, "fulfilled purchase should mark owned")
  _assert_eq(state.ui.skin_panel.selected_by_role["1"], "skin_1", "fulfilled purchase should equip original product")
  _assert_eq(equipped[1], "skin_1", "fulfillment should apply equip adapter")
  _assert_eq(archive.store.marked[1], "skin_1", "fulfillment should persist ownership")
end)
end)
