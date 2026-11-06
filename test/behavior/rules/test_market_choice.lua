require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
local saved_modules
local patched_events = require("src.foundation.events")
local patched_choice_contract = require("src.config.choice.contract")
local saved_emit, saved_owner_resolver
before_each(function()
  saved_emit = patched_events.emit
  saved_owner_resolver = patched_choice_contract.resolve_owner_role_id
  saved_modules = {}
  for name, module in pairs(package.loaded) do saved_modules[name] = module end
end)
after_each(function()
  patched_events.emit = saved_emit
  patched_choice_contract.resolve_owner_role_id = saved_owner_resolver
  for name in pairs(package.loaded) do
    if saved_modules[name] == nil then package.loaded[name] = nil end
  end
  for name, module in pairs(saved_modules) do package.loaded[name] = module end
end)
---@diagnostic disable: need-check-nil, different-requires, undefined-field


-- ===== 段 1:market_choice 主 describe(2 例,带配置 reset) =====
do
local _config_reset = require("test.support.config_reset")



describe("TestMarketChoice", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_append_visible_entries_respects_limit", function()
    local eligibility = require("src.rules.market.query").eligibility

    local entries = eligibility.sorted_entries()
    local visible = {}
    local limit = 3

    local hit_limit = eligibility._append_visible_entries(visible, entries, true, limit)

    if #entries >= limit then
      luassert.truthy(#visible == limit, "append_visible_entries should respect limit")
      luassert.truthy(hit_limit == true, "append_visible_entries should return true when limit hit")
    end
  end)

  it("test_append_visible_entries_without_limit_adds_all", function()
    local eligibility = require("src.rules.market.query").eligibility

    local entries = eligibility.sorted_entries()
    local visible = {}

    local hit_limit = eligibility._append_visible_entries(visible, entries, true, nil)

    luassert.truthy(#visible == #entries, "append_visible_entries without limit should add all entries")
    luassert.truthy(hit_limit == false, "append_visible_entries should return false when no limit")
  end)
end)
end

-- ===== 段 2:builder.build / session.* / feedback(30 例) =====
do
local P = require("test.support.shared_support")
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _with_patches = P.with_patches

local choice = require("src.rules.market.choice")
local market_query = require("src.rules.market.query")
local dirty_tracker = require("src.state.dirty_tracker")

local function _ok(val, msg)
  luassert.truthy(val, msg or "expected truthy")
end

local function _stub_player(id)
  return {
    id = id,
    name = "player_" .. tostring(id),
    inventory = {
      items = {},
      count = 0,
      is_full = function() return false end,
    },
  }
end

local function _make_pending_choice(player_id)
  return {
    kind = "market_buy",
    owner_role_id = player_id,
    active_tab = "item",
    page_index = 1,
    page_count = 1,
  }
end

local function _patch_market_query_empty()
  return {
    { target = market_query.eligibility, key = "sorted_entries", value = function() return {} end },
    { target = market_query.eligibility, key = "can_buy_entry", value = function() return false end },
    { target = market_query.eligibility, key = "can_buy_with_free_slot", value = function() return false end },
    { target = market_query.context, key = "entry_market_enabled", value = function() return true end },
    { target = market_query.context, key = "entry_name", value = function() return "item" end },
    { target = market_query.context, key = "entry_price", value = function() return 100 end },
    { target = market_query.context, key = "entry_currency", value = function() return "gold" end },
    { target = dirty_tracker, key = "mark", value = function() end },
  }
end


describe("TestMarketChoiceSession", function()
  it("test_builder_build_returns_market_buy_kind", function()
    local player = _stub_player(1)
    local game = {}

    _with_patches(_patch_market_query_empty(), function()
      local spec = choice.builder.build(player, game, {})
      _assert_eq(spec.kind, "market_buy", "should be market_buy kind")
      _assert_eq(spec.route_key, "market", "should route to market")
      _assert_eq(spec.owner_role_id, player.id, "owner should be player")
    end)
  end)

  it("test_builder_build_defaults_active_tab_to_item_when_nil", function()
    local player = _stub_player(1)
    local game = {}

    _with_patches(_patch_market_query_empty(), function()
      local spec = choice.builder.build(player, game, { active_tab = nil })
      _assert_eq(spec.active_tab, "item", "should default to item tab")
    end)
  end)

  it("test_builder_build_keeps_valid_active_tab", function()
    local player = _stub_player(1)
    local game = {}

    _with_patches(_patch_market_query_empty(), function()
      local spec = choice.builder.build(player, game, { active_tab = "item" })
      _assert_eq(spec.active_tab, "item", "should keep item tab")
    end)
  end)

  it("test_builder_build_rejects_invalid_active_tab_and_defaults_to_item", function()
    local player = _stub_player(1)
    local game = {}

    _with_patches(_patch_market_query_empty(), function()
      local spec = choice.builder.build(player, game, { active_tab = "nonexistent" })
      _assert_eq(spec.active_tab, "item", "should default to item for invalid tab")
    end)
  end)

  it("test_builder_build_clamps_page_index_to_valid_range", function()
    local player = _stub_player(1)
    local game = {}

    _with_patches(_patch_market_query_empty(), function()
      local spec = choice.builder.build(player, game, { page_index = 99 })
      _ok(spec.page_index >= 1, "page_index should be at least 1")
      _ok(spec.page_index <= spec.page_count, "page_index should not exceed page_count")
    end)
  end)

  it("test_builder_build_handles_nil_page_index", function()
    local player = _stub_player(1)
    local game = {}

    _with_patches(_patch_market_query_empty(), function()
      local spec = choice.builder.build(player, game, { page_index = nil })
      _assert_eq(spec.page_index, 1, "nil page_index should default to 1")
    end)
  end)

  it("test_builder_build_sets_allow_cancel_and_cancel_label", function()
    local player = _stub_player(1)
    local game = {}

    _with_patches(_patch_market_query_empty(), function()
      local spec = choice.builder.build(player, game, {})
      _ok(spec.allow_cancel == true, "should allow cancel")
      _assert_eq(spec.cancel_label, "不买", "cancel label should be 不买")
    end)
  end)

  it("test_builder_build_includes_meta_with_player_id_and_pagination_state", function()
    local player = _stub_player(1)
    local game = {}

    _with_patches(_patch_market_query_empty(), function()
      local spec = choice.builder.build(player, game, {})
      _ok(spec.meta ~= nil, "should have meta")
      _assert_eq(spec.meta.player_id, player.id, "meta should have player_id")
      _assert_eq(spec.meta.active_tab, spec.active_tab, "meta should mirror active_tab")
      _assert_eq(spec.meta.page_index, spec.page_index, "meta should mirror page_index")
      _assert_eq(spec.meta.page_count, spec.page_count, "meta should mirror page_count")
    end)
  end)

  it("test_builder_build_defaults_state_to_empty_table_when_nil", function()
    local player = _stub_player(1)
    local game = {}

    _with_patches(_patch_market_query_empty(), function()
      local spec = choice.builder.build(player, game, nil)
      _assert_eq(spec.active_tab, "item", "should default to item")
      _assert_eq(spec.page_index, 1, "should default page to 1")
    end)
  end)

  it("test_rebuild_pending_returns_false_when_game_is_nil", function()
    local pending = _make_pending_choice(1)
    local player = _stub_player(1)

    local ok = choice.session.rebuild_pending(nil, pending, player, {})
    _ok(ok == false, "should return false when game is nil")
  end)

  it("test_rebuild_pending_returns_false_when_pending_choice_is_nil", function()
    local player = _stub_player(1)
    local game = {}

    local ok = choice.session.rebuild_pending(game, nil, player, {})
    _ok(ok == false, "should return false when pending_choice is nil")
  end)

  it("test_rebuild_pending_returns_false_when_pending_choice_kind_is_not_market_buy", function()
    local player = _stub_player(1)
    local game = {}
    local pending = { kind = "other" }

    local ok = choice.session.rebuild_pending(game, pending, player, {})
    _ok(ok == false, "should return false for non-market_buy kind")
  end)

  it("test_rebuild_pending_returns_false_when_player_is_nil", function()
    local game = {}
    local pending = _make_pending_choice(1)

    local ok = choice.session.rebuild_pending(game, pending, nil, {})
    _ok(ok == false, "should return false when player is nil")
  end)

  it("test_rebuild_pending_returns_true_on_success_and_updates_pending_choice", function()
    local player = _stub_player(1)
    local game = {}
    local pending = _make_pending_choice(1)

    _with_patches(_patch_market_query_empty(), function()
      local ok = choice.session.rebuild_pending(game, pending, player, {})
      _ok(ok == true, "should return true on success")
      _assert_eq(pending.kind, "market_buy", "pending kind should be updated")
    end)
  end)

  it("test_apply_navigation_returns_false_when_game_is_nil", function()
    local pending = _make_pending_choice(1)
    local ok = choice.session.apply_navigation(nil, pending, { type = "market_tab_select", tab = "item" })
    _ok(ok == false, "should return false when game is nil")
  end)

  it("test_apply_navigation_returns_false_when_pending_choice_is_nil", function()
    local player = _stub_player(1)
    local game = { find_player_by_id = function() return player end }
    local ok = choice.session.apply_navigation(game, nil, { type = "market_tab_select", tab = "item" })
    _ok(ok == false, "should return false when pending_choice is nil")
  end)

  it("test_apply_navigation_returns_false_when_pending_choice_kind_is_not_market_buy", function()
    local player = _stub_player(1)
    local game = { find_player_by_id = function() return player end }
    local pending = { kind = "other" }
    local ok = choice.session.apply_navigation(game, pending, { type = "market_tab_select", tab = "item" })
    _ok(ok == false, "should return false for non-market_buy kind")
  end)

  it("test_apply_navigation_returns_false_when_owner_role_id_is_nil", function()
    local player = _stub_player(1)
    local game = { find_player_by_id = function() return player end }
    local pending = _make_pending_choice(1)
    pending.owner_role_id = nil

    local ok = choice.session.apply_navigation(game, pending, { type = "market_tab_select", tab = "item" })
    _ok(ok == false, "should return false when owner_role_id is nil")
  end)

  it("test_apply_navigation_returns_false_when_player_not_found", function()
    local game = { find_player_by_id = function() return nil end }
    local pending = _make_pending_choice(1)

    local ok = choice.session.apply_navigation(game, pending, { type = "market_tab_select", tab = "item" })
    _ok(ok == false, "should return false when player not found")
  end)

  it("test_apply_navigation_returns_true_unchanged_when_tab_is_same", function()
    local player = _stub_player(1)
    local game = { find_player_by_id = function() return player end }
    local pending = _make_pending_choice(1)
    pending.active_tab = "item"

    _with_patches(_patch_market_query_empty(), function()
      local ok = choice.session.apply_navigation(game, pending, { type = "market_tab_select", tab = "item" })
      _ok(ok == true, "should return true when tab unchanged")
    end)
  end)

  it("test_apply_navigation_switches_tab_and_resets_page_on_tab_select", function()
    local player = _stub_player(1)
    local game = { find_player_by_id = function() return player end }
    local pending = _make_pending_choice(1)
    pending.active_tab = "item"
    pending.page_index = 3

    _with_patches(_patch_market_query_empty(), function()
      local ok = choice.session.apply_navigation(game, pending, { type = "market_tab_select", tab = "item" })
      _ok(ok == true, "should succeed on tab switch")
    end)
  end)

  it("test_apply_navigation_decrements_page_on_page_prev", function()
    local player = _stub_player(1)
    local game = { find_player_by_id = function() return player end }
    local pending = _make_pending_choice(1)
    pending.active_tab = "item"
    pending.page_index = 3
    pending.page_count = 5

    local entries = {}
    for i = 1, 25 do
      entries[#entries + 1] = { kind = "item", product_id = i, market_enabled = true }
    end

    _with_patches({
      { target = market_query.eligibility, key = "sorted_entries", value = function() return entries end },
      { target = market_query.eligibility, key = "can_buy_entry", value = function() return true end },
      { target = market_query.eligibility, key = "can_buy_with_free_slot", value = function() return true end },
      { target = market_query.context, key = "entry_market_enabled", value = function() return true end },
      { target = market_query.context, key = "entry_name", value = function() return "item" end },
      { target = market_query.context, key = "entry_price", value = function() return 100 end },
      { target = market_query.context, key = "entry_currency", value = function() return "gold" end },
      { target = dirty_tracker, key = "mark", value = function() end },
    }, function()
      local ok = choice.session.apply_navigation(game, pending, { type = "market_page_prev" })
      _ok(ok == true, "should succeed on page_prev")
      _assert_eq(pending.page_index, 2, "page should decrement")
    end)
  end)

  it("test_apply_navigation_increments_page_on_page_next", function()
    local player = _stub_player(1)
    local game = { find_player_by_id = function() return player end }
    local pending = _make_pending_choice(1)
    pending.active_tab = "item"
    pending.page_index = 1
    pending.page_count = 5

    local entries = {}
    for i = 1, 25 do
      entries[#entries + 1] = { kind = "item", product_id = i, market_enabled = true }
    end

    _with_patches({
      { target = market_query.eligibility, key = "sorted_entries", value = function() return entries end },
      { target = market_query.eligibility, key = "can_buy_entry", value = function() return true end },
      { target = market_query.eligibility, key = "can_buy_with_free_slot", value = function() return true end },
      { target = market_query.context, key = "entry_market_enabled", value = function() return true end },
      { target = market_query.context, key = "entry_name", value = function() return "item" end },
      { target = market_query.context, key = "entry_price", value = function() return 100 end },
      { target = market_query.context, key = "entry_currency", value = function() return "gold" end },
      { target = dirty_tracker, key = "mark", value = function() end },
    }, function()
      local ok = choice.session.apply_navigation(game, pending, { type = "market_page_next" })
      _ok(ok == true, "should succeed on page_next")
      _assert_eq(pending.page_index, 2, "page should increment")
    end)
  end)

  it("test_apply_navigation_returns_true_for_unknown_action_type_without_changes", function()
    local player = _stub_player(1)
    local game = { find_player_by_id = function() return player end }
    local pending = _make_pending_choice(1)
    local original_tab = pending.active_tab
    local original_page = pending.page_index

    _with_patches(_patch_market_query_empty(), function()
      local ok = choice.session.apply_navigation(game, pending, { type = "unknown_action" })
      _ok(ok == true, "should succeed for unknown action")
      _assert_eq(pending.active_tab, original_tab, "tab should not change")
      _assert_eq(pending.page_index, original_page, "page should not change")
    end)
  end)

  it("test_feedback_emit_buy_failed_does_not_error_with_valid_inputs", function()
    local player = _stub_player(1)
    local ok = pcall(choice.feedback.emit_buy_failed, player, { id = 1 }, "no_gold", "金币不足")
    _ok(ok, "emit_buy_failed should not error")
  end)

  it("test_feedback_emit_inventory_full_does_not_error_with_valid_inputs", function()
    local player = _stub_player(1)
    local ok = pcall(choice.feedback.emit_inventory_full, player, { id = 1 })
    _ok(ok, "emit_inventory_full should not error")
  end)

  it("test_refresh_after_paid_callback_returns_false_when_game_is_nil", function()
    local player = _stub_player(1)
    local entry = { id = 1 }

    local ok = choice.session.refresh_after_paid_callback(nil, player, entry)
    _ok(ok == false, "should return false when game is nil")
  end)

  it("test_refresh_after_paid_callback_returns_false_when_no_pending_choice", function()
    local game = { turn = {} }
    local player = _stub_player(1)
    local entry = { id = 1 }

    local ok = choice.session.refresh_after_paid_callback(game, player, entry)
    _ok(ok == false, "should return false when no pending_choice")
  end)

  it("test_refresh_after_paid_callback_returns_false_when_pending_choice_is_not_market_buy", function()
    local game = { turn = { pending_choice = { kind = "other" } } }
    local player = _stub_player(1)
    local entry = { id = 1 }

    local ok = choice.session.refresh_after_paid_callback(game, player, entry)
    _ok(ok == false, "should return false for non-market_buy")
  end)

  it("test_refresh_after_paid_callback_returns_false_when_turn_is_nil", function()
    local game = {}
    local player = _stub_player(1)
    local entry = { id = 1 }

    local ok = choice.session.refresh_after_paid_callback(game, player, entry)
    _ok(ok == false, "should return false when turn is nil")
  end)
end)
end

-- ===== 段 3:extra_survivors(23 例) =====
do
local P = require("test.support.shared_support")
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _with_patches = P.with_patches

local choice = require("src.rules.market.choice")
local purchase_settlement = require("src.rules.market.purchase_settlement")
local market_query = require("src.rules.market.query")
local dirty_tracker = require("src.state.dirty_tracker")
local choice_contract = require("src.config.choice.contract")
local monopoly_event = require("src.foundation.events")

local function _stub_player(id) return { id = id } end

local function _make_entries(n)
  local list = {}
  for i = 1, n do
    list[i] = {
      product_id = "p" .. i, name = "n_" .. i, price = 100, currency = "金币",
      kind = "item", market_enabled = true,
    }
  end
  return list
end

local function _patch_market_query(entries, dirty_mark_calls)
  return {
    { target = market_query.eligibility, key = "sorted_entries", value = function() return entries end },
    { target = market_query.eligibility, key = "can_buy_entry", value = function() return true end },
    { target = market_query.eligibility, key = "can_buy_with_free_slot", value = function() return true end },
    { target = market_query.context, key = "entry_market_enabled", value = function() return true end },
    { target = market_query.context, key = "entry_name", value = function(e) return e.name end },
    { target = market_query.context, key = "entry_price", value = function(e) return e.price end },
    { target = market_query.context, key = "entry_currency", value = function(e) return e.currency end },
    { target = dirty_tracker, key = "mark", value = function(d, domain)
      d.any = true
      d[domain] = true
      if dirty_mark_calls then
        dirty_mark_calls[#dirty_mark_calls + 1] = domain
      end
    end },
  }
end


describe("TestMarketChoiceExtraSurvivors", function()
  it("test_game.dirty present → marks 'turn' and 'market' domains", function()
    local mark_calls = {}
    local game = { dirty = { any = false, turn = false, market = false } }
    local pc = { kind = "market_buy", owner_role_id = 1, active_tab = "item", page_index = 1, page_count = 1 }
    _with_patches(_patch_market_query(_make_entries(3), mark_calls), function()
      local ok = choice.session.rebuild_pending(game, pc, _stub_player(1), {})
      _assert_eq(ok, true, "rebuild must succeed")
    end)
    -- mark_calls should include "turn" and "market"
    local turn_seen, market_seen = false, false
    for _, domain in ipairs(mark_calls) do
      if domain == "turn" then turn_seen = true end
      if domain == "market" then market_seen = true end
    end
    luassert.truthy(turn_seen, "_mark_choice_dirty must mark 'turn'")
    luassert.truthy(market_seen, "_mark_choice_dirty must mark 'market'")
  end)

  it("test_game.dirty nil → early return, no mark calls", function()
    local mark_calls = {}
    local game = { dirty = nil }
    local pc = { kind = "market_buy", owner_role_id = 1, active_tab = "item", page_index = 1, page_count = 1 }
    _with_patches(_patch_market_query(_make_entries(2), mark_calls), function()
      local ok = choice.session.rebuild_pending(game, pc, _stub_player(1), {})
      _assert_eq(ok, true, "rebuild succeeds even without dirty tracker")
    end)
    _assert_eq(#mark_calls, 0, "L144 guard: no marks when game.dirty is nil")
  end)

  it("test_current_choice_state_copies_active_tab_and_page_index", function()
    local pc = {
      kind = "market_buy", owner_role_id = 1,
      active_tab = "item", page_index = 2, page_count = 3,
    }
    local game = { dirty = { any = false } }
    _with_patches(_patch_market_query(_make_entries(25)), function()
      -- state arg = nil → triggers `state or _current_choice_state(pending_choice)`
      local ok = choice.session.rebuild_pending(game, pc, _stub_player(1), nil)
      _assert_eq(ok, true, "rebuild must succeed via _current_choice_state")
      _assert_eq(pc.active_tab, "item", "active_tab survives the round-trip from _current_choice_state")
      _assert_eq(pc.page_index, 2, "page_index 2 from pc must drive builder via _current_choice_state")
    end)
  end)

  it("test_nil pending_choice fields → builder receives nil → defaults applied", function()
    local pc = {
      kind = "market_buy", owner_role_id = 1,
      active_tab = nil, page_index = nil, page_count = nil,
    }
    local game = { dirty = { any = false } }
    _with_patches(_patch_market_query(_make_entries(5)), function()
      local ok = choice.session.rebuild_pending(game, pc, _stub_player(1), nil)
      _assert_eq(ok, true, "rebuild succeeds with nil fields → defaults")
      _assert_eq(pc.active_tab, "item", "nil active_tab defaults to 'item'")
      _assert_eq(pc.page_index, 1, "nil page_index defaults to 1 via _clamp_page")
    end)
  end)

  it("test_nil game → false (L177 guard)", function()
    _assert_eq(choice.session.rebuild_pending(nil, { kind = "market_buy" }, _stub_player(1), {}), false,
      "nil game must yield false")
  end)

  it("test_nil pending_choice → false (L177 guard)", function()
    _assert_eq(choice.session.rebuild_pending({}, nil, _stub_player(1), {}), false,
      "nil pending_choice must yield false")
  end)

  it("test_pending_choice.kind != 'market_buy' → false (L177 guard)", function()
    _assert_eq(choice.session.rebuild_pending({}, { kind = "other" }, _stub_player(1), {}), false,
      "non-market_buy kind must yield false")
  end)

  it("test_nil player → false (L181 guard)", function()
    _assert_eq(choice.session.rebuild_pending({}, { kind = "market_buy" }, nil, {}), false,
      "nil player must yield false")
  end)

  it("test_tab_change_resets_page_index_to_1", function()
    -- Drive via session.apply_navigation with action.tab != pending_choice.active_tab.
    -- Since TAB_ITEM is the only tab, builder.build will normalize back to "item",
    -- but the intermediate state still shows page_index reset to 1.
    local game = {
      find_player_by_id = function() return _stub_player(1) end,
      dirty = { any = false },
      turn = {},
    }
    local pc = {
      kind = "market_buy", owner_role_id = 1,
      active_tab = "item", page_index = 3, page_count = 3,
    }
    _with_patches(_patch_market_query(_make_entries(25)), function()
      -- action.tab "different_tab" != pending_choice.active_tab "item" → page_index reset to 1
      local ok = choice.session.apply_navigation(game, pc,
        { type = "market_tab_select", tab = "different_tab" })
      _assert_eq(ok, true, "tab change must apply")
      _assert_eq(pc.page_index, 1, "L199: tab change resets page_index to 1")
    end)
  end)

  it("test_result.ok != true → not keep_open", function()
    local v = purchase_settlement.resolve({}, {}, _stub_player(1), { kind = "item" }, { ok = false })
    _assert_eq(v.keep_open, false, "non-keep-open + non-failure-stay path must not keep open")
  end)

  it("test_result.deferred_fulfillment=true → keep_open", function()
    local mark_calls = {}
    local game = { dirty = { any = false } }
    local pc = { kind = "market_buy", owner_role_id = 1, active_tab = "item", page_index = 1, page_count = 1 }
    local v
    _with_patches(_patch_market_query(_make_entries(2), mark_calls), function()
      v = purchase_settlement.resolve(game, pc, _stub_player(1),
        { kind = "item" }, { ok = true, deferred_fulfillment = true })
    end)
    _assert_eq(v.keep_open, true, "deferred_fulfillment=true must yield keep_open=true")
  end)

  it("test_result.fulfilled_now=true + entry.kind='item' → keep_open", function()
    local mark_calls = {}
    local game = { dirty = { any = false } }
    local pc = { kind = "market_buy", owner_role_id = 1, active_tab = "item", page_index = 1, page_count = 1 }
    local v
    _with_patches(_patch_market_query(_make_entries(2), mark_calls), function()
      v = purchase_settlement.resolve(game, pc, _stub_player(1),
        { kind = "item" }, { ok = true, fulfilled_now = true })
    end)
    _assert_eq(v.keep_open, true, "fulfilled_now=true + entry.kind='item' must yield keep_open=true")
  end)

  it("test_result.fulfilled_now=true but entry.kind='other' → NOT keep_open → finish path", function()
    local mark_calls = {}
    local game = { dirty = { any = false } }
    local pc = { kind = "market_buy", owner_role_id = 1, active_tab = "item", page_index = 1, page_count = 1 }
    local v
    _with_patches(_patch_market_query(_make_entries(2), mark_calls), function()
      v = purchase_settlement.resolve(game, pc, _stub_player(1),
        { kind = "other" }, { ok = true, fulfilled_now = true })
    end)
    _assert_eq(v.keep_open, false, "non-item kind blocks keep_open even with fulfilled_now=true")
  end)

end)
local function _reload_settlement_with_emit_stub(captured_ref)
  local prev_emit = monopoly_event.emit
  monopoly_event.emit = function(kind, payload)
    captured_ref.kind = kind
    captured_ref.payload = payload
  end
  -- 串行全跑(crap_collect adapter)时 test_market.lua 的 _reload_market_service
  -- 已把 package.loaded["src.rules.market.query"] 换成新表;reload choice 前钉回
  -- 本文件捕获的顶层表,保证 fresh 模块与 _patch_market_query 的 patch 目标一致。
  package.loaded["src.rules.market.query"] = market_query
  package.loaded["src.rules.market.choice"] = nil
  package.loaded["src.rules.market.purchase_settlement"] = nil
  local fresh = require("src.rules.market.purchase_settlement")
  monopoly_event.emit = prev_emit
  package.loaded["src.rules.market.query"] = market_query
  package.loaded["src.rules.market.choice"] = nil
  package.loaded["src.rules.market.purchase_settlement"] = nil
  require("src.rules.market.choice")
  require("src.rules.market.purchase_settlement")
  return fresh
end

describe("TestMarketChoiceExtraSurvivors", function()
  it("test_full_buy: entry.kind='item' + fulfilled_now=true + inventory_full_after=true → emit_inventory_full", function()
    local emitted = {}
    local fresh = _reload_settlement_with_emit_stub(emitted)

    local game = { dirty = { any = false } }
    local pc = { kind = "market_buy", owner_role_id = 1, active_tab = "item", page_index = 1, page_count = 1 }
    local v
    _with_patches(_patch_market_query(_make_entries(2)), function()
      v = fresh.resolve(game, pc, _stub_player(1),
        { kind = "item" }, { ok = true, fulfilled_now = true, inventory_full_after = true })
    end)
    _assert_eq(v.keep_open, true, "should keep open")
    luassert.truthy(emitted ~= nil, "inventory_full event must be emitted on full_buy path")
    _assert_eq(emitted.payload.body, "卡槽已满，无法继续购买", "inventory full body literal")
  end)

  it("test_not_full_buy_no_emit_inventory_full", function()
    local emitted = {}
    local fresh = _reload_settlement_with_emit_stub(emitted)

    local game = { dirty = { any = false } }
    local pc = { kind = "market_buy", owner_role_id = 1, active_tab = "item", page_index = 1, page_count = 1 }
    _with_patches(_patch_market_query(_make_entries(2)), function()
      fresh.resolve(game, pc, _stub_player(1),
        { kind = "item" }, { ok = true, fulfilled_now = true, inventory_full_after = false })
    end)
    _assert_eq(emitted.kind, nil, "no emit when inventory_full_after is false")
  end)

  it("test_ok=false + rebuild succeeds → keep_open=true", function()
    local game = { dirty = { any = false } }
    local pc = { kind = "market_buy", owner_role_id = 1, active_tab = "item", page_index = 1, page_count = 1 }
    local v
    _with_patches(_patch_market_query(_make_entries(2)), function()
      v = purchase_settlement.resolve(game, pc, _stub_player(1),
        { kind = "item" }, { ok = false })
    end)
    _assert_eq(v.keep_open, true, "failure stay path must yield keep_open=true")
  end)

  it("test_ok=false + rebuild fails (non-market_buy kind) → not keep_open", function()
    local pc = { kind = "other_kind" }
    local v = purchase_settlement.resolve({}, pc, _stub_player(1),
      { kind = "item" }, { ok = false })
    _assert_eq(v.keep_open, false, "rebuild failure on failure_stay must fall through to finish")
  end)

  it("test_nil pending_choice → false", function()
    local game = { turn = { pending_choice = nil } }
    _assert_eq(choice.session.refresh_after_paid_callback(game, _stub_player(1), { product_id = "p1" }), false,
      "nil pending → false")
  end)

  it("test_wrong kind → false", function()
    local game = { turn = { pending_choice = { kind = "other" } } }
    _assert_eq(choice.session.refresh_after_paid_callback(game, _stub_player(1), { product_id = "p1" }), false,
      "non-market_buy kind → false")
  end)

  it("test_owner mismatch → false", function()
    local game = { turn = { pending_choice = { kind = "market_buy", owner_role_id = 99 } } }
    -- _resolve_owner_role_id returns 99; player.id = 1; mismatch
    local prev_resolve = choice_contract.resolve_owner_role_id
    choice_contract.resolve_owner_role_id = function(pc) return pc.owner_role_id end
    _assert_eq(choice.session.refresh_after_paid_callback(game, _stub_player(1), { product_id = "p1" }), false,
      "owner mismatch → false")
    choice_contract.resolve_owner_role_id = prev_resolve
  end)

  it("test_owner matches + rebuild succeeds → true", function()
    local game = {
      turn = {
        pending_choice = { kind = "market_buy", owner_role_id = 1,
          active_tab = "item", page_index = 1, page_count = 1 },
      },
      dirty = { any = false },
    }
    local prev_resolve = choice_contract.resolve_owner_role_id
    choice_contract.resolve_owner_role_id = function(pc) return pc.owner_role_id end
    _with_patches(_patch_market_query(_make_entries(2)), function()
      _assert_eq(choice.session.refresh_after_paid_callback(game, _stub_player(1), { product_id = "p1" }), true,
        "owner match + rebuild ok → true")
    end)
    choice_contract.resolve_owner_role_id = prev_resolve
  end)

  it("test_ok=false + deferred + fulfilled + inventory_full_after=true: NO emit_inventory_full (kills or→and)", function()
    local emitted = {}
    local fresh = _reload_settlement_with_emit_stub(emitted)

    local game = { dirty = { any = false } }
    local pc = { kind = "market_buy", owner_role_id = 1, active_tab = "item", page_index = 1, page_count = 1 }
    local result = {
      ok = false,
      deferred_fulfillment = true,
      fulfilled_now = true,
      inventory_full_after = true,
    }
    _with_patches(_patch_market_query(_make_entries(2)), function()
      fresh.resolve(game, pc, _stub_player(1),
        { kind = "item" }, result)
    end)
    _assert_eq(emitted.kind, nil,
      "ok=false MUST short-circuit keep_open at disjunction; failure_stay path does not emit inventory_full")
  end)

  it("test_keep_open path + rebuild failure → keep_open=false", function()
    local v = purchase_settlement.resolve({}, { kind = "wrong_kind" }, _stub_player(1),
      { kind = "item" }, { ok = true, deferred_fulfillment = true })
    _assert_eq(v.keep_open, false,
      "rebuild fail in keep_open path MUST return keep_open=false")
  end)
end)
end

-- ===== 段 4:residual_closure(8 例) =====
do
local P = require("test.support.shared_support")
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _with_patches = P.with_patches

local choice = require("src.rules.market.choice")
local purchase_settlement = require("src.rules.market.purchase_settlement")
local market_query = require("src.rules.market.query")
local monopoly_event = require("src.foundation.events")
local dirty_tracker = require("src.state.dirty_tracker")

local function _stub_player(id) return { id = id } end

local function _make_entries(n)
  local list = {}
  for i = 1, n do
    list[i] = {
      product_id = "p" .. i, name = "n_" .. i, price = 100, currency = "金币",
      kind = "item", market_enabled = true,
    }
  end
  return list
end

local function _patch_market_query(entries)
  return {
    { target = market_query.eligibility, key = "sorted_entries", value = function() return entries end },
    { target = market_query.eligibility, key = "can_buy_entry", value = function() return true end },
    { target = market_query.eligibility, key = "can_buy_with_free_slot", value = function() return true end },
    { target = market_query.context, key = "entry_market_enabled", value = function() return true end },
    { target = market_query.context, key = "entry_name", value = function(e) return e.name end },
    { target = market_query.context, key = "entry_price", value = function(e) return e.price end },
    { target = market_query.context, key = "entry_currency", value = function(e) return e.currency end },
    { target = dirty_tracker, key = "mark", value = function() end },
  }
end

local function _reload_choice_with_emit_stub(captured_ref)
  local prev_emit = monopoly_event.emit
  monopoly_event.emit = function(kind, payload)
    captured_ref.kind = kind
    captured_ref.payload = payload
  end
  package.loaded["src.rules.market.choice"] = nil
  local fresh = require("src.rules.market.choice")
  monopoly_event.emit = prev_emit
  package.loaded["src.rules.market.choice"] = nil
  require("src.rules.market.choice")
  return fresh
end

local function _reload_settlement_with_emit_stub(captured_ref)
  local prev_emit = monopoly_event.emit
  monopoly_event.emit = function(kind, payload)
    captured_ref.kind = kind
    captured_ref.payload = payload
  end
  -- 串行全跑(crap_collect adapter)时 test_market.lua 的 _reload_market_service
  -- 已把 package.loaded["src.rules.market.query"] 换成新表;reload choice 前钉回
  -- 本文件捕获的顶层表,保证 fresh 模块与 _patch_market_query 的 patch 目标一致。
  package.loaded["src.rules.market.query"] = market_query
  package.loaded["src.rules.market.choice"] = nil
  package.loaded["src.rules.market.purchase_settlement"] = nil
  local fresh = require("src.rules.market.purchase_settlement")
  monopoly_event.emit = prev_emit
  package.loaded["src.rules.market.query"] = market_query
  package.loaded["src.rules.market.choice"] = nil
  package.loaded["src.rules.market.purchase_settlement"] = nil
  require("src.rules.market.choice")
  require("src.rules.market.purchase_settlement")
  return fresh
end


describe("TestMarketChoiceResidualClosure", function()
  it("test_emit_buy_failed_payload_passes_entry_and_player", function()
    local cap = {}
    local fresh = _reload_choice_with_emit_stub(cap)
    local player = _stub_player(7)
    local entry = { product_id = "p_x", kind = "item", price = 999 }

    fresh.feedback.emit_buy_failed(player, entry, "no_funds", "现金不足")

    _assert_eq(cap.payload.player, player, "payload.player must be the argument verbatim")
    _assert_eq(cap.payload.entry, entry, "payload.entry must be the argument verbatim")
    _assert_eq(cap.payload.reason, "no_funds", "payload.reason verbatim")
  end)

  it("test_emit_buy_failed_uses_market_buy_failed_kind", function()
    local cap = {}
    local fresh = _reload_choice_with_emit_stub(cap)
    fresh.feedback.emit_buy_failed(_stub_player(1), { product_id = "p1" }, "r", "b")
    _assert_eq(cap.kind, monopoly_event.market.buy_failed, "kind must be market.buy_failed event id")
  end)

  it("test_emit_inventory_full_kind_and_body_literal", function()
    local cap = {}
    local fresh = _reload_choice_with_emit_stub(cap)
    local player = _stub_player(3)
    local entry = { product_id = "p_q", kind = "item" }

    fresh.feedback.emit_inventory_full(player, entry)

    _assert_eq(cap.kind, monopoly_event.market.inventory_full, "kind must be market.inventory_full")
    _assert_eq(cap.payload.player, player, "payload.player verbatim")
    _assert_eq(cap.payload.entry, entry, "payload.entry verbatim")
    _assert_eq(cap.payload.body, "卡槽已满，无法继续购买", "L32 body literal pinned")
  end)

  it("test_handle_keep_open_deferred_other_kind_no_emit", function()
    -- _should_keep_market_open returns true via deferred_fulfillment arm regardless of entry.kind.
    -- _handle_keep_open's full_buy requires entry.kind == "item" → false for "other" → no inventory_full emit.
    local cap = {}
    local fresh = _reload_settlement_with_emit_stub(cap)
    local game = { dirty = { any = false } }
    local pc = { kind = "market_buy", owner_role_id = 1, active_tab = "item", page_index = 1, page_count = 1 }
    local v
    _with_patches(_patch_market_query(_make_entries(2)), function()
      v = fresh.resolve(game, pc, _stub_player(1),
        { kind = "other" }, { ok = true, deferred_fulfillment = true, fulfilled_now = true, inventory_full_after = true })
    end)
    _assert_eq(v.keep_open, true, "deferred_fulfillment=true must yield keep_open=true")
    _assert_eq(cap.kind, nil, "non-item entry.kind must NOT emit inventory_full even with all other flags true")
  end)

  it("test_handle_keep_open_nil_entry_no_emit", function()
    -- _should_keep_market_open: type(result)=='table' + result.ok==true + deferred_fulfillment==true → return true.
    -- _handle_keep_open: full_buy starts with `entry and ...` → entry==nil short-circuits → false → no emit.
    local cap = {}
    local fresh = _reload_settlement_with_emit_stub(cap)
    local game = { dirty = { any = false } }
    local pc = { kind = "market_buy", owner_role_id = 1, active_tab = "item", page_index = 1, page_count = 1 }
    local v
    _with_patches(_patch_market_query(_make_entries(2)), function()
      v = fresh.resolve(game, pc, _stub_player(1),
        nil, { ok = true, deferred_fulfillment = true, fulfilled_now = true, inventory_full_after = true })
    end)
    _assert_eq(v.keep_open, true, "entry nil + deferred_fulfillment=true → keep_open=true")
    _assert_eq(cap.kind, nil, "entry nil → no inventory_full emit even with other flags true")
  end)

  it("test_keep_open_rejects_truthy_string_deferred", function()
    local game = { dirty = { any = false } }
    local pc = { kind = "market_buy", owner_role_id = 1, active_tab = "item", page_index = 1, page_count = 1 }
    local v
    _with_patches(_patch_market_query(_make_entries(2)), function()
      v = purchase_settlement.resolve(game, pc, _stub_player(1),
        { kind = "item" }, { ok = true, deferred_fulfillment = "yes", fulfilled_now = false })
    end)
    _assert_eq(v.keep_open, false, "non-literal-true deferred_fulfillment must NOT trigger keep_open arm")
  end)

  it("test_apply_navigation_unknown_action_marks_dirty_via_rebuild", function()
    -- Coder asserts page/tab equality but the L205 `false` for unchanged means the rebuild path runs.
    -- Verify rebuild side-effect: dirty.market and dirty.turn get marked.
    local marks = {}
    local game = {
      find_player_by_id = function() return _stub_player(1) end,
      dirty = { any = false, turn = false, market = false },
      turn = {},
    }
    local pc = { kind = "market_buy", owner_role_id = 1, active_tab = "item", page_index = 2, page_count = 3 }
    local patches = _patch_market_query(_make_entries(25))
    -- swap dirty_tracker.mark patch to capture
    for i, p in ipairs(patches) do
      if p.target == dirty_tracker and p.key == "mark" then
        patches[i] = { target = dirty_tracker, key = "mark", value = function(_, domain) marks[#marks+1] = domain end }
      end
    end
    _with_patches(patches, function()
      local ok = choice.session.apply_navigation(game, pc, { type = "unknown_action_type" })
      _assert_eq(ok, true, "unknown action type still must succeed via builder rebuild")
    end)
    local turn_seen, market_seen = false, false
    for _, d in ipairs(marks) do
      if d == "turn" then turn_seen = true end
      if d == "market" then market_seen = true end
    end
    luassert.truthy(turn_seen and market_seen, "unknown action → unchanged=false → builder rebuild → dirty.mark turn+market")
  end)

  it("test_handle_keep_open_rebuild_failure_returns_false", function()
    local v = purchase_settlement.resolve({}, { kind = "wrong" }, _stub_player(1),
      { kind = "item" }, { ok = true, deferred_fulfillment = true })
    _assert_eq(v.keep_open, false, "rebuild failure in keep_open path must return keep_open=false")
  end)
end)
end

-- ===== 段 5:choices_session(4 例) =====
do
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

local function _make_query_mock()
  return {
    context = {
      entry_by_id = function() return nil end,
      entry_currency = function() return "" end,
      is_paid_currency = function() return false end,
      entry_market_enabled = function() return true end,
    },
    eligibility = {},
  }
end


describe("TestMarketChoiceSessionReload", function()
  it("test_choice_session_apply_navigation_tab_select_and_empty_tab_feedback", function()
    local feedback_calls = {}
    _reload_module("src.rules.market.choice", {
      ["src.rules.market.query"] = _make_query_mock(),
      ["src.config.choice.contract"] = {
        resolve_owner_role_id = function(choice) return choice.owner_role_id end,
      },
    }, function(choice)
      choice.builder.build = function()
        return {
          title = "Market",
          body_lines = {},
          options = {},
          allow_cancel = true,
          cancel_label = "Cancel",
          active_tab = "item",
          page_index = 1,
          page_count = 2,
          owner_role_id = 2,
          meta = {},
        }
      end
      choice.feedback.emit_buy_failed = function(player, entry, reason, body)
        feedback_calls[#feedback_calls + 1] = { player = player, reason = reason, body = body }
      end

      local game = {
        dirty = {},
        find_player_by_id = function(_, id)
          return { id = id, name = "P" .. tostring(id) }
        end,
      }
      local pending_choice = { kind = "market_buy", owner_role_id = 2, active_tab = "legacy", page_index = 3, page_count = 5 }
      local ok = choice.session.apply_navigation(game, pending_choice, { type = "market_tab_select", tab = "item" })
      luassert.truthy(ok == true, "tab select should succeed")
      luassert.truthy(pending_choice.active_tab == "item", "should switch active tab")
      luassert.truthy(pending_choice.page_index == 1, "tab switch should reset page index")
      luassert.truthy(game.dirty.turn == true and game.dirty.any == true, "should mark choice dirty")
    end)
    luassert.truthy(#feedback_calls == 1, "empty tab should emit feedback once")
    luassert.truthy(feedback_calls[1].reason == "empty_tab", "should emit empty_tab reason")
  end)

  it("test_choice_session_apply_navigation_prev_next_and_rejects", function()
    local build_calls = {}
    _reload_module("src.rules.market.choice", {
      ["src.rules.market.query"] = _make_query_mock(),
      ["src.config.choice.contract"] = {
        resolve_owner_role_id = function(choice) return choice.owner_role_id end,
      },
    }, function(choice)
      choice.builder.build = function(_, _, state)
        build_calls[#build_calls + 1] = {
          active_tab = state.active_tab,
          page_index = state.page_index,
          page_count = state.page_count,
        }
        if state.page_index == 9 then
          return nil
        end
        return {
          title = "Market",
          body_lines = {},
          options = { { id = "opt" } },
          allow_cancel = true,
          cancel_label = "Cancel",
          active_tab = state.active_tab,
          page_index = state.page_index,
          page_count = state.page_count,
          owner_role_id = 2,
          meta = {},
        }
      end
      choice.feedback.emit_buy_failed = function() end

      local game = {
        dirty = {},
        find_player_by_id = function(_, id)
          if id == 2 then
            return { id = id, name = "P2" }
          end
          return nil
        end,
      }
      local pending_choice = { kind = "market_buy", owner_role_id = 2, active_tab = "item", page_index = 2, page_count = 5 }
      luassert.truthy(choice.session.apply_navigation(game, pending_choice, { type = "market_page_prev" }) == true, "prev page should rebuild")
      luassert.truthy(build_calls[1].page_index == 1, "prev page should decrement page index")
      luassert.truthy(choice.session.apply_navigation(game, pending_choice, { type = "market_page_next" }) == true, "next page should rebuild")
      luassert.truthy(build_calls[2].page_index == 2, "next page should increment page index from updated state")
      pending_choice.owner_role_id = nil
      luassert.truthy(choice.session.apply_navigation(game, pending_choice, { type = "market_page_next" }) == false, "missing owner should reject")
      pending_choice.owner_role_id = 99
      luassert.truthy(choice.session.apply_navigation(game, pending_choice, { type = "market_page_next" }) == false, "missing player should reject")
      pending_choice.owner_role_id = 2
      pending_choice.page_index = 8
      luassert.truthy(choice.session.apply_navigation(game, pending_choice, { type = "market_page_next" }) == false, "build nil should reject")
    end)
    luassert.truthy(#build_calls == 3, "should build for prev, next, and nil-spec branch")
  end)

  it("test_choice_session_refresh_after_paid_callback_rebuilds_pending", function()
    local rebuilt_calls = 0
    local result = _reload_module("src.rules.market.choice", {
      ["src.rules.market.query"] = _make_query_mock(),
      ["src.config.choice.contract"] = {
        resolve_owner_role_id = function(choice) return choice.owner_role_id end,
      },
    }, function(choice)
      choice.builder.build = function()
        rebuilt_calls = rebuilt_calls + 1
        return {
          title = "Market",
          body_lines = { "line" },
          options = { { id = 1 } },
          allow_cancel = true,
          cancel_label = "Cancel",
          active_tab = "item",
          page_index = 2,
          page_count = 4,
          owner_role_id = 7,
          meta = { refreshed = true },
        }
      end

      local pending_choice = { kind = "market_buy", owner_role_id = 7, active_tab = "item", page_index = 1, page_count = 1 }
      local game = { dirty = {}, turn = { pending_choice = pending_choice } }
      local ok = choice.session.refresh_after_paid_callback(game, { id = 7, name = "P7" }, { product_id = 2001 })
      luassert.truthy(ok == true, "refresh_after_paid_callback should rebuild pending choice")
      luassert.truthy(pending_choice.page_index == 2, "should update pending choice page")
      luassert.truthy(pending_choice.meta.refreshed == true, "should update pending choice meta")
    end)
    luassert.truthy(result == nil, "reload wrapper should finish")
    luassert.truthy(rebuilt_calls == 1, "should rebuild exactly once")
  end)

  it("test_choice_session_refresh_after_paid_callback_rejects_non_owner_and_failed_rebuild", function()
    local warnings = {}
    _reload_module("src.rules.market.choice", {
      ["src.rules.market.query"] = _make_query_mock(),
      ["src.config.choice.contract"] = {
        resolve_owner_role_id = function(choice) return choice.owner_role_id end,
      },
      ["src.foundation.log"] = {
        warn = function(...)
          warnings[#warnings + 1] = table.concat({ ... }, " ")
        end,
      },
    }, function(choice)
      choice.builder.build = function()
        return nil
      end

      local pending_choice = { kind = "market_buy", owner_role_id = 7, active_tab = "item", page_index = 1, page_count = 1 }
      local game = { dirty = {}, turn = { pending_choice = pending_choice } }
      luassert.truthy(choice.session.refresh_after_paid_callback(game, { id = 8, name = "P8" }, { product_id = 2001 }) == false, "other player callback should be ignored")
      luassert.truthy(choice.session.refresh_after_paid_callback(game, { id = 7, name = "P7" }, { product_id = 2001 }) == false, "failed rebuild should return false")
      game.turn.pending_choice = { kind = "other_kind", owner_role_id = 7 }
      luassert.truthy(choice.session.refresh_after_paid_callback(game, { id = 7, name = "P7" }, { product_id = 2001 }) == false, "non-market pending choice should reject")
    end)
    luassert.truthy(#warnings == 1, "failed rebuild should emit only callback warning")
    luassert.truthy(warnings[1]:find("market paid callback refresh skipped:", 1, true), "failed rebuild should keep the callback refresh warning")
  end)
end)
end

-- ===== 段 6:survivors(33 例) =====
do
local P = require("test.support.shared_support")
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _with_patches = P.with_patches

local choice = require("src.rules.market.choice")
local market_query = require("src.rules.market.query")
local monopoly_event = require("src.foundation.events")
local dirty_tracker = require("src.state.dirty_tracker")

local function _stub_player(id)
  return { id = id, name = "player_" .. tostring(id) }
end

local function _patch_market_query(entries, opts)
  opts = opts or {}
  return {
    { target = market_query.eligibility, key = "sorted_entries", value = function() return entries end },
    { target = market_query.eligibility, key = "can_buy_entry", value = opts.can_buy or function() return true end },
    { target = market_query.eligibility, key = "can_buy_with_free_slot", value = opts.can_buy or function() return true end },
    { target = market_query.context, key = "entry_market_enabled", value = function() return true end },
    { target = market_query.context, key = "entry_name", value = function(entry) return entry.name end },
    { target = market_query.context, key = "entry_price", value = function(entry) return entry.price end },
    { target = market_query.context, key = "entry_currency", value = function(entry) return entry.currency end },
    { target = dirty_tracker, key = "mark", value = function() end },
  }
end

local function _entry(product_id, name, price, currency)
  return {
    product_id = product_id, name = name, price = price, currency = currency,
    kind = "item", market_enabled = true,
  }
end

local function _make_entries(n)
  local list = {}
  for i = 1, n do
    list[i] = _entry("p" .. i, "name_" .. i, 100 + i, "金币")
  end
  return list
end


describe("TestMarketChoiceSurvivors", function()
  it("test_spec.title is exactly '黑市'", function()
    _with_patches(_patch_market_query({}), function()
      local spec = choice.builder.build(_stub_player(1), {}, {})
      _assert_eq(spec.title, "黑市", "spec.title must be the literal '黑市'")
    end)
  end)

  it("test_emit_buy_failed payload.popup.title is exactly '黑市'", function()
    -- choice captures monopoly_event.emit as upvalue at module load (L14).
    -- Stub emit, reload choice so the upvalue points at the stub, then restore.
    local captured
    local prev_emit = monopoly_event.emit
    monopoly_event.emit = function(_, payload) captured = payload end
    package.loaded["src.rules.market.choice"] = nil
    local fresh_choice = require("src.rules.market.choice")
    monopoly_event.emit = prev_emit
    -- Need to ALSO reload the cached top-level `choice` so other describes here still hit the original
    -- emit reference path. fresh_choice has the stub baked in; we use it just for this case.
    package.loaded["src.rules.market.choice"] = nil
    require("src.rules.market.choice")  -- restore the original-emit copy for subsequent specs

    fresh_choice.feedback.emit_buy_failed(_stub_player(1), { product_id = "p1" }, "no_funds", "现金不足")

    luassert.truthy(captured ~= nil, "emit must be invoked through reloaded upvalue")
    _assert_eq(captured.popup.title, "黑市", "popup.title must be literal '黑市'")
    _assert_eq(captured.popup.body, "现金不足", "popup.body must pass through from arg")
    _assert_eq(captured.reason, "no_funds", "reason must pass through")
  end)

  it("test_zero entries → page_count == 1 (L107 total<=0 boundary)", function()
    _with_patches(_patch_market_query({}), function()
      local spec = choice.builder.build(_stub_player(1), {}, {})
      _assert_eq(spec.page_count, 1, "0 entries must yield page_count=1")
    end)
  end)

  it("test_exactly PAGE_SIZE (10) entries → page_count == 1 (boundary)", function()
    _with_patches(_patch_market_query(_make_entries(10)), function()
      local spec = choice.builder.build(_stub_player(1), {}, {})
      _assert_eq(spec.page_count, 1, "10 entries must yield page_count=1 (floor((10+9)/10))")
    end)
  end)

  it("test_PAGE_SIZE+1 (11) entries → page_count == 2 (boundary just above)", function()
    _with_patches(_patch_market_query(_make_entries(11)), function()
      local spec = choice.builder.build(_stub_player(1), {}, {})
      _assert_eq(spec.page_count, 2, "11 entries must yield page_count=2")
    end)
  end)

  it("test_25 entries → page_count == 3", function()
    _with_patches(_patch_market_query(_make_entries(25)), function()
      local spec = choice.builder.build(_stub_player(1), {}, {})
      _assert_eq(spec.page_count, 3, "25 entries must yield page_count=3")
    end)
  end)

  it("test_page_index nil → defaults to 1 (L47 'or 1' fallback)", function()
    _with_patches(_patch_market_query(_make_entries(25)), function()
      local spec = choice.builder.build(_stub_player(1), {}, { page_index = nil })
      _assert_eq(spec.page_index, 1, "nil page_index must default to 1")
    end)
  end)

  it("test_page_index 0 → clamped up to 1 (lower bound)", function()
    _with_patches(_patch_market_query(_make_entries(25)), function()
      local spec = choice.builder.build(_stub_player(1), {}, { page_index = 0 })
      _assert_eq(spec.page_index, 1, "page_index 0 must clamp to 1")
    end)
  end)

  it("test_page_index way over count → clamped down to count (upper bound)", function()
    _with_patches(_patch_market_query(_make_entries(25)), function()
      local spec = choice.builder.build(_stub_player(1), {}, { page_index = 99 })
      _assert_eq(spec.page_index, 3, "page_index 99 must clamp to page_count=3")
    end)
  end)

  it("test_page_1_options_reflect_entries_1_10_in_order", function()
    _with_patches(_patch_market_query(_make_entries(25)), function()
      local spec = choice.builder.build(_stub_player(1), {}, { page_index = 1 })
      _assert_eq(#spec.options, 10, "page 1 must have 10 options")
      _assert_eq(spec.options[1].id, "p1", "first option must be entry 1")
      _assert_eq(spec.options[10].id, "p10", "last option must be entry 10")
    end)
  end)

  it("test_page_2_options_reflect_entries_11_20", function()
    _with_patches(_patch_market_query(_make_entries(25)), function()
      local spec = choice.builder.build(_stub_player(1), {}, { page_index = 2 })
      _assert_eq(#spec.options, 10, "page 2 must have 10 options")
      _assert_eq(spec.options[1].id, "p11", "page 2 first option must be entry 11")
      _assert_eq(spec.options[10].id, "p20", "page 2 last option must be entry 20")
    end)
  end)

  it("test_page_3_partial_options_reflect_entries_21_25", function()
    _with_patches(_patch_market_query(_make_entries(25)), function()
      local spec = choice.builder.build(_stub_player(1), {}, { page_index = 3 })
      _assert_eq(#spec.options, 5, "page 3 must have 5 options (partial)")
      _assert_eq(spec.options[1].id, "p21", "page 3 first option must be entry 21")
      _assert_eq(spec.options[5].id, "p25", "page 3 last option must be entry 25")
    end)
  end)

  it("test_body_lines_parallel_to_options_in_same_order", function()
    _with_patches(_patch_market_query(_make_entries(3)), function()
      local spec = choice.builder.build(_stub_player(1), {}, { page_index = 1 })
      _assert_eq(#spec.body_lines, 3, "body_lines length must equal options length")
      luassert.truthy(spec.body_lines[1] == spec.options[1].label, "body_lines[1] must equal options[1].label")
      luassert.truthy(spec.body_lines[3] == spec.options[3].label, "body_lines[3] must equal options[3].label")
    end)
  end)

  it("test_label_format_name_int_currency_separator_literals_pinned", function()
    local entries = { _entry("p_label_1", "苹果", 250, "金豆") }
    _with_patches(_patch_market_query(entries), function()
      local spec = choice.builder.build(_stub_player(1), {}, {})
      _assert_eq(spec.options[1].label, "苹果 - 250 金豆",
        "label must match exact format 'name - price currency'")
      _assert_eq(spec.body_lines[1], "苹果 - 250 金豆", "body_lines also match")
    end)
  end)

  it("test_entry_currency_surfaces_verbatim_into_label", function()
    local entries = { _entry("p2", "面包", 99, "现金") }
    _with_patches(_patch_market_query(entries), function()
      local spec = choice.builder.build(_stub_player(1), {}, {})
      _assert_eq(spec.options[1].label, "面包 - 99 现金", "alternate currency must surface")
    end)
  end)

  it("test_can_buy_true_entries_listed_as_options_with_can_buy_true", function()
    local entries = _make_entries(2)
    _with_patches(_patch_market_query(entries, {
      can_buy = function(_, _, entry) return entry.product_id == "p1" end,
    }), function()
      local spec = choice.builder.build(_stub_player(1), {}, {})
      _assert_eq(#spec.options, 2, "both entries appear as options")
      _assert_eq(spec.options[1].can_buy, true, "p1 can_buy=true")
      _assert_eq(spec.options[2].can_buy, false, "p2 can_buy=false")
    end)
  end)

  it("test_nil game → false", function()
    _assert_eq(choice.session.apply_navigation(nil, { kind = "market_buy" }, { type = "market_tab_select", tab = "item" }), false,
      "nil game must yield false")
  end)

  it("test_nil pending_choice → false", function()
    _assert_eq(choice.session.apply_navigation({}, nil, { type = "market_tab_select", tab = "item" }), false,
      "nil pending_choice must yield false")
  end)

  it("test_wrong kind → false", function()
    _assert_eq(choice.session.apply_navigation({}, { kind = "other_choice" }, { type = "market_tab_select", tab = "item" }), false,
      "non-market_buy kind must yield false")
  end)

-- Drive via session.apply_navigation with stubbed builder so we can observe page_index/active_tab moves.
end)
local function _drive(action, initial)
  local result_spec
  local game = {
    find_player_by_id = function() return _stub_player(1) end,
    dirty = { any = false, turn = false, market = false },
    turn = {},
  }
  local pending_choice = {
    kind = "market_buy",
    owner_role_id = 1,
    active_tab = initial.tab,
    page_index = initial.page_index,
    page_count = initial.page_count,
  }
  _with_patches(_patch_market_query(_make_entries(initial.entries or 25)), function()
    local applied = choice.session.apply_navigation(game, pending_choice, action)
    result_spec = applied and pending_choice or nil
  end)
  return result_spec
end

describe("TestMarketChoiceSurvivors", function()
  it("test_market_page_next_page_index_increments", function()
    local pc = _drive({ type = "market_page_next" },
      { tab = "item", page_index = 1, page_count = 3, entries = 25 })
    _assert_eq(pc.page_index, 2, "page_next from 1 must move to 2")
  end)

  it("test_market_page_prev_page_index_decrements_clamped_at_1", function()
    local pc = _drive({ type = "market_page_prev" },
      { tab = "item", page_index = 2, page_count = 3, entries = 25 })
    _assert_eq(pc.page_index, 1, "page_prev from 2 must move to 1")
  end)

  it("test_market_page_prev_from_1_clamps_to_1", function()
    local pc = _drive({ type = "market_page_prev" },
      { tab = "item", page_index = 1, page_count = 3, entries = 25 })
    _assert_eq(pc.page_index, 1, "page_prev from 1 must clamp at 1")
  end)

  it("test_market_tab_select_same_tab_returns_true_unchanged", function()
    local pc = _drive({ type = "market_tab_select", tab = "item" },
      { tab = "item", page_index = 2, page_count = 3, entries = 25 })
    -- unchanged path returns true early without rebuild → pending_choice page_index stays 2
    _assert_eq(pc.page_index, 2, "tab_select with same tab must leave page_index untouched (unchanged early return)")
    _assert_eq(pc.active_tab, "item", "active_tab stays")
  end)

  it("test_unknown_action_type_unchanged_via_builder_rebuild", function()
    local pc = _drive({ type = "unknown_action" },
      { tab = "item", page_index = 2, page_count = 3, entries = 25 })
    -- _apply_navigation_action default branch returns (active_tab, page_index, false) → triggers rebuild with same coords
    _assert_eq(pc.page_index, 2, "unknown action must preserve page_index through rebuild")
    _assert_eq(pc.active_tab, "item", "unknown action must preserve active_tab through rebuild")
  end)

  it("test_wrong_kind_entry_excluded_by_and_combinator", function()
    -- Goal: differentiate `kind == active_tab AND market_enabled` from `kind == active_tab OR market_enabled`.
    -- Strategy: mixed entries where some have wrong kind but enabled=true, others have right kind but enabled=false.
    local entries = {
      { product_id = "right_kind",  name = "rk",  price = 100, currency = "金币", kind = "item",  market_enabled = true },
      { product_id = "wrong_kind",  name = "wk",  price = 200, currency = "金币", kind = "other", market_enabled = true },
    }
    _with_patches({
      { target = market_query.eligibility, key = "sorted_entries",     value = function() return entries end },
      { target = market_query.eligibility, key = "can_buy_entry",      value = function() return true end },
      { target = market_query.eligibility, key = "can_buy_with_free_slot",      value = function() return true end },
      -- entry_market_enabled returns true for BOTH — so mutation `and→or` would let wrong_kind slip through.
      { target = market_query.context,     key = "entry_market_enabled", value = function() return true end },
      { target = market_query.context,     key = "entry_name",          value = function(e) return e.name end },
      { target = market_query.context,     key = "entry_price",         value = function(e) return e.price end },
      { target = market_query.context,     key = "entry_currency",      value = function(e) return e.currency end },
      { target = dirty_tracker, key = "mark", value = function() end },
    }, function()
      local spec = choice.builder.build(_stub_player(1), {}, { active_tab = "item" })
      _assert_eq(#spec.options, 1, "L60 `and`: only kind=='item' AND enabled must surface (would be 2 under `or`)")
      _assert_eq(spec.options[1].id, "right_kind",
        "L59-60 conjunction must drop kind!=active_tab even when market_enabled=true")
    end)
  end)

  it("test_kind_match_disabled_entry_excluded_by_and_combinator", function()
    local entries = {
      { product_id = "right_kind_on",  name = "rkn", price = 100, currency = "金币", kind = "item", market_enabled = true },
      { product_id = "right_kind_off", name = "rko", price = 200, currency = "金币", kind = "item", market_enabled = false },
    }
    _with_patches({
      { target = market_query.eligibility, key = "sorted_entries",     value = function() return entries end },
      { target = market_query.eligibility, key = "can_buy_entry",      value = function() return true end },
      { target = market_query.eligibility, key = "can_buy_with_free_slot",      value = function() return true end },
      -- per-entry market_enabled echoes flag → `and` keeps only the on row, `or` would keep both via kind match.
      { target = market_query.context,     key = "entry_market_enabled", value = function(e) return e.market_enabled end },
      { target = market_query.context,     key = "entry_name",          value = function(e) return e.name end },
      { target = market_query.context,     key = "entry_price",         value = function(e) return e.price end },
      { target = market_query.context,     key = "entry_currency",      value = function(e) return e.currency end },
      { target = dirty_tracker, key = "mark", value = function() end },
    }, function()
      local spec = choice.builder.build(_stub_player(1), {}, { active_tab = "item" })
      _assert_eq(#spec.options, 1, "L60 `and`: enabled=false must drop entry even when kind matches")
      _assert_eq(spec.options[1].id, "right_kind_on",
        "L60 conjunction must require market_enabled=true on the entry surface")
    end)
  end)

  it("test_same-tab market_tab_select must NOT trigger rebuild → 0 dirty_tracker.mark calls", function()
    -- Strategy: original `unchanged=true` short-circuits without rebuild → no _mark_choice_dirty.
    -- Mutated `unchanged=false` falls through to rebuild → _apply_spec → _mark_choice_dirty fires.
    -- Observe via dirty_tracker.mark call count.
    local mark_calls = {}
    local game = {
      find_player_by_id = function() return _stub_player(1) end,
      dirty = { any = false, turn = false, market = false },
      turn = {},
    }
    local pc = {
      kind = "market_buy", owner_role_id = 1,
      active_tab = "item", page_index = 2, page_count = 3,
    }
    _with_patches({
      { target = market_query.eligibility, key = "sorted_entries",     value = function() return _make_entries(25) end },
      { target = market_query.eligibility, key = "can_buy_entry",      value = function() return true end },
      { target = market_query.eligibility, key = "can_buy_with_free_slot",      value = function() return true end },
      { target = market_query.context,     key = "entry_market_enabled", value = function() return true end },
      { target = market_query.context,     key = "entry_name",          value = function(e) return e.name end },
      { target = market_query.context,     key = "entry_price",         value = function(e) return e.price end },
      { target = market_query.context,     key = "entry_currency",      value = function(e) return e.currency end },
      { target = dirty_tracker, key = "mark", value = function(_, domain)
        mark_calls[#mark_calls + 1] = domain
      end },
    }, function()
      choice.session.apply_navigation(game, pc, { type = "market_tab_select", tab = "item" })
    end)
    _assert_eq(#mark_calls, 0,
      "L197 unchanged=true: same-tab early return MUST skip rebuild → 0 dirty marks " ..
      "(mutated unchanged=false → rebuild → dirty marks)")
  end)

  it("test_nil pending_choice.page_index + market_page_next + 25 entries → page_index lands on 2", function()
    -- Strategy: pending_choice.page_index=nil triggers the `or 1` fallback at L203.
    -- Original `... + 1` with nil page → 1+1=2. Mutated `... + 0` (1→0) → 1+0=1.
    -- With page_count >= 2, clamp yields different observable values.
    local game = {
      find_player_by_id = function() return _stub_player(1) end,
      dirty = { any = false, turn = false, market = false },
      turn = {},
    }
    local pc = {
      kind = "market_buy", owner_role_id = 1,
      active_tab = "item",
      page_index = nil,  -- crucial: triggers `or 1` fallback
      page_count = 3,
    }
    _with_patches(_patch_market_query(_make_entries(25)), function()
      choice.session.apply_navigation(game, pc, { type = "market_page_next" })
    end)
    _assert_eq(pc.page_index, 2,
      "L203: nil page + 1 must = 2 (mutated +0 would yield 1)")
  end)

  it("test_unknown action + out-of-bounds page_index → rebuild clamps; mutated would skip clamp", function()
    -- Strategy: unknown action returns (active_tab, page_index, false) → rebuild → clamps page_index.
    -- Mutated `unchanged=true` skips rebuild → out-of-bounds page_index stays unclamped.
    -- Observe via out-of-bounds page_index passing through rebuild's clamp.
    local game = {
      find_player_by_id = function() return _stub_player(1) end,
      dirty = { any = false, turn = false, market = false },
      turn = {},
    }
    local pc = {
      kind = "market_buy", owner_role_id = 1,
      active_tab = "item",
      page_index = 99,  -- out of bounds → rebuild's _clamp_page would clamp to page_count (3)
      page_count = 3,
    }
    _with_patches(_patch_market_query(_make_entries(25)), function()
      choice.session.apply_navigation(game, pc, { type = "totally_unknown_action_type" })
    end)
    _assert_eq(pc.page_index, 3,
      "L205 unchanged=false: rebuild runs → clamp 99 → 3. Mutated unchanged=true would stay 99")
  end)

-- These tests use a dedicated local driver so we can pin pre-rebuild page_index movement.
end)
local function _drive_nav(action, initial)
  local game = {
    find_player_by_id = function() return _stub_player(1) end,
    dirty = { any = false, turn = false, market = false },
    turn = {},
  }
  local pc = {
    kind = "market_buy", owner_role_id = 1,
    active_tab = initial.tab,
    page_index = initial.page_index,
    page_count = initial.page_count,
  }
  _with_patches(_patch_market_query(_make_entries(initial.entries or 25)), function()
    choice.session.apply_navigation(game, pc, action)
  end)
  return pc
end

describe("TestMarketChoiceSurvivors", function()
  it("test_market_page_next from page 2 → page 3 (kills L203 `+1 → -1` and `+1 → +0`)", function()
    local pc = _drive_nav({ type = "market_page_next" },
      { tab = "item", page_index = 2, page_count = 3, entries = 25 })
    _assert_eq(pc.page_index, 3, "L203 page_next from 2 must land on 3 (-1 would yield 1, +0 would yield 2)")
  end)

  it("test_market_page_prev from page 3 → page 2 (kills L201 `-1 → +1` and `-1 → -0`)", function()
    local pc = _drive_nav({ type = "market_page_prev" },
      { tab = "item", page_index = 3, page_count = 3, entries = 25 })
    _assert_eq(pc.page_index, 2, "L201 page_prev from 3 must land on 2 (+1 would clamp to 3, -0 would stay 3)")
  end)

  it("test_market_tab_select different tab from page 3 → page_index reset to 1 (L199 literal '1')", function()
    local pc = _drive_nav({ type = "market_tab_select", tab = "different_tab" },
      { tab = "item", page_index = 3, page_count = 3, entries = 25 })
    -- Even though TAB_ITEM is the only tab and builder normalizes back, the L199 literal 1 drives
    -- the page_index reset before rebuild. With 25 entries, page_count=3, builder uses page_index=1.
    _assert_eq(pc.page_index, 1, "L199: tab change MUST reset page_index to literal 1 (kills 1→2 / 1→0)")
  end)
end)
end

-- ===== 段 7:purchase_settlement.resolve(8 例) =====
do
-- purchase_settlement.resolve verdict 契约直测。
-- 由 market_choice_outcome_spec 九用例迁来:{stay}/finish_called → keep_open true/false(nil finish_choice 用例因不变式上移至 adapter 已移除)。
local function _with_modules(overrides, fn)
  local saved = {}
  for key, value in pairs(overrides) do
    saved[key] = package.loaded[key]
    package.loaded[key] = value
  end
  for _, key in ipairs({ "src.rules.market.choice", "src.rules.market.purchase_settlement" }) do
    saved[key] = saved[key] or package.loaded[key]
    package.loaded[key] = nil
  end
  local ok, result = pcall(function()
    local choice = require("src.rules.market.choice")
    return fn(require("src.rules.market.purchase_settlement"), choice)
  end)
  for key, value in pairs(saved) do package.loaded[key] = value end
  if not ok then error(result, 2) end
  return result
end

local function _base_overrides()
  return {
    ["src.rules.market.query"] = {
      context = {
        entry_by_id = function() return nil end, entry_currency = function() return "金币" end,
        entry_market_enabled = function() return true end, entry_name = function() return "item" end,
        entry_price = function() return 100 end,
      },
      eligibility = {
        sorted_entries = function() return {} end, can_buy_entry = function() return false end,
      },
    },
    ["src.config.choice.contract"] = { resolve_owner_role_id = function(c) return c.owner_role_id end },
    ["src.rules.ports.intent_output"] = { open_choice = function() return {} end, push_popup = function() return true end },
    ["src.state.dirty_tracker"] = { mark = function() end },
  }
end

local function _game() return { dirty = {}, turn = {} } end
local function _choice() return { kind = "market_buy", owner_role_id = 1, active_tab = "item", page_index = 1, page_count = 1 } end
local function _player() return { id = 1, name = "Alice" } end
local function _entry(kind) return { kind = kind or "item", product_id = 101 } end
local function _rebuildable(choice)
  choice.builder.build = function()
    return { title="T", body_lines={}, options={{}}, allow_cancel=true, cancel_label="X",
             active_tab="item", page_index=1, page_count=1, owner_role_id=1, meta={} }
  end
end


describe("TestMarketChoicePurchaseSettlement", function()
  it("test_deferred_fulfillment_keeps_market_open", function()
    _with_modules(_base_overrides(), function(settlement, choice)
      _rebuildable(choice)
      local v = settlement.resolve(_game(), _choice(), _player(), _entry("item"), { ok = true, deferred_fulfillment = true })
      luassert.truthy(v.keep_open == true, "deferred should keep open")
    end)
  end)

  it("test_item_fulfilled_now_keeps_market_open", function()
    _with_modules(_base_overrides(), function(settlement, choice)
      _rebuildable(choice)
      local v = settlement.resolve(_game(), _choice(), _player(), _entry("item"), { ok = true, fulfilled_now = true })
      luassert.truthy(v.keep_open == true, "item fulfilled should keep open")
    end)
  end)

  it("test_non_item_fulfilled_now_does_not_keep_open", function()
    _with_modules(_base_overrides(), function(settlement)
      local v = settlement.resolve(_game(), _choice(), _player(), _entry("non_item"), { ok = true, fulfilled_now = true })
      luassert.truthy(v.keep_open == false, "non-item fulfilled should not keep open")
    end)
  end)

  it("test_item_fulfilled_with_full_inventory_emits_feedback_and_keeps_open", function()
    local emitted = false
    _with_modules(_base_overrides(), function(settlement, choice)
      _rebuildable(choice)
      choice.feedback.emit_inventory_full = function() emitted = true end
      local v = settlement.resolve(_game(), _choice(), _player(), _entry("item"),
        { ok = true, fulfilled_now = true, inventory_full_after = true })
      luassert.truthy(v.keep_open == true, "should keep open")
      luassert.truthy(emitted, "should emit inventory full feedback")
    end)
  end)

  it("test_failure_keeps_open_when_rebuild_succeeds", function()
    _with_modules(_base_overrides(), function(settlement, choice)
      _rebuildable(choice)
      local v = settlement.resolve(_game(), _choice(), _player(), _entry("item"), { ok = false, reason = "not_enough_coins" })
      luassert.truthy(v.keep_open == true, "failure + rebuild should keep open")
    end)
  end)

  it("test_failure_does_not_keep_open_when_rebuild_fails", function()
    _with_modules(_base_overrides(), function(settlement, choice)
      choice.builder.build = function() return nil end
      local v = settlement.resolve(_game(), _choice(), _player(), _entry("item"), { ok = false })
      luassert.truthy(v.keep_open == false, "failure + failed rebuild should not keep open")
    end)
  end)

  it("test_no_intent_does_not_keep_open", function()
    _with_modules(_base_overrides(), function(settlement)
      local v = settlement.resolve(_game(), _choice(), _player(), _entry("item"), { ok = nil })
      luassert.truthy(v.keep_open == false, "no intent should not keep open")
    end)
  end)

  it("test_non_table_result_does_not_keep_open", function()
    _with_modules(_base_overrides(), function(settlement)
      local v = settlement.resolve(_game(), _choice(), _player(), _entry("item"), "some_string")
      luassert.truthy(v.keep_open == false, "non-table should not keep open")
    end)
  end)
end)
end

-- ===== 段 8:market.choice survivor closure #259(2 例) =====
do
local P = require("test.support.shared_support")
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _with_patches = P.with_patches
local choice = require("src.rules.market.choice")
local market_query = require("src.rules.market.query")
local monopoly_event = require("src.foundation.events")
local dirty_tracker = require("src.state.dirty_tracker")

local function _empty_query_patches()
  return {
    { target = market_query.eligibility, key = "sorted_entries", value = function() return {} end },
    { target = dirty_tracker, key = "mark", value = function() end },
  }
end


describe("TestMarketChoiceClosure", function()
  it("test_current_choice_state_passes_both_fields_through_verbatim", function()
    -- kills `pending_choice and pending_choice.active_tab or nil` `and` -> `or`
    -- (yields the choice table itself) and `or` -> `and` (yields nil).
    local state = choice._M_test._current_choice_state({ active_tab = "item", page_index = 3 })
    _assert_eq(state.active_tab, "item", "active_tab must pass through verbatim")
    _assert_eq(state.page_index, 3, "page_index must pass through verbatim")
    local empty = choice._M_test._current_choice_state(nil)
    _assert_eq(empty.active_tab, nil, "nil choice should yield nil active_tab")
    _assert_eq(empty.page_index, nil, "nil choice should yield nil page_index")
  end)

  it("test_apply_navigation_onto_an_empty_tab_emits_the_empty_tab_popup_body", function()
    -- kills _apply_navigation_spec's "当前页签暂无可购买项" -> nil.
    -- reload so the module-local `_emit_event` upvalue binds the stub.
    local cap = {}
    local prev_emit = monopoly_event.emit
    monopoly_event.emit = function(kind, payload)
      cap.kind = kind
      cap.payload = payload
    end
    -- 串行全跑(crap_collect adapter)时 test_market.lua 的 _reload_market_service
    -- 已把 package.loaded["src.rules.market.query"] 换成新表;reload choice 前钉回
    -- 本文件捕获的顶层表,保证 fresh 模块与 _empty_query_patches 的 patch 目标一致。
    package.loaded["src.rules.market.query"] = market_query
    package.loaded["src.rules.market.choice"] = nil
    local fresh = require("src.rules.market.choice")
    monopoly_event.emit = prev_emit
    package.loaded["src.rules.market.query"] = market_query
    package.loaded["src.rules.market.choice"] = nil
    require("src.rules.market.choice")

    local player = { id = 1 }
    local game = { find_player_by_id = function() return player end, dirty = {}, turn = {} }
    local pending = {
      kind = "market_buy", owner_role_id = 1,
      active_tab = "item", page_index = 1, page_count = 1,
    }
    _with_patches(_empty_query_patches(), function()
      local ok = fresh.session.apply_navigation(game, pending, { type = "market_page_next" })
      _assert_eq(ok, true, "navigation onto the empty tab should still apply")
    end)
    _assert_eq(cap.kind, monopoly_event.market.buy_failed, "empty tab should emit buy_failed")
    _assert_eq(cap.payload.reason, "empty_tab", "empty tab should carry the empty_tab reason")
    _assert_eq(cap.payload.popup.body, "当前页签暂无可购买项", "empty tab popup body literal pinned")
  end)
end)
end


-- mutate 车道统一返回（#283 多类文件假幸存方向）：仅合并不 reload 的类。
-- ExtraSurvivors/ResidualClosure/SessionReload/Survivors/Closure 会重置
-- package.loaded，mutate 内建 runner 无文件隔离会污染后续用例，维持单类返回，
-- 其幸存者按惰性重载缺陷单独裁定。
