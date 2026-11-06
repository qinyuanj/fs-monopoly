require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- luacheck: ignore 211
local pending_confirmation = require("src.state.pending_confirmation")
local support = require("test.support.shared_support")
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _bind_ui_runtime = support.bind_ui_runtime
local _with_patches = support.with_patches
local ui_intent_dispatcher = require("src.ui.input.intent_dispatcher")
local choice_openers = require("src.ui.coord.choice_openers")
local pre_confirm_flow = require("src.ui.input.pre_confirm")
local market_modal_renderer = require("src.ui.screens.market")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local market_cfg = require("src.config.content.market")
local market_nodes = require("src.ui.schema.market")
local runtime_state = require("src.ui.state.runtime")
local route_model = require("src.ui.input.route_model")
local item_slice = require("src.ui.view.item_slice")
local tip_queue = require("src.foundation.tips")
describe("TestMarketConfirmFlow", function()
after_each(function()
  runtime_ports.reset_for_tests()
  -- 拆了共享端口基线必须装回,否则 mutate 车道窄 suite 子集会撞空端口(#217)
  support.restore_runtime_services()
end)

it("test_market_open_keeps_market_canvas_visible_when_item_atlas_was_open", function()
  local events = {}
  local role1 = {
    get_roleid = function()
      return 1
    end,
    send_ui_custom_event = function(event_name)
      events[#events + 1] = event_name
    end,
  }
  runtime_ports.configure({
    resolve_role = function(role_id)
      if tostring(role_id) == "1" then
        return role1
      end
      return nil
    end,
    resolve_roles = function()
      return { role1 }
    end,
  })

  local entry = assert(market_cfg[1], "missing market config entry")
  local product_id = entry.product_id
  local state = {
    runtime_asset_context = { refs = {
      images = {
        Empty = 1,
        lv1 = 2,
        lv2 = 3,
        lv3 = 4,
        [tostring(product_id)] = 5,
      },
    } },
    ui_model = {
      current_player_id = 1,
      item_slots_by_player = { [1] = {} },
      board = { players = {} },
      panel = {},
    },
    ui = {
      market_active = false,
      current_action_role_id = 1,
      item_atlas = { open = true, role_id = 1 },
      set_label = function() end,
      set_visible = function() end,
      set_touch_enabled = function() end,
      query_node = function()
        return {
          set_texture_keep_size = function() end,
        }
      end,
    },
  }
  _bind_ui_runtime(state)

  _with_patches({
    { key = "UIManager", value = {
      client_role = nil,
      query_nodes_by_name = function()
        return {
          {
            set_texture_keep_size = function() end,
          },
        }
      end,
    } },
  }, function()
    market_modal_renderer.open_market_panel(state, {
      id = 101,
      options = {
        { id = product_id, label = entry.name, can_buy = true },
      },
      allow_cancel = true,
    }, 101)
  end, { skip_runtime_context_refresh = true })

  local last_market_event = nil
  for _, event_name in ipairs(events) do
    if event_name == "显示" .. market_nodes.canvas or event_name == "隐藏" .. market_nodes.canvas then
      last_market_event = event_name
    end
  end

  _assert_eq(state.ui.market_active, true, "market should be active after opening")
  _assert_eq(state.ui.item_atlas.open, false, "opening market should close the atlas for the acting role")
  _assert_eq(last_market_event, "显示" .. market_nodes.canvas,
    "market canvas must remain visible after closing the previously open atlas")
end)

-- 杀 screens/market.lua L140 `opened=false→true` 幸存者:没有任何可操作角色时,
-- refresh 不发生,market_active 必须保持 false —— 否则「打不开的商店」会被标成已打开,
-- 后续 close/interrupt 逻辑会对着不存在的面板走一遍。
it("test_market_open_stays_inactive_when_no_role_can_operate", function()
  local spectator_role = {
    get_roleid = function()
      return 2
    end,
    send_ui_custom_event = function() end,
  }
  runtime_ports.configure({
    resolve_role = function(role_id)
      if tostring(role_id) == "2" then
        return spectator_role
      end
      return nil
    end,
    resolve_roles = function()
      return { spectator_role }
    end,
  })

  local entry = assert(market_cfg[1], "missing market config entry")
  local state = {
    ui_model = {
      current_player_id = 1,
      -- role 2 已映射但不是当前行动玩家 → can_operate=false(观战视角)。
      item_slots_by_player = { [1] = {}, [2] = {} },
      board = { players = {} },
      panel = {},
    },
    ui = {
      market_active = false,
      current_action_role_id = 1,
      set_label = function() end,
      set_visible = function() end,
      set_touch_enabled = function() end,
      query_node = function()
        return { set_texture_keep_size = function() end }
      end,
    },
  }
  _bind_ui_runtime(state)

  _with_patches({
    { key = "UIManager", value = { client_role = nil } },
  }, function()
    market_modal_renderer.open_market_panel(state, {
      id = 101,
      options = {
        { id = entry.product_id, label = entry.name, can_buy = true },
      },
      allow_cancel = true,
    }, 101)
  end, { skip_runtime_context_refresh = true })

  _assert_eq(state.ui.market_active, false,
    "market must stay inactive when no role can operate (nothing was refreshed)")
end)

it("test_market_open_without_roles_switches_the_base_canvas_globally", function()
  local runtime_ui = require("src.ui.render.support.runtime_ui")
  local canvas = require("src.ui.coord.canvas_coordinator")
  local market_view = require("src.ui.render.market")
  local switches = {}
  local state = {
    ui_model = {
      current_player_id = 1,
      item_slots_by_player = {},
      board = { players = {} },
      panel = {},
    },
    ui = {
      market_active = false,
      current_action_role_id = 1,
      set_label = function() end,
      set_visible = function() end,
      set_touch_enabled = function() end,
      query_node = function()
        return { set_texture_keep_size = function() end }
      end,
    },
  }
  _bind_ui_runtime(state)

  _with_patches({
    { key = "UIManager", value = { client_role = nil } },
    {
      target = runtime_ui,
      key = "for_each_role_or_global",
      value = function(fn)
        fn(nil)
      end,
    },
    {
      target = canvas,
      key = "switch",
      value = function(ui, target)
        switches[#switches + 1] = { ui = ui, target = target }
      end,
    },
    {
      target = market_view,
      key = "refresh_market",
      value = function()
        return false
      end,
    },
  }, function()
    market_modal_renderer.open_market_panel(state, {
      id = 101,
      options = {},
      allow_cancel = true,
    }, 101)
  end, { skip_runtime_context_refresh = true })

  _assert_eq(#switches, 1, "a no-role open should still switch the canvas once")
end)

-- 杀 screens/market.lua L113 `require("src.ui.state.modal")→nil` 幸存者:真 modal 的
-- select_market_option 会 set_ui_dirty(true)(fallback 不会),这是选中后触发重投影的
-- 可观测契约 —— 丢了它,选中态不会刷新到画面。
it("test_market_select_option_marks_ui_dirty_via_real_modal_state", function()
  local entry = assert(market_cfg[1], "missing market config entry")
  local state = {
    ui_model = {
      current_player_id = 1,
      item_slots_by_player = { [1] = {} },
      board = { players = {} },
      panel = {},
    },
    ui = {
      set_label = function() end,
      set_visible = function() end,
      set_touch_enabled = function() end,
      query_node = function()
        return { set_texture_keep_size = function() end }
      end,
    },
  }
  _bind_ui_runtime(state)
  runtime_state.set_ui_dirty(state, false)

  _with_patches({
    { key = "UIManager", value = { client_role = nil } },
  }, function()
    market_modal_renderer.select_market_option(state, entry.product_id)
  end, { skip_runtime_context_refresh = true })

  _assert_eq(runtime_state.is_ui_dirty(state), true,
    "selecting a market option must mark ui dirty through the real modal state module")
end)

it("test_ui_intent_dispatcher_market_confirm_dispatches_directly", function()
  local captured = nil
  local state = {
    turn_action_port = {
      dispatch_action = function(_, _, action)
        captured = action
      end,
      should_block_action = function()
        return false
      end,
    },
    ui_model = {
      choice = {
        id = 12,
        kind = "market_buy",
        route_key = "market",
        options = {
          { id = 2001, label = "路障卡" },
        },
      },
    },
    ui = {
      input_blocked = false,
    },
  }
  local game = {}

  _with_patches({}, function()
    ui_intent_dispatcher.dispatch(state, game, {
      type = "market_confirm",
      choice_id = 12,
      option_id = 2001,
    }, {})
  end)

  _assert_eq(captured and captured.type, "choice_select", "market_confirm should dispatch choice_select directly")
  _assert_eq(captured and captured.choice_id, 12, "market_confirm should keep choice id")
  _assert_eq(captured and captured.option_id, 2001, "market_confirm should keep option id")
end)

it("test_ui_intent_dispatcher_market_confirm_without_pre_confirm_flag_dispatches_directly", function()
  local captured = nil
  local state = {
    turn_action_port = {
      dispatch_action = function(_, _, action)
        captured = action
      end,
      should_block_action = function()
        return false
      end,
    },
    ui_model = {
      choice = {
        id = 12,
        kind = "market_buy",
        route_key = "market",
        options = {
          { id = 2001, label = "路障卡" },
        },
      },
    },
    ui = {
      input_blocked = false,
      active_choice_screen_key = "market",
    },
  }
  local game = {}

  _with_patches({}, function()
    ui_intent_dispatcher.dispatch(state, game, {
      type = "market_confirm",
      choice_id = 12,
      option_id = 2001,
    }, {})
  end)

  _assert_eq(captured and captured.type, "choice_select",
    "market_confirm without explicit pre-confirm flag should dispatch directly")
  _assert_eq(captured and captured.choice_id, 12,
    "direct dispatch should keep market choice id when pre-confirm flag missing")
  _assert_eq(captured and captured.option_id, 2001,
    "direct dispatch should keep selected option id when pre-confirm flag missing")
end)

it("test_ui_intent_dispatcher_item_slot_dispatches_directly", function()
  local dispatched = {}
  local state = {
    turn_action_port = {
      dispatch_action = function(_, _, action)
        dispatched[#dispatched + 1] = action
      end,
      should_block_action = function()
        return false
      end,
    },
    ui_model = {
      choice = {
        id = 21,
        kind = "item_phase_passive",
        route_key = "base_inline",
        owner_role_id = 7,
        uses_item_slots = true,
        pre_confirm_before_slot_pick = true,
        options = {
          { id = 2001, label = "路障卡" },
          { id = 2002, label = "导弹卡" },
        },
      },
    },
    ui = {
      input_blocked = false,
      active_choice_screen_key = "base_inline",
    },
    game = {},
  }
  _bind_ui_runtime(state)

  _with_patches({
    { key = "UIManager", value = { client_role = nil } },
  }, function()
    ui_intent_dispatcher.dispatch(state, {}, {
      type = "ui_button",
      id = "item_slot_1",
      actor_role_id = 7,
    }, {})
  end)

  _assert_eq(#dispatched, 1, "item slot should dispatch directly without pre_confirm")
  _assert_eq(dispatched[1] and dispatched[1].type, "ui_button", "item slot should dispatch original ui_button")
  _assert_eq(pending_confirmation.is_source_active(state, pending_confirmation.SOURCE_CHOICE_SELECT), false, "item slot should not activate pre_confirm")
end)

it("test_ui_intent_dispatcher_remote_choice_skips_pre_confirm_when_disabled", function()
  local opened_pre_confirm = 0
  local dispatched = {}
  local state = {
    turn_action_port = {
      dispatch_action = function(_, _, action)
        dispatched[#dispatched + 1] = action
      end,
      should_block_action = function()
        return false
      end,
    },
    ui_model = {
      choice = {
        id = 31,
        kind = "remote_dice_value",
        route_key = "remote",
        pre_confirm_on_select = false,
        options = {
          { id = 4, label = "4" },
        },
      },
    },
    ui = {
      input_blocked = false,
      active_choice_screen_key = "remote",
    },
    game = {},
  }
  _bind_ui_runtime(state)
  state.ui_model.choice.owner_role_id = 7

  _with_patches({
    { key = "UIManager", value = { client_role = nil } },
    { target = choice_openers, key = "open_pre_confirm_screen", value = function()
      opened_pre_confirm = opened_pre_confirm + 1
    end },
  }, function()
    ui_intent_dispatcher.dispatch(state, {}, {
      type = "choice_select",
      choice_id = 31,
      option_id = 4,
      actor_role_id = 7,
    }, {})
  end)

  _assert_eq(opened_pre_confirm, 0, "remote choice with disabled pre-confirm should not open secondary confirm")
  _assert_eq(#dispatched, 1, "remote choice with disabled pre-confirm should dispatch immediately")
  _assert_eq(dispatched[1] and dispatched[1].type, "choice_select",
    "remote choice with disabled pre-confirm should dispatch choice_select")
  _assert_eq(dispatched[1] and dispatched[1].option_id, 4,
    "remote choice with disabled pre-confirm should keep selected option id")
end)

it("test_secondary_confirm_flow_opens_its_own_confirm_screen_and_dispatches_choice_select_on_confirm", function()
  local opened_pre_confirm = 0
  local dispatched = {}
  local state = {
    turn_action_port = {
      dispatch_action = function(_, _, action)
        dispatched[#dispatched + 1] = action
      end,
      should_block_action = function()
        return false
      end,
    },
    ui_model = {
      choice = {
        id = 42,
        kind = "tax_card_prompt",
        route_key = "secondary_confirm",
        requires_confirm = true,
        owner_role_id = 7,
        options = {
          { id = "use", label = "使用" },
          { id = "skip", label = "跳过" },
        },
      },
    },
    ui = {
      input_blocked = false,
      active_choice_screen_key = nil,
      set_label = function() end,
      set_button = function() end,
      choice_screens = {
        secondary_confirm = {
          root = "通用二次确认屏",
          title = "通用二次确认_标题",
          body = "通用二次确认_文本",
          confirm = "通用二次确认_确定按钮",
          cancel = "通用二次确认_取消",
        },
      },
    },
    game = {},
  }
  _bind_ui_runtime(state)

  _with_patches({
    { key = "UIManager", value = { client_role = nil } },
    { target = pre_confirm_flow, key = "enter", value = function()
      opened_pre_confirm = opened_pre_confirm + 1
    end },
  }, function()
    choice_openers.open_secondary_confirm_screen(state, state.ui_model.choice, state.ui_model.choice.id)
    _assert_eq(state.ui.active_choice_screen_key, "secondary_confirm", "secondary_confirm should open its own confirm screen")

    ui_intent_dispatcher.dispatch(state, {}, {
      type = "choice_select",
      choice_id = 42,
      option_id = "use",
      actor_role_id = 7,
    }, {})
  end)

  _assert_eq(opened_pre_confirm, 0, "secondary_confirm should not enter pre_confirm_flow")
  _assert_eq(#dispatched, 1, "secondary_confirm confirm should dispatch once")
  _assert_eq(dispatched[1] and dispatched[1].type, "choice_select", "secondary_confirm confirm should dispatch choice_select")
  _assert_eq(dispatched[1] and dispatched[1].option_id, "use", "secondary_confirm confirm should keep selected option id")
end)

it("test_market_select_still_requires_confirm_after_item_flatten", function()
  local dispatched = {}
  local selected_option = nil
  local state = {
    turn_action_port = {
      dispatch_action = function(_, _, action)
        dispatched[#dispatched + 1] = action
      end,
      should_block_action = function()
        return false
      end,
    },
    ui_model = {
      choice = {
        id = 88,
        kind = "market_buy",
        route_key = "market",
        owner_role_id = 7,
        options = {
          { id = 2001, label = "路障卡" },
        },
      },
    },
    ui = {
      input_blocked = false,
      active_choice_screen_key = "market",
      set_label = function() end,
      set_button = function() end,
      choice_screens = {
        market = {
          root = "market",
          title = "market_title",
          body = "market_body",
          confirm = "market_confirm",
          cancel = "market_cancel",
        },
      },
    },
    game = {},
  }
  _bind_ui_runtime(state)

  _with_patches({
    { key = "UIManager", value = { client_role = nil } },
    { target = market_modal_renderer, key = "select_market_option", value = function(_, option_id)
      selected_option = option_id
    end },
  }, function()
    ui_intent_dispatcher.dispatch(state, {}, {
      type = "market_select",
      option_id = 2001,
    }, {})

    _assert_eq(selected_option, 2001, "market select should update selected option first")
    _assert_eq(#dispatched, 0, "market select should not confirm immediately after item flatten")

    ui_intent_dispatcher.dispatch(state, {}, {
      type = "market_confirm",
      choice_id = 88,
      option_id = 2001,
    }, {})
  end)

  _assert_eq(#dispatched, 1, "market confirm should dispatch once after selection")
  _assert_eq(dispatched[1] and dispatched[1].type, "choice_select", "market confirm should dispatch choice_select")
  _assert_eq(dispatched[1] and dispatched[1].option_id, 2001, "market confirm should keep selected option id")
end)

it("test_ui_intent_dispatcher_item_slot_dispatches_directly_for_non_owner", function()
  local opened_pre_confirm = 0
  local dispatched = {}
  local state = {
    turn_action_port = {
      dispatch_action = function(_, _, action)
        dispatched[#dispatched + 1] = action
      end,
      should_block_action = function()
        return false
      end,
    },
    ui_model = {
      choice = {
        id = 21,
        kind = "item_phase_passive",
        route_key = "base_inline",
        owner_role_id = 7,
        uses_item_slots = true,
        pre_confirm_before_slot_pick = true,
        options = {
          { id = 2001, label = "路障卡" },
          { id = 2002, label = "导弹卡" },
        },
      },
    },
    ui = {
      input_blocked = false,
      active_choice_screen_key = "base_inline",
    },
    game = {},
  }
  _bind_ui_runtime(state)

  _with_patches({
    { key = "UIManager", value = { client_role = nil } },
    { target = choice_openers, key = "open_pre_confirm_screen", value = function()
      opened_pre_confirm = opened_pre_confirm + 1
    end },
  }, function()
    ui_intent_dispatcher.dispatch(state, {}, {
      type = "ui_button",
      id = "item_slot_1",
      actor_role_id = 7,
    }, {})
  end)

  _assert_eq(opened_pre_confirm, 0, "non-owner item slot should not open pre-confirm")
  _assert_eq(pending_confirmation.is_source_active(state, pending_confirmation.SOURCE_CHOICE_SELECT), false, "non-owner item slot should keep pre-confirm inactive")
  _assert_eq(#dispatched, 1, "non-owner item slot should continue with original action path")
  _assert_eq(dispatched[1] and dispatched[1].type, "ui_button", "non-owner item slot should dispatch original ui_button")
end)

-- ===== 槽满点击拦截(UI 本地闸,工单见提交说明) =====
-- 契约:道具槽满时点击购买按钮在 build_intent 处打回 —— tip 告知 + 不生出
-- market_confirm intent,引擎往返整段跳过;引擎侧 inventory_full 校验保留兜底。

local function _market_gate_state(owner_slots, current_view_slots)
  local by_player = {}
  if owner_slots ~= nil then
    by_player[1] = owner_slots
  end
  local state = {
    ui_model = {
      current_player_id = 1,
      item_choice_owner_id = 1,
      item_slots_by_player = by_player,
      item_slots = current_view_slots,
      market = {
        choice_id = 88,
        options = {
          { id = 2001, label = "路障卡" },
        },
      },
      board = { players = {} },
      panel = {},
    },
    ui = {},
  }
  _bind_ui_runtime(state)
  runtime_state.ensure_ui_runtime(state).pending_choice_selected_option_id = 2001
  return state
end

local function _market_confirm_spec(state)
  for _, spec in ipairs(market_modal_renderer.build_controls(state)) do
    if spec.name == market_nodes.confirm then
      return spec
    end
  end
  return nil
end

local function _with_captured_tips(fn)
  local tips = {}
  _with_patches({
    { target = tip_queue, key = "enqueue", value = function(intent)
      tips[#tips + 1] = intent
      return true
    end },
  }, function()
    fn(tips)
  end)
  return tips
end

it("test_market_confirm_blocked_with_tip_when_buyer_slots_full", function()
  local state = _market_gate_state({ "a", "b", "c", "d", "e" }, nil)
  local spec = assert(_market_confirm_spec(state), "confirm route spec should exist")

  local intent = "unset"
  local tips = _with_captured_tips(function()
    intent = spec.build_intent()
  end)

  luassert.is_nil(intent, "slots full must reject the click locally: no market_confirm intent")
  _assert_eq(#tips, 1, "slots full should enqueue exactly one rejection tip")
  _assert_eq(tips[1] and tips[1].text, "道具槽已满，无法购买",
    "rejection tip should tell the player slots are full")
end)

-- 界面未刷新时点到买满商品:UI 不再拦,意图放行给规则层下单校验兜底(ADR 0081)。
it("test_market_confirm_leaves_a_stale_maxed_click_to_the_order_check", function()
  local state = _market_gate_state({ "a", nil, "c", "d", "e" }, nil)
  runtime_state.get_ui_model(state).market.options[1].purchase_limit_reached = true
  local spec = assert(_market_confirm_spec(state), "confirm route spec should exist")

  local intent = nil
  local tips = _with_captured_tips(function()
    intent = spec.build_intent()
  end)

  _assert_eq(intent and intent.option_id, 2001, "the order check owns the maxed rejection")
  _assert_eq(#tips, 0, "no local maxed tip remains")
end)

it("test_market_confirm_passes_when_buyer_has_empty_slot", function()
  local state = _market_gate_state({ "a", nil, "c", "d", "e" }, nil)
  local spec = assert(_market_confirm_spec(state), "confirm route spec should exist")

  local intent = nil
  local tips = _with_captured_tips(function()
    intent = spec.build_intent()
  end)

  assert(intent ~= nil, "empty slot must let market_confirm through")
  _assert_eq(intent.type, "market_confirm", "unblocked click should build market_confirm")
  _assert_eq(intent.choice_id, 88, "unblocked click should keep choice id")
  _assert_eq(intent.option_id, 2001, "unblocked click should keep selected option id")
  _assert_eq(#tips, 0, "no rejection tip when a slot is free")
end)

-- 闸的槽位必须按 choice owner 取(item_slots_by_player[owner]),不能拿当前视角的
-- item_slots 凑数 —— 否则观战/视角错位时满槽会被漏判、空槽会被误判。
it("test_market_confirm_gate_reads_choice_owner_slots", function()
  local owner_full = { "a", "b", "c", "d", "e" }
  local current_view_holey = { "a", nil, nil, nil, nil }
  local state = _market_gate_state(owner_full, current_view_holey)
  local spec = assert(_market_confirm_spec(state), "confirm route spec should exist")

  local intent = "unset"
  _with_captured_tips(function()
    intent = spec.build_intent()
  end)

  luassert.is_nil(intent, "gate must judge by the choice owner's slots, not the viewing player's")
end)

-- 模型里没有任何槽位数据时放行,交给引擎侧兜底 —— 本地闸只做「确定满了」的
-- 提前打回,数据缺失不得误拦正常购买。
it("test_market_confirm_passes_when_slots_unknown", function()
  local state = _market_gate_state(nil, nil)
  local spec = assert(_market_confirm_spec(state), "confirm route spec should exist")

  local intent = nil
  local tips = _with_captured_tips(function()
    intent = spec.build_intent()
  end)

  assert(intent ~= nil, "unknown slots must fall through to the engine-side backstop")
  _assert_eq(intent.type, "market_confirm", "unknown slots should still build market_confirm")
  _assert_eq(#tips, 0, "unknown slots should not enqueue a rejection tip")
end)

-- _buyer_slots 的 model==nil 早退:ui_model 缺失(刷新窗口期)时槽位未知,
-- 本地闸必须放行、交给引擎侧兜底,不能对着 nil 模型炸索引。
it("test_market_confirm_passes_when_ui_model_is_missing", function()
  local state = { ui = {} }
  _bind_ui_runtime(state)
  runtime_state.ensure_ui_runtime(state).pending_choice_selected_option_id = 2001

  local intent = nil
  local tips = _with_captured_tips(function()
    _with_patches({
      { target = route_model, key = "market", value = function() return { choice_id = 88 } end },
      { target = runtime_state, key = "get_ui_model", value = function() return nil end },
    }, function()
      local spec = assert(_market_confirm_spec(state), "confirm route spec should exist")
      intent = spec.build_intent()
    end)
  end)

  assert(intent ~= nil, "missing ui_model must fall through to the engine-side backstop")
  _assert_eq(intent.type, "market_confirm", "missing ui_model should still build market_confirm")
  _assert_eq(#tips, 0, "missing ui_model should not enqueue a rejection tip")
end)

-- _buyer_inventory_full 的 slot_count<=0 早退:零槽配置没有可用的「满」判定,
-- 闸必须放行,不得误拦购买。
it("test_market_confirm_passes_when_slot_count_is_zero", function()
  local state = _market_gate_state({}, nil)
  local spec = assert(_market_confirm_spec(state), "confirm route spec should exist")

  local intent = nil
  local tips = _with_captured_tips(function()
    _with_patches({
      { target = item_slice, key = "resolve_slot_count", value = function() return 0 end },
    }, function()
      intent = spec.build_intent()
    end)
  end)

  assert(intent ~= nil, "zero slot count must not block the purchase")
  _assert_eq(intent.type, "market_confirm", "zero slot count should still build market_confirm")
  _assert_eq(#tips, 0, "zero slot count should not enqueue a rejection tip")
end)


end)
