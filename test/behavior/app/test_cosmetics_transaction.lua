-- 门面级可观察行为规约。内部子模块直测已按 #241 等价迁出:
--   * transaction_state / transaction_result 内部形状 →
--     test_cosmetics_transaction_state_pin.lua（read-model/state pin）
--   * transaction_purchase 付费入场私有契约 →
--     test_cosmetics_transaction_paid_entry_pin.lua（paid-entry pin）
--
require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local with_patches = support.with_patches

local transaction = require("src.app.cosmetics.transaction")
local transaction_purchase = require("src.app.cosmetics.transaction_purchase")
local paid_purchase_port = require("src.rules.ports.paid_purchase")

local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end

local function _assert_rejected(result, reason)
  luassert.truthy(result and result.accepted == false, "transaction should reject")
  _assert_eq(result.reason, reason, "rejection reason should be stable")
end

local function _catalog()
  return {
    { product_id = "skin_1", name = "皮肤一", unlock = "purchase", currency = "金豆", price = 198 },
    { product_id = "skin_2", name = "皮肤二", unlock = "purchase", currency = "金豆", price = 198 },
  }
end

local function _catalog_size(count)
  local catalog = {}
  for i = 1, count do
    catalog[#catalog + 1] = {
      product_id = "skin_" .. tostring(i),
      name = "皮肤" .. tostring(i),
      unlock = "purchase",
      currency = "金豆",
      price = 198,
    }
  end
  return catalog
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

describe("TestCosmeticsTransaction", function()
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

local function _test_open_restores_owned_and_auto_equips_archived_skin()
  local state = _state()
  local archive = _archive({ ["1"] = { "skin_1" } }, { ["1"] = "skin_1" })
  local equipped = {}
  transaction.configure_archive(archive)
  transaction.configure_equip(function(role_id, skin)
    equipped[#equipped + 1] = { role_id = role_id, product_id = skin.product_id }
    return true
  end)

  local result = transaction.handle_skin_transaction(state, 1, { type = "open" })

  luassert.truthy(result.accepted == true, "open should be accepted")
  _assert_eq(state.ui.skin_panel.owned_by_role["1"]["skin_1"], true, "archive owned skin should seed panel state")
  _assert_eq(state.ui.skin_panel.selected_by_role["1"], "skin_1", "owned archived equipped skin should be selected")
  _assert_eq(equipped[1] and equipped[1].product_id, "skin_1", "open should apply equipped skin to host adapter")
end

local function _test_page_commands_return_results_and_support_aliases()
  transaction.configure_catalog_for_tests(_catalog_size(7))
  local state = _state()
  transaction.handle_skin_transaction(state, 1, { type = "open" })

  local next_result = transaction.handle_skin_transaction(state, 1, "next")
  luassert.truthy(next_result.accepted == true, "next alias should be accepted")
  _assert_eq(next_result.action, "page", "next alias should return a page result")
  _assert_eq(next_result.slot_view_dirty, true, "page result should dirty slots")
  _assert_eq(state.ui.skin_panel.page_index, 2, "next alias should advance the page")

  local page_next_result = transaction.handle_skin_transaction(state, 1, { type = "page_next" })
  luassert.truthy(page_next_result.accepted == true, "page_next should be accepted at max page")
  _assert_eq(state.ui.skin_panel.page_index, 2, "page_next should clamp at max page")

  local prev_result = transaction.handle_skin_transaction(state, 1, "prev")
  luassert.truthy(prev_result.accepted == true, "prev alias should be accepted")
  _assert_eq(prev_result.action, "page", "prev alias should return a page result")
  _assert_eq(state.ui.skin_panel.page_index, 1, "prev alias should move back")

  local page_prev_result = transaction.handle_skin_transaction(state, 1, { type = "page_prev" })
  luassert.truthy(page_prev_result.accepted == true, "page_prev should be accepted at min page")
  _assert_eq(state.ui.skin_panel.page_index, 1, "page_prev should clamp at min page")
end

local function _test_page_prev_from_second_page_moves_back_one_page()
  -- #293:L160 `-1` -> `0` 只在非钳制位置可分;钳制位两种变异观测相同。
  transaction.configure_catalog_for_tests(_catalog_size(7))
  local state = _state()
  transaction.handle_skin_transaction(state, 1, { type = "open" })
  transaction.handle_skin_transaction(state, 1, "next")
  _assert_eq(state.ui.skin_panel.page_index, 2, "precondition: second page")
  local back = transaction.handle_skin_transaction(state, 1, { type = "page_prev" })
  _assert_eq(back.accepted, true, "page_prev should accept")
  _assert_eq(state.ui.skin_panel.page_index, 1, "page_prev should move back one page")
end

local function _test_open_and_close_results_carry_dirty_and_role_fallback_fields()
  -- #293:open 的 slot_view_dirty 与 close 的 role_id 回落未断言。
  local state = _state()
  local opened = transaction.handle_skin_transaction(state, 1, { type = "open" })
  _assert_eq(opened.slot_view_dirty, true, "open result should dirty slots")
  local closed = transaction.handle_skin_transaction(state, nil, { type = "close" })
  _assert_eq(closed.accepted, true, "close should accept")
  _assert_eq(closed.role_id, 1, "close without role_id should fall back to panel.role_id")
end

local function _test_unlock_result_carries_ownership_and_dirty_fields()
  -- #293:unlock 结果的 ownership_changed/slot_view_dirty 未断言。
  local state = _state()
  transaction.handle_skin_transaction(state, 1, { type = "open" })
  local unlock = transaction.handle_skin_transaction(state, 1, {
    type = "unlock_slot",
    slot_index = 1,
  })
  _assert_eq(unlock.accepted, true, "unlock should accept")
  _assert_eq(unlock.action, "unlock", "unlock action")
  _assert_eq(unlock.ownership_changed, true, "unlock should mark ownership changed")
  _assert_eq(unlock.slot_view_dirty, true, "unlock should dirty slots")
end

local function _test_unequip_result_fields_and_notification()
  -- #293:unequip 结果的 unequipped/slot_view_dirty/host_action_attempted/
  -- notification 未断言;无适配器时 host_action_attempted 应显式 false。
  local state = _state()
  transaction.handle_skin_transaction(state, 1, { type = "open" })
  transaction.handle_skin_transaction(state, 1, { type = "unlock_slot", slot_index = 1 })
  local unequip = transaction.handle_skin_transaction(state, 1, { type = "unequip" })
  _assert_eq(unequip.accepted, true, "unequip should accept")
  _assert_eq(unequip.unequipped, true, "unequip should mark unequipped")
  _assert_eq(unequip.slot_view_dirty, true, "unequip should dirty slots")
  _assert_eq(unequip.host_action_attempted, false,
    "without an unequip adapter host_action_attempted should be false")
  _assert_eq(unequip.notification, "已脱下皮肤", "unequip should notify")
end

local function _test_unlock_commands_support_request_slot_aliases_sources_and_string_fallbacks()
  transaction.configure_catalog_for_tests(_catalog_size(3))
  local state = _state()
  local archive = _archive()
  transaction.configure_archive(archive)
  transaction.handle_skin_transaction(state, 1, { type = "open" })

  local purchase_result = transaction.handle_skin_transaction(state, 1, {
    type = "unlock_slot",
    index = 2,
    source = "purchase",
  })
  luassert.truthy(purchase_result.accepted == true, "unlock_slot with index alias should be accepted")
  _assert_eq(purchase_result.action, "unlock", "unlock_slot should return an unlock result")
  _assert_eq(purchase_result.product_id, "skin_2", "index alias should select the indexed skin")
  _assert_eq(archive.store.marked[1], "skin_2", "purchase source should persist ownership")

  local gift_result = transaction.handle_skin_transaction(state, 1, {
    type = "gift",
    slot = 3,
  })
  luassert.truthy(gift_result.accepted == true, "gift with slot alias should be accepted")
  _assert_eq(gift_result.product_id, "skin_3", "slot alias should select the requested skin")

  local buy_result = transaction.handle_skin_transaction(state, 1, "buy")
  luassert.truthy(buy_result.accepted == true, "string buy should use the fallback handler")
  _assert_eq(buy_result.product_id, "skin_1", "string buy should default to slot 1")

  local table_buy_result = transaction.handle_skin_transaction(state, 1, { type = "buy" })
  luassert.truthy(table_buy_result.accepted == true, "table buy without slot should be accepted")
  _assert_eq(table_buy_result.product_id, "skin_1", "table buy should default to slot 1")

  local string_gift_result = transaction.handle_skin_transaction(state, 1, "gift")
  luassert.truthy(string_gift_result.accepted == true, "string gift should use the fallback handler")
  _assert_eq(string_gift_result.product_id, "skin_1", "string gift should default to slot 1")
end

local function _test_unknown_transaction_returns_stable_rejection_with_panel()
  local state = _state()
  state.ui.skin_panel = {
    open = true,
    page_index = 1,
    owned_by_role = {},
    selected_by_role = {},
  }
  local existing_panel = state.ui.skin_panel

  local result = transaction.handle_skin_transaction(state, 1, { type = "bogus" })

  _assert_rejected(result, "unknown_skin_transaction")
  luassert.truthy(result.panel == existing_panel, "unknown transaction should still expose the ensured panel")
end

local function _test_locked_purchase_rejects_missing_paid_purchase_contexts()
  local missing_game = { ui = {} }
  transaction.handle_skin_transaction(missing_game, 1, { type = "open" })
  _assert_rejected(
    transaction.handle_skin_transaction(missing_game, 1, { type = "equip_slot", slot_index = 1 }),
    "missing_game"
  )

  local missing_lookup = { ui = {}, game = {} }
  transaction.handle_skin_transaction(missing_lookup, 1, { type = "open" })
  _assert_rejected(
    transaction.handle_skin_transaction(missing_lookup, 1, { type = "equip_slot", slot_index = 1 }),
    "missing_player_lookup"
  )

  local missing_player = {
    ui = {},
    game = {
      find_player_by_id = function()
        return nil
      end,
    },
  }
  transaction.handle_skin_transaction(missing_player, 1, { type = "open" })
  _assert_rejected(
    transaction.handle_skin_transaction(missing_player, 1, { type = "equip_slot", slot_index = 1 }),
    "missing_player"
  )
end

local function _test_locked_purchase_preserves_paid_gateway_rejection_reasons_and_clears_pending()
  local state = _state()
  local starts = 0
  transaction.handle_skin_transaction(state, 1, { type = "open" })

  with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function()
        starts = starts + 1
        return false, "gateway_says_no"
      end,
    },
  }, function()
    _assert_rejected(
      transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 }),
      "gateway_says_no"
    )
    _assert_rejected(
      transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 }),
      "gateway_says_no"
    )
  end)

  _assert_eq(starts, 2, "failed paid gateway starts should clear pending state")
end

local function _test_locked_purchase_uses_default_paid_gateway_rejection_reason()
  local state = _state()
  transaction.handle_skin_transaction(state, 1, { type = "open" })

  with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function()
        return false
      end,
    },
  }, function()
    _assert_rejected(
      transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 }),
      "paid_gateway_rejected"
    )
  end)
end

local function _test_locked_purchase_rejects_paid_gateway_errors()
  local state = _state()
  transaction.handle_skin_transaction(state, 1, { type = "open" })

  with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function()
        error("gateway unavailable")
      end,
    },
  }, function()
    _assert_rejected(
      transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 }),
      "paid_gateway_missing"
    )
  end)
end

local function _test_complete_skin_purchase_rejects_duplicate_or_mismatched_callback()
  local state = _state()
  local captured = nil
  transaction.handle_skin_transaction(state, 1, { type = "open" })

  with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function(_, _, entry)
        captured = entry
        return true
      end,
    },
  }, function()
    transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
  end)

  local mismatch = transaction.complete_skin_purchase(state, 1, "skin_2")
  luassert.truthy(mismatch.accepted == false, "wrong product callback should reject")
  _assert_eq(mismatch.reason, "pending_purchase_mismatch", "wrong callback should have stable reason")

  _assert_eq(captured.on_purchase(), true, "original callback should still fulfill")
  local duplicate = transaction.complete_skin_purchase(state, 1, "skin_1")
  luassert.truthy(duplicate.accepted == false, "duplicate callback should reject")
  _assert_eq(duplicate.reason, "pending_purchase_missing", "duplicate callback should have stable reason")
end

local function _test_complete_skin_purchase_success_marks_purchase_complete_fields()
  -- #293:complete_skin_purchase 成功路径的 action/fulfilled/ownership 字段
  -- 未被断言,三个字段位变异存活;补钉后击杀。
  local state = _state()
  transaction.handle_skin_transaction(state, 1, { type = "open" })
  with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function()
        return true
      end,
    },
  }, function()
    transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
  end)
  local result = transaction.complete_skin_purchase(state, 1, "skin_1")
  _assert_eq(result.accepted, true, "valid completion should accept")
  _assert_eq(result.action, "purchase_complete", "completion action should be purchase_complete")
  _assert_eq(result.purchase_fulfilled, true, "purchase should be marked fulfilled")
  _assert_eq(result.ownership_changed, true, "ownership should be marked changed")
end

local function _test_complete_skin_purchase_rejects_unknown_product_reason()
  -- #293:pending 商品在目录中消失 → missing_product 拒绝路径未测。
  local state = _state()
  transaction.handle_skin_transaction(state, 1, { type = "open" })
  with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function()
        return true
      end,
    },
  }, function()
    transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
  end)
  transaction.configure_catalog_for_tests({})
  local missing = transaction.complete_skin_purchase(state, 1, "skin_1")
  _assert_eq(missing.accepted, false, "unknown product should reject")
  _assert_eq(missing.reason, "missing_product", "unknown product should carry missing_product reason")
  transaction.configure_catalog_for_tests(_catalog())
end

local function _test_purchase_start_rejects_unlock_gift_with_notification()
  -- #293:unlock ~= "purchase" 的拒绝带 notification,路径未测。
  local state = _state()
  transaction.handle_skin_transaction(state, 1, { type = "open" })
  with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function()
        return true
      end,
    },
  }, function()
    -- 默认目录 slot 1 是 purchase 皮肤;换 gift 皮肤后重开
    transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
  end)
  transaction.configure_catalog_for_tests({
    { product_id = "gift_skin", name = "礼包皮", unlock = "gift", currency = "金豆", price = 0 },
  })
  transaction.handle_skin_transaction(state, 1, { type = "open" })
  local rejected = transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
  _assert_eq(rejected.accepted, false, "gift skin should reject purchase start")
  _assert_eq(rejected.reason, "invalid_purchase_skin", "gift skin should carry invalid_purchase_skin")
  _assert_eq(rejected.notification, "皮肤尚未解锁", "gift skin rejection should notify")
  transaction.configure_catalog_for_tests(_catalog())
end

local function _test_purchase_start_rejects_missing_product_id_with_notification()
  -- #293:product_id 缺失的拒绝带 notification,路径未测。
  local state = _state()
  transaction.configure_catalog_for_tests({
    { name = "无 id 皮", unlock = "purchase", currency = "金豆", price = 198 },
  })
  transaction.handle_skin_transaction(state, 1, { type = "open" })
  local rejected = transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
  _assert_eq(rejected.reason, "invalid_purchase_skin", "missing product_id should reject")
  _assert_eq(rejected.notification, "皮肤尚未解锁", "missing product_id rejection should notify")
  transaction.configure_catalog_for_tests(_catalog())
end

local function _test_purchase_start_failed_rejects_with_notification()
  -- #293:付费网关拒绝时的 reason/notification 路径未测。
  local state = _state()
  transaction.handle_skin_transaction(state, 1, { type = "open" })
  with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function()
        return false
      end,
    },
  }, function()
    local rejected = transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
    _assert_eq(rejected.accepted, false, "gateway rejection should reject")
    _assert_eq(rejected.reason, "paid_gateway_rejected", "gateway rejection should carry stable reason")
    _assert_eq(rejected.notification, "皮肤尚未解锁", "gateway rejection should notify")
  end)
end

local function _test_purchase_start_marks_host_action_attempted()
  -- #293:accepted 结果的 host_action_attempted 字段未测。
  local state = _state()
  transaction.handle_skin_transaction(state, 1, { type = "open" })
  with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function()
        return true
      end,
    },
  }, function()
    local started = transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
    _assert_eq(started.accepted, true, "purchase start should accept")
    _assert_eq(started.host_action_attempted, true, "host action should be marked attempted")
  end)
end

local function _test_pin_native_paid_path_builds_a_skin_paid_entry_and_fulfills_without_any_ui_on_success()
  -- 皮肤付费购买只有一条 transaction_purchase 原生 _start_via_paid_port 路径:
  -- 拼 paid entry -> paid_purchase_port.start -> entry.on_purchase 履约。
  local state = _state()
  transaction.configure_equip(function() return true end)
  transaction.handle_skin_transaction(state, 1, { type = "open" })

  local captured = nil
  with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function(_, _, entry)
        captured = entry
        return true
      end,
    },
  }, function()
    local started = transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 1 })
    luassert.truthy(started.accepted == true, "native paid path should accept the purchase start")
    _assert_eq(started.action, "purchase_start", "start returns pending purchase_start")
    _assert_eq(started.pending_purchase, true, "start marks pending purchase")
  end)

  -- entry 由 transaction_purchase._purchase_entry 拼出，携带 skin 商品信息。
  _assert_eq(captured ~= nil, true, "native path must reach paid_purchase_port.start")
  _assert_eq(captured.kind, "skin", "entry is tagged as skin")
  _assert_eq(captured.product_id, "skin_1", "entry carries the pending product id")
  luassert.truthy(captured.name ~= nil, "entry carries display name")
  luassert.truthy(captured.on_purchase ~= nil, "entry carries an on_purchase fulfillment")

  -- 履约：on_purchase 走内部 complete_skin_purchase，无 UI on_success 闭包。
  local fulfilled = captured.on_purchase()
  _assert_eq(fulfilled, true, "fulfillment reports success")
  _assert_eq(state.ui.skin_panel.selected_by_role["1"], "skin_1",
    "native fulfillment equips the purchased skin")
end

local function _test_locked_purchase_rejects_invalid_purchase_inputs_and_duplicate_starts()
  local missing_slot_state = _state()
  transaction.handle_skin_transaction(missing_slot_state, 1, { type = "open" })
  _assert_rejected(
    transaction.handle_skin_transaction(missing_slot_state, 1, { type = "equip_slot", slot_index = 9 }),
    "missing_skin"
  )

  transaction.configure_catalog_for_tests({
    { product_id = "gift_skin", name = "礼物皮肤", unlock = "gift" },
  })
  local gift_state = _state()
  transaction.handle_skin_transaction(gift_state, 1, { type = "open" })
  _assert_rejected(
    transaction.handle_skin_transaction(gift_state, 1, { type = "equip_slot", slot_index = 1 }),
    "invalid_purchase_skin"
  )

  transaction.configure_catalog_for_tests({
    { name = "缺失商品", unlock = "purchase" },
  })
  local missing_product_state = _state()
  transaction.handle_skin_transaction(missing_product_state, 1, { type = "open" })
  _assert_rejected(
    transaction.handle_skin_transaction(missing_product_state, 1, { type = "equip_slot", slot_index = 1 }),
    "invalid_purchase_skin"
  )

  transaction.configure_catalog_for_tests(_catalog())
  local missing_role_state = _state()
  transaction.handle_skin_transaction(missing_role_state, nil, { type = "open" })
  _assert_rejected(
    transaction.handle_skin_transaction(missing_role_state, nil, { type = "equip_slot", slot_index = 1 }),
    "missing_role"
  )

  local duplicate_state = _state()
  transaction.handle_skin_transaction(duplicate_state, 1, { type = "open" })
  with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function()
        return true
      end,
    },
  }, function()
    local first = transaction.handle_skin_transaction(duplicate_state, 1, { type = "equip_slot", slot_index = 1 })
    luassert.truthy(first.accepted == true, "first purchase start should be accepted")
    _assert_rejected(
      transaction.handle_skin_transaction(duplicate_state, 1, { type = "equip_slot", slot_index = 1 }),
      "purchase_in_flight"
    )
  end)
end

local function _test_purchase_module_guards_internal_public_entrypoints()
  local state = _state()
  transaction.handle_skin_transaction(state, 1, { type = "open" })
  local panel = state.ui.skin_panel

  _assert_rejected(
    transaction_purchase.start(state, panel, 1, nil, function()
      return true
    end),
    "missing_skin"
  )

  panel.pending_skin_purchase_by_role["1"] = { product_id = "skin_1" }
  transaction_purchase.clear_pending(panel, nil)
  luassert.truthy(panel.pending_skin_purchase_by_role["1"] ~= nil, "nil role clear should leave existing pending state intact")
end

local function _test_is_slot_equipped_guards_panel_role_and_slot_state()
  luassert.truthy(transaction.is_slot_equipped(nil, 1) == false, "nil root state should not report equipped")
  luassert.truthy(transaction.is_slot_equipped({ ui = {} }, 1) == false, "missing panel should not report equipped")

  local state = _state()
  transaction.handle_skin_transaction(state, 1, { type = "open" })
  luassert.truthy(transaction.is_slot_equipped(state, 1) == false, "unselected skin should not report equipped")
  luassert.truthy(transaction.is_slot_equipped(state, 9) == false, "missing catalog slot should not report equipped")

  local panel = state.ui.skin_panel
  panel.role_id = nil
  panel.selected_by_role["1"] = "skin_1"
  luassert.truthy(transaction.is_slot_equipped(state, 1) == false, "missing panel role should not report equipped")

  panel.role_id = 1
  luassert.truthy(transaction.is_slot_equipped(state, 1) == true, "selected skin should report equipped")
  luassert.truthy(transaction.is_slot_equipped(state, 2) == false, "different slot should not report equipped")

  panel.role_id = 2
  luassert.truthy(transaction.is_slot_equipped(state, 1) == false, "selection should be scoped to panel role")
end

local function _test_slot_view_models_expose_transaction_owned_slot_state()
  transaction.configure_catalog_for_tests({
    { product_id = "skin_1", name = "购买皮肤", unlock = "purchase", currency = "金豆", price = 198 },
    { product_id = "skin_2", name = "已装备皮肤", unlock = "purchase", currency = "金豆", price = 198 },
    { product_id = "skin_3", name = "赠礼皮肤", unlock = "gift", gift_name = "谢礼" },
  })
  transaction.configure_archive(_archive({ ["1"] = { "skin_2", "skin_3" } }, { ["1"] = "skin_2" }))
  transaction.configure_equip(function()
    return true
  end)
  local state = _state()

  transaction.handle_skin_transaction(state, 1, { type = "open" })

  local views = transaction.slot_view_models(state)
  _assert_eq(views[1].product_id, "skin_1", "view should expose the first product id")
  _assert_eq(views[1].status, "locked", "unowned purchase skin should be locked")
  _assert_eq(views[1].button_text, "198", "locked purchase should expose price button text")
  _assert_eq(views[1].button_touch_enabled, true, "locked purchase should be touchable")
  _assert_eq(views[1].price_icon_visible, true, "locked priced purchase should show price icon")

  _assert_eq(views[2].status, "equipped", "archived equipped skin should render as equipped")
  _assert_eq(views[2].button_text, "脱下", "equipped skin should expose unequip text")
  _assert_eq(views[2].price_icon_visible, false, "equipped skin should hide price icon")

  _assert_eq(views[3].status, "owned", "archived gift skin should render as owned")
  _assert_eq(views[3].button_text, "穿上", "owned skin should expose equip text")
  _assert_eq(views[3].button_touch_enabled, true, "owned skin should be touchable")

  _assert_eq(views[4].status, "empty", "missing catalog entries should render empty slots")
  _assert_eq(views[4].has_skin, false, "empty slot should report no skin")
  _assert_eq(views[4].button_text, "", "empty slot should have no button text")
  _assert_eq(views[4].button_touch_enabled, false, "empty slot should not be touchable")
  _assert_eq(views[4].price_icon_visible, false, "empty slot should hide price icon")

  _assert_eq(transaction.slot_view_model(state, 2).status, "equipped",
    "single-slot view should use the same transaction-owned status")
  _assert_eq(transaction.equipped_product(state), "skin_2",
    "transaction should expose the currently equipped product")
end

local function _test_activate_slot_owns_equip_or_unequip_decision()
  local state = _state()
  transaction.configure_equip(function()
    return true
  end)
  transaction.configure_unequip(function()
    return true
  end)
  transaction.handle_skin_transaction(state, 1, { type = "open" })
  transaction.handle_skin_transaction(state, 1, { type = "unlock_slot", slot_index = 1 })

  local equip = transaction.handle_skin_transaction(state, 1, { type = "activate_slot", slot_index = 1 })
  luassert.truthy(equip.accepted == true, "activate_slot should equip an owned inactive slot")
  _assert_eq(equip.action, "equip", "activate_slot should return the equip result when inactive")
  _assert_eq(transaction.equipped_product(state), "skin_1", "activate_slot equip should select the skin")

  local unequip = transaction.handle_skin_transaction(state, 1, { type = "activate_slot", slot_index = 1 })
  luassert.truthy(unequip.accepted == true, "activate_slot should unequip the active slot")
  _assert_eq(unequip.action, "unequip", "activate_slot should return the unequip result when active")
  _assert_eq(transaction.equipped_product(state), nil, "activate_slot unequip should clear the selection")
end

local function _test_activate_slot_honors_explicit_role_over_panel_owner()
  local state = _state()
  transaction.configure_equip(function()
    return true
  end)
  transaction.handle_skin_transaction(state, 1, { type = "open" })
  transaction.handle_skin_transaction(state, 2, { type = "unlock_slot", slot_index = 2 })

  local equip = transaction.handle_skin_transaction(state, 2, { type = "activate_slot", slot_index = 2 })
  luassert.truthy(equip.accepted == true, "explicit-role activate_slot should equip for the given role")
  _assert_eq(transaction.equipped_product(state, 2), "skin_2",
    "activate_slot should equip for the explicit role, not the panel owner")
  _assert_eq(transaction.equipped_product(state, 1), nil,
    "panel owner should stay unequipped when another role activates")
end

local function _test_owned_skin_equips_without_paid_purchase_and_unequip_clears_archive()
  local state = _state()
  local archive = _archive({ ["1"] = { "skin_2" } }, {})
  local paid_starts = 0
  local unequipped = nil
  transaction.configure_archive(archive)
  transaction.configure_equip(function() return true end)
  transaction.configure_unequip(function(role_id) unequipped = role_id end)
  transaction.handle_skin_transaction(state, 1, { type = "open" })

  with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function()
        paid_starts = paid_starts + 1
        return true
      end,
    },
  }, function()
    local equip_result = transaction.handle_skin_transaction(state, 1, { type = "equip_slot", slot_index = 2 })
    luassert.truthy(equip_result.accepted == true, "owned skin should equip")
  end)

  _assert_eq(paid_starts, 0, "owned equip should not start paid purchase")
  _assert_eq(state.ui.skin_panel.selected_by_role["1"], "skin_2", "owned equip should select product")

  local unequip_result = transaction.handle_skin_transaction(state, 1, { type = "unequip" })
  luassert.truthy(unequip_result.accepted == true, "unequip should be accepted")
  _assert_eq(state.ui.skin_panel.selected_by_role["1"], nil, "unequip should clear selected product")
  _assert_eq(archive.store.equipped["1"], nil, "unequip should persist cleared equipped product")
  _assert_eq(unequipped, 1, "unequip should call host adapter")
end


local function _test_equip_slot_rejects_when_panel_state_missing()
  _assert_rejected(
    transaction.handle_skin_transaction({}, 1, { type = "equip_slot", slot_index = 1 }),
    "missing_state"
  )
end


it("test_open_restores_owned_and_auto_equips_archived_skin", _test_open_restores_owned_and_auto_equips_archived_skin)
it("test_page_commands_return_results_and_support_aliases", _test_page_commands_return_results_and_support_aliases)
it("test_page_prev_from_second_page_moves_back_one_page", _test_page_prev_from_second_page_moves_back_one_page)
it("test_open_and_close_results_carry_dirty_and_role_fallback_fields", _test_open_and_close_results_carry_dirty_and_role_fallback_fields)
it("test_unlock_result_carries_ownership_and_dirty_fields", _test_unlock_result_carries_ownership_and_dirty_fields)
it("test_unequip_result_fields_and_notification", _test_unequip_result_fields_and_notification)
it("test_unlock_commands_support_request_slot_aliases_sources_and_string_fallbacks", _test_unlock_commands_support_request_slot_aliases_sources_and_string_fallbacks)
it("test_unknown_transaction_returns_stable_rejection_with_panel", _test_unknown_transaction_returns_stable_rejection_with_panel)
it("test_locked_purchase_rejects_missing_paid_purchase_contexts", _test_locked_purchase_rejects_missing_paid_purchase_contexts)
it("test_locked_purchase_preserves_paid_gateway_rejection_reasons_and_clears_pending", _test_locked_purchase_preserves_paid_gateway_rejection_reasons_and_clears_pending)
it("test_locked_purchase_uses_default_paid_gateway_rejection_reason", _test_locked_purchase_uses_default_paid_gateway_rejection_reason)
it("test_locked_purchase_rejects_paid_gateway_errors", _test_locked_purchase_rejects_paid_gateway_errors)
it("test_complete_skin_purchase_rejects_duplicate_or_mismatched_callback", _test_complete_skin_purchase_rejects_duplicate_or_mismatched_callback)
it("test_complete_skin_purchase_success_marks_purchase_complete_fields", _test_complete_skin_purchase_success_marks_purchase_complete_fields)
it("test_complete_skin_purchase_rejects_unknown_product_reason", _test_complete_skin_purchase_rejects_unknown_product_reason)
it("test_purchase_start_rejects_unlock_gift_with_notification", _test_purchase_start_rejects_unlock_gift_with_notification)
it("test_purchase_start_rejects_missing_product_id_with_notification", _test_purchase_start_rejects_missing_product_id_with_notification)
it("test_purchase_start_failed_rejects_with_notification", _test_purchase_start_failed_rejects_with_notification)
it("test_purchase_start_marks_host_action_attempted", _test_purchase_start_marks_host_action_attempted)
it("test_pin_native_paid_path_builds_a_skin_paid_entry_and_fulfills_without_any_ui_on_success", _test_pin_native_paid_path_builds_a_skin_paid_entry_and_fulfills_without_any_ui_on_success)
it("test_locked_purchase_rejects_invalid_purchase_inputs_and_duplicate_starts", _test_locked_purchase_rejects_invalid_purchase_inputs_and_duplicate_starts)
it("test_purchase_module_guards_internal_public_entrypoints", _test_purchase_module_guards_internal_public_entrypoints)
it("test_is_slot_equipped_guards_panel_role_and_slot_state", _test_is_slot_equipped_guards_panel_role_and_slot_state)
it("test_slot_view_models_expose_transaction_owned_slot_state", _test_slot_view_models_expose_transaction_owned_slot_state)
it("test_activate_slot_owns_equip_or_unequip_decision", _test_activate_slot_owns_equip_or_unequip_decision)
it("test_activate_slot_honors_explicit_role_over_panel_owner", _test_activate_slot_honors_explicit_role_over_panel_owner)
it("test_owned_skin_equips_without_paid_purchase_and_unequip_clears_archive", _test_owned_skin_equips_without_paid_purchase_and_unequip_clears_archive)
it("test_equip_slot_rejects_when_panel_state_missing", _test_equip_slot_rejects_when_panel_state_missing)
end)
