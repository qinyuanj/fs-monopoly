require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
local support = require("test.support.shared_support")
local _with_patches = support.with_patches
local _build_role_with_events = support.build_role_with_events
local _has_event = support.has_event
local item_atlas = require("src.ui.screens.item_atlas")
local item_atlas_view = require("src.ui.render.widgets.item_atlas")
local item_atlas_nodes = require("src.ui.schema.item_atlas")
local runtime_ports = require("src.foundation.ports.runtime_ports")

local function _make_state()
  return { ui = {} }
end

local function _make_catalog(n)
  local t = {}
  for i = 1, n do
    t[i] = { id = "item_" .. i, name = "道具" .. i, description = "描述" .. i }
  end
  return t
end

local function _make_render_state()
  local calls = {}
  local state = {
    ui = {
      set_visible = function(_, name, visible)
        calls[#calls + 1] = { "set_visible", name, visible }
      end,
      -- #544 退役钉:global 广播变体已拆除,单独打标记录;
      -- 放大/隐藏用例断言零调用(旁观者泄漏即由广播变体造成)。
      set_visible_global = function(_, name, visible)
        calls[#calls + 1] = { "set_visible_global", name, visible }
      end,
      set_touch_enabled = function(_, name, enabled)
        calls[#calls + 1] = { "set_touch_enabled", name, enabled }
      end,
      set_touch_enabled_global = function(_, name, enabled)
        calls[#calls + 1] = { "set_touch_enabled_global", name, enabled }
      end,
      set_label = function(_, name, text)
        calls[#calls + 1] = { "set_label", name, text }
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

local function _stub_runtime()
  local textures = {}
  return {
    query_node = function(name) return { name = name } end,
    set_node_texture_keep_size = function(node, key)
      textures[node.name] = key
    end,
    textures = textures,
  }
end
describe("TestItemAtlas", function()
before_each(function()
  item_atlas.reset_for_tests()
  runtime_ports.reset_for_tests()
end)

after_each(function()
  runtime_ports.reset_for_tests()
  -- 拆了共享端口基线必须装回,否则 mutate 车道窄 suite 子集会撞空端口(#217)。
  support.restore_runtime_services()
end)

it("test_marks_atlas_open_after_open", function()
  local s = _make_state()
  local atlas = item_atlas.open(s, 1)
  luassert.truthy(atlas.open == true, "atlas should be open")
end)

it("test_opens_the_atlas_canvas_for_the_active_role", function()
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
    item_atlas.open(s, 1)
  end)

  luassert.truthy(_has_event(events, "显示道具图鉴"), "opening atlas should show atlas canvas")
end)

it("test_open_normalizes_a_nil_page_index_to_page_1", function()
  local s = _make_state()
  s.ui.item_atlas = { open = false, page_index = nil, selected_item_id = "stale" }
  local atlas = item_atlas.open(s, 1)
  luassert.truthy(atlas.page_index == 1, "nil page_index should reopen at page 1")
end)

it("test_open_refreshes_page_even_when_the_owner_role_cannot_be_resolved", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(3))
  local s, calls = _make_render_state()
  s.runtime_asset_context = { refs = { images = {} } }

  _with_patches({
    { target = runtime_ports, key = "resolve_role", value = function()
      return nil
    end },
  }, function()
    item_atlas.open(s, 99)
  end)

  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.card_images[1]) == true,
    "global fallback open should render the first catalog card")
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.card_images[4]) == false,
    "global fallback open should hide the first empty card")
  luassert.truthy(_find_call(calls, "set_touch_enabled", item_atlas_nodes.card_images[4]) == false,
    "global fallback open should disable the first empty card")
end)

it("test_owner_refresh_uses_the_state_presentation_runtime", function()
  local role = { id = 4 }
  local active_role = nil
  local refresh_role = nil
  local s = _make_state()
  s.presentation_runtime = {
    runtime = {
      with_client_role = function(next_role, fn)
        active_role = next_role
        local result = fn()
        active_role = nil
        return result
      end,
    },
  }

  _with_patches({
    { target = runtime_ports, key = "resolve_role", value = function(role_id)
      if role_id == 4 then
        return role
      end
      return nil
    end },
    { target = item_atlas_view, key = "refresh_page", value = function()
      refresh_role = active_role
    end },
    { target = item_atlas_view, key = "hide_enlarged", value = function() end },
  }, function()
    item_atlas.open(s, 4)
  end)

  luassert.truthy(refresh_role == role, "owner refresh should run under the provided presentation runtime")
end)

it("test_open_disables_passthrough_touch_on_the_open_path_itself", function()
  -- #176 review:passthrough 文字(关闭文字/提示文字)的关触摸不得只依赖
  -- refresh_page 内部顺手做;open 是公共接缝,开屏路径自身就必须把它们关掉。
  -- 用不存在的 role_id 走全局 fallback 分支,refresh_page 不执行仍能观测开屏调用。
  local s, calls = _make_render_state()
  _with_patches({
    { target = runtime_ports, key = "resolve_role", value = function()
      return nil
    end },
  }, function()
    item_atlas.open(s, 99)
  end)
  luassert.equal(true, _find_call(calls, "set_touch_enabled", item_atlas_nodes.background),
    "open path must arm background touch for click-background close")
  for _, node_name in ipairs(item_atlas_nodes.passthrough_nodes) do
    luassert.equal(false, _find_call(calls, "set_touch_enabled", node_name),
      "open path must disable passthrough touch for " .. node_name)
  end
end)

it("test_marks_atlas_closed_after_close", function()
  local s = _make_state()
  item_atlas.open(s, 1)
  local atlas = item_atlas.close(s)
  luassert.truthy(atlas.open == false, "atlas should be closed")
end)

it("test_closes_the_atlas_canvas_for_the_active_role", function()
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
    item_atlas.open(s, 1)
    item_atlas.handle_action(s, "close", 1)
  end)

  luassert.truthy(_has_event(events, "隐藏道具图鉴"), "closing atlas should hide atlas canvas")
end)

it("test_configure_catalog_for_tests_replaces_active_catalog", function()
  local cat = _make_catalog(5)
  item_atlas.configure_catalog_for_tests(cat)
  luassert.truthy(#item_atlas.catalog == 5, "catalog size should be 5")
end)

it("test_reset_for_tests_restores_default_catalog_size", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(3))
  item_atlas.reset_for_tests()
  luassert.truthy(#item_atlas.catalog == 19, "default catalog has 19 items")
end)

it("test_select_slot_records_selected_item_id", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(8))
  local s = _make_state()
  item_atlas.open(s, 1)
  item_atlas.handle_action(s, { type = "select", slot_index = 1 }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == "item_1", "slot 1 should select item_1")
end)

it("test_select_slot_5_records_item_5", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(8))
  local s = _make_state()
  item_atlas.open(s, 1)
  item_atlas.handle_action(s, { type = "select", slot_index = 5 }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == "item_5", "slot 5 should select item_5")
end)

it("test_selecting_empty_slot_does_not_set_selected_item_id", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(5))
  local s = _make_state()
  item_atlas.open(s, 1)
  item_atlas.handle_action(s, { type = "select", slot_index = 7 }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == nil, "empty slot should leave selection nil")
end)

it("test_dismiss_action_clears_selected_item_id", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(8))
  local s = _make_state()
  item_atlas.open(s, 1)
  item_atlas.handle_action(s, { type = "select", slot_index = 1 }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == "item_1")
  item_atlas.handle_action(s, "dismiss", 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == nil, "dismiss should clear selection")
end)

it("test_dismiss_action_never_dispatches_anim_done", function()
  -- #543:图鉴放大卡回归纯浏览用途,获得展示不再经过图鉴屏;
  -- dismiss 只收浏览放大卡,不再向回合机派发 action_anim_done。
  local s = _make_state()
  local dispatched = {}
  s.game = {
    turn = {
      action_anim = { seq = 33, kind = "item_gain_popup", player_id = 7 },
    },
    dispatch_action = function(_, action)
      dispatched[#dispatched + 1] = action
    end,
  }

  item_atlas.handle_action(s, "dismiss", 7)
  luassert.truthy(#dispatched == 0, "dismiss must not dispatch action_anim_done")
end)

it("test_dismiss_action_tolerates_state_without_dispatch_action", function()
  local s = _make_state()
  s.game = {
    turn = {
      action_anim = { seq = 33, kind = "item_gain_popup", player_id = 7 },
    },
  }

  item_atlas.handle_action(s, "dismiss", 7)
  luassert.truthy(s.ui.item_atlas ~= nil, "dismiss should leave atlas state valid")
end)

it("test_select_and_reselect_refresh_enlarged_card_visibility", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(8))
  local s, calls = _make_render_state()
  local runtime = _stub_runtime()
  s.runtime_asset_context = { refs = { images = { item_2 = "tex_item_2" } } }
  s.presentation_runtime = { runtime = runtime }

  item_atlas.open(s, 1)
  item_atlas.handle_action(s, { type = "select", slot_index = 2 }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == "item_2",
    "selecting a non-empty slot should record its public selection")
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.enlarged_card) == true,
    "selecting a non-empty slot should show its enlarged card")
  luassert.truthy(runtime.textures[item_atlas_nodes.enlarged_card] == "tex_item_2",
    "selecting item_2 should show the item_2 texture")

  item_atlas.handle_action(s, { type = "select", slot_index = 2 }, 1)
  luassert.is_nil(s.ui.item_atlas.selected_item_id,
    "reselecting the selected item should clear its public selection")
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.enlarged_card) == false,
    "reselecting the selected item should hide the enlarged card")
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.close_hint_label) == false,
    "reselecting the selected item should hide the close hint")
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.close_blank) == false,
    "reselecting the selected item should hide the close layer")
  luassert.truthy(_find_call(calls, "set_touch_enabled", item_atlas_nodes.close_blank) == false,
    "reselecting the selected item should disable the close layer")
end)

it("test_background_click_closes_atlas_but_enlarged_state_backs_out_one_layer", function()
  -- #178 点背景关闭:图鉴背景与"关闭"同一动作;放大态下背景触摸关闭,
  -- 点空白先收起放大卡,收起后背景重新可点。
  item_atlas.configure_catalog_for_tests(_make_catalog(8))
  local s, calls = _make_render_state()
  s.runtime_asset_context = { refs = { images = { item_2 = "tex_item_2" } } }
  s.presentation_runtime = { runtime = _stub_runtime() }

  local intents = {}
  for _, spec in ipairs(item_atlas.build_route_specs(s)) do
    intents[spec.name] = spec.build_intent()
  end
  luassert.same({ type = "item_atlas_action", action = "close" }, intents["图鉴_关闭图鉴"], "close button intent")
  luassert.same(intents["图鉴_关闭图鉴"], intents["图鉴-背景"], "background click must equal close button intent")

  item_atlas.open(s, 1)
  luassert.equal(true, _find_call(calls, "set_touch_enabled", "图鉴-背景"), "background touchable once atlas opens")
  luassert.equal(false, _find_call(calls, "set_touch_enabled", "图鉴_关闭图鉴文本提示"), "hint text passes touch through")
  luassert.equal(true, _find_call(calls, "set_touch_enabled", item_atlas_nodes.card_images[1]), "cards stay clickable")

  item_atlas.handle_action(s, { type = "select", slot_index = 2 }, 1)
  luassert.equal(false, _find_call(calls, "set_touch_enabled", "图鉴-背景"), "enlarged state withdraws background touch")
  luassert.equal(true, _find_call(calls, "set_touch_enabled", item_atlas_nodes.close_blank), "blank layer collapses the card")

  item_atlas.handle_action(s, intents[item_atlas_nodes.close_blank].action, 1)
  luassert.equal(true, s.ui.item_atlas.open, "tapping blank only collapses the enlarged card")
  luassert.equal(true, _find_call(calls, "set_touch_enabled", "图鉴-背景"), "background touchable again after collapse")

  item_atlas.handle_action(s, intents["图鉴-背景"].action, 1)
  luassert.equal(false, s.ui.item_atlas.open, "background click then closes the atlas")
end)

it("test_page_next_advances_page_when_multiple_pages_exist", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(16))
  local s = _make_state()
  item_atlas.open(s, 1)
  item_atlas.handle_action(s, "next", 1)
  luassert.truthy(s.ui.item_atlas.page_index == 2, "page should advance to 2")
end)

it("test_page_next_does_not_exceed_max_page", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(8))
  local s = _make_state()
  item_atlas.open(s, 1)
  item_atlas.handle_action(s, "next", 1)
  item_atlas.handle_action(s, "next", 1)
  luassert.truthy(s.ui.item_atlas.page_index == 1, "single-page atlas should clamp to page 1")
end)

it("test_page_prev_goes_to_previous_page", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(16))
  local s = _make_state()
  item_atlas.open(s, 1)
  item_atlas.handle_action(s, "next", 1)
  luassert.truthy(s.ui.item_atlas.page_index == 2)
  item_atlas.handle_action(s, "prev", 1)
  luassert.truthy(s.ui.item_atlas.page_index == 1, "prev should go back to page 1")
end)

it("test_page_prev_does_not_go_below_page_1", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(16))
  local s = _make_state()
  item_atlas.open(s, 1)
  item_atlas.handle_action(s, "prev", 1)
  luassert.truthy(s.ui.item_atlas.page_index == 1, "prev on page 1 should stay at page 1")
end)

it("test_page_next_clears_selected_item_id", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(16))
  local s = _make_state()
  item_atlas.open(s, 1)
  item_atlas.handle_action(s, { type = "select", slot_index = 1 }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == "item_1")
  item_atlas.handle_action(s, "next", 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == nil, "page_next should clear selection")
end)

it("test_nil_role_atlas_actions_keep_the_existing_owner_role", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(16))
  local s = _make_state()
  item_atlas.open(s, 7)

  item_atlas.handle_action(s, "next", nil)
  luassert.truthy(s.ui.item_atlas.role_id == 7, "page movement without role_id should keep atlas owner")

  item_atlas.handle_action(s, { type = "select", slot_index = 1 }, nil)
  luassert.truthy(s.ui.item_atlas.role_id == 7, "selection without role_id should keep atlas owner")

  item_atlas.handle_action(s, "dismiss", nil)
  luassert.truthy(s.ui.item_atlas.role_id == 7, "dismiss without role_id should keep atlas owner")
end)

it("test_page_next_refreshes_card_textures_for_the_atlas_owner_role", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(16))
  local s = _make_state()
  s.runtime_asset_context = { refs = { images = {} } }
  for i = 1, 16 do
    s.runtime_asset_context.refs.images["item_" .. tostring(i)] = "tex_" .. tostring(i)
  end
  s.ui.set_visible = function() end

  local role2 = {
    get_roleid = function()
      return 2
    end,
    send_ui_custom_event = function() end,
  }
  runtime_ports.configure({
    resolve_role = function(role_id)
      if tostring(role_id) == "2" then
        return role2
      end
      return nil
    end,
  })

  local textures_by_role = {}
  local function _role_key()
    local role = UIManager and UIManager.client_role or nil
    if role and role.get_roleid then
      return role.get_roleid()
    end
    return "global"
  end

  _with_patches({
    { key = "UIManager", value = {
      client_role = nil,
      query_nodes_by_name = function(name)
        return {
          {
            set_texture_keep_size = function(_, key)
              local role_key = _role_key()
              textures_by_role[role_key] = textures_by_role[role_key] or {}
              textures_by_role[role_key][name] = key
            end,
          },
        }
      end,
    } },
  }, function()
    item_atlas.open(s, 2)
    item_atlas.handle_action(s, "next", 2)
  end, { skip_runtime_context_refresh = true })

  local role2_textures = textures_by_role[2] or {}
  luassert.truthy(role2_textures[item_atlas_nodes.card_images[1]] == "tex_9",
    "page_next should refresh slot 1 texture on the atlas owner role")
end)

it("test_page_prev_clears_selected_item_id", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(16))
  local s = _make_state()
  item_atlas.open(s, 1)
  item_atlas.handle_action(s, "next", 1)
  item_atlas.handle_action(s, { type = "select", slot_index = 1 }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == "item_9")
  item_atlas.handle_action(s, "prev", 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == nil, "page_prev should clear selection")
end)

it("test_unknown_string_action_returns_state_and_sets_role_id", function()
  local s = _make_state()
  item_atlas.open(s, 1)
  local atlas = item_atlas.handle_action(s, "no_such_action", 2)
  luassert.truthy(atlas == s.ui.item_atlas, "unknown action should still return atlas state")
  luassert.truthy(atlas.role_id == 2, "unknown action should update role_id from arg")
end)

it("test_unknown_table_action_returns_state_without_crashing", function()
  local s = _make_state()
  item_atlas.open(s, 1)
  local atlas = item_atlas.handle_action(s, { type = "unknown_intent_kind" }, 1)
  luassert.truthy(atlas == s.ui.item_atlas, "unknown table action should return atlas state")
end)

it("test_re_selecting_the_same_slot_clears_the_selection_toggle_off", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(8))
  local s = _make_state()
  item_atlas.open(s, 1)
  item_atlas.handle_action(s, { type = "select", slot_index = 3 }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == "item_3", "first select should pick item_3")
  item_atlas.handle_action(s, { type = "select", slot_index = 3 }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == nil, "second select on same slot should clear selection")
end)

it("test_selecting_a_different_slot_replaces_the_selection", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(8))
  local s = _make_state()
  item_atlas.open(s, 1)
  item_atlas.handle_action(s, { type = "select", slot_index = 2 }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == "item_2")
  item_atlas.handle_action(s, { type = "select", slot_index = 5 }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == "item_5", "selecting another slot should replace selection")
end)

it("test_selecting_an_empty_slot_does_not_clear_an_existing_selection", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(5))
  local s = _make_state()
  item_atlas.open(s, 1)
  item_atlas.handle_action(s, { type = "select", slot_index = 3 }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == "item_3")
  item_atlas.handle_action(s, { type = "select", slot_index = 7 }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == "item_3",
    "empty-slot click while item selected must leave selection intact")
end)

it("test_shows_present_items_and_hides_empty_slots", function()
  local catalog = _make_catalog(3)
  local state, calls = _make_render_state()
  item_atlas_view.refresh_page(state, catalog, 1)
  for slot = 1, 3 do
    local vis = _find_call(calls, "set_visible", item_atlas_nodes.card_images[slot])
    luassert.truthy(vis == true, "slot " .. slot .. " with item should be visible")
  end
  for slot = 4, 8 do
    local vis = _find_call(calls, "set_visible", item_atlas_nodes.card_images[slot])
    luassert.truthy(vis == false, "slot " .. slot .. " without item should be hidden")
  end
end)

it("test_disables_touch_for_hidden_empty_card_slots", function()
  local catalog = _make_catalog(3)
  local state, calls = _make_render_state()
  item_atlas_view.refresh_page(state, catalog, 1)
  for slot = 1, 3 do
    local enabled = _find_call(calls, "set_touch_enabled", item_atlas_nodes.card_images[slot])
    luassert.truthy(enabled == true, "slot " .. slot .. " with item should be touch-enabled")
  end
  for slot = 4, 8 do
    local enabled = _find_call(calls, "set_touch_enabled", item_atlas_nodes.card_images[slot])
    luassert.truthy(enabled == false, "hidden slot " .. slot .. " must not consume clicks")
  end
end)

it("test_never_writes_the_static_title_label_on_refresh_page", function()
  local catalog = _make_catalog(16)
  local state, calls = _make_render_state()
  item_atlas_view.refresh_page(state, catalog, 2)
  for _, c in ipairs(calls) do
    luassert.truthy(not (c[1] == "set_label" and c[2] == "图鉴_图鉴文本"),
      "refresh_page must not write to 图鉴_图鉴文本")
  end
end)

it("test_single_page_catalog_hides_both_prev_and_next_arrows", function()
  local catalog = _make_catalog(8)
  local state, calls = _make_render_state()
  item_atlas_view.refresh_page(state, catalog, 1)
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.page_prev) == false,
    "prev arrow should be hidden on single-page catalog")
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.page_next) == false,
    "next arrow should be hidden on single-page catalog")
end)

it("test_multi_page_first_page_shows_only_next_arrow", function()
  local catalog = _make_catalog(16)
  local state, calls = _make_render_state()
  item_atlas_view.refresh_page(state, catalog, 1)
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.page_prev) == false,
    "prev arrow should be hidden on first page")
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.page_next) == true,
    "next arrow should be visible on first page of multi-page catalog")
  luassert.truthy(_find_call(calls, "set_touch_enabled", item_atlas_nodes.page_prev) == false,
    "hidden prev arrow must not consume clicks on first page")
  luassert.truthy(_find_call(calls, "set_touch_enabled", item_atlas_nodes.page_next) == true,
    "visible next arrow should be touchable on first page")
end)

it("test_multi_page_middle_page_shows_both_arrows", function()
  local catalog = _make_catalog(24)
  local state, calls = _make_render_state()
  item_atlas_view.refresh_page(state, catalog, 2)
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.page_prev) == true,
    "prev arrow should be visible on middle page")
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.page_next) == true,
    "next arrow should be visible on middle page")
end)

it("test_multi_page_last_page_shows_only_prev_arrow", function()
  local catalog = _make_catalog(16)
  local state, calls = _make_render_state()
  item_atlas_view.refresh_page(state, catalog, 2)
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.page_prev) == true,
    "prev arrow should be visible on last page")
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.page_next) == false,
    "next arrow should be hidden on last page")
  luassert.truthy(_find_call(calls, "set_touch_enabled", item_atlas_nodes.page_prev) == true,
    "visible prev arrow should be touchable on last page")
  luassert.truthy(_find_call(calls, "set_touch_enabled", item_atlas_nodes.page_next) == false,
    "hidden next arrow must not consume clicks on last page")
end)

it("test_single_page_catalog_with_out_of_range_page_index_still_hides_both_arrows", function()
  local catalog = _make_catalog(8)
  local state, calls = _make_render_state()
  item_atlas_view.refresh_page(state, catalog, 5)
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.page_prev) == false,
    "single-page catalog must keep prev arrow hidden regardless of page_index")
  luassert.truthy(_find_call(calls, "set_visible", item_atlas_nodes.page_next) == false,
    "single-page catalog must keep next arrow hidden regardless of page_index")
end)

it("test_refresh_page_queries_exactly_page_size_card_nodes_on_a_full_page", function()
  local catalog = _make_catalog(8)
  local state, _ = _make_render_state()
  state.runtime_asset_context = { refs = { images = {} } }
  for i = 1, 8 do
    state.runtime_asset_context.refs.images["item_" .. i] = "tex_" .. i
  end
  local query_count = 0
  local runtime = {
    query_node = function(name)
      query_count = query_count + 1
      return { name = name }
    end,
    set_node_texture_keep_size = function(_, _) end,
  }
  item_atlas_view.refresh_page(state, catalog, 1, { runtime = runtime })
  -- lint-allow: call-count runtime 经参数注入(宿主节点边界),整页恰查询页容量个节点
  luassert.truthy(query_count == 8,
    "refresh_page should query exactly 8 card nodes for a full page, got " .. tostring(query_count))
end)

it("test_sets_texture_when_image_refs_are_provided", function()
  local catalog = { { id = "item_A", name = "A" } }
  local state, _ = _make_render_state()
  state.runtime_asset_context = { refs = { images = { item_A = "texture_A" } } }
  local runtime = _stub_runtime()
  item_atlas_view.refresh_page(state, catalog, 1, { runtime = runtime })
  luassert.truthy(runtime.textures[item_atlas_nodes.card_images[1]] == "texture_A",
    "should set texture for item with image ref")
end)

it("test_sets_texture_from_resolver_asset_context", function()
  local catalog = { { id = "item_A", name = "A" } }
  local state, _ = _make_render_state()
  state.runtime_asset_context = { refs = { images = { item_A = "texture_A" } } }
  local runtime = _stub_runtime()

  item_atlas_view.refresh_page(state, catalog, 1, { runtime = runtime })

  luassert.truthy(runtime.textures[item_atlas_nodes.card_images[1]] == "texture_A",
    "item atlas renderer should consume resolver asset context")
end)

it("test_sets_texture_on_all_matched_card_nodes_when_runtime_exposes_query_nodes", function()
  local catalog = { { id = "item_A", name = "A" } }
  local state, _ = _make_render_state()
  state.runtime_asset_context = { refs = { images = { item_A = "texture_A" } } }
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
  item_atlas_view.refresh_page(state, catalog, 1, { runtime = runtime })
  luassert.truthy(textures[item_atlas_nodes.card_images[1] .. "#a"] == "texture_A",
    "should set texture on first matched node")
  luassert.truthy(textures[item_atlas_nodes.card_images[1] .. "#b"] == "texture_A",
    "should set texture on second matched node")
end)

it("test_show_enlarged_shows_the_enlarged_card_trio_and_sets_texture", function()
  local state, calls = _make_render_state()
  state.runtime_asset_context = { refs = { images = { item_X = "texture_X" } } }
  local runtime = _stub_runtime()
  item_atlas_view.show_enlarged(state, "item_X", { runtime = runtime })
  local card_vis = _find_call(calls, "set_visible", item_atlas_nodes.enlarged_card)
  local hint_vis = _find_call(calls, "set_visible", item_atlas_nodes.close_hint_label)
  local blank_vis = _find_call(calls, "set_visible", item_atlas_nodes.close_blank)
  luassert.truthy(card_vis == true, "enlarged card should be visible")
  luassert.truthy(hint_vis == true, "close hint should be visible")
  luassert.truthy(blank_vis == true, "close blank layer should be visible")
  luassert.truthy(_find_call(calls, "set_touch_enabled", item_atlas_nodes.close_blank) == true,
    "visible blank close layer should be touchable")
  luassert.truthy(runtime.textures[item_atlas_nodes.enlarged_card] == "texture_X",
    "enlarged card should show correct texture")
  luassert.truthy(_find_call(calls, "set_visible_global", item_atlas_nodes.enlarged_card) == nil,
    "enlarged overlay must not use global broadcast variants (#544)")
  luassert.truthy(_find_call(calls, "set_touch_enabled_global", item_atlas_nodes.close_blank) == nil,
    "close blank touch must not use global broadcast variants (#544)")
end)

it("test_hide_enlarged_hides_the_enlarged_card_trio", function()
  local state, calls = _make_render_state()
  item_atlas_view.hide_enlarged(state)
  local card_vis = _find_call(calls, "set_visible", item_atlas_nodes.enlarged_card)
  local hint_vis = _find_call(calls, "set_visible", item_atlas_nodes.close_hint_label)
  local blank_vis = _find_call(calls, "set_visible", item_atlas_nodes.close_blank)
  luassert.truthy(card_vis == false, "enlarged card should be hidden")
  luassert.truthy(hint_vis == false, "close hint should be hidden")
  luassert.truthy(blank_vis == false, "close blank layer should be hidden")
  luassert.truthy(_find_call(calls, "set_touch_enabled", item_atlas_nodes.close_blank) == false,
    "hidden blank close layer must not consume clicks")
  luassert.truthy(_find_call(calls, "set_visible_global", item_atlas_nodes.enlarged_card) == nil,
    "hide enlarged must not use global broadcast variants (#544)")
end)

it("test_show_enlarged_sets_texture_on_all_matched_nodes_when_runtime_exposes_query_nodes", function()
  local state = _make_render_state()
  state.runtime_asset_context = { refs = { images = { item_X = "texture_X" } } }
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
  item_atlas_view.show_enlarged(state, "item_X", { runtime = runtime })
  luassert.truthy(textures[item_atlas_nodes.enlarged_card .. "#a"] == "texture_X",
    "should set texture on first matched enlarged node")
  luassert.truthy(textures[item_atlas_nodes.enlarged_card .. "#b"] == "texture_X",
    "should set texture on second matched enlarged node")
end)

it("test_show_enlarged_with_missing_image_ref_is_a_no_op", function()
  local state, calls = _make_render_state()
  item_atlas_view.show_enlarged(state, "no_such_item")
  luassert.truthy(#calls == 0, "no calls when image ref missing")
end)

it("test_show_enlarged_falls_back_to_module_level_runtime_ui_when_deps_omitted", function()
  local state, calls = _make_render_state()
  state.runtime_asset_context = { refs = { images = { item_X = "texture_X" } } }
  local queried = {}
  local prev_query = UIManager.query_nodes_by_name
  UIManager.query_nodes_by_name = function(name)
    queried[name] = (queried[name] or 0) + 1
    return {
      {
        name = name,
        set_texture_keep_size = function(_, _) end,
        set_texture_native_size = function(_, _) end,
      },
    }
  end
  local ok, err = pcall(item_atlas_view.show_enlarged, state, "item_X")
  UIManager.query_nodes_by_name = prev_query
  luassert.truthy(ok, "show_enlarged should succeed without deps: " .. tostring(err))
  luassert.truthy(queried[item_atlas_nodes.enlarged_card] == 1,
    "fallback runtime should query enlarged_card via UIManager exactly once")
  local card_vis = _find_call(calls, "set_visible", item_atlas_nodes.enlarged_card)
  luassert.truthy(card_vis == true, "enlarged card should be visible via fallback path")
end)

it("test_page_2_shows_correct_items_by_offset", function()
  local catalog = _make_catalog(12)
  local state, calls = _make_render_state()
  state.runtime_asset_context = { refs = { images = {} } }
  for i = 1, 12 do
    state.runtime_asset_context.refs.images["item_" .. i] = "tex_" .. i
  end
  local runtime = _stub_runtime()
  item_atlas_view.refresh_page(state, catalog, 2, { runtime = runtime })
  luassert.truthy(runtime.textures[item_atlas_nodes.card_images[1]] == "tex_9",
    "page 2 slot 1 should show item 9")
  luassert.truthy(runtime.textures[item_atlas_nodes.card_images[4]] == "tex_12",
    "page 2 slot 4 should show item 12")
  local vis5 = _find_call(calls, "set_visible", item_atlas_nodes.card_images[5])
  luassert.truthy(vis5 == false, "page 2 slot 5 should be hidden (only 12 items)")
end)

it("test_integer_action_selects_slot_by_index", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(8))
  local s = _make_state()
  item_atlas.open(s, 1)
  item_atlas.handle_action(s, 3, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == "item_3", "integer 3 should select item_3")
end)

-- T16 mutation-pinning addendum.
--
-- _ensure_state defaults observed via unknown-action path (which calls
-- _ensure_state then returns the atlas without further mutation). open() is
-- intentionally NOT called first so the defaults remain visible.
--
it("test_initial_open_flag_is_false_until_item_atlas_open_flips_it_l18", function()
  local s = _make_state()
  local atlas = item_atlas.handle_action(s, "no_such_action", 1)
  luassert.truthy(atlas.open == false,
    "default atlas.open must be false; L18 mutation flips _ensure_state default to true. " ..
    "Got: " .. tostring(atlas.open))
end)

it("test_initial_page_index_is_1_so_item_at_points_at_catalog_1_l19", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(8))
  local s = _make_state()
  -- handle_action with unknown action triggers _ensure_state without overwriting
  -- page_index. Then a select with slot_index=1 should resolve to catalog[1] (page 1).
  item_atlas.handle_action(s, "no_such_action", 1)
  local atlas = s.ui.item_atlas
  luassert.truthy(atlas.page_index == 1,
    "default page_index must be 1; L19 mutation makes it 0. Got: " .. tostring(atlas.page_index))
  -- Cross-check via _item_at: page_index=1 + slot 1 ⇒ item_1; mutated page_index=0 ⇒
  -- catalog[(0-1)*8+1] = catalog[-7] = nil ⇒ no selection.
  item_atlas.handle_action(s, { type = "select", slot_index = 1 }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == "item_1",
    "page_index default must allow selecting item_1; L19 makes catalog index negative. " ..
    "Got: " .. tostring(s.ui.item_atlas.selected_item_id))
end)

it("test_select_with_nil_slot_index_resolves_to_catalog_slot_1_l31", function()
  item_atlas.configure_catalog_for_tests(_make_catalog(8))
  local s = _make_state()
  item_atlas.open(s, 1)
  -- slot_index=nil → _item_at(atlas, nil) → to_integer(nil) is nil → fallback to 1.
  -- Original: catalog[(1-1)*8 + 1] = catalog[1] = item_1 → selection set.
  -- Mutated `or 0`: catalog[(1-1)*8 + 0] = catalog[0] = nil → no selection.
  item_atlas.handle_action(s, { type = "select", slot_index = nil }, 1)
  luassert.truthy(s.ui.item_atlas.selected_item_id == "item_1",
    "_item_at fallback must pick slot 1 when slot_index is nil; L31 mutation `or 1 → or 0` " ..
    "makes catalog[0] = nil and leaves selection unset. Got: " ..
    tostring(s.ui.item_atlas.selected_item_id))
end)


end)
