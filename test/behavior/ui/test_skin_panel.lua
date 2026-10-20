require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
local support = require("test.support.shared_support")
local _with_patches = support.with_patches
local _build_role_with_events = support.build_role_with_events
local _has_event = support.has_event
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local canvas = require("src.ui.coord.canvas_coordinator")
local skin_panel = require("src.ui.screens.skin_panel")
local transaction = require("src.app.cosmetics.transaction")
local paid_purchase_port = require("src.rules.ports.paid_purchase")
local tip_queue = require("src.foundation.tips")
local skin_panel_view = require("src.ui.render.widgets.skin_panel")
local skin_nodes = require("src.ui.schema.skin")
local default_skins = require("src.config.content.skins")
local logger = require("src.foundation.log")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local runtime_assets = require("src.config.runtime_assets")

local function _make_state()
  return { ui = {} }
end

-- Locked-skin purchases route through transaction_purchase's native paid path,
-- which resolves the buyer via state.game:find_player_by_id(role_id). Tests that
-- exercise the paid port need a game whose player id echoes the role id.
local function _make_paid_state()
  return {
    ui = {},
    game = {
      find_player_by_id = function(_, role_id)
        return { id = role_id }
      end,
    },
  }
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
    owned_by_role = {},
    selected_by_role = {},
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

local function _with_clean_tip_runtime(fn)
  tip_queue.clear()
  local handler = debug and debug.traceback or function(err) return err end
  local ok, err = xpcall(fn, handler)
  tip_queue.clear()
  support.restore_runtime_services()
  if not ok then
    error(err)
  end
end

-- In-memory stand-in for the host skin archive port. Records mark/save calls so
-- tests can assert what was persisted, and serves load_* back for seeding.
local function _make_fake_archive()
  local store = { owned = {}, equipped = {}, mark_calls = {}, save_calls = {} }
  return {
    store = store,
    mark_owned = function(role, product_id)
      store.mark_calls[#store.mark_calls + 1] = { role = role, product_id = product_id }
      store.owned[tostring(role)] = store.owned[tostring(role)] or {}
      store.owned[tostring(role)][product_id] = true
    end,
    load_owned = function(role)
      local out = {}
      for product_id in pairs(store.owned[tostring(role)] or {}) do
        out[#out + 1] = product_id
      end
      return out
    end,
    save_equipped = function(role, product_id)
      store.save_calls[#store.save_calls + 1] = { role = role, product_id = product_id }
      store.equipped[tostring(role)] = product_id
    end,
    load_equipped = function(role)
      return store.equipped[tostring(role)]
    end,
  }
end

describe("TestSkinPanel", function()
before_each(function()
  skin_panel.reset_for_tests()
end)

-- open/close
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

-- owner refresh 经 presentation_runtime.with_client_role 的路由由
-- with_client_role_spec（直接单测 runtime.with_client_role 分支）与
-- skin_panel_intent_canvas_spec（经 view_command.dispatch 全路径验证
-- 仅点击者 canvas 切换、他人不被牵动）二处承载，此处不再双测（#237）。
it("test_falls_back_to_ensured_panel_when_transaction_returns_nil", function()
  local presented_text = nil

  _with_clean_tip_runtime(function()
    local s = _make_state()
    _with_patches({
      { target = transaction, key = "handle_skin_transaction", value = function()
        return nil
      end },
    }, function()
      tip_queue.configure_runtime({
        presenter = function(text)
          presented_text = text
        end,
        scheduler = function()
          return true
        end,
        test_mode = false,
      })

      local unlock_panel = skin_panel.unlock(s, 1, "buy", 1)
      local next_panel = skin_panel.handle_action(s, "next", 1)
      local prev_panel = skin_panel.handle_action(s, "prev", 1)
      local unequip_panel = skin_panel.handle_action(s, "unequip", 1)

      luassert.truthy(unlock_panel == s.ui.skin_panel, "nil transaction result should return ensured panel")
      luassert.truthy(next_panel == s.ui.skin_panel, "nil next result should return ensured panel")
      luassert.truthy(prev_panel == s.ui.skin_panel, "nil prev result should return ensured panel")
      luassert.truthy(unequip_panel == s.ui.skin_panel, "nil unequip result should return ensured panel")
    end)

    luassert.is_nil(presented_text, "nil transaction result should not present notifications")
  end)
end)

it("test_uses_stable_notification_keys_and_honors_silent_close", function()
  local s = _make_state()
  local tips = {}

  _with_patches({
    { target = tip_queue, key = "enqueue", value = function(tip)
      tips[#tips + 1] = tip
    end },
  }, function()
    skin_panel.open(s, 1)
    skin_panel.close(s, 1, { silent = true })
    skin_panel.open(s, 1)
    skin_panel.close(s)
  end)

  luassert.truthy(#tips == 3, "silent close should not enqueue a notification")
  luassert.truthy(tips[1].dedupe_key == "skin_panel:open:1:",
    "open notification key should include empty product suffix")
  luassert.truthy(tips[2].dedupe_key == "skin_panel:open:1:",
    "second open notification key should remain stable")
  luassert.truthy(tips[3].dedupe_key == "skin_panel:close:1:",
    "close notification key should include empty product suffix")
end)

it("test_uses_equipped_product_in_equip_notification_key", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(1))
  local s = _make_state()
  local tips = {}

  _with_patches({
    { target = tip_queue, key = "enqueue", value = function(tip)
      tips[#tips + 1] = tip
    end },
  }, function()
    skin_panel.open(s, 1)
    skin_panel.unlock(s, 1, "buy", 1)
    skin_panel.equip(s, 1, 1)
  end)

  luassert.truthy(tips[#tips].dedupe_key == "skin_panel:equip:1:skin_1",
    "equip notification key should use equipped_product")
end)

it("test_does_not_close_canvas_when_result_does_not_request_close", function()
  local events = {}
  local role = _build_role_with_events(1, events)
  local s = _make_state()
  s.ui.skin_panel = {
    open = true,
    role_id = 1,
    page_index = 1,
    owned_by_role = {},
    selected_by_role = {},
  }

  _with_patches({
    { target = transaction, key = "handle_skin_transaction", value = function()
      return {
        accepted = true,
        ok = true,
        action = "close",
        panel = s.ui.skin_panel,
        panel_should_close = false,
      }
    end },
    { target = runtime_ports, key = "resolve_role", value = function(role_id)
      if role_id == 1 then return role end
      return nil
    end },
  }, function()
    skin_panel.close(s, 1)
  end)

  luassert.truthy(not _has_event(events, "隐藏皮肤商店"),
    "close result without panel_should_close must not hide the skin canvas")
end)

-- unlock and equip
it("test_is_slot_equipped_returns_false_for_an_empty_slot", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(1))
  local s = _make_state()
  skin_panel.open(s, 1)
  luassert.is.equal(false, skin_panel.is_slot_equipped(s, 2))
end)

it("test_unequip_invokes_the_restore_callback_with_the_role_id", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(5))
  local received = "unset"
  skin_panel.configure_unequip(function(role_id) received = role_id end)
  local s = _make_state()
  skin_panel.open(s, 2)
  skin_panel.unlock(s, 2, "buy", 1)
  skin_panel.equip(s, 2, 1)
  skin_panel.handle_action(s, "unequip", 2)
  luassert.truthy(received == 2,
    "unequip should pass the role id to the restore callback, got " .. tostring(received))
end)

it("test_unequip_warns_and_still_clears_selection_when_the_restore_callback_throws", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(5))
  skin_panel.configure_unequip(function() error("boom") end)
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.unlock(s, 1, "buy", 1)
  skin_panel.equip(s, 1, 1)
  local warned = false
  _with_patches({
    { target = logger, key = "warn", value = function(message)
      if tostring(message):match("unequip callback failed") then
        warned = true
      end
    end },
  }, function()
    skin_panel.handle_action(s, "unequip", 1)
  end)
  luassert.truthy(warned, "a throwing restore callback must hit the warn failure path")
  luassert.is_nil(s.ui.skin_panel.selected_by_role["1"],
    "a throwing restore callback must not block selection clearing")
end)

it("test_unequip_clears_the_explicitly_passed_role_not_the_panels_open_role", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(5))
  local s = _make_state()
  skin_panel.open(s, 1) -- panel.role_id stays 1
  skin_panel.unlock(s, 2, "buy", 1)
  skin_panel.equip(s, 2, 1)
  luassert.truthy(s.ui.skin_panel.selected_by_role["2"] == "skin_1", "role 2 should be equipped")
  skin_panel.handle_action(s, "unequip", 2)
  luassert.is_nil(s.ui.skin_panel.selected_by_role["2"],
    "unequip must act on the passed role id (role_id or panel.role_id), not panel.role_id")
end)

-- archive persistence
it("test_purchase_unlock_marks_ownership_and_persists_the_auto_equipped_skin", function()
  skin_panel.configure_catalog_for_tests(_make_rich_catalog())
  local archive = _make_fake_archive()
  skin_panel.configure_archive(archive)
  local s = _make_paid_state()
  skin_panel.open(s, 1)
  _with_patches({
    { target = paid_purchase_port, key = "start", value = function(_, _, entry)
      entry.on_purchase()
      return true
    end },
  }, function()
    skin_panel.equip(s, 1, 1) -- slot 1 is a locked purchase skin -> initiates purchase
  end)
  luassert.truthy(archive.store.owned["1"][5001] == true, "purchase should persist ownership")
  luassert.truthy(archive.store.equipped["1"] == 5001, "purchase auto-equip should persist equipped product")
end)

it("test_does_not_persist_gift_unlocked_ownership", function()
  skin_panel.configure_catalog_for_tests(_make_rich_catalog())
  local archive = _make_fake_archive()
  skin_panel.configure_archive(archive)
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.unlock(s, 1, "gift", 3)
  luassert.truthy(archive.store.owned["1"] == nil or archive.store.owned["1"][5003] == nil,
    "gift unlock must not write to the archive")
end)

it("test_unequip_clears_the_persisted_equipped_product", function()
  skin_panel.configure_catalog_for_tests(_make_rich_catalog())
  local archive = _make_fake_archive()
  skin_panel.configure_archive(archive)
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.unlock(s, 1, "purchase", 1)
  skin_panel.equip(s, 1, 1)
  luassert.truthy(archive.store.equipped["1"] == 5001, "equip should persist equipped product")
  skin_panel.handle_action(s, "unequip", 1)
  luassert.is_nil(archive.store.equipped["1"], "unequip should clear the persisted equipped product")
end)

-- open 从档案重建持有集 + 仅对已持有的存档皮肤自动装备,由文件末尾
-- 迁自 property 车道的「skin archive read-back properties」随机组合覆盖(#237)。
-- 此处仅保留「自动装备后保持开启」这一 property 未断言的独有观察。
it("test_open_auto_equips_the_persisted_skin_fires_the_equip_callback_and_stays_open", function()
  skin_panel.configure_catalog_for_tests(_make_rich_catalog())
  local archive = _make_fake_archive()
  archive.store.owned["1"] = { [5001] = true }
  archive.store.equipped["1"] = 5001
  local equipped_product
  skin_panel.configure_equip(function(_, skin)
    equipped_product = skin and skin.product_id
    return true
  end)
  skin_panel.configure_archive(archive)
  local s = _make_state()
  skin_panel.open(s, 1)
  luassert.truthy(s.ui.skin_panel.selected_by_role["1"] == 5001, "open should auto-equip the persisted skin")
  luassert.truthy(equipped_product == 5001, "auto-equip should fire the equip callback with the product id")
  luassert.truthy(s.ui.skin_panel.open == true, "panel must stay open after seeding auto-equip")
end)

it("test_no_archive_configured_leaves_persistence_paths_inert", function()
  skin_panel.configure_catalog_for_tests(_make_rich_catalog())
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.unlock(s, 1, "purchase", 1)
  skin_panel.equip(s, 1, 1)
  skin_panel.handle_action(s, "unequip", 1)
  luassert.is_nil(s.ui.skin_panel.selected_by_role["1"],
    "without an archive the equip/unequip flow behaves as before")
end)

-- configure_archive only asserts nil-or-table, so a partial port (a table
-- missing some methods) is a contract-allowed input. Seeding must degrade
-- gracefully rather than call a nil method.
it("test_open_skips_ownership_seeding_when_the_archive_lacks_load_owned", function()
  skin_panel.configure_catalog_for_tests(_make_rich_catalog())
  skin_panel.configure_archive({}) -- partial port: no load_owned
  local s = _make_state()
  skin_panel.open(s, 1) -- must not call a nil load_owned
  local owned = s.ui.skin_panel.owned_by_role["1"]
  luassert.truthy(owned == nil or next(owned) == nil,
    "a missing load_owned must leave ownership unseeded, not error")
end)

it("test_open_skips_equipped_restore_when_the_archive_lacks_load_equipped", function()
  skin_panel.configure_catalog_for_tests(_make_rich_catalog())
  skin_panel.configure_archive({
    load_owned = function() return { 5001 } end,
    -- no load_equipped
  })
  local s = _make_state()
  skin_panel.open(s, 1) -- must not call a nil load_equipped
  luassert.truthy(s.ui.skin_panel.owned_by_role["1"][5001] == true,
    "ownership is still seeded when only load_equipped is absent")
  luassert.is_nil(s.ui.skin_panel.selected_by_role["1"],
    "a missing load_equipped must skip equipped restore, not error")
end)

-- handle_action
it("test_dispatches_buy_gift_close_equip_integer_action_forms", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(3))
  local s = _make_state()
  skin_panel.open(s, 1)

  skin_panel.handle_action(s, { type = "buy", slot_index = 2 }, 1)
  luassert.truthy(s.ui.skin_panel.owned_by_role["1"]["skin_2"] == true, "buy action should own skin_2")

  skin_panel.handle_action(s, { type = "gift", slot_index = 1 }, 1)
  luassert.truthy(s.ui.skin_panel.owned_by_role["1"]["skin_1"] == true, "gift action should own skin")

  skin_panel.handle_action(s, { type = "equip", slot_index = 2 }, 1)
  luassert.truthy(s.ui.skin_panel.selected_by_role["1"] == "skin_2", "equip action should select skin")

  skin_panel.open(s, 1)
  skin_panel.handle_action(s, 1, 1)
  luassert.truthy(s.ui.skin_panel.selected_by_role["1"] == "skin_1", "integer action should equip slot")

  skin_panel.open(s, 1)
  skin_panel.handle_action(s, "close", 1)
  luassert.truthy(s.ui.skin_panel.open == false, "close action should close panel")
end)

it("test_activate_slot_action_toggles_equip_and_unequip_via_handle_action", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(3))
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.unlock(s, 1, "buy", 2)
  skin_panel.handle_action(s, { type = "activate_slot", slot_index = 2 }, 1)
  luassert.truthy(s.ui.skin_panel.selected_by_role["1"] == "skin_2",
    "activate_slot should equip owned unequipped skin")
  skin_panel.handle_action(s, { type = "activate_slot", slot_index = 2 }, 1)
  luassert.is_nil(s.ui.skin_panel.selected_by_role["1"],
    "activate_slot on equipped slot should unequip")
end)

it("test_apply_transaction_result_honors_opts_and_returns_result_panel", function()
  local s = _make_state()
  local tips = {}

  _with_patches({
    { target = tip_queue, key = "enqueue", value = function(tip)
      tips[#tips + 1] = tip
    end },
  }, function()
    skin_panel.open(s, 1)
    local result = { panel = s.ui.skin_panel, action = "external", notification = "外部结果" }
    local panel = skin_panel.apply_transaction_result(s, result, { silent = true })
    luassert.truthy(panel == s.ui.skin_panel, "apply_transaction_result should return the result panel")
    local tip_count = #tips
    skin_panel.apply_transaction_result(s, result)
    luassert.truthy(#tips == tip_count + 1, "default opts should enqueue the result notification")
    luassert.truthy(tips[#tips].dedupe_key == "skin_panel:external:1:",
      "external result notification key should follow the panel key scheme")
  end)
end)

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
  local owned_state, owned_calls = _make_render_state({
    owned_by_role = { ["1"] = { [5001] = true } },
  })
  skin_panel_view.refresh_slots(owned_state, catalog)
  local owned_text = _find_call(owned_calls, "set_button", skin_nodes.action_buttons[1])
  luassert.truthy(owned_text == "穿上", "owned button should show 穿上, got: " .. tostring(owned_text))
  luassert.truthy(_find_call(owned_calls, "set_touch_enabled", skin_nodes.action_buttons[1]) == true,
    "owned button should be touch-enabled")

  local equipped_state, equipped_calls = _make_render_state({
    owned_by_role = { ["1"] = { [5001] = true } },
    selected_by_role = { ["1"] = 5001 },
  })
  skin_panel_view.refresh_slots(equipped_state, catalog)
  local equipped_text = _find_call(equipped_calls, "set_button", skin_nodes.action_buttons[1])
  luassert.truthy(equipped_text == "脱下", "equipped button should show 脱下, got: " .. tostring(equipped_text))
  luassert.truthy(_find_call(equipped_calls, "set_touch_enabled", skin_nodes.action_buttons[1]) == true,
    "equipped button should be touch-enabled")
end)

it("test_card_outline_containers_follow_slot_occupancy_regardless_of_equip_state", function()
  local catalog = _make_rich_catalog()
  local state, calls = _make_render_state({
    owned_by_role = { ["1"] = { [5002] = true } },
    selected_by_role = { ["1"] = 5002 },
  })
  skin_panel_view.refresh_slots(state, catalog)
  for slot = 1, 3 do
    local vis = _find_call(calls, "set_visible", skin_nodes.card_outlines[slot])
    luassert.truthy(vis == true, "occupied outline container " .. slot .. " should be visible")
  end
  for slot = 4, #skin_nodes.card_outlines do
    local vis = _find_call(calls, "set_visible", skin_nodes.card_outlines[slot])
    luassert.truthy(vis == false, "empty outline container " .. slot .. " should be hidden")
  end
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
  -- #178 点背景关闭:背景可点,"关闭"文字与提示文字关闭触摸;关闭按钮与卡牌照常可点。
  local state, calls = _make_render_state()
  skin_panel_view.refresh_slots(state, _make_catalog(3))
  _assert_eq(_find_call(calls, "set_touch_enabled", "皮肤商店-活动背景"), true,
    "skin shop background must accept touch")
  _assert_eq(_find_call(calls, "set_touch_enabled", "皮肤_关闭皮肤文本"), false,
    "close text must not swallow touch")
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

it("test_price_icon_hides_for_owned_equipped_skins_but_stays_for_unowned_neighbors", function()
  local catalog = _make_rich_catalog()
  local owned_state, owned_calls = _make_render_state({
    owned_by_role = { ["1"] = { [5001] = true } },
  })
  skin_panel_view.refresh_slots(owned_state, catalog)
  luassert.truthy(_find_call(owned_calls, "set_visible", skin_nodes.price_icons[1]) == false,
    "owned purchase skin should hide its price icon")
  luassert.truthy(_find_call(owned_calls, "set_visible", skin_nodes.price_icons[2]) == true,
    "an unowned purchase skin should still show its price icon")

  local equipped_state, equipped_calls = _make_render_state({
    owned_by_role = { ["1"] = { [5001] = true } },
    selected_by_role = { ["1"] = 5001 },
  })
  skin_panel_view.refresh_slots(equipped_state, catalog)
  luassert.truthy(_find_call(equipped_calls, "set_visible", skin_nodes.price_icons[1]) == false,
    "equipped purchase skin should hide its price icon")
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

-- purchase flow
it("test_equip_on_locked_purchase_skin_calls_purchase_handler", function()
  local catalog = _make_rich_catalog()
  skin_panel.configure_catalog_for_tests(catalog)
  local purchase_calls = {}
  local s = _make_paid_state()
  skin_panel.open(s, 1)
  _with_patches({
    { target = paid_purchase_port, key = "start", value = function(_, player, entry)
      purchase_calls[#purchase_calls + 1] = { role_id = player.id, product_id = entry.product_id }
      return true
    end },
  }, function()
    skin_panel.equip(s, 1, 1)
  end)
  luassert.truthy(#purchase_calls == 1, "should call purchase handler once, got " .. #purchase_calls)
  luassert.truthy(purchase_calls[1].product_id == 5001, "should pass correct product_id")
  luassert.truthy(purchase_calls[1].role_id == 1, "should pass correct role_id")
end)

it("test_equip_on_locked_gift_skin_does_not_call_purchase_handler", function()
  local catalog = _make_rich_catalog()
  skin_panel.configure_catalog_for_tests(catalog)
  local purchase_calls = {}
  local s = _make_paid_state()
  skin_panel.open(s, 1)
  _with_patches({
    { target = paid_purchase_port, key = "start", value = function(_, player, entry)
      purchase_calls[#purchase_calls + 1] = { role_id = player.id, product_id = entry.product_id }
      return true
    end },
  }, function()
    skin_panel.equip(s, 1, 3)
  end)
  luassert.truthy(#purchase_calls == 0, "gift skin should not trigger purchase")
end)

it("test_purchase_success_unlocks_and_selects_skin", function()
  local catalog = _make_rich_catalog()
  skin_panel.configure_catalog_for_tests(catalog)
  local captured_entry = nil
  local s = _make_paid_state()
  skin_panel.open(s, 1)
  _with_patches({
    { target = paid_purchase_port, key = "start", value = function(_, _, entry)
      captured_entry = entry
      return true
    end },
  }, function()
    skin_panel.equip(s, 1, 1)
  end)
  luassert.is_not_nil(captured_entry, "locked equip should reach the paid gateway")
  captured_entry.on_purchase()
  local panel = s.ui.skin_panel
  luassert.truthy(panel.owned_by_role["1"][5001] == true, "skin should be owned after purchase success")
  luassert.truthy(panel.selected_by_role["1"] == 5001, "skin should be selected after purchase success")
end)

it("test_asynchronous_purchase_success_refreshes_the_slot_view", function()
  local catalog = _make_rich_catalog()
  skin_panel.configure_catalog_for_tests(catalog)
  local captured_entry = nil
  local s, calls = _make_render_state()
  s.game = _make_paid_state().game
  s.runtime_asset_context = { refs = { images = {} } }

  _with_patches({
    { target = paid_purchase_port, key = "start", value = function(_, _, entry)
      captured_entry = entry
      return true
    end },
  }, function()
    skin_panel.open(s, 1)
    skin_panel.equip(s, 1, 1)
    luassert.is_not_nil(captured_entry, "locked equip should reach the paid gateway")
    luassert.truthy(_find_call(calls, "set_button", skin_nodes.action_buttons[1]) == "198",
      "locked purchase should render its price before the asynchronous callback")

    captured_entry.on_purchase()

    luassert.truthy(_find_call(calls, "set_button", skin_nodes.action_buttons[1]) == "脱下",
      "asynchronous purchase success must refresh the slot to the equipped state")
    luassert.truthy(_find_call(calls, "set_visible", skin_nodes.price_icons[1]) == false,
      "asynchronous purchase success must hide the equipped slot price icon")
  end)
end)

it("test_purchase_success_keeps_the_originally_purchased_skin_after_page_changes", function()
  local catalog = {}
  for index = 1, 7 do
    catalog[index] = {
      product_id = 7000 + index,
      name = "skin" .. tostring(index),
      unlock = "purchase",
      currency = "beans",
      price = 10,
    }
  end
  skin_panel.configure_catalog_for_tests(catalog)
  local captured_entry = nil

  local s = _make_paid_state()
  skin_panel.open(s, 1)
  _with_patches({
    { target = paid_purchase_port, key = "start", value = function(_, _, entry)
      captured_entry = entry
      return true
    end },
  }, function()
    skin_panel.equip(s, 1, 1)
  end)
  luassert.truthy(captured_entry ~= nil and captured_entry.product_id == 7001,
    "purchase should start for page 1 slot 1")
  skin_panel.handle_action(s, "next", 1)
  luassert.truthy(s.ui.skin_panel.page_index == 2, "precondition: panel moved to page 2 before payment callback")

  captured_entry.on_purchase()

  local panel = s.ui.skin_panel
  luassert.truthy(panel.owned_by_role["1"][7001] == true, "success should own the purchased skin")
  luassert.truthy(panel.selected_by_role["1"] == 7001, "success should equip the purchased skin")
  luassert.truthy(panel.owned_by_role["1"][7007] ~= true, "success must not own page 2 slot 1")
end)

it("test_equip_on_owned_skin_still_equips_normally_without_purchase_handler", function()
  local catalog = _make_rich_catalog()
  skin_panel.configure_catalog_for_tests(catalog)
  local purchase_calls = {}
  local s = _make_paid_state()
  skin_panel.open(s, 1)
  skin_panel.unlock(s, 1, "buy", 1)
  _with_patches({
    { target = paid_purchase_port, key = "start", value = function()
      purchase_calls[#purchase_calls + 1] = true
      return true
    end },
  }, function()
    skin_panel.equip(s, 1, 1)
  end)
  luassert.truthy(#purchase_calls == 0, "owned skin should not trigger purchase")
  luassert.truthy(s.ui.skin_panel.selected_by_role["1"] == 5001, "should equip normally")
end)

it("test_leaves_selection_unchanged_when_the_paid_gateway_errors", function()
  skin_panel.configure_catalog_for_tests(_make_rich_catalog())
  local s = _make_paid_state()
  skin_panel.open(s, 1)

  _with_patches({
    { target = paid_purchase_port, key = "start", value = function()
      error("paid gateway unavailable")
    end },
  }, function()
    skin_panel.equip(s, 1, 1)
  end)

  luassert.is_nil(s.ui.skin_panel.selected_by_role["1"], "failed purchase must not equip skin")
end)

-- equip callback outcomes
it("test_last_equip_ok_reflects_callback_outcome_true_only_on_true_return", function()
  local cases = {
    { label = "callback returning true", callback = function() return true end, expect = true },
    { label = "callback returning false", callback = function() return false end, expect = false },
    { label = "callback returning nil", callback = function() return nil end, expect = false },
    { label = "callback that errors", callback = function() error("boom") end, expect = false },
    { label = "no callback configured", callback = nil, expect = false },
  }

  for _, case in ipairs(cases) do
    skin_panel.reset_for_tests()
    skin_panel.configure_catalog_for_tests(_make_catalog(3))
    if case.callback then
      skin_panel.configure_equip(case.callback)
    end
    local s = _make_state()
    skin_panel.open(s, 1)
    skin_panel.unlock(s, 1, "buy", 1)
    skin_panel.equip(s, 1, 1)
    luassert.truthy(s.ui.skin_panel.last_equip_ok_by_role["1"] == case.expect,
      case.label .. " should set last_equip_ok to " .. tostring(case.expect))
  end
end)

-- equip branches
-- Each branch in skin_panel.equip lands here once for explicit
-- branch-coverage attribution; some paths are also exercised in
-- other describes (purchase flow, equip callback outcomes).
it("test_branch_1_out_of_range_slots_beyond_catalog_or_page_size_are_inert", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(3))
  local s = _make_state()
  skin_panel.open(s, 1)
  for _, slot in ipairs({ 5, 99 }) do
    local panel = skin_panel.equip(s, 1, slot)
    luassert.truthy(panel == s.ui.skin_panel, "equip on slot " .. slot .. " should still return the panel state")
    luassert.is_nil(s.ui.skin_panel.selected_by_role["1"],
      "slot-" .. slot .. " equip must not touch selection")
    luassert.is_nil(s.ui.skin_panel.last_equip_ok_by_role,
      "out-of-range equip must short-circuit before last_equip_ok bookkeeping")
  end
end)

it("test_branch_2_not_owned_purchase_skin_without_callback_leaves_selection_nil", function()
  skin_panel.configure_catalog_for_tests(_make_rich_catalog())
  -- skin slot 1 (5001) is unlock=purchase, no purchase_callback configured
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.equip(s, 1, 1)
  luassert.is_nil(s.ui.skin_panel.selected_by_role["1"],
    "without purchase callback, not-owned purchase skin equip leaves selection nil")
  luassert.truthy(s.ui.skin_panel.owned_by_role["1"] == nil or
    s.ui.skin_panel.owned_by_role["1"][5001] ~= true,
    "without purchase callback, skin should not become owned")
end)

it("test_branch_3_not_owned_non_purchase_gift_skin_notifies_and_returns", function()
  skin_panel.configure_catalog_for_tests(_make_rich_catalog())
  -- skin slot 3 (5003) is unlock=gift
  local s = _make_state()
  skin_panel.open(s, 1)
  local panel = skin_panel.equip(s, 1, 3)
  luassert.truthy(panel == s.ui.skin_panel, "not-owned gift skin should return the panel state")
  luassert.is_nil(s.ui.skin_panel.selected_by_role["1"],
    "equip on not-owned gift skin must not select it")
  luassert.truthy(s.ui.skin_panel.owned_by_role["1"] == nil or
    s.ui.skin_panel.owned_by_role["1"][5003] ~= true,
    "equip on not-owned gift skin must not mark it owned")
end)

it("test_branch_4_owned_skin_success_sets_selection_and_last_equip_ok", function()
  skin_panel.configure_catalog_for_tests(_make_rich_catalog())
  skin_panel.configure_equip(function() return true end)
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.unlock(s, 1, "buy", 2)
  skin_panel.equip(s, 1, 2)
  luassert.truthy(s.ui.skin_panel.selected_by_role["1"] == 5002,
    "owned equip success must set selected_by_role to product_id")
  luassert.truthy(s.ui.skin_panel.last_equip_ok_by_role["1"] == true,
    "owned equip success must record callback outcome in last_equip_ok_by_role")
  luassert.truthy(s.ui.skin_panel.open == false,
    "owned equip success must close the skin panel")
end)

it("test_equip_with_role_id_nil_falls_back_to_panel_role_id", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(3))
  local s = _make_state()
  skin_panel.open(s, 7)  -- panel.role_id = 7
  skin_panel.unlock(s, 7, "buy", 1)
  skin_panel.equip(s, nil, 1)  -- role_id=nil → should use panel.role_id (7)
  luassert.truthy(s.ui.skin_panel.selected_by_role["7"] == "skin_1",
    "equip with role_id=nil should use panel.role_id (7) for the key")
end)

it("test_unlock_with_nil_skin_slot_out_of_range_is_no_op", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(3))
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.unlock(s, 1, "buy", 99)
  luassert.is_nil(s.ui.skin_panel.owned_by_role["1"],
    "unlock on out-of-range slot must not initialize owned_by_role bucket")
end)

-- equip refreshes button state
it("test_coord_equip_calls_refresh_slots_to_update_buttons", function()
  local catalog = _make_rich_catalog()
  skin_panel.configure_catalog_for_tests(catalog)
  local s, calls = _make_render_state()
  s.runtime_asset_context = { refs = { images = {} } }

  skin_panel.open(s, 1)
  skin_panel.unlock(s, 1, "buy", 1)
  luassert.truthy(_find_call(calls, "set_button", skin_nodes.action_buttons[1]) == "穿上",
    "owned skin should render its equip action before selection")

  skin_panel.equip(s, 1, 1)

  luassert.truthy(_find_call(calls, "set_button", skin_nodes.action_buttons[1]) == "脱下",
    "equip should refresh the slot button to the equipped state")
  luassert.truthy(s.ui.skin_panel.selected_by_role["1"] == 5001,
    "equip should publish the selected skin in panel state")
end)

-- T16 mutation-pinning addendum.
it("test_handle_action_with_unknown_action_returns_panel_with_defaults_l21_l22_l236", function()
  local s = _make_state() -- fresh, no skin_panel yet
  local result = skin_panel.handle_action(s, "unknown_xyz_no_handler", 1)
  luassert.truthy(type(result) == "table",
    "L236 _ensure_state mutation to nil would return nil; got " .. type(result))
  luassert.truthy(result.open == false,
    "L21 default open=false; mutation 'true' would yield true. Got " .. tostring(result.open))
  luassert.truthy(result.page_index == 1,
    "L22 default page_index=1; mutation '0' would yield 0. Got " .. tostring(result.page_index))
end)

it("test_equip_with_non_integer_slot_defaults_to_slot_1_l34_or_1", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(3))
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.unlock(s, 1, "buy", 1) -- own skin_1
  skin_panel.equip(s, 1, "not_an_integer")
  luassert.truthy(s.ui.skin_panel.selected_by_role["1"] == "skin_1",
    "L34 default slot=1 must pick skin_1; mutation 0 yields nil catalog lookup. " ..
    "Got: " .. tostring(s.ui.skin_panel.selected_by_role["1"]))
end)

it("test_equip_on_page_2_uses_page_1_page_size_arithmetic_l35_not", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(12)) -- 2 pages of 6
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.handle_action(s, "next", 1) -- advance to page 2
  luassert.truthy(s.ui.skin_panel.page_index == 2, "precondition: now on page 2")
  skin_panel.unlock(s, 1, "buy", 1) -- slot 1 on page 2 = catalog index 7
  skin_panel.equip(s, 1, 1)
  luassert.truthy(s.ui.skin_panel.selected_by_role["1"] == "skin_7",
    "L35 multiplication must yield slot 7 (page=2 slot=1); division gives ~1.17 → wrong skin. " ..
    "Got: " .. tostring(s.ui.skin_panel.selected_by_role["1"]))
end)

it("test_buy_action_with_only_type_field_defaults_slot_to_1_l61_last_1_default", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(3))
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.handle_action(s, { type = "buy" }, 1) -- no slot_index/index/slot
  luassert.truthy(s.ui.skin_panel.owned_by_role["1"]["skin_1"] == true,
    "L61 default '1' must own skin_1; mutation 0 yields out-of-range no-op")
end)

it("test_buy_action_prefers_slot_index_over_index_l61_first_or", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(3))
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.handle_action(s, { type = "buy", slot_index = 2, index = 99 }, 1)
  luassert.truthy(s.ui.skin_panel.owned_by_role["1"]["skin_2"] == true,
    "L61 first 'or' must short-circuit to slot_index=2; mutation 'and' yields slot=99 (out of range, no own)")
  luassert.is_nil(s.ui.skin_panel.owned_by_role["1"]["skin_99"],
    "skin_99 must not exist; sanity check")
end)

it("test_buy_action_falls_back_to_index_when_slot_index_missing_l61_second_or", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(3))
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.handle_action(s, { type = "buy", index = 2, slot = 99 }, 1)
  luassert.truthy(s.ui.skin_panel.owned_by_role["1"]["skin_2"] == true,
    "L61 second 'or' must fall back to index=2 when slot_index nil; " ..
    "mutation 'and' yields slot=99 (out of range)")
end)

it("test_buy_action_falls_back_to_slot_when_slot_index_index_missing_l61_third_or", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(3))
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.handle_action(s, { type = "buy", slot = 2 }, 1)
  -- Original: nil or nil or 2 or 1 → 2. Mutated 3rd 'or→and': nil or nil or 2 and 1 → 1.
  luassert.truthy(s.ui.skin_panel.owned_by_role["1"]["skin_2"] == true,
    "L61 third 'or' must yield slot=2 from .slot field; mutation 'and' yields 1 (2 and 1 = 1)")
end)

it("test_string_buy_action_non_table_defaults_slot_to_1_l63", function()
  skin_panel.configure_catalog_for_tests(_make_catalog(3))
  local s = _make_state()
  skin_panel.open(s, 1)
  skin_panel.handle_action(s, "buy", 1)
  luassert.truthy(s.ui.skin_panel.owned_by_role["1"]["skin_1"] == true,
    "L63 non-table action must default slot to 1; mutation 0 yields no ownership")
end)

it("test_configure_equip_nil_does_not_throw_l84_guards_the_assert", function()
  local ok, err = pcall(function() skin_panel.configure_equip(nil) end)
  luassert.truthy(ok,
    "L84 '~=' must skip assert when callback is nil. Mutation '==' makes assert fire on nil. Err: " ..
    tostring(err))
end)

-- ===== 迁自 test/property/test_skin_archive.lua（#190, 测试极简化决策：property 车道退场，性质并入 behavior）=====
do

  local property = require("test.support.property")

  -- Round-trip / read-back property for the skin purchase archive: for an arbitrary
  -- persisted state (a subset of products owned, plus an optionally-equipped one),
  -- opening a fresh panel must reconstruct ownership exactly and auto-equip the
  -- archived skin — firing the equip callback so the host restores the model — but
  -- only when that skin is actually owned. The example-based behaviour spec pins a
  -- few representative cases; this exercises the owned-set seeding and the auto-equip
  -- guards across random ownership/equipped combinations.

  local PRODUCTS = { 5001, 5002, 5003, 5004, 5005 }

  local function _catalog()
    local catalog = {}
    for index, product_id in ipairs(PRODUCTS) do
      catalog[index] = {
        product_id = product_id,
        name = "skin " .. tostring(product_id),
        unlock = "purchase",
        currency = "金豆",
        price = 100 + index,
      }
    end
    return catalog
  end

  -- Read-only archive port: serves the seeded owned list / equipped product back;
  -- the write hooks are inert no-ops since this property only drives the read path.
  local function _archive(owned_list, equipped)
    return {
      load_owned = function(_)
        return owned_list
      end,
      load_equipped = function(_)
        return equipped
      end,
      mark_owned = function() end,
      save_equipped = function() end,
    }
  end

  local function _gen(rng)
    local owned = {}
    for _, product_id in ipairs(PRODUCTS) do
      if rng:bool() then
        owned[#owned + 1] = product_id
      end
    end
    -- Cover all equipped branches: owned, in-catalog-but-unowned, and nil.
    local equipped = nil
    local roll = rng:int(1, 3)
    if roll == 1 and #owned > 0 then
      equipped = owned[rng:int(1, #owned)]
    elseif roll == 2 then
      equipped = PRODUCTS[rng:int(1, #PRODUCTS)]
    end
    return { owned = owned, equipped = equipped }
  end

  local function _owned_set(list)
    local set = {}
    for _, product_id in ipairs(list) do
      set[product_id] = true
    end
    return set
  end

  describe("TestSkinPanelArchiveReadBackProperties", function()
  after_each(function()
    skin_panel.reset_for_tests()
  end)

  it("test_open_reconstructs_ownership_and_auto_equips_only_an_owned_archived_skin", function()
    property.for_all(_gen, function(case)
      skin_panel.reset_for_tests()
      skin_panel.configure_catalog_for_tests(_catalog())
      local equip_calls = {}
      skin_panel.configure_equip(function(_, skin)
        equip_calls[#equip_calls + 1] = skin.product_id
        return true
      end)
      skin_panel.configure_archive(_archive(case.owned, case.equipped))

      local panel = skin_panel.open({ ui = {} }, 1)
      local owned_map = panel.owned_by_role["1"] or {}
      local owned_set = _owned_set(case.owned)

      for _, product_id in ipairs(PRODUCTS) do
        luassert.truthy((owned_map[product_id] == true) == (owned_set[product_id] == true),
          "ownership of " .. tostring(product_id) .. " must match the archive")
      end

      local should_restore = case.equipped ~= nil and owned_set[case.equipped] == true
      if should_restore then
        luassert.truthy(panel.selected_by_role["1"] == case.equipped,
          "an owned archived equipped skin must be auto-equipped")
        luassert.truthy(#equip_calls == 1 and equip_calls[1] == case.equipped,
          "auto-equip must fire the equip callback once with the archived skin (model restore)")
      else
        luassert.is_nil(panel.selected_by_role["1"],
          "no auto-equip when the archived equipped skin is nil or unowned")
        luassert.truthy(#equip_calls == 0,
          "no equip callback fires when there is nothing to restore")
      end
    end)
  end)
  end)
end


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

it("test_notification_payloads_pin_source_blocking_and_unknown_action_key", function()
  -- 杀 L59 blocks_inter_turn false->true、L60 source->nil 与 L85 "unknown"->nil:
  -- 通知载荷契约必须保持。
  local s = _make_state()
  local tips = {}
  local result = { panel = s.ui.skin_panel, notification = "无操作类型的结果" }
  _with_patches({
    { target = tip_queue, key = "enqueue", value = function(tip)
      tips[#tips + 1] = tip
    end },
  }, function()
    skin_panel.apply_transaction_result(s, result)
  end)
  _assert_eq(tips[1].blocks_inter_turn, false, "skin panel notifications must not block inter-turn")
  _assert_eq(tips[1].source, "ui.skin_panel", "notification source should be pinned")
  luassert.truthy(string.find(tips[1].dedupe_key, "unknown", 1, true) ~= nil,
    "result without action should use the unknown key suffix")
end)

it("test_canvas_switches_pass_state_ui_and_resolved_role", function()
  -- 杀 L102/L114 的 state and state.ui -> or 与 L114 result.role_id or effective_role -> and:
  -- switch_by_role_id 必须收 state.ui(不是 state 本身)与显式 role_id。
  local s = _make_state()
  local switches = {}
  _with_patches({
    { target = canvas, key = "switch_by_role_id", value = function(ui, name, role_id)
      switches[#switches + 1] = { ui, name, role_id }
    end },
    { target = transaction, key = "handle_skin_transaction", value = function()
      return {
        accepted = true,
        action = "open",
        panel = s.ui.skin_panel,
        role_id = "R1",
      }
    end },
  }, function()
    skin_panel.open(s, 1)
  end)
  luassert.truthy(#switches >= 1, "open result should switch the canvas")
  _assert_eq(switches[1][1], s.ui, "canvas switch should receive state.ui, not the state")
  _assert_eq(switches[1][2], skin_nodes.canvas, "open should switch to the skin canvas")

  switches = {}
  _with_patches({
    { target = canvas, key = "switch_by_role_id", value = function(ui, name, role_id)
      switches[#switches + 1] = { ui, name, role_id }
    end },
    { target = transaction, key = "handle_skin_transaction", value = function()
      return {
        accepted = true,
        action = "close",
        panel = s.ui.skin_panel,
        panel_should_close = true,
        role_id = "R1",
      }
    end },
  }, function()
    skin_panel.close(s, 2)
  end)
  luassert.truthy(#switches >= 1, "close result should switch the canvas")
  _assert_eq(switches[1][1], s.ui, "close canvas switch should receive state.ui")
  _assert_eq(switches[1][3], "R1", "close should switch to the result role id")
end)

it("test_apply_transaction_result_silent_suppresses_notification", function()
  -- 杀 L133 opts or {} -> and:opts.silent 必须生效,不能丢成空表。
  local s = _make_state()
  local tips = 0
  _with_patches({
    { target = tip_queue, key = "enqueue", value = function()
      tips = tips + 1
    end },
  }, function()
    local result = { panel = s.ui.skin_panel, notification = "通知" }
    skin_panel.apply_transaction_result(s, result, { silent = true })
    _assert_eq(tips, 0, "silent apply must suppress the notification")
    skin_panel.apply_transaction_result(s, result)
    _assert_eq(tips, 1, "non-silent apply should notify")
  end)
end)

it("test_page_actions_are_silent", function()
  -- 杀 L196 _page 的 silent true->false:翻页请求不得弹出通知。
  local s = _make_state()
  local tips = 0
  _with_patches({
    { target = transaction, key = "handle_skin_transaction", value = function()
      return { notification = "翻页通知", panel = s.ui.skin_panel }
    end },
    { target = tip_queue, key = "enqueue", value = function()
      tips = tips + 1
    end },
  }, function()
    skin_panel.handle_action(s, "next", 1)
    skin_panel.handle_action(s, "prev", 1)
  end)
  _assert_eq(tips, 0, "page actions must stay silent")
end)

it("test_buy_gift_and_page_actions_pass_request_params", function()
  -- 杀 L201 source "buy"->nil、L202 source "gift"->nil 与 slot_index() -> nil、
  -- L212 "page_prev"->nil:handler 表必须透传请求参数给 transaction。
  local s = _make_state()
  skin_panel.configure_catalog_for_tests(_make_catalog(2))
  skin_panel.open(s, 1)
  local requests = {}
  _with_patches({
    { target = transaction, key = "handle_skin_transaction", value = function(_, _, request)
      requests[#requests + 1] = request
      return { panel = s.ui.skin_panel }
    end },
  }, function()
    skin_panel.handle_action(s, { type = "buy", slot_index = 2 }, 1)
    skin_panel.handle_action(s, { type = "gift", slot_index = 1 }, 1)
    skin_panel.handle_action(s, { type = "prev" }, 1)
  end)
  _assert_eq(requests[1].source, "buy", "buy action should pass the buy source")
  _assert_eq(requests[1].slot_index, 2, "buy action should pass the slot index")
  _assert_eq(requests[2].source, "gift", "gift action should pass the gift source")
  _assert_eq(requests[2].slot_index, 1, "gift action should pass the slot index")
  _assert_eq(requests[3].type, "page_prev", "prev action should pass the page_prev type")
end)


end)
