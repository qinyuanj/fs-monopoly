-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
local P = require("test.support.shared_support")
local _new_game = P.new_game
local function _assert_eq(actual, expected, message) luassert.is.equal(expected, actual, message) end
local _bind_ui_runtime = P.bind_ui_runtime
local _with_patches = P.with_patches
local _build_asset_context = P.build_asset_context
local _ui_runtime = P.ui_runtime
local market_view = require("src.ui.render.market")
local market_view_controls = require("src.ui.render.market.controls")
local market_layout = require("src.ui.schema.market_layout")
local canvas_event_router = require("src.ui.coord.canvas_event_router")
local ui_view = require("src.ui.coord.ui_runtime")
local market_cfg = require("src.config.content.market")
local market_service = require("src.rules.market")
local choice_slice = require("src.ui.view.choice_slice")
local market_sold_out_fixture = require("test.support.market_sold_out_fixture")
local runtime_state = require("src.state.runtime")
local slot_assets = require("src.ui.render.market.slot_assets")
local runtime_ref_images = require("src.config.content.runtime_ref_images")

local function _build_market_state(product_ids)
  local visible = {}
  local labels = {}
  local touch = {}
  local refs = { ["Empty"] = 1, ["lv1"] = 2, ["lv2"] = 3, ["lv3"] = 4 }
  for i, product_id in ipairs(product_ids or {}) do
    refs[tostring(product_id)] = 4 + i
  end
  local state = {
    runtime_asset_context = _build_asset_context(refs),
    ui = {
      market_active = false,
      set_label = function(_, name, text) labels[name] = text end,
      set_visible = function(_, name, flag) visible[name] = flag == true end,
      set_touch_enabled = function(_, name, flag) touch[name] = flag == true end,
      query_node = function() return {} end,
    },
  }
  return state, visible, labels, touch
end

local function _build_cash_display_state(opts)
  opts = opts or {}
  local labels = {}
  local visible = {}
  local state = {
    ui = {
      set_label = function(_, name, text) labels[name] = text end,
      set_visible = function(_, name, flag) visible[name] = flag == true end,
      set_touch_enabled = function() end,
      query_node = function() return {} end,
    },
  }
  _bind_ui_runtime(state)
  if opts.bind_model ~= false then
    runtime_state.set_ui_model(state, { current_player_cash = opts.current_player_cash })
  end
  return state, labels, visible
end

local function _first_two_market_entries()
  return assert(market_cfg[1], "missing market cfg entry a"),
    assert(market_cfg[2], "missing market cfg entry b")
end

local function _two_entry_options(entry_a, entry_b)
  return {
    { id = entry_a.product_id, label = entry_a.name, can_buy = true },
    { id = entry_b.product_id, label = entry_b.name, can_buy = true },
  }
end

local function _refresh_two_entry_market(state, choice_id, entry_a, entry_b, selected_option_id)
  return market_view.refresh_market(state, {
    choice_id = choice_id,
    options = _two_entry_options(entry_a, entry_b),
    allow_cancel = true,
    selected_option_id = selected_option_id,
  })
end

local function _assert_first_two_selection_frames(visible, first_visible, second_visible, context)
  _assert_eq(visible[market_layout.item_selection_frames[1]], first_visible,
    context .. ": first selection frame")
  _assert_eq(visible[market_layout.item_selection_frames[2]], second_visible,
    context .. ": second selection frame")
end

describe("TestMarketPanel", function()

  it("test_01_market_selection_updates_icon_and_price", function()
    local entry = assert(market_cfg[1], "missing market cfg entry")
    local option_id = entry.product_id
    local selected_node = {}
    local labels = {}
    local state = {
      runtime_asset_context = _build_asset_context({
        ["Empty"] = 1001,
        [tostring(option_id)] = 1002,
      }),
      ui = {
        set_label = function(_, name, text)
          labels[name] = text
        end,
        query_node = function(name)
          _assert_eq(name, market_layout.selected_card, "selected card node expected")
          return selected_node
        end,
      },
    }

    market_view.refresh_market_selection(state, option_id)

    _assert_eq(selected_node.image_texture, 1002, "market selected icon should update")
    _assert_eq(labels[market_layout.price_label], tostring(entry.price) .. " " .. entry.currency,
      "market price label should update")
  end)

  it("test_02_market_price_text_hides_float_decimal_suffix", function()
    _assert_eq(slot_assets.price_text({ price = 10.0, currency = "金豆" }), "10 金豆",
      "jindou market price should render as integer text")
    _assert_eq(slot_assets.price_text({ price = 1200.0, currency = "金币" }), "1200 金币",
      "coin market price should render as integer text")
  end)

  it("test_03_market_close_resets_icon_and_selection", function()
    local visible = {}
    local selected_node = {}
    local state = {
      choice_visible_option_ids = { 1, 2 },
      pending_choice_selected_option_id = 1,
      runtime_asset_context = _build_asset_context({
        ["Empty"] = 4321,
      }),
      ui = {
        market_active = true,
        set_visible = function(_, name, value)
          visible[name] = value == true
        end,
        set_label = function() end,
        set_touch_enabled = function() end,
        query_node = function(name)
          _assert_eq(name, market_layout.selected_card, "selected card node expected")
          return selected_node
        end,
      },
    }

    market_view.close_market_panel(state)

    _assert_eq(state.ui.market_active, false, "market panel should be inactive")
    _assert_eq(_ui_runtime(state).choice_visible_option_ids, nil, "market options should clear")
    _assert_eq(_ui_runtime(state).pending_choice_selected_option_id, nil, "selected market option should clear")
    _assert_eq(selected_node.image_texture, 4321, "market selected icon should reset to empty key")
    for _, name in ipairs(market_layout.item_selection_frames) do
      _assert_eq(visible[name], false, "market close should hide selection frame")
    end
  end)

  it("test_04_market_view_default_selection_shows_matching_selection_frame", function()
    local entry_a, entry_b = _first_two_market_entries()
    local state, visible = _build_market_state({ entry_a.product_id, entry_b.product_id })

    local opened = _refresh_two_entry_market(state, 21, entry_a, entry_b, entry_b.product_id)

    _assert_eq(opened, true, "market panel should open")
    _assert_eq(_ui_runtime(state).pending_choice_selected_option_id, entry_a.product_id,
      "market should still prefer first visible buyable option by default")
    _assert_first_two_selection_frames(visible, true, false, "default selection")
  end)

  it("test_05_market_view_populated_market_tolerates_missing_asset_context", function()
    local entry = assert(market_cfg[1], "missing market cfg entry")
    local state, visible, labels = _build_market_state({})
    state.runtime_asset_context = nil

    local opened = market_view.refresh_market(state, {
      choice_id = 21,
      options = {
        { id = entry.product_id, label = entry.name, can_buy = true },
      },
      allow_cancel = true,
    })

    _assert_eq(opened, true, "market panel should open without ui refs")
    _assert_eq(labels[market_layout.item_labels[1]], entry.name,
      "market item label should still render without ui refs")
    _assert_eq(visible[market_layout.item_buttons[1]], true,
      "market item button should still render without ui refs")
  end)

  it("test_06_market_select_switches_selection_frame", function()
    local entry_a, entry_b = _first_two_market_entries()
    local state, visible = _build_market_state({ entry_a.product_id, entry_b.product_id })

    _refresh_two_entry_market(state, 22, entry_a, entry_b, entry_a.product_id)

    market_view.select_market_option(state, entry_b.product_id)

    _assert_eq(_ui_runtime(state).pending_choice_selected_option_id, entry_b.product_id, "market select should update selected option")
    _assert_first_two_selection_frames(visible, false, true, "reselection")
  end)

  it("test_07_market_view_refresh_preserves_manual_selection_on_same_page", function()
    local entry_a, entry_b = _first_two_market_entries()
    local state, visible = _build_market_state({ entry_a.product_id, entry_b.product_id })

    _refresh_two_entry_market(state, 22, entry_a, entry_b, entry_a.product_id)

    market_view.select_market_option(state, entry_b.product_id)

    local reopened = _refresh_two_entry_market(
      state, 22, entry_a, entry_b, _ui_runtime(state).pending_choice_selected_option_id
    )

    _assert_eq(reopened, true, "market panel should refresh after manual selection")
    _assert_eq(_ui_runtime(state).pending_choice_selected_option_id, entry_b.product_id,
      "same-page refresh should preserve the manually selected market option")
    _assert_first_two_selection_frames(visible, false, true, "same-page refresh")
  end)

  it("test_08_market_view_empty_filtered_tab_hides_selection_frames", function()
    local visible_entry = assert(market_cfg[1], "missing market cfg entry")
    local hidden_entry = {
      product_id = 999101,
      name = "隐藏测试商品2",
      market_enabled = false,
      currency = visible_entry.currency,
      price = visible_entry.price,
    }

    local state, visible = _build_market_state({ visible_entry.product_id, hidden_entry.product_id })

    local market_cfg_size = #market_cfg
    local old_market_view = package.loaded["src.ui.render.market"]
    market_cfg[market_cfg_size + 1] = hidden_entry
    package.loaded["src.ui.render.market"] = nil

    local ok, err = xpcall(function()
      local test_market_view = require("src.ui.render.market")

      test_market_view.refresh_market(state, {
        choice_id = 23,
        options = {
          { id = visible_entry.product_id, label = visible_entry.name, can_buy = true },
        },
        allow_cancel = true,
        selected_option_id = visible_entry.product_id,
      })

      local reopened = test_market_view.refresh_market(state, {
        choice_id = 24,
        options = {
          { id = hidden_entry.product_id, label = hidden_entry.name, can_buy = false },
        },
        allow_cancel = true,
        selected_option_id = hidden_entry.product_id,
      })

      _assert_eq(reopened, true, "market panel should stay open when filtered tab is empty")
      _assert_eq(_ui_runtime(state).pending_choice_selected_option_id, nil, "empty filtered tab should clear selected option")
      for _, name in ipairs(market_layout.item_selection_frames) do
        _assert_eq(visible[name], false, "empty filtered tab should hide all selection frames")
      end
    end, debug.traceback or function(e) return e end)

    market_cfg[market_cfg_size + 1] = nil
    package.loaded["src.ui.render.market"] = nil
    package.loaded["src.ui.render.market"] = old_market_view
    if not ok then
      error(err)
    end
  end)

  it("test_09_market_view_refresh_retargets_selection_frame_on_page_change", function()
    local entry_a = assert(market_cfg[1], "missing market cfg entry a")
    local entry_b = assert(market_cfg[2], "missing market cfg entry b")
    local state, visible = _build_market_state({ entry_a.product_id, entry_b.product_id })

    market_view.refresh_market(state, {
      choice_id = 25,
      options = {
        { id = entry_a.product_id, label = entry_a.name, can_buy = true },
      },
      allow_cancel = true,
      selected_option_id = entry_a.product_id,
      page_index = 1,
      page_count = 2,
    })

    local reopened = market_view.refresh_market(state, {
      choice_id = 25,
      options = {
        { id = entry_b.product_id, label = entry_b.name, can_buy = true },
      },
      allow_cancel = true,
      selected_option_id = entry_b.product_id,
      page_index = 2,
      page_count = 2,
    })

    _assert_eq(reopened, true, "market panel should refresh on page change")
    _assert_eq(_ui_runtime(state).pending_choice_selected_option_id, entry_b.product_id,
      "page change should retarget selected option to current visible page")
    _assert_eq(visible[market_layout.item_selection_frames[1]], true,
      "current page selected option should show selection frame")
    for index = 2, #market_layout.item_selection_frames do
      _assert_eq(visible[market_layout.item_selection_frames[index]], false,
        "non-current page frames should remain hidden after refresh")
    end
  end)

  it("test_10_market_view_hides_market_disabled_entries", function()
    local visible_entry = nil
    for _, entry in ipairs(market_cfg) do
      if visible_entry == nil and entry.market_enabled ~= false then
        visible_entry = entry
      end
      if visible_entry then
        break
      end
    end
    luassert.truthy(visible_entry ~= nil, "missing market visible entry for presentation test")
    local hidden_entry = {
      product_id = 999001,
      name = "隐藏测试商品",
      market_enabled = false,
      currency = visible_entry.currency,
      price = visible_entry.price,
    }

    local state, visible, labels = _build_market_state({ hidden_entry.product_id, visible_entry.product_id })

    local market_cfg_size = #market_cfg
    local old_market_view = package.loaded["src.ui.render.market"]
    market_cfg[market_cfg_size + 1] = hidden_entry
    package.loaded["src.ui.render.market"] = nil

    local ok, err = xpcall(function()
      local test_market_view = require("src.ui.render.market")

      local opened = test_market_view.refresh_market(state, {
        choice_id = 7,
        options = {
          { id = hidden_entry.product_id, label = hidden_entry.name, can_buy = false },
          { id = visible_entry.product_id, label = visible_entry.name, can_buy = true },
        },
        allow_cancel = true,
        selected_option_id = hidden_entry.product_id,
      })

      _assert_eq(opened, true, "market panel should open when at least one visible option exists")
      _assert_eq(labels[market_layout.item_labels[1]], visible_entry.name, "first rendered market option should skip disabled entry")
      _assert_eq(visible[market_layout.item_labels[2]], false, "second slot should remain hidden after filtering")

      local reopened = test_market_view.refresh_market(state, {
        choice_id = 8,
        options = {
          { id = hidden_entry.product_id, label = hidden_entry.name, can_buy = false },
        },
        allow_cancel = true,
        selected_option_id = hidden_entry.product_id,
      })

      _assert_eq(reopened, true, "market panel should stay open when all options are filtered out")
      _assert_eq(state.ui.market_active, true, "market panel should remain active on empty filtered tab")
      _assert_eq(visible[market_layout.item_labels[1]], false, "empty filtered tab should hide first slot label")
      _assert_eq(visible[market_layout.item_buttons[1]], false, "empty filtered tab should hide first slot button")
      _assert_eq(_ui_runtime(state).pending_choice_selected_option_id, nil, "empty filtered tab should clear selected option")
    end, debug.traceback or function(e) return e end)

    market_cfg[market_cfg_size + 1] = nil
    package.loaded["src.ui.render.market"] = nil
    package.loaded["src.ui.render.market"] = old_market_view
    if not ok then
      error(err)
    end
  end)

  it("test_11_market_view_unbuyable_option_is_clickable", function()
    local entry = assert(market_cfg[1], "missing market cfg entry")
    local state, _, _, touch = _build_market_state({ entry.product_id })

    local opened = market_view.refresh_market(state, {
      choice_id = 10,
      options = {
        { id = entry.product_id, label = entry.name, can_buy = false },
      },
      allow_cancel = true,
      selected_option_id = entry.product_id,
    })

    _assert_eq(opened, true, "market panel should open with unbuyable options")
    _assert_eq(touch[market_layout.item_buttons[1]], true, "unbuyable option button should still be clickable")
  end)

  it("test_12_market_view_invalid_selected_option_falls_back_to_current_visible_option", function()
    local entry_a = nil
    local entry_b = nil
    for _, entry in ipairs(market_cfg) do
      if entry.market_enabled ~= false then
        if entry_a == nil then
          entry_a = entry
        elseif entry_b == nil and entry.product_id ~= entry_a.product_id then
          entry_b = entry
        end
      end
      if entry_a and entry_b then
        break
      end
    end
    luassert.truthy(entry_a ~= nil and entry_b ~= nil, "missing visible market entries for selected fallback test")

    local state = _build_market_state({ entry_a.product_id, entry_b.product_id })

    local opened = market_view.refresh_market(state, {
      choice_id = 13,
      options = {
        { id = entry_a.product_id, label = entry_a.name, can_buy = true },
        { id = entry_b.product_id, label = entry_b.name, can_buy = true },
      },
      allow_cancel = true,
      selected_option_id = 999999,
    })

    _assert_eq(opened, true, "market panel should open")
    _assert_eq(_ui_runtime(state).pending_choice_selected_option_id, entry_a.product_id,
      "invalid selected option should fallback to first visible buyable option")
  end)

  it("test_13_market_view_page_arrows_visibility_follows_page_count", function()
    local entry = assert(market_cfg[1], "missing market cfg entry")
    local state, visible, labels, touch = _build_market_state({ entry.product_id })

    market_view.refresh_market(state, {
      choice_id = 11,
      options = {
        { id = entry.product_id, label = entry.name, can_buy = true },
      },
      allow_cancel = true,
      selected_option_id = entry.product_id,
      page_index = 1,
      page_count = 1,
    })

    _assert_eq(visible[market_layout.page_prev], false, "page_prev should be hidden when only one page")
    _assert_eq(visible[market_layout.page_next], false, "page_next should be hidden when only one page")
    _assert_eq(labels[market_layout.page_prev_label], "", "page_prev_label should be cleared when only one page")
    _assert_eq(labels[market_layout.page_next_label], "", "page_next_label should be cleared when only one page")

    market_view.refresh_market(state, {
      choice_id = 12,
      options = {
        { id = entry.product_id, label = entry.name, can_buy = true },
      },
      allow_cancel = true,
      selected_option_id = entry.product_id,
      page_index = 1,
      page_count = 2,
    })

    _assert_eq(visible[market_layout.page_prev], false, "page_prev should be hidden on first page")
    _assert_eq(visible[market_layout.page_next], true, "page_next should be visible when next page exists")
    _assert_eq(touch[market_layout.page_prev], false, "page_prev should be disabled on first page")
    _assert_eq(touch[market_layout.page_next], true, "page_next should be enabled when next page exists")
    _assert_eq(labels[market_layout.page_prev_label], "", "page_prev_label should be empty on first page")
    _assert_eq(labels[market_layout.page_next_label], market_layout.page_next_text, "page_next_label should show text when next page exists")

    market_view.refresh_market(state, {
      choice_id = 13,
      options = {
        { id = entry.product_id, label = entry.name, can_buy = true },
      },
      allow_cancel = true,
      selected_option_id = entry.product_id,
      page_index = 2,
      page_count = 2,
    })

    _assert_eq(visible[market_layout.page_prev], true, "page_prev should be visible when prev page exists")
    _assert_eq(visible[market_layout.page_next], false, "page_next should be hidden on last page")
    _assert_eq(touch[market_layout.page_prev], true, "page_prev should be enabled when prev page exists")
    _assert_eq(touch[market_layout.page_next], false, "page_next should be disabled on last page")
    _assert_eq(labels[market_layout.page_prev_label], market_layout.page_prev_text, "page_prev_label should show text when prev page exists")
    _assert_eq(labels[market_layout.page_next_label], "", "page_next_label should be empty on last page")

    market_view.refresh_market(state, {
      choice_id = 14,
      options = {
        { id = entry.product_id, label = entry.name, can_buy = true },
      },
      allow_cancel = true,
      selected_option_id = entry.product_id,
      page_index = 2,
      page_count = 3,
    })

    _assert_eq(visible[market_layout.page_prev], true, "page_prev should be visible on middle page")
    _assert_eq(visible[market_layout.page_next], true, "page_next should be visible on middle page")
    _assert_eq(touch[market_layout.page_prev], true, "page_prev should be enabled on middle page")
    _assert_eq(touch[market_layout.page_next], true, "page_next should be enabled on middle page")
    _assert_eq(labels[market_layout.page_prev_label], market_layout.page_prev_text, "page_prev_label should show text on middle page")
    _assert_eq(labels[market_layout.page_next_label], market_layout.page_next_text, "page_next_label should show text on middle page")
  end)

  it("test_14_ui_model_market_payload_prefers_explicit_choice_fields", function()
    local ui_model = require("src.ui.view")
    local g = _new_game()
    local current_player = g:current_player()
    g.turn.pending_choice = {
      id = 321,
      kind = "market_buy",
      route_key = "market",
      owner_role_id = current_player.id,
      title = "黑市",
      options = {
        {
          id = 7001,
          label = "测试商品",
          can_buy = true,
          requires_pre_confirm = true,
          confirm_title = "请确认",
          confirm_body = "你选的是：测试商品",
        },
      },
      allow_cancel = true,
      cancel_label = "不买",
      active_tab = "skin",
      page_index = 2,
      page_count = 5,
      meta = {
        player_id = current_player.id,
        active_tab = "item",
        page_index = 9,
        page_count = 9,
      },
    }

    local model = ui_model.build(g, {
      game = g,
      ui_state = { ui = { item_slots = { 1, 2, 3, 4, 5 }, auto_play = false } },
      last_turn = g.last_turn,
      finished = g.finished,
    })

    _assert_eq(model.choice and model.choice.options[1] and model.choice.options[1].requires_pre_confirm, true,
      "choice view should preserve explicit option pre-confirm flag")
    _assert_eq(model.choice and model.choice.owner_role_id, current_player.id,
      "choice view should preserve explicit owner role id")
    _assert_eq(model.market and model.market.active_tab, "item", "market payload should normalize retired skin tab")
    _assert_eq(model.market and model.market.page_index, 2, "market payload should prefer explicit page_index")
    _assert_eq(model.market and model.market.page_count, 5, "market payload should prefer explicit page_count")
  end)

  it("test_15_modal_presenter_market_same_choice_id_still_refreshes_market_panel", function()
    local modal_presenter = require("src.ui.coord.modal")
    local market_presenter = require("src.ui.screens.market")
    local canvas_store = require("src.ui.state.canvas_store")

    local opened = 0
    local state = {
      pending_choice_id = 21,
      ui_dirty = false,
      ui = ui_view.build_ui_state(),
    }
    _bind_ui_runtime(state)
    state.ui.market_active = true
    state.ui.choice_active = false
    local choice = {
      id = 21,
      kind = "market_buy",
      route_key = "market",
      title = "黑市",
      options = {
        { id = 2001, label = "A", can_buy = true },
      },
      allow_cancel = true,
      cancel_label = "取消",
    }
    local market = {
      choice_id = 21,
      options = choice.options,
      allow_cancel = true,
      selected_option_id = 2001,
      active_tab = "item",
      page_index = 1,
      page_count = 1,
    }

    _with_patches({
      { target = market_presenter, key = "open", value = function()
        opened = opened + 1
      end },
      { target = canvas_store, key = "mark_dirty", value = function() end },
    }, function()
      modal_presenter.open_choice_modal(state, choice, market)
    end)

    _assert_eq(opened, 1, "market choice with same id should still refresh market presenter")
  end)

  it("test_16_ui_event_router_market_cancel_button_dispatches_choice_cancel", function()
    local market_nodes = require("src.ui.schema.market")

    local function new_node()
      local node = {}
      function node:listen(_, cb)
        self._listener_cb = cb
        return {
          destroy = function()
            self._listener_cb = nil
          end,
        }
      end
      return node
    end

    local captured = {}
    local show_tip_calls = 0
    local node_map = {
      [market_nodes.cancel] = new_node(),
    }

    _with_patches({
      { key = "all_roles", value = nil },
      { key = "GlobalAPI", value = { show_tips = function()
        show_tip_calls = show_tip_calls + 1
      end } },
      { key = "UIManager", value = {
        EVENT = { CLICK = "click" },
        query_nodes_by_name = function(name)
          local node = node_map[name] or new_node()
          node_map[name] = node
          return { node }
        end,
        client_role = nil,
      } },
    }, function()
      local state = {
        turn_action_port = {
          dispatch_action = function(_, _, action)
            captured[#captured + 1] = action
          end,
          should_block_action = function()
            return false
          end,
        },
        ui = ui_view.build_ui_state(),
        ui_runtime = {
          ui_model = {
            current_player_id = "3",
            choice = {
              id = 12,
              kind = "market_buy",
              allow_cancel = true,
              options = { { id = 34, label = "X" } },
            },
            market = {
              choice_id = 12,
              options = { { id = 34, label = "X" } },
            },
          },
          pending_choice_selected_option_id = 34,
        },
      }
      canvas_event_router.bind(state, function()
        return {}
      end)
      -- 身份随事件数据携带(#341):匿名点击不再回落缓存注入 actor。
      node_map[market_nodes.cancel]._listener_cb({ role = { get_roleid = function() return 3 end } })
    end)

    _assert_eq(captured[1] and captured[1].type, "choice_cancel", "market_cancel button should dispatch choice_cancel")
    _assert_eq(captured[1] and captured[1].choice_id, 12, "market_cancel should keep choice id")
    _assert_eq(captured[1] and captured[1].actor_role_id, 3, "market_cancel should inject actor_role_id")
    _assert_eq(show_tip_calls, 0, "market_cancel should not show unadapted tip")
  end)

  it("test_17_market_view_sets_sold_out_visibility_per_option", function()
    local entry_a = assert(market_cfg[1], "missing market cfg entry a")
    local entry_b = assert(market_cfg[2], "missing market cfg entry b")
    local state, visible = _build_market_state({ entry_a.product_id, entry_b.product_id })

    market_view.refresh_market(state, {
      choice_id = 31,
      options = {
        { id = entry_a.product_id, label = entry_a.name, can_buy = false, sold_out = true },
        { id = entry_b.product_id, label = entry_b.name, can_buy = true,  sold_out = false },
      },
      allow_cancel = true,
    })

    _assert_eq(visible[market_layout.sold_out_badges[1]], true,
      "slot 1 badge should be visible when sold_out = true")
    _assert_eq(visible[market_layout.sold_out_labels[1]], true,
      "slot 1 label should be visible when sold_out = true")
    _assert_eq(visible[market_layout.sold_out_badges[2]], false,
      "slot 2 badge should be hidden when sold_out = false")
    _assert_eq(visible[market_layout.sold_out_labels[2]], false,
      "slot 2 label should be hidden when sold_out = false")
  end)

  it("test_18_market_sold_out_profile_projects_sold_out_to_badges", function()
    local game = _new_game({
      players = { "P1", "P2", "P3", "P4" },
      ai = { [2] = true, [3] = true, [4] = true },
    })
    market_sold_out_fixture.apply(game)
    local player = game:current_player()
    local choice = market_service.choice.build(player, game, { active_tab = "item", page_index = 1 })
    choice.id = 32
    game.turn.pending_choice = choice

    local _, market_model = choice_slice.build_choice_and_market(game, { game = game }, {})
    local product_ids = {}
    for index, option in ipairs(market_model.options or {}) do
      product_ids[index] = option.id
    end
    local state, visible = _build_market_state(product_ids)

    market_view.refresh_market(state, market_model)

    for index = 1, 5 do
      local option = assert(market_model.options[index], "missing sold out option at slot " .. tostring(index))
      _assert_eq(option.sold_out, true, "market model should preserve sold_out for slot " .. tostring(index))
      _assert_eq(visible[market_layout.sold_out_badges[index]], true,
        "sold_out badge should be visible for slot " .. tostring(index))
      _assert_eq(visible[market_layout.sold_out_labels[index]], true,
        "sold_out label should be visible for slot " .. tostring(index))
    end
  end)

  it("test_19_market_confirm_button_stays_visible_when_sold_out_item_selected", function()
    local entry_a = assert(market_cfg[1], "missing market cfg entry a")
    local entry_b = assert(market_cfg[2], "missing market cfg entry b")
    local state, visible = _build_market_state({ entry_a.product_id, entry_b.product_id })

    market_view.refresh_market(state, {
      choice_id = 33,
      options = {
        { id = entry_a.product_id, label = entry_a.name, can_buy = false, sold_out = true },
        { id = entry_b.product_id, label = entry_b.name, can_buy = true,  sold_out = false },
      },
      allow_cancel = true,
    })

    _assert_eq(visible[market_layout.confirm_button], true,
      "confirm button should be visible when buyable item is auto-selected")

    market_view.select_market_option(state, entry_a.product_id)

    _assert_eq(visible[market_layout.confirm_button], true,
      "confirm button should stay visible when sold_out item is selected")

    market_view.select_market_option(state, entry_b.product_id)

    _assert_eq(visible[market_layout.confirm_button], true,
      "confirm button should remain visible when buyable item is re-selected")
  end)

  it("test_20_market_close_hides_all_sold_out_nodes", function()
    local state, visible = _build_market_state({})
    _bind_ui_runtime(state)
    state.ui.market_active = true

    market_view.close_market_panel(state)

    for i = 1, #market_layout.sold_out_badges do
      _assert_eq(visible[market_layout.sold_out_badges[i]], false,
        "sold_out badge " .. i .. " should be hidden after close")
      _assert_eq(visible[market_layout.sold_out_labels[i]], false,
        "sold_out label " .. i .. " should be hidden after close")
    end
  end)

  it("test_21_market_cash_display_shows_current_player_balance", function()
    local state, labels, visible = _build_cash_display_state({
      current_player_cash = 1500.0,
    })

    market_view.refresh_cash_display(state)

    _assert_eq(labels[market_layout.cash_text_label], "现金",
      "cash text label should keep the static caption")
    _assert_eq(labels[market_layout.cash_amount_label], "1500",
      "cash amount label should show player balance")
    _assert_eq(visible[market_layout.cash_text_label], true,
      "cash text label should be visible")
    _assert_eq(visible[market_layout.cash_amount_label], true,
      "cash amount label should be visible")
    _assert_eq(visible[market_layout.cash_icon], true,
      "cash icon should be visible")
  end)

  it("test_22_market_cash_display_skips_when_ui_missing", function()
    local state = {}
    local labels = {}

    market_view.refresh_cash_display(state)

    _assert_eq(labels[market_layout.cash_amount_label], nil,
      "cash amount label should not be set when ui is missing")
  end)

  it("test_23_market_cash_display_defaults_to_zero_when_model_cash_nil", function()
    local state, labels = _build_cash_display_state({
      current_player_cash = nil,
    })

    market_view.refresh_cash_display(state)

    _assert_eq(labels[market_layout.cash_amount_label], "0",
      "cash amount label should default to 0 when balance is nil")
  end)

  it("test_24_market_cash_display_defaults_to_zero_when_ui_model_nil", function()
    local state, labels = _build_cash_display_state({
      bind_model = false,
    })

    market_view.refresh_cash_display(state)

    _assert_eq(labels[market_layout.cash_amount_label], "0",
      "cash amount label should default to 0 when ui_model is nil")
  end)


  it("test_25_market_selection_without_runtime_deps_asserts_descriptive_error", function()
    -- 杀 market/init L48 "missing deps.runtime" 消息钉:deps={} 且 icon_key 非 nil
    -- 时 assert 必须保留描述性消息(_resolve_deps 只认 truthy deps,空表不回落)。
    local entry = assert(market_cfg[1], "missing market cfg entry")
    local state = {
      runtime_asset_context = _build_asset_context({
        ["Empty"] = 1001,
        [tostring(entry.product_id)] = 1002,
      }),
      ui = {
        set_label = function() end,
        query_node = function()
          return {}
        end,
      },
    }
    luassert.has_error(function()
      market_view.refresh_market_selection(state, entry.product_id, {})
    end, "missing deps.runtime")
  end)

  it("test_26_market_view_empty_asset_context_falls_back_to_default_refs", function()
    -- 生产回归:init_ui_assets 把 runtime_asset_context 置为空表 {},
    -- 空 context 必须等价于「无覆盖」走默认 refs;否则黑市 _asset_opts 会把它
    -- 包装成空 images 表吞掉默认查找,道具预览图从不应用(黑市道具图加载不出来)。
    local entry = assert(market_cfg[1], "missing market cfg entry")
    local nodes = {}
    local state = {
      runtime_asset_context = {},
      ui = {
        market_active = false,
        set_label = function() end,
        set_visible = function() end,
        set_touch_enabled = function() end,
        query_node = function(name)
          if nodes[name] == nil then
            nodes[name] = {}
          end
          return nodes[name]
        end,
      },
    }

    local opened = market_view.refresh_market(state, {
      choice_id = 21,
      options = {
        { id = entry.product_id, label = entry.name, can_buy = true },
      },
      allow_cancel = true,
    })

    _assert_eq(opened, true, "market panel should open under an empty asset context")
    local expected = assert(runtime_ref_images[tostring(entry.product_id)],
      "default refs must map the market product image")
    local selected_node = assert(nodes[market_layout.selected_card],
      "selected card node should be queried under an empty asset context")
    _assert_eq(selected_node.image_texture, expected,
      "selected card should use the default-refs item image under an empty context")
  end)

  it("test_27_market_countdown_mirrors_label_only_when_market_active", function()
    -- 黑市屏自带倒计时节点(黑市_倒计时/黑市_倒计时横线):黑市激活且倒计时
    -- 可见时镜像基础屏文本;黑市未激活或倒计时隐藏时一律压灭,文本照写
    -- (语义对齐基础屏 apply_countdown:label 不随显隐缺席)。
    local state, visible, labels = _build_market_state({})
    state.ui.market_active = true

    market_view_controls.apply_market_countdown(state.ui, "倒计时 5", true)

    _assert_eq(visible[market_layout.countdown], true,
      "market countdown should be visible while market is active and countdown shows")
    _assert_eq(visible[market_layout.countdown_line], true,
      "market countdown line should follow the countdown label")
    _assert_eq(labels[market_layout.countdown], "倒计时 5",
      "market countdown should mirror the base countdown text")

    local hidden_state, hidden_visible, hidden_labels = _build_market_state({})
    hidden_state.ui.market_active = true

    market_view_controls.apply_market_countdown(hidden_state.ui, "倒计时 4", false)

    _assert_eq(hidden_visible[market_layout.countdown], false,
      "market countdown should hide when the countdown itself is hidden")
    _assert_eq(hidden_visible[market_layout.countdown_line], false,
      "market countdown line should hide with the countdown")
    _assert_eq(hidden_labels[market_layout.countdown], "倒计时 4",
      "market countdown label should still be written while hidden")

    local closed_state, closed_visible = _build_market_state({})

    market_view_controls.apply_market_countdown(closed_state.ui, "倒计时 3", true)

    _assert_eq(closed_visible[market_layout.countdown], false,
      "market countdown must stay dark while the market is inactive")
    _assert_eq(closed_visible[market_layout.countdown_line], false,
      "market countdown line must stay dark while the market is inactive")
  end)

  it("test_28_market_close_hides_countdown_nodes", function()
    local state, visible, labels = _build_market_state({})
    _bind_ui_runtime(state)
    state.ui.market_active = true

    market_view.close_market_panel(state)

    _assert_eq(visible[market_layout.countdown], false,
      "market countdown should be hidden after close")
    _assert_eq(visible[market_layout.countdown_line], false,
      "market countdown line should be hidden after close")
    _assert_eq(labels[market_layout.countdown], "",
      "market countdown text should be cleared after close")
  end)


end)
