require("test.bootstrap").install_package_paths()
local luassert = require("luassert")

local function _reload_module(module_name, overrides, fn)
  local original = {}
  for key, value in pairs(overrides or {}) do
    original[key] = package.loaded[key]
    package.loaded[key] = value
  end
  local original_module = package.loaded[module_name]
  package.loaded[module_name] = nil
  local ok, result = pcall(function()
    local loaded = require(module_name)
    return fn(loaded)
  end)
  package.loaded[module_name] = original_module
  for key, value in pairs(original) do
    package.loaded[key] = value
  end
  if not ok then
    error(result)
  end
  return result
end

local function _make_query_mock(overrides)
  overrides = overrides or {}
  return {
    context = {
      entry_by_id = overrides.entry_by_id or function(product_id)
        return { product_id = product_id, kind = "item", currency = "金豆", name = "Paid Item" }
      end,
      entry_currency = overrides.entry_currency or function(entry)
        return entry.currency
      end,
      entry_price = overrides.entry_price or function(entry)
        return entry.price or 0
      end,
      entry_name = overrides.entry_name or function(entry)
        return entry.name or tostring(entry.product_id)
      end,
      is_paid_currency = overrides.is_paid_currency or function(currency)
        return currency == "金豆"
      end,
      assert_cash_currency = overrides.assert_cash_currency or function(currency)
        luassert.truthy(currency == "金币", "unsupported market currency: " .. tostring(currency))
      end,
      entry_market_enabled = overrides.entry_market_enabled or function() return true end,
      try_charge_player = overrides.try_charge_player or function() return true end,
    },
    eligibility = {},
  }
end

local function _make_choice_mock(feedback_fn)
  return {
    feedback = {
      emit_buy_failed = feedback_fn or function() end,
    },
    session = { refresh_after_paid_callback = function() end },
    builder = {},
    outcome = {},
  }
end


describe("TestMarketPurchase", function()
  it("test_purchase_execute_paid_purchase_success_and_failure", function()
    local start_calls = {}
    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock(),
      ["src.rules.market.choice"] = _make_choice_mock(function(player, entry, reason, body)
        start_calls[#start_calls + 1] = { failed = true, reason = reason, body = body }
      end),
      ["src.rules.ports.paid_purchase"] = {
        setup_for_game = function() end,
        start = function(_, _, entry)
          start_calls[#start_calls + 1] = { failed = false, product_id = entry.product_id }
          if #start_calls == 1 then
            return true
          end
          return false, "gateway_down"
        end,
      },
    }, function(purchase)
      local game = {}
      local player = { id = 3, name = "Buyer" }
      local success = purchase.execute(game, player, "2001", {})
      luassert.truthy(success.ok == true and success.deferred_fulfillment == true, "paid purchase should defer fulfillment on success")
      local failure = purchase.execute(game, player, "2001", {})
      luassert.truthy(failure.ok == false and failure.reason == "gateway_down", "paid purchase failure should preserve gateway reason")
    end)
    luassert.truthy(#start_calls == 3, "expected success start, failed start, and failure feedback")
    luassert.truthy(start_calls[1].product_id == 2001, "product id should be normalized before start")
    luassert.truthy(start_calls[3].failed == true and start_calls[3].reason == "gateway_down", "failure should emit feedback")
  end)

  it("test_handle_paid_purchase_logs_warning_on_failure", function()
    local start_calls = {}
    local warn_calls = {}
    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock(),
      ["src.rules.market.choice"] = _make_choice_mock(function(player, entry, reason, body)
        start_calls[#start_calls + 1] = { failed = true, reason = reason, body = body }
      end),
      ["src.rules.ports.paid_purchase"] = {
        setup_for_game = function() end,
        start = function(_, _, entry)
          return false, "payment_gateway_error"
        end,
      },
      ["src.foundation.log"] = {
        warn = function(...)
          warn_calls[#warn_calls + 1] = table.concat({ ... }, " ")
        end,
      },
    }, function(purchase)
      local game = {}
      local player = { id = 3, name = "Buyer" }
      local result = purchase.execute(game, player, "2001", {})
      luassert.truthy(result.ok == false, "should fail when gateway returns error")
      luassert.truthy(#warn_calls >= 1, "should log warning when gateway returns error")
      luassert.truthy(string.find(warn_calls[1], "market paid purchase blocked:", 1, true) ~= nil, "warning should use the single-path message")
    end)
  end)

  it("test_handle_paid_purchase_success_path", function()
    local start_calls = {}
    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock(),
      ["src.rules.market.choice"] = _make_choice_mock(),
      ["src.rules.ports.paid_purchase"] = {
        setup_for_game = function() end,
        start = function(_, _, entry)
          start_calls[#start_calls + 1] = { product_id = entry.product_id }
          return true
        end,
      },
    }, function(purchase)
      local game = {}
      local player = { id = 3, name = "Buyer" }
      local result = purchase.execute(game, player, "2001", {})
      luassert.truthy(result.ok == true, "should succeed when gateway returns true")
      luassert.truthy(result.deferred_fulfillment == true, "should indicate deferred fulfillment")
      luassert.truthy(result.kind == "item", "should preserve entry kind")
      luassert.truthy(result.product_id == 2001, "should preserve product_id")
      luassert.truthy(#start_calls == 1, "should call start once")
    end)
  end)

  it("test_purchase_execute_rejects_disabled_entries", function()
    local failures = {}
    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock({
        entry_by_id = function(product_id)
          return { product_id = product_id, kind = "item", currency = "金币", name = "Blocked Item" }
        end,
        entry_market_enabled = function()
          return false
        end,
        is_paid_currency = function()
          return false
        end,
      }),
      ["src.rules.market.choice"] = _make_choice_mock(function(_, entry, reason, body)
        failures[#failures + 1] = { entry = entry, reason = reason, body = body }
      end),
    }, function(purchase)
      local result = purchase.execute({}, { id = 3, name = "Buyer" }, "2001")
      luassert.truthy(result.ok == false, "disabled entries should be rejected")
      luassert.truthy(result.reason == "disabled", "disabled entries should keep disabled reason")
    end)
    luassert.truthy(#failures == 1, "disabled rejection should emit feedback")
    luassert.truthy(failures[1].reason == "disabled", "disabled feedback should keep reason")
    luassert.truthy(failures[1].body == "Buyer 该商品暂不可购买", "disabled feedback should keep body")
  end)

  it("test_purchase_execute_local_item_success_keeps_payload_and_exact_balance_boundary", function()
    local entry = { product_id = 1, kind = "item", currency = "金币", price = 7, name = "路障卡" }
    local give_calls = {}
    local give_contexts = {}
    local emitted = {}
    local published = {}
    local is_full_calls = 0

    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock({
        entry_by_id = function()
          return entry
        end,
        is_paid_currency = function()
          return false
        end,
      }),
      ["src.rules.items.inventory"] = {
        is_full = function()
          is_full_calls = is_full_calls + 1
          return is_full_calls > 1
        end,
        give = function(_, product_id, context)
          give_calls[#give_calls + 1] = product_id
          give_contexts[#give_contexts + 1] = context
        end,
      },
      ["src.foundation.events"] = {
        market = { bought_item = "mk.bought_item" },
        emit = function(kind, payload)
          emitted[#emitted + 1] = { kind = kind, payload = payload }
        end,
      },
      ["src.rules.ports.event_feed"] = {
        publish = function(_, payload)
          published[#published + 1] = payload
        end,
      },
      ["src.rules.market.choice"] = _make_choice_mock(),
    }, function(purchase)
      local game = {
        player_cash = function()
          return 7
        end,
      }
      local result = purchase.execute(game, { id = 3, name = "Buyer" }, "1")
      luassert.truthy(result.ok == true, "exact balance should be enough to buy")
      luassert.truthy(result.kind == "item", "local purchase should report item kind")
      luassert.truthy(result.product_id == 1, "local purchase should keep normalized product id")
      luassert.truthy(result.inventory_full_after == true, "result should report inventory fullness after giving item")
      luassert.truthy(result.fulfilled_now == true, "local item purchase should fulfill immediately")
    end)

    luassert.truthy(give_calls[1] == 1, "purchase should give the item")
    luassert.truthy(give_contexts[1] and give_contexts[1].game ~= nil, "purchase should pass game context to inventory give")
    luassert.truthy(emitted[1].kind == "mk.bought_item", "purchase should emit bought item event")
    luassert.truthy(emitted[1].payload.price == 7, "bought item payload should keep price")
    luassert.truthy(emitted[1].payload.currency == "金币", "bought item payload should keep currency")
    luassert.truthy(published[1].kind == "item_acquired", "purchase should publish item acquired feed")
    luassert.truthy(published[1].text == "Buyer 在黑市购买 路障卡 花费 7 金币", "feed should use priced success text")
  end)

  it("test_purchase_execute_reports_local_item_failures", function()
    local failures = {}
    local entry = { product_id = 2001, kind = "item", currency = "金币", price = 7, name = "路障卡" }

    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock({
        entry_by_id = function()
          return entry
        end,
        is_paid_currency = function()
          return false
        end,
      }),
      ["src.rules.market.choice"] = _make_choice_mock(function(_, _, reason, body)
        failures[#failures + 1] = { reason = reason, body = body }
      end),
    }, function(purchase)
      local game = {
        player_cash = function()
          return 6
        end,
      }
      local result = purchase.execute(game, { id = 3, name = "Buyer" }, "2001")
      luassert.truthy(result.ok == false, "insufficient balance should fail")
      luassert.truthy(result.reason == "insufficient_balance", "insufficient balance should keep reason")
      luassert.truthy(result.option_id == 2001, "insufficient balance should keep option id")
    end)
    luassert.truthy(failures[1].reason == "insufficient_balance", "insufficient balance should emit reason")
    luassert.truthy(failures[1].body == "Buyer 余额不足", "insufficient balance should emit body")

    failures = {}
    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock({
        entry_by_id = function()
          return entry
        end,
        is_paid_currency = function()
          return false
        end,
      }),
      ["src.rules.items.inventory"] = {
        is_full = function()
          return true
        end,
        give = function()
          error("full inventory should not receive item")
        end,
      },
      ["src.rules.market.choice"] = _make_choice_mock(function(_, _, reason, body)
        failures[#failures + 1] = { reason = reason, body = body }
      end),
    }, function(purchase)
      local game = {
        player_cash = function()
          return 7
        end,
      }
      local result = purchase.execute(game, { id = 3, name = "Buyer" }, "2001")
      luassert.truthy(result.ok == false, "full inventory should fail")
      luassert.truthy(result.reason == "inventory_full", "full inventory should keep reason")
    end)
    luassert.truthy(failures[1].reason == "inventory_full", "full inventory should emit reason")
    luassert.truthy(failures[1].body == "Buyer 卡槽已满", "full inventory should emit body")

    failures = {}
    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock({
        entry_by_id = function()
          return entry
        end,
        is_paid_currency = function()
          return false
        end,
        try_charge_player = function()
          return false
        end,
      }),
      ["src.rules.items.inventory"] = {
        is_full = function()
          return false
        end,
        give = function()
          error("charge failure should not receive item")
        end,
      },
      ["src.rules.market.choice"] = _make_choice_mock(function(_, _, reason, body)
        failures[#failures + 1] = { reason = reason, body = body }
      end),
    }, function(purchase)
      local game = {
        player_cash = function()
          return 7
        end,
      }
      local result = purchase.execute(game, { id = 3, name = "Buyer" }, "2001")
      luassert.truthy(result.ok == false, "charge failure should fail")
      luassert.truthy(result.reason == "charge_failed", "charge failure should keep reason")
    end)
    luassert.truthy(failures[1].reason == "charge_failed", "charge failure should emit reason")
    luassert.truthy(failures[1].body == "Buyer 支付失败", "charge failure should emit body")
  end)

  it("test_purchase_execute_hard_fails_before_charging_unknown_currency", function()
    local asserted = {}
    local entry = { product_id = 2001, kind = "item", currency = "贝壳", price = 5, name = "神秘货" }
    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock({
        entry_by_id = function()
          return entry
        end,
        is_paid_currency = function()
          return false
        end,
        assert_cash_currency = function(currency)
          asserted[#asserted + 1] = currency
          error("unsupported market currency: " .. tostring(currency))
        end,
      }),
      ["src.rules.items.inventory"] = {
        is_full = function()
          return false
        end,
        give = function()
          error("unknown currency must not fulfill item")
        end,
      },
      ["src.rules.market.choice"] = _make_choice_mock(),
    }, function(purchase)
      local game = {
        player_cash = function()
          error("unknown currency must not read cash balance")
        end,
        deduct_player_cash = function()
          error("unknown currency must not deduct cash balance")
        end,
      }
      local ok, err = pcall(purchase.execute, game, { id = 3, name = "Buyer" }, "2001")
      luassert.truthy(ok == false, "unknown currency purchase should hard fail")
      luassert.truthy(string.find(tostring(err), "unsupported market currency", 1, true) ~= nil, "error should surface unsupported market currency")
    end)
    luassert.truthy(#asserted == 1 and asserted[1] == "贝壳", "local purchase should validate entry currency before touching cash balance")
  end)

  it("test_purchase_execute_rejects_invalid_product_ids_with_public_result", function()
    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock({
        is_paid_currency = function()
          return false
        end,
      }),
      ["src.rules.market.choice"] = _make_choice_mock(),
      ["src.foundation.log"] = { warn = function() end },
    }, function(purchase)
      luassert.truthy(purchase.execute({}, { id = 3, name = "Buyer" }, "0") == false, "zero product id should be rejected")
      luassert.truthy(purchase.execute({}, { id = 3, name = "Buyer" }, "-1") == false, "negative product id should be rejected")
      luassert.truthy(purchase.execute({}, { id = 3, name = "Buyer" }, "bad") == false, "non-numeric product id should be rejected")
    end)
  end)

  it("test_paid_purchase_callback_clears_in_flight_and_fulfills_item", function()
    local entry = { product_id = 2001, kind = "item", currency = "金豆", price = 5, name = "Paid Item" }
    local callback = nil
    local give_calls = {}
    local refreshed = 0
    local emitted = {}
    local published = {}

    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock({
        entry_by_id = function()
          return entry
        end,
        try_charge_player = function(game, player, price)
          game:deduct_player_cash(player, price)
          return true
        end,
      }),
      ["src.rules.items.inventory"] = {
        is_full = function()
          return false
        end,
        give = function(_, product_id)
          give_calls[#give_calls + 1] = product_id
        end,
      },
      ["src.rules.ports.paid_purchase"] = {
        setup_for_game = function(_, on_purchase)
          callback = on_purchase
        end,
        start = function()
          return true
        end,
      },
      ["src.foundation.ports.runtime_ports"] = {
        schedule = function(_, fn)
          luassert.truthy(type(fn) == "function", "paid purchase should schedule in-flight cleanup")
        end,
      },
      ["src.foundation.events"] = {
        market = { bought_item = "mk.bought_item" },
        emit = function(kind, payload)
          emitted[#emitted + 1] = { kind = kind, payload = payload }
        end,
      },
      ["src.rules.ports.event_feed"] = {
        publish = function(_, payload)
          published[#published + 1] = payload
        end,
      },
      ["src.rules.market.choice"] = {
        feedback = { emit_buy_failed = function() end },
        session = {
          refresh_after_paid_callback = function()
            refreshed = refreshed + 1
          end,
        },
      },
    }, function(purchase)
      local game = { cash = 100 }
      local player = { id = 3, name = "Buyer" }
      function game:deduct_player_cash(_, price)
        self.cash = self.cash - price
      end
      local started = purchase.execute(game, player, "2001")
      luassert.truthy(started.ok == true, "paid purchase should start")
      luassert.truthy(game._market_paid_in_flight["3:2001"] == true, "paid purchase should mark in-flight")
      luassert.truthy(callback(game, player, entry) == true, "paid callback should fulfill item")
      luassert.truthy(game._market_paid_in_flight["3:2001"] == nil, "paid callback should clear in-flight")
      luassert.truthy(game.cash == 100, "paid callback fulfillment should leave local currency unchanged")
    end)

    luassert.truthy(give_calls[1] == 2001, "paid callback should give item")
    -- lint-allow: call-count session 端口经依赖注入,刷新次数即回调结果的对外输出
    luassert.truthy(refreshed == 1, "paid callback success should refresh market choice")
    luassert.truthy(emitted[1].payload.price == 5, "paid callback event should keep price")
    luassert.truthy(emitted[1].payload.currency == "金豆", "paid callback event should keep currency")
    luassert.truthy(published[1].text == "Buyer 在黑市购买 Paid Item 成功", "paid callback feed should use unpriced text")
  end)

  it("test_paid_purchase_paths_report_gateway_fallback_and_callback_failure", function()
    local failures = {}
    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock(),
      ["src.rules.ports.paid_purchase"] = {
        setup_for_game = function() end,
        start = function()
          return false, nil
        end,
      },
      ["src.rules.market.choice"] = _make_choice_mock(function(_, _, reason, body)
        failures[#failures + 1] = { reason = reason, body = body }
      end),
    }, function(purchase)
      local result = purchase.execute({}, { id = 3, name = "Buyer" }, "2001")
      luassert.truthy(result.ok == false, "gateway failure should fail")
      luassert.truthy(result.reason == "paid_purchase_start_failed", "nil gateway reason should use fallback")
    end)
    luassert.truthy(failures[1].reason == "paid_purchase_start_failed", "gateway fallback should emit fallback reason")
    luassert.truthy(failures[1].body == "Buyer 购买通道暂不可用", "gateway fallback should emit body")

    failures = {}
    local callback = nil
    local refreshed = 0
    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock(),
      ["src.rules.items.inventory"] = {
        is_full = function()
          return false
        end,
        give = function()
          error("unsupported callback entry should not give item")
        end,
      },
      ["src.rules.ports.paid_purchase"] = {
        setup_for_game = function(_, on_purchase)
          callback = on_purchase
        end,
        start = function()
          return true
        end,
      },
      ["src.foundation.ports.runtime_ports"] = {
        schedule = function() end,
      },
      ["src.rules.market.choice"] = {
        feedback = {
          emit_buy_failed = function(_, _, reason, body)
            failures[#failures + 1] = { reason = reason, body = body }
          end,
        },
        session = {
          refresh_after_paid_callback = function()
            refreshed = refreshed + 1
          end,
        },
      },
    }, function(purchase)
      local game = {}
      local player = { id = 3, name = "Buyer" }
      purchase.execute(game, player, "2001")
      luassert.truthy(callback(game, player, { product_id = 5001, kind = "skin", currency = "金豆", name = "Skin" }) == false, "paid callback should reject unsupported entries")
    end)
    luassert.truthy(failures[1].reason == "unsupported_kind", "unsupported callback entry should emit reason")
    -- lint-allow: call-count session 端口经依赖注入,刷新次数即回调结果的对外输出
    luassert.truthy(refreshed == 0, "unsupported callback entry should not refresh market choice")

    failures = {}
    callback = nil
    refreshed = 0
    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock(),
      ["src.rules.items.inventory"] = {
        is_full = function()
          return true
        end,
        give = function()
          error("callback failure should not give item")
        end,
      },
      ["src.rules.ports.paid_purchase"] = {
        setup_for_game = function(_, on_purchase)
          callback = on_purchase
        end,
        start = function()
          return true
        end,
      },
      ["src.foundation.ports.runtime_ports"] = {
        schedule = function() end,
      },
      ["src.rules.market.choice"] = {
        feedback = {
          emit_buy_failed = function(_, _, reason, body)
            failures[#failures + 1] = { reason = reason, body = body }
          end,
        },
        session = {
          refresh_after_paid_callback = function()
            refreshed = refreshed + 1
          end,
        },
      },
    }, function(purchase)
      local game = {}
      local player = { id = 3, name = "Buyer" }
      purchase.execute(game, player, "2001")
      luassert.truthy(callback(game, player, { product_id = 2001, kind = "item", currency = "金豆", name = "Paid Item" }) == false, "callback fulfillment failure should return false")
    end)
    luassert.truthy(failures[1].reason == "inventory_full", "callback failure should emit fulfillment reason")
    -- lint-allow: call-count session 端口经依赖注入,刷新次数即回调结果的对外输出
    luassert.truthy(refreshed == 0, "callback failure should not refresh market choice")
  end)

  it("test_purchase_execute_rejects_non_item_entries", function()
    local failures = {}
    _reload_module("src.rules.market.purchase", {
      ["src.rules.market.query"] = _make_query_mock({
        entry_by_id = function(product_id)
          return { product_id = product_id, kind = "skin", currency = "金币", name = "Retired Skin" }
        end,
        is_paid_currency = function()
          return false
        end,
      }),
      ["src.rules.market.choice"] = _make_choice_mock(function(_, entry, reason, body)
        failures[#failures + 1] = { entry = entry, reason = reason, body = body }
      end),
    }, function(purchase)
      local game = {}
      local player = { id = 3, name = "Buyer" }
      local result = purchase.execute(game, player, "5001", {})
      luassert.truthy(result.ok == false, "skin entries should be rejected by black-market purchase")
      luassert.truthy(result.reason == "unsupported_kind", "skin rejection should use unsupported_kind")
    end)
    luassert.truthy(#failures == 1, "rejected skin purchase should emit feedback")
    luassert.truthy(failures[1].entry.product_id == 5001, "feedback should include rejected entry")
    luassert.truthy(failures[1].reason == "unsupported_kind", "feedback should keep unsupported_kind reason")
  end)


end)
