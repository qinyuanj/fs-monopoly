-- 皮肤商店屏(#204):经皮肤归属 seam 假实现(test.support.fake_skin_ownership)驱动,
-- 只验证屏的两类映射——面板动作 → 皮肤归属接口调用,领域结果 → 提示 / 关屏 /
-- canvas 切换 / 槽位刷新——以及槽位渲染。归属规则本身由
-- test/behavior/rules/test_skin_ownership*.lua 经模块接口覆盖。
require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
local support = require("test.support.shared_support")
local fake_skin_ownership = require("test.support.fake_skin_ownership")
local _with_patches = support.with_patches
local _build_role_with_events = support.build_role_with_events
local _has_event = support.has_event
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local canvas = require("src.ui.coord.canvas_coordinator")
local skin_panel = require("src.ui.screens.skin_panel")
local tip_queue = require("src.foundation.tips")
local skin_panel_view = require("src.ui.render.widgets.skin_panel")
local skin_nodes = require("src.ui.schema.skin")
local base_nodes = require("src.ui.schema.base")
local default_skins = require("src.config.content.skins")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local runtime_assets = require("src.config.runtime_assets")

local function _make_state()
  return { ui = {} }
end

local function _make_catalog(n)
  local t = {}
  for i = 1, n do
    t[i] = { product_id = "skin_" .. i, name = "皮肤" .. i }
  end
  return t
end

local function _make_rich_catalog()
  return {
    { product_id = 5001, name = "皮肤甲", unlock = "purchase", currency = "金豆", price = 198 },
    { product_id = 5002, name = "皮肤乙", unlock = "purchase", currency = "金豆", price = 198 },
    { product_id = 5003, name = "奶龙", unlock = "gift", gift_name = "谢礼" },
  }
end

local function _make_render_state(panel_overrides)
  local calls = {}
  local panel = {
    role_id = 1,
    page_index = 1,
  }
  if panel_overrides then
    for k, v in pairs(panel_overrides) do
      panel[k] = v
    end
  end
  local state = {
    ui = {
      skin_panel = panel,
      set_button = function(_, name, text)
        calls[#calls + 1] = { "set_button", name, text }
      end,
      set_visible = function(_, name, visible)
        calls[#calls + 1] = { "set_visible", name, visible }
      end,
      set_touch_enabled = function(_, name, enabled)
        calls[#calls + 1] = { "set_touch_enabled", name, enabled }
      end,
    },
  }
  return state, calls
end

local function _find_call(calls, method, name)
  for i = #calls, 1, -1 do
    local c = calls[i]
    if c[1] == method and c[2] == name then
      return c[3]
    end
  end
  return nil
end

-- 捕获入队提示;返回提示列表。
local function _capture_tips(fn)
  local tips = {}
  _with_patches({
    { target = tip_queue, key = "enqueue", value = function(tip)
      tips[#tips + 1] = tip
    end },
  }, fn)
  return tips
end

local function _capture_switches(fn)
  local switches = {}
  _with_patches({
    { target = canvas, key = "switch_by_role_id", value = function(ui, name, role_id)
      switches[#switches + 1] = { ui = ui, name = name, role_id = role_id }
    end },
  }, fn)
  return switches
end

local function _tip_keys(tips)
  local keys = {}
  for _, tip in ipairs(tips) do
    keys[#keys + 1] = tip.dedupe_key
  end
  return keys
end

describe("TestSkinPanel", function()
local fake
local restore_seam

local function _use_fake(opts)
  restore_seam()
  fake = fake_skin_ownership.new(opts)
  restore_seam = fake_skin_ownership.install(fake)
  return fake
end

before_each(function()
  fake = fake_skin_ownership.new()
  restore_seam = fake_skin_ownership.install(fake)
end)

after_each(function()
  restore_seam()
end)

-- ===== open / close =====

it("test_open_shows_and_close_hides_the_skin_canvas_for_the_active_role", function()
  local events = {}
  local role = _build_role_with_events(1, events)
  local s = _make_state()

  _with_patches({
    { target = runtime_ports, key = "resolve_role", value = function(role_id)
      if role_id == 1 then
        return role
      end
      return nil
    end },
  }, function()
    skin_panel.open(s, 1)
    luassert.truthy(_has_event(events, "显示皮肤商店"), "opening skin panel should show skin canvas")
    skin_panel.handle_action(s, "close", 1)
  end)

  luassert.truthy(_has_event(events, "隐藏皮肤商店"), "closing skin panel should hide skin canvas")
end)

it("test_open_resets_the_page_syncs_ownership_for_the_role_and_keeps_only_display_state", function()
  _use_fake({ catalog = _make_catalog(12) })
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.handle_action(s, "next", 1)

  local p = skin_panel.open(s, 3)

  _assert_eq(p.open, true, "panel open")
  _assert_eq(p.role_id, 3, "panel owned by the opener")
  _assert_eq(p.page_index, 1, "open resets to the first page")
  luassert.same({ "sync_on_shop_open:1:nil", "sync_on_shop_open:3:nil" }, fake.ops(), "each open syncs ownership")
  local keys = {}
  for key in pairs(p) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  luassert.same({ "open", "page_index", "role_id" }, keys, "panel state is display-only")
end)

it("test_uses_stable_notification_keys_and_honors_silent_close", function()
  local s = _make_state()
  local tips = _capture_tips(function()
    skin_panel.open(s, 1)
    skin_panel.close(s, 1, { silent = true })
    skin_panel.open(s, 1)
    skin_panel.close(s)
  end)

  luassert.same({ "skin_panel:open:1:", "skin_panel:open:1:", "skin_panel:close:1:" }, _tip_keys(tips),
    "silent close should not notify; keys carry an empty product suffix")
  _assert_eq(tips[1].text, "皮肤已打开", "open tip")
  _assert_eq(tips[3].text, "已关闭", "close tip")
end)

it("test_open_tip_key_names_the_skin_restored_on_open_and_the_panel_stays_open", function()
  _use_fake({ catalog = _make_rich_catalog(), restored = 5001 })
  local s = _make_state()
  local p
  local tips = _capture_tips(function()
    p = skin_panel.open(s, 1)
  end)
  luassert.same({ "skin_panel:open:1:5001" }, _tip_keys(tips), "open key carries the restored skin")
  _assert_eq(p.open, true, "restoring a skin keeps the shop open")
end)

it("test_notification_payloads_pin_source_and_non_blocking", function()
  local tips = _capture_tips(function()
    skin_panel.open(_make_state(), 1)
  end)
  _assert_eq(tips[1].blocks_inter_turn, false, "skin panel notifications must not block inter-turn")
  _assert_eq(tips[1].source, "ui.skin_panel", "notification source should be pinned")
  _assert_eq(tips[1].duration, 2.0, "notification duration")
end)

it("test_canvas_switches_pass_state_ui_and_resolved_role", function()
  local s = _make_state()
  local switches = _capture_switches(function()
    skin_panel.open(s, 1)
    skin_panel.close(s, 2)
    skin_panel.close(s)
  end)
  _assert_eq(switches[1].ui, s.ui, "canvas switch should receive state.ui, not the state")
  _assert_eq(switches[1].name, skin_nodes.canvas, "open should switch to the skin canvas")
  _assert_eq(switches[1].role_id, 1, "open switches the opener")
  _assert_eq(switches[2].name, base_nodes.canvas, "close should switch back to the base canvas")
  _assert_eq(switches[2].role_id, 2, "close switches the explicit role")
  _assert_eq(switches[3].role_id, 1, "close without a role falls back to the panel owner")
end)

-- ===== 请求映射 =====

it("test_dispatches_buy_gift_equip_integer_and_close_action_forms", function()
  _use_fake({ catalog = _make_catalog(3) })
  local s = _make_state()
  skin_panel.open(s, 1)

  skin_panel.handle_action(s, { type = "buy", slot_index = 2 }, 1)
  skin_panel.handle_action(s, { type = "gift", slot_index = 1 }, 1)
  skin_panel.handle_action(s, { type = "equip", slot_index = 2 }, 1)
  skin_panel.open(s, 1)
  skin_panel.handle_action(s, 1, 1)
  skin_panel.handle_action(s, "close", 1)

  luassert.same({
    "sync_on_shop_open:1:nil",
    "grant:1:skin_2",
    "grant:1:skin_1",
    "equip:1:skin_2",
    "sync_on_shop_open:1:nil",
    "equip:1:skin_1",
  }, fake.ops(), "each action form maps to its ownership command")
  _assert_eq(s.ui.skin_panel.open, false, "close action closes the panel")
end)

it("test_slot_alias_precedence_and_defaults", function()
  local cases = {
    { action = { type = "buy" }, product = "skin_1" },
    { action = { type = "buy", slot_index = 2, index = 99 }, product = "skin_2" },
    { action = { type = "buy", index = 2, slot = 99 }, product = "skin_2" },
    { action = { type = "buy", slot = 2 }, product = "skin_2" },
    { action = "buy", product = "skin_1" },
  }
  for _, case in ipairs(cases) do
    _use_fake({ catalog = _make_catalog(3) })
    local s = _make_state()
    skin_panel.open(s, 1)
    skin_panel.handle_action(s, case.action, 1)
    _assert_eq(fake.ops()[2], "grant:1:" .. case.product, "slot resolution for " .. tostring(case.product))
  end
end)

it("test_equip_on_page_2_and_non_integer_slot_resolve_the_catalog_index", function()
  _use_fake({ catalog = _make_catalog(12) })
  local s = _make_state()
  skin_panel.open(s, 1)
  fake.own(1, "skin_1")
  fake.own(1, "skin_7")

  skin_panel.equip(s, 1, "not_an_integer")
  skin_panel.handle_action(s, "next", 1)
  skin_panel.equip(s, 1, 1)

  _assert_eq(s.ui.skin_panel.page_index, 2, "next moves to page 2")
  luassert.same({ "sync_on_shop_open:1:nil", "equip:1:skin_1", "equip:1:skin_7" }, fake.ops(),
    "non-integer slot defaults to 1; page 2 slot 1 is catalog index 7")
end)

it("test_paging_clamps_to_the_catalog_and_stays_silent", function()
  _use_fake({ catalog = _make_catalog(8) })
  local s = _make_state()
  skin_panel.open(s, 1)
  local tips = _capture_tips(function()
    skin_panel.handle_action(s, "next", 1)
    skin_panel.handle_action(s, "next", 1)
    _assert_eq(s.ui.skin_panel.page_index, 2, "next stops at the last page")
    skin_panel.handle_action(s, "prev", 1)
    skin_panel.handle_action(s, "prev", 1)
    _assert_eq(s.ui.skin_panel.page_index, 1, "prev stops at the first page")
  end)
  luassert.same({}, tips, "page actions must stay silent")
end)

it("test_out_of_range_slots_are_inert", function()
  _use_fake({ catalog = _make_catalog(3) })
  local s = _make_state()
  skin_panel.open(s, 1)
  for _, slot in ipairs({ 5, 99 }) do
    _assert_eq(skin_panel.equip(s, 1, slot), s.ui.skin_panel, "equip returns the panel")
    _assert_eq(skin_panel.unlock(s, 1, "buy", slot), s.ui.skin_panel, "unlock returns the panel")
  end
  luassert.same({ "sync_on_shop_open:1:nil" }, fake.ops(), "no ownership command for an empty slot")
end)

it("test_role_falls_back_to_the_panel_owner_but_an_explicit_role_wins", function()
  _use_fake({ catalog = _make_catalog(3) })
  local s = _make_state()
  skin_panel.open(s, 7)
  fake.own(7, "skin_1")
  fake.wear(2, "skin_2")

  skin_panel.equip(s, nil, 1)
  skin_panel.handle_action(s, "unequip", 2)

  luassert.same({ "sync_on_shop_open:7:nil", "equip:7:skin_1", "unequip:2:nil" }, fake.ops(),
    "nil role uses the panel owner; an explicit role is honoured")
end)

it("test_activate_slot_toggles_between_equip_and_unequip", function()
  _use_fake({ catalog = _make_catalog(3) })
  local s = _make_state()
  skin_panel.open(s, 1)
  fake.own(1, "skin_2")

  skin_panel.handle_action(s, { type = "activate_slot", slot_index = 2 }, 1)
  skin_panel.handle_action(s, { type = "activate_slot", slot_index = 2 }, 1)

  luassert.same({ "sync_on_shop_open:1:nil", "equip:1:skin_2", "unequip:1:nil" }, fake.ops(),
    "activate equips an owned skin, then unequips the worn one")
end)

it("test_handle_action_with_unknown_action_returns_panel_with_defaults", function()
  local result = skin_panel.handle_action(_make_state(), "unknown_xyz_no_handler", 1)
  _assert_eq(type(result), "table", "unknown action returns the panel state")
  _assert_eq(result.open, false, "default open=false")
  _assert_eq(result.page_index, 1, "default page_index=1")
end)

-- ===== 结果展示 =====

it("test_equipping_an_owned_skin_closes_the_shop_and_tips_with_the_skin_name", function()
  _use_fake({ catalog = _make_catalog(1) })
  local s = _make_state()
  skin_panel.open(s, 1)
  fake.own(1, "skin_1")
  local tips
  local switches = _capture_switches(function()
    tips = _capture_tips(function()
      skin_panel.equip(s, 1, 1)
    end)
  end)

  _assert_eq(s.ui.skin_panel.open, false, "equip closes the shop")
  _assert_eq(switches[1].name, base_nodes.canvas, "equip returns to the base canvas")
  _assert_eq(switches[1].role_id, 1, "for the equipping role")
  _assert_eq(tips[1].text, "已换装 皮肤1", "equip tip names the skin")
  _assert_eq(tips[1].dedupe_key, "skin_panel:equip:1:skin_1", "equip tip key")
end)

it("test_unlock_and_unequip_tips_keep_the_shop_open", function()
  _use_fake({ catalog = _make_catalog(2) })
  local s = _make_state()
  skin_panel.open(s, 1)
  fake.wear(1, "skin_2")
  local tips = _capture_tips(function()
    skin_panel.unlock(s, 1, "gift", 1)
    skin_panel.handle_action(s, "unequip", 1)
  end)
  _assert_eq(tips[1].text, "皮肤1 已解锁", "unlock tip")
  _assert_eq(tips[1].dedupe_key, "skin_panel:unlock:1:skin_1", "unlock tip key")
  _assert_eq(tips[2].text, "已脱下皮肤", "unequip tip")
  _assert_eq(tips[2].dedupe_key, "skin_panel:unequip:1:", "unequip tip key")
  _assert_eq(s.ui.skin_panel.open, true, "unlock and unequip keep the shop open")
end)

it("test_refused_commands_show_nothing", function()
  _use_fake({ catalog = _make_catalog(2) })
  local s = _make_state()
  local tips = _capture_tips(function()
    skin_panel.unlock(s, nil, "gift", 1)
    skin_panel.handle_action(s, "unequip", nil)
  end)
  luassert.same({}, tips, "refused grant / unequip show no tip")
end)

it("test_locked_skin_equip_starts_a_purchase_without_tip_or_close", function()
  _use_fake({ catalog = _make_rich_catalog() })
  local s = _make_state()
  skin_panel.open(s, 1)
  local tips = _capture_tips(function()
    skin_panel.equip(s, 1, 1)
  end)
  luassert.same({ "sync_on_shop_open:1:nil", "start_purchase:1:5001" }, fake.ops(), "locked skin starts a purchase")
  luassert.same({}, tips, "an accepted purchase start shows nothing")
  _assert_eq(s.ui.skin_panel.open, true, "the shop stays open while paying")
end)

it("test_purchase_refusals_map_to_tips", function()
  local cases = {
    { reason = "archive_unavailable", text = "存档未开启，暂时无法购买皮肤" },
    { reason = "invalid_purchase_skin", text = "皮肤尚未解锁" },
    { reason = "host_busy", text = "皮肤尚未解锁" },
    { reason = "paid_gateway_missing", text = "皮肤尚未解锁" },
    { reason = "purchase_in_flight", text = nil },
    { reason = "missing_role", text = nil },
  }
  for _, case in ipairs(cases) do
    _use_fake({ catalog = _make_rich_catalog(), purchase_refusal = case.reason })
    local s = _make_state()
    skin_panel.open(s, 1)
    local tips = _capture_tips(function()
      skin_panel.equip(s, 1, 1)
    end)
    if case.text == nil then
      luassert.same({}, tips, case.reason .. " shows no tip")
    else
      _assert_eq(tips[1] and tips[1].text, case.text, case.reason .. " tip")
      _assert_eq(tips[1].dedupe_key, "skin_panel:unknown:1:", case.reason .. " tip key")
    end
  end
end)

it("test_purchase_completion_closes_the_shop_refreshes_slots_and_tips_for_the_panel_owner", function()
  _use_fake({ catalog = _make_rich_catalog() })
  local s, calls = _make_render_state()
  s.runtime_asset_context = { refs = { images = {} } }
  skin_panel.open(s, 1)
  skin_panel.equip(s, 1, 1)
  _assert_eq(_find_call(calls, "set_button", skin_nodes.action_buttons[1]), "198", "price before completion")

  local tips
  local switches = _capture_switches(function()
    tips = _capture_tips(function()
      fake.complete_purchase()
    end)
  end)

  _assert_eq(_find_call(calls, "set_button", skin_nodes.action_buttons[1]), "脱下", "slot refreshed to worn")
  _assert_eq(_find_call(calls, "set_visible", skin_nodes.price_icons[1]), false, "price icon hidden")
  _assert_eq(s.ui.skin_panel.open, false, "completion closes the shop")
  _assert_eq(switches[1].name, base_nodes.canvas, "completion returns to the base canvas")
  _assert_eq(switches[1].role_id, 1, "for the panel owner")
  _assert_eq(tips[1].text, "已换装 皮肤甲", "completion tip names the skin")
  _assert_eq(tips[1].dedupe_key, "skin_panel:purchase_complete:1:5001", "completion tip key")
end)

it("test_purchase_completion_names_the_bought_skin_after_page_changes", function()
  local catalog = {}
  for index = 1, 7 do
    catalog[index] = { product_id = 7000 + index, name = "skin" .. index, unlock = "purchase", currency = "beans", price = 10 }
  end
  _use_fake({ catalog = catalog })
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.equip(s, 1, 1)
  skin_panel.handle_action(s, "next", 1)

  local tips = _capture_tips(function()
    fake.complete_purchase()
  end)

  _assert_eq(fake.purchases[1].product_id, 7001, "purchase started for page 1 slot 1")
  _assert_eq(tips[1].text, "已换装 skin1", "completion names the originally bought skin")
end)

it("test_rejected_purchase_completion_changes_nothing", function()
  _use_fake({ catalog = _make_rich_catalog() })
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.equip(s, 1, 1)
  local tips = _capture_tips(function()
    fake.complete_purchase(1, { accepted = false, reason = "pending_purchase_missing", product_id = 5001 })
  end)
  luassert.same({}, tips, "rejected completion shows nothing")
  _assert_eq(s.ui.skin_panel.open, true, "rejected completion keeps the shop open")
end)

it("test_equip_refreshes_the_slot_button_to_the_worn_state", function()
  _use_fake({ catalog = _make_rich_catalog() })
  local s, calls = _make_render_state()
  s.runtime_asset_context = { refs = { images = {} } }
  skin_panel.open(s, 1)
  skin_panel.unlock(s, 1, "buy", 1)
  _assert_eq(_find_call(calls, "set_button", skin_nodes.action_buttons[1]), "穿上", "owned skin offers 穿上")

  skin_panel.equip(s, 1, 1)

  _assert_eq(_find_call(calls, "set_button", skin_nodes.action_buttons[1]), "脱下", "equip refreshes to 脱下")
end)

-- ===== 槽位渲染 =====

-- button rendering
it("test_locked_skins_render_price_gift_text_and_touch_state_per_unlock_kind", function()
  -- 富 catalog:购买皮显示价格且可点,礼皮显示 gift_name 且不可点
  local state, calls = _make_render_state()
  skin_panel_view.refresh_slots(state, _make_rich_catalog())
  local price_text = _find_call(calls, "set_button", skin_nodes.action_buttons[1])
  luassert.truthy(price_text == "198", "locked purchase button should show price only, got: " .. tostring(price_text))
  luassert.truthy(_find_call(calls, "set_touch_enabled", skin_nodes.action_buttons[1]) == true,
    "locked purchase button should be touch-enabled")
  local gift_text = _find_call(calls, "set_button", skin_nodes.action_buttons[3])
  luassert.truthy(gift_text == "谢礼", "locked gift button should show gift_name, got: " .. tostring(gift_text))
  luassert.truthy(_find_call(calls, "set_touch_enabled", skin_nodes.action_buttons[3]) == false,
    "locked gift button should be touch-disabled")

  -- 缺 gift_name 的礼皮回退价格文本;两样皆缺时清掉旧文案
  local fallback_state, fallback_calls = _make_render_state()
  skin_panel_view.refresh_slots(fallback_state, {
    { product_id = 1, name = "gift_without_name", unlock = "gift", currency = "金豆", price = 100 },
  })
  luassert.truthy(_find_call(fallback_calls, "set_button", skin_nodes.action_buttons[1]) == "100",
    "gift skin without gift_name should fall back to price text only")

  local bare_state, bare_calls = _make_render_state()
  skin_panel_view.refresh_slots(bare_state, {
    { product_id = 1, name = "missing_price", unlock = "purchase" },
  })
  luassert.truthy(_find_call(bare_calls, "set_button", skin_nodes.action_buttons[1]) == "",
    "locked skin without display text should clear stale button text")
end)

it("test_default_catalog_fills_slots_1_to_4_and_leaves_5_and_6_empty", function()
  local state, calls = _make_render_state()
  skin_panel_view.refresh_slots(state, default_skins)
  local expected_prices = { "68", "98", "198", "198" }
  for slot = 1, 4 do
    local text = _find_call(calls, "set_button", skin_nodes.action_buttons[slot])
    local enabled = _find_call(calls, "set_touch_enabled", skin_nodes.action_buttons[slot])
    local price_visible = _find_call(calls, "set_visible", skin_nodes.price_icons[slot])
    luassert.truthy(text == expected_prices[slot],
      "default slot " .. tostring(slot) .. " should show price " .. expected_prices[slot])
    luassert.truthy(enabled == true, "default slot " .. tostring(slot) .. " should be touch-enabled")
    luassert.truthy(price_visible == true, "default slot " .. tostring(slot) .. " should show price icon")
  end
  for slot = 5, 6 do
    luassert.truthy(_find_call(calls, "set_visible", skin_nodes.card_images[slot]) == false,
      "empty default slot " .. tostring(slot) .. " card image should be hidden")
    luassert.truthy(_find_call(calls, "set_touch_enabled", skin_nodes.action_buttons[slot]) == false,
      "empty default slot " .. tostring(slot) .. " action button must not consume clicks")
    luassert.truthy(_find_call(calls, "set_visible", skin_nodes.price_icons[slot]) == false,
      "empty default slot " .. tostring(slot) .. " should hide stale price icon")
  end
end)

it("test_owned and equipped skins render 穿上/脱下 with touch enabled", function()
  local catalog = _make_rich_catalog()
  fake.own(1, 5001)
  local owned_state, owned_calls = _make_render_state()
  skin_panel_view.refresh_slots(owned_state, catalog)
  luassert.truthy(_find_call(owned_calls, "set_button", skin_nodes.action_buttons[1]) == "穿上",
    "owned button should show 穿上")
  luassert.truthy(_find_call(owned_calls, "set_touch_enabled", skin_nodes.action_buttons[1]) == true,
    "owned button should be touch-enabled")

  fake.wear(1, 5001)
  local equipped_state, equipped_calls = _make_render_state()
  skin_panel_view.refresh_slots(equipped_state, catalog)
  luassert.truthy(_find_call(equipped_calls, "set_button", skin_nodes.action_buttons[1]) == "脱下",
    "equipped button should show 脱下")
  luassert.truthy(_find_call(equipped_calls, "set_touch_enabled", skin_nodes.action_buttons[1]) == true,
    "equipped button should be touch-enabled")
end)

it("test_card_outline_containers_follow_slot_occupancy_regardless_of_equip_state", function()
  fake.wear(1, 5002)
  local state, calls = _make_render_state()
  skin_panel_view.refresh_slots(state, _make_rich_catalog())
  for slot = 1, 3 do
    luassert.truthy(_find_call(calls, "set_visible", skin_nodes.card_outlines[slot]) == true,
      "occupied outline container " .. slot .. " should be visible")
  end
  for slot = 4, #skin_nodes.card_outlines do
    luassert.truthy(_find_call(calls, "set_visible", skin_nodes.card_outlines[slot]) == false,
      "empty outline container " .. slot .. " should be hidden")
  end
end)

it("test_price_icon_hides_for_owned_equipped_skins_but_stays_for_unowned_neighbors", function()
  local catalog = _make_rich_catalog()
  fake.own(1, 5001)
  local owned_state, owned_calls = _make_render_state()
  skin_panel_view.refresh_slots(owned_state, catalog)
  luassert.truthy(_find_call(owned_calls, "set_visible", skin_nodes.price_icons[1]) == false,
    "owned purchase skin should hide its price icon")
  luassert.truthy(_find_call(owned_calls, "set_visible", skin_nodes.price_icons[2]) == true,
    "an unowned purchase skin should still show its price icon")

  fake.wear(1, 5001)
  local equipped_state, equipped_calls = _make_render_state()
  skin_panel_view.refresh_slots(equipped_state, catalog)
  luassert.truthy(_find_call(equipped_calls, "set_visible", skin_nodes.price_icons[1]) == false,
    "equipped purchase skin should hide its price icon")
end)

it("test_slots_render_another_roles_ownership_only_for_that_panel_owner", function()
  fake.own(2, 5001)
  local state, calls = _make_render_state({ role_id = 1 })
  skin_panel_view.refresh_slots(state, _make_rich_catalog())
  _assert_eq(_find_call(calls, "set_button", skin_nodes.action_buttons[1]), "198",
    "slot status follows the panel owner's ownership")
end)

it("test_sets_card_texture_when_image_ref_exists", function()
  local catalog = _make_rich_catalog()
  local state, _ = _make_render_state()
  state.runtime_asset_context = { refs = { images = { ["5001"] = "tex_pig" } } }
  local textures = {}
  local runtime = {
    query_node = function(name) return { name = name } end,
    set_node_texture_keep_size = function(node, key)
      textures[node.name] = key
    end,
  }
  skin_panel_view.refresh_slots(state, catalog, { runtime = runtime })
  luassert.truthy(textures[skin_nodes.card_images[1]] == "tex_pig",
    "should set texture for skin with image ref")
  luassert.is_nil(textures[skin_nodes.card_images[2]],
    "should not set texture for skin without image ref")
end)

it("test_sets_card_texture_from_resolver_asset_context", function()
  local catalog = _make_rich_catalog()
  local state, _ = _make_render_state()
  state.runtime_asset_context = {
    refs = {
      images = {
        ["5001"] = "tex_pig",
      },
    },
  }
  local textures = {}
  local runtime = {
    query_node = function(name) return { name = name } end,
    set_node_texture_keep_size = function(node, key)
      textures[node.name] = key
    end,
  }

  skin_panel_view.refresh_slots(state, catalog, { runtime = runtime })

  luassert.truthy(runtime_assets.asset_context(state) == state.runtime_asset_context,
    "state asset context should be the adapter-facing resolver fixture")
  luassert.truthy(textures[skin_nodes.card_images[1]] == "tex_pig",
    "skin card renderer should consume resolver asset context")
end)

it("test_uses_card_image_refs_instead_of_skin_prefab_refs_for_card_textures", function()
  local catalog = _make_rich_catalog()
  local state, _ = _make_render_state()
  state.runtime_asset_context = { refs = {
    images = { ["5001"] = "card_tex_pig" },
    skins = { ["5001"] = "unit_prefab_pig" },
  } }
  local textures = {}
  local runtime = {
    query_node = function(name) return { name = name } end,
    set_node_texture_keep_size = function(node, key)
      textures[node.name] = key
    end,
  }
  skin_panel_view.refresh_slots(state, catalog, { runtime = runtime })
  luassert.truthy(textures[skin_nodes.card_images[1]] == "card_tex_pig",
    "skin shop card image must use context images, not context skins prefab refs")
end)

it("test_sets_card_texture_on_all_matched_nodes_when_runtime_exposes_query_nodes", function()
  local catalog = _make_rich_catalog()
  local state, _ = _make_render_state()
  state.runtime_asset_context = { refs = { images = { ["5001"] = "tex_pig" } } }
  local textures = {}
  local runtime = {
    query_nodes = function(name)
      return {
        { name = name .. "#a" },
        { name = name .. "#b" },
      }
    end,
    set_node_texture_keep_size = function(node, key)
      textures[node.name] = key
    end,
  }
  skin_panel_view.refresh_slots(state, catalog, { runtime = runtime })
  luassert.truthy(textures[skin_nodes.card_images[1] .. "#a"] == "tex_pig",
    "should set texture on first matched node")
  luassert.truthy(textures[skin_nodes.card_images[1] .. "#b"] == "tex_pig",
    "should set texture on second matched node")
end)

it("test_ignores_non_table_and_failed_query_nodes_results_when_setting_card_textures", function()
  local catalog = _make_rich_catalog()
  local state, _ = _make_render_state()
  state.runtime_asset_context = { refs = { images = { ["5001"] = "tex_pig" } } }
  local texture_calls = 0
  skin_panel_view.refresh_slots(state, catalog, { runtime = {
    query_nodes = function() return "not-a-node-list" end,
    set_node_texture_keep_size = function()
      texture_calls = texture_calls + 1
    end,
  } })
  -- lint-allow: call-count runtime 经参数注入(宿主节点边界),不设贴图即可见副作用
  luassert.truthy(texture_calls == 0, "non-table query_nodes result should not set textures")

  local failed_state, _ = _make_render_state()
  failed_state.runtime_asset_context = { refs = { images = { ["5001"] = "tex_pig" } } }
  local textures = {}
  skin_panel_view.refresh_slots(failed_state, catalog, { runtime = {
    query_nodes = function()
      error({ { name = "should_not_be_textured" } })
    end,
    set_node_texture_keep_size = function(node, key)
      textures[node.name] = key
    end,
  } })
  luassert.is_nil(textures.should_not_be_textured,
    "failed query_nodes payload must not be treated as matched nodes")
end)

it("test_shows_action_buttons_and_card_frames_only_for_occupied_slots", function()
  local catalog = _make_catalog(3)
  local state, calls = _make_render_state()
  skin_panel_view.refresh_slots(state, catalog)
  luassert.truthy(_find_call(calls, "set_visible", skin_nodes.action_buttons[1]) == true,
    "occupied slot action button should be visible")
  luassert.truthy(_find_call(calls, "set_visible", skin_nodes.action_buttons[4]) == false,
    "empty slot action button should be hidden")
  luassert.truthy(_find_call(calls, "set_visible", skin_nodes.card_frames[1]) == true,
    "occupied slot frame should be visible")
  luassert.truthy(_find_call(calls, "set_visible", skin_nodes.card_frames[4]) == false,
    "empty slot frame should be hidden")
end)

it("test_open_render_enables_background_touch_and_passes_through_close_texts", function()
  -- #178 点背景关闭:背景可点,提示文字关闭触摸;关闭按钮与卡牌照常可点。
  local state, calls = _make_render_state()
  skin_panel_view.refresh_slots(state, _make_catalog(3))
  _assert_eq(_find_call(calls, "set_touch_enabled", "皮肤商店-活动背景"), true,
    "skin shop background must accept touch")
  _assert_eq(_find_call(calls, "set_touch_enabled", "皮肤_关闭皮肤文本提示"), false,
    "click-background hint must not swallow touch")
  _assert_eq(_find_call(calls, "set_touch_enabled", skin_nodes.close_button), true,
    "close button stays clickable")
  _assert_eq(_find_call(calls, "set_touch_enabled", skin_nodes.card_images[1]), true,
    "occupied card stays clickable")
end)

it("test_price_icon_visible_for_purchase_skin_hidden_for_gift_skin", function()
  local catalog = _make_rich_catalog()
  local state, calls = _make_render_state()
  skin_panel_view.refresh_slots(state, catalog)
  local purchase_icon = _find_call(calls, "set_visible", skin_nodes.price_icons[1])
  local gift_icon = _find_call(calls, "set_visible", skin_nodes.price_icons[3])
  luassert.truthy(purchase_icon == true, "purchase skin should show price icon")
  luassert.truthy(gift_icon == false, "gift skin should hide price icon")
end)

-- 价格图标只对同时声明价格与币种的购买皮肤显示。
-- 分别缺少购买路径、价格或币种时都应隐藏。
it("test_l111_conjuncts_each_independently_hide_the_price_icon", function()
  local cases = {
    { catalog = { { product_id = 1, name = "gift_with_price",
        unlock = "gift", gift_name = "谢礼", currency = "金豆", price = 100 } },
      message = "gift unlock should hide price icon even when price/currency set (L111 M1)" },
    { catalog = { { product_id = 1, name = "purchase_no_price",
        unlock = "purchase", currency = "金豆", price = nil } },
      message = "purchase unlock with nil price should hide price icon (L111 M2)" },
    { catalog = { { product_id = 1, name = "purchase_no_currency",
        unlock = "purchase", currency = nil, price = 100 } },
      message = "purchase unlock with nil currency should hide price icon (L111 M2 sym)" },
  }
  for _, case in ipairs(cases) do
    local state, calls = _make_render_state()
    skin_panel_view.refresh_slots(state, case.catalog)
    luassert.truthy(_find_call(calls, "set_visible", skin_nodes.price_icons[1]) == false, case.message)
  end
end)

it("test_full_first_page_shows_all_6_card_images_also_without_panel_state", function()
  local catalog = _make_catalog(6)
  local state, calls = _make_render_state()
  skin_panel_view.refresh_slots(state, catalog)
  for slot = 1, 6 do
    luassert.truthy(_find_call(calls, "set_visible", skin_nodes.card_images[slot]) == true,
      "slot " .. slot .. " card image should be visible")
  end

  local bare_state, bare_calls = _make_render_state()
  bare_state.ui.skin_panel = nil
  skin_panel_view.refresh_slots(bare_state, catalog)
  for slot = 1, 6 do
    luassert.truthy(_find_call(bare_calls, "set_visible", skin_nodes.card_images[slot]) == true,
      "slot " .. slot .. " should render from the first page without panel state")
  end
end)

it("test_trailing_empty_slots_hide_disable_card_images_buttons_and_price_icons", function()
  local catalog = _make_catalog(3)
  local state, calls = _make_render_state()
  skin_panel_view.refresh_slots(state, catalog)
  for slot = 1, 3 do
    luassert.truthy(_find_call(calls, "set_visible", skin_nodes.card_images[slot]) == true,
      "slot " .. slot .. " card image should be visible")
    luassert.truthy(_find_call(calls, "set_touch_enabled", skin_nodes.card_images[slot]) == true,
      "slot " .. slot .. " card image should be touch-enabled")
  end
  for slot = 4, 6 do
    luassert.truthy(_find_call(calls, "set_visible", skin_nodes.card_images[slot]) == false,
      "slot " .. slot .. " card image should be hidden (no skin)")
    luassert.truthy(_find_call(calls, "set_touch_enabled", skin_nodes.card_images[slot]) == false,
      "empty card slot " .. slot .. " must not consume clicks")
    luassert.truthy(_find_call(calls, "set_button", skin_nodes.action_buttons[slot]) == "",
      "empty slot " .. slot .. " should clear stale button text")
    luassert.truthy(_find_call(calls, "set_touch_enabled", skin_nodes.action_buttons[slot]) == false,
      "empty slot " .. slot .. " action button must not consume clicks")
    luassert.truthy(_find_call(calls, "set_visible", skin_nodes.price_icons[slot]) == false,
      "empty slot " .. slot .. " should hide stale price icon")
  end
end)

it("test_page_2_renders_offset_card_slots_from_full_catalog", function()
  local catalog = _make_catalog(12)
  local state, _ = _make_render_state({ page_index = 2 })
  state.runtime_asset_context = { refs = { images = {} } }
  for i = 1, 12 do
    state.runtime_asset_context.refs.images["skin_" .. i] = "tex_" .. i
  end
  local textures = {}
  local runtime = {
    query_node = function(name) return { name = name } end,
    set_node_texture_keep_size = function(node, key)
      textures[node.name] = key
    end,
  }
  skin_panel_view.refresh_slots(state, catalog, { runtime = runtime })
  luassert.truthy(textures[skin_nodes.card_images[1]] == "tex_7",
    "page 2 slot 1 should render skin_7 texture, got " .. tostring(textures[skin_nodes.card_images[1]]))
  luassert.truthy(textures[skin_nodes.card_images[6]] == "tex_12",
    "page 2 slot 6 should render skin_12 texture, got " .. tostring(textures[skin_nodes.card_images[6]]))
end)

it("test_page_2_hides_trailing_empty_slots_when_last_page_partially_fills", function()
  local catalog = _make_catalog(8)
  local state, calls = _make_render_state({ page_index = 2 })
  skin_panel_view.refresh_slots(state, catalog)
  for slot = 1, 2 do
    local vis = _find_call(calls, "set_visible", skin_nodes.card_images[slot])
    luassert.truthy(vis == true, "page 2 slot " .. slot .. " card image should be visible")
  end
  for slot = 3, 6 do
    local vis = _find_call(calls, "set_visible", skin_nodes.card_images[slot])
    luassert.truthy(vis == false, "page 2 slot " .. slot .. " card image should be hidden")
  end
end)

-- ===== route 面 =====

it("test_build_route_specs_pins_close_and_equip_actions", function()
  -- 杀 L42 "close"->nil 与 L47 "equip"->nil:route spec 的 intent action 必须保留。
  local specs = skin_panel.build_route_specs(_make_state())
  local close_intent, equip_intent = nil, nil
  for _, spec in ipairs(specs) do
    if spec.name == skin_nodes.close_button then
      close_intent = spec.build_intent()
    end
    if spec.name == skin_nodes.card_images[1] then
      equip_intent = spec.build_intent()
    end
  end
  luassert.truthy(close_intent ~= nil, "close button should be routed")
  luassert.truthy(close_intent.action == "close", "close intent action should be pinned")
  luassert.truthy(equip_intent ~= nil, "card image should be routed")
  luassert.truthy(equip_intent.action.type == "equip", "card intent action type should be equip")
  luassert.truthy(equip_intent.action.slot_index == 1, "card intent slot index should pass through")
end)

it("test_background_click_routes_same_intent_as_close_button", function()
  -- #178 点背景关闭:皮肤商店背景与关闭按钮产出同一面板动作意图。
  local specs = skin_panel.build_route_specs(_make_state())
  local close_intent, background_intent = nil, nil
  for _, spec in ipairs(specs) do
    if spec.name == "皮肤商店-关闭" then
      close_intent = spec.build_intent()
    end
    if spec.name == "皮肤商店-活动背景" then
      background_intent = spec.build_intent()
    end
  end
  luassert.same({ type = "skin_panel_action", action = "close" }, close_intent, "close button intent")
  luassert.same(close_intent, background_intent, "background click must equal close button intent")
end)
end)
