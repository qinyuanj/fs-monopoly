-- effect_payments 直测:租金/税收执行器的 can_apply 判定与 apply 三路
-- (强卡 intent / 免费卡直执 / 现金兜底 + 税同类)。集成 spec 覆盖零星路径
-- (变异清扫 #259 survivor 真缺口闭合);land_actions / inventory / property_value /
-- choice_specs / event feed 口全桩,只留被测模块本体。
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local with_patches = support.with_patches
local item_ids = require("src.config.gameplay.item_ids")
local land_actions = require("src.rules.land.actions")
local land_choice_specs = require("src.rules.land.choice_specs")
local inventory = require("src.rules.items.inventory")
local property_value = require("src.rules.commerce.property_value")
local event_feed = require("src.rules.ports.event_feed")
local effect_payments = require("src.rules.land.effect_payments")

-- describe 级共享 fixture(_player / _land_tile / 桩工厂)→ 原样留在块内。
do
  local _player = { id = 1, name = "P" }
  local _land_tile = { id = 7, type = "land", name = "T" }

  -- game 桩:现金 / 挂起免租 / 挂起免税三个宿主方法按测试需要配置。
  local function _make_game(opts)
    opts = opts or {}
    return {
      player_cash = function()
        return opts.cash or 0
      end,
      consume_pending_free_rent = function()
        return opts.pending_free_rent == true
      end,
      consume_pending_tax_free = function()
        return opts.pending_tax_free == true
      end,
    }
  end

  -- 常规补丁:tile 状态/地主解析/三个执行器记录 + 持卡映射 + 投资总额。
  local function _make_patches(opts)
    opts = opts or {}
    local calls = { executors = {}, feeds = 0 }
    local card_map = opts.cards or {}
    local patches = {
      { target = land_actions, key = "safe_tile_state", value = function()
        return opts.tile_state or { owner_id = 2, level = 1 }
      end },
      { target = land_actions, key = "resolve_rent_owner", value = function()
        if opts.no_owner then
          return nil
        end
        return { id = 2 }, opts.tile_state or { owner_id = 2, level = 1 }
      end },
      { target = property_value, key = "total_invested", value = function()
        return opts.total_value or 500
      end },
      { target = inventory, key = "find_index", value = function(_, item_id)
        return card_map[item_id]
      end },
      { target = land_choice_specs, key = "rent_prompt", value = function()
        return { prompt = "rent" }
      end },
      { target = land_choice_specs, key = "tax_prompt", value = function()
        return { prompt = "tax" }
      end },
      { target = event_feed, key = "publish", value = function()
        calls.feeds = calls.feeds + 1
      end },
    }
    for _, name in ipairs({ "execute_free_card", "execute_pay_rent", "execute_pay_tax" }) do
      patches[#patches + 1] = { target = land_actions, key = name, value = function()
        calls.executors[#calls.executors + 1] = name
      end }
    end
    return calls, patches
  end

  local function _ctx(game, tile)
    return { game = game, player = _player, tile = tile }
  end

  describe("TestEffectPayments", function()
  it("test_pay_rent_can_apply_pins_the_owned_by_other_land_rule", function()
    local can_apply = effect_payments.executors.pay_rent.can_apply
    local _, patches = _make_patches()

    with_patches(patches, function()
      luassert.is_true(can_apply(_ctx(_make_game(), _land_tile)) == true, "owned by another player")
    end)

    local _, patches_unowned = _make_patches({ tile_state = { owner_id = nil, level = 0 } })
    with_patches(patches_unowned, function()
      luassert.truthy(not can_apply(_ctx(_make_game(), _land_tile)), "unowned land cannot charge rent")
    end)

    local _, patches_self = _make_patches({ tile_state = { owner_id = 1, level = 1 } })
    with_patches(patches_self, function()
      luassert.truthy(not can_apply(_ctx(_make_game(), _land_tile)), "own land cannot charge rent")
    end)

    luassert.truthy(not can_apply(_ctx(_make_game(), { id = 8, type = "tax" })), "non-land tile")
    luassert.has_error(function()
      can_apply(_ctx(_make_game(), nil))
    end, "missing tile")
  end)

  it("test_tax_can_apply_pins_the_tax_tile_rule", function()
    local can_apply = effect_payments.executors.tax.can_apply

    luassert.is_true(can_apply(_ctx(_make_game(), { id = 8, type = "tax" })) == true, "tax tile")
    luassert.truthy(not can_apply(_ctx(_make_game(), _land_tile)), "land tile is not taxable here")
    luassert.has_error(function()
      can_apply(_ctx(_make_game(), nil))
    end, "missing tile")
  end)

  it("test_pay_rent_apply_rejects_a_non_land_tile", function()
    luassert.has_error(function()
      effect_payments.executors.pay_rent.apply(_ctx(_make_game(), { id = 8, type = "tax" }))
    end, "invalid land tile")
  end)

  it("test_pay_rent_apply_asks_the_rent_choice_when_a_strong_card_covers_the_rent", function()
    -- 边界:cash 恰好 == total_value(>= 成立,> 不成立)。
    local calls, patches = _make_patches({ cards = { [item_ids.strong] = 1 } })
    local result
    with_patches(patches, function()
      result = effect_payments.executors.pay_rent.apply(_ctx(_make_game({ cash = 500 }), _land_tile))
    end)

    luassert.truthy(result ~= nil and result.waiting == true and result.reason == "rent_choice",
      "strong card path waits with rent_choice")
    luassert.truthy(result.intent ~= nil and result.intent.kind == "need_choice"
      and result.intent.choice_spec ~= nil and result.intent.choice_spec.prompt == "rent",
      "intent carries the rent_prompt choice spec")
    luassert.truthy(#calls.executors == 0, "no executor fires while waiting for the choice")
  end)

  it("test_pay_rent_apply_auto_plays_the_free_card_when_cash_cannot_cover_a_strong_card", function()
    local calls, patches = _make_patches({ cards = { [item_ids.strong] = 1, [item_ids.free_rent] = 2 } })
    local result
    with_patches(patches, function()
      result = effect_payments.executors.pay_rent.apply(_ctx(_make_game({ cash = 100 }), _land_tile))
    end)

    luassert.is_nil(result)
    luassert.truthy(#calls.executors == 1 and calls.executors[1] == "execute_free_card",
      "free card executes directly")
  end)

  it("test_pay_rent_apply_pays_cash_rent_with_no_usable_cards", function()
    local calls, patches = _make_patches({})
    local result
    with_patches(patches, function()
      result = effect_payments.executors.pay_rent.apply(_ctx(_make_game({ cash = 100 }), _land_tile))
    end)

    luassert.is_nil(result)
    luassert.truthy(#calls.executors == 1 and calls.executors[1] == "execute_pay_rent",
      "cash rent executes directly")
  end)

  it("test_pay_rent_apply_consumes_a_pending_free_rent_instead_of_charging", function()
    local calls, patches = _make_patches({})
    with_patches(patches, function()
      local result = effect_payments.executors.pay_rent.apply(
        _ctx(_make_game({ pending_free_rent = true }), _land_tile))
      luassert.is_nil(result)
    end)

    luassert.truthy(#calls.executors == 0, "pending free rent skips every executor")
    luassert.truthy(calls.feeds == 1, "free rent publishes its event")
  end)

  it("test_pay_rent_apply_does_nothing_when_the_tile_has_no_owner", function()
    local calls, patches = _make_patches({ no_owner = true })
    with_patches(patches, function()
      luassert.is_nil(effect_payments.executors.pay_rent.apply(_ctx(_make_game(), _land_tile)))
    end)

    luassert.truthy(#calls.executors == 0, "ownerless tile charges nobody")
  end)

  it("test_tax_apply_consumes_a_pending_tax_free_instead_of_charging", function()
    local calls, patches = _make_patches({})
    with_patches(patches, function()
      luassert.is_nil(effect_payments.executors.tax.apply(
        _ctx(_make_game({ pending_tax_free = true }), { id = 8, type = "tax" })))
    end)

    luassert.truthy(#calls.executors == 0, "pending tax-free skips the tax executor")
    luassert.truthy(calls.feeds == 1, "tax-free publishes its event")
  end)

  it("test_tax_apply_asks_the_tax_choice_when_a_tax_free_card_is_in_hand", function()
    local calls, patches = _make_patches({ cards = { [item_ids.tax_free] = 3 } })
    local result
    with_patches(patches, function()
      result = effect_payments.executors.tax.apply(_ctx(_make_game(), { id = 8, type = "tax" }))
    end)

    luassert.truthy(result ~= nil and result.waiting == true and result.reason == "tax_choice",
      "tax-free card path waits with tax_choice")
    luassert.truthy(result.intent ~= nil and result.intent.kind == "need_choice"
      and result.intent.choice_spec ~= nil and result.intent.choice_spec.prompt == "tax",
      "intent carries the tax_prompt choice spec")
    luassert.truthy(#calls.executors == 0, "no executor fires while waiting for the choice")
  end)

  it("test_tax_apply_pays_cash_tax_without_a_tax_free_card", function()
    local calls, patches = _make_patches({})
    with_patches(patches, function()
      luassert.is_nil(effect_payments.executors.tax.apply(_ctx(_make_game(), { id = 8, type = "tax" })))
    end)

    luassert.truthy(#calls.executors == 1 and calls.executors[1] == "execute_pay_tax",
      "cash tax executes directly")
  end)
end)
end
