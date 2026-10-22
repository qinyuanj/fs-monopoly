-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
local P = require("test.support.shared_support")
local modal_timeout = require("src.turn.waits.modal_timeout")
local function _assert_eq(actual, expected, message) luassert.is.equal(expected, actual, message) end
local _with_patches = P.with_patches
local _build_popup_view_state = P.build_popup_view_state
local runtime_port = require("src.ui.render.support.runtime_ui")
local market_view = require("src.ui.render.market")
local ui_view = require("src.ui.coord.ui_runtime")
local ui_events = require("src.ui.coord.ui_events")
local modal_presenter = require("src.ui.coord.popup_presenter")
local popup_renderer = require("src.ui.coord.popup")
local market_modal_renderer = require("src.ui.screens.market")
local event_log_ports_module = require("src.ui.ports.event_log")
local dice_nodes = require("src.ui.schema.dice")

-- 三个 renderer 的「role 扇出后还原 client_role=nil」用例共用同一套
-- 假 UIManager + 双角色扇出补丁;fn 里跑完渲染后由调用方断言 manager.client_role。
local function _with_role_cycling_manager(extra_patches, fn)
  local canvas = require("src.ui.coord.canvas_coordinator")
  local role_ctx = require("src.ui.view.role_context")
  local manager = { client_role = { stale = true } }
  local role1 = { id = 1, get_roleid = function() return 1 end }
  local role2 = { id = 2, get_roleid = function() return 2 end }

  local patches = {
    { key = "UIManager", value = manager },
    { target = runtime_port, key = "for_each_role_or_global", value = function(cb)
      cb(role1)
      cb(role2)
    end },
    { target = runtime_port, key = "set_client_role", value = function(role)
      manager.client_role = role
    end },
    { target = runtime_port, key = "with_client_role", value = function(role, cb)
      local prev = manager.client_role
      manager.client_role = role
      local ok, err = pcall(cb)
      manager.client_role = prev
      if not ok then
        error(err)
      end
    end },
    { target = role_ctx, key = "resolve", value = function(role)
      return { can_operate = role == role1 }
    end },
    { target = canvas, key = "switch_for_role", value = function() end },
    { target = canvas, key = "switch", value = function() end },
  }
  for _, patch in ipairs(extra_patches or {}) do
    patches[#patches + 1] = patch
  end
  _with_patches(patches, fn)
  return manager
end

describe("TestPopupModal", function()

  it("test_popup_timeout_closes_even_when_input_blocked", function()
    local state, nodes, query_nodes = _build_popup_view_state({
      ["Empty"] = "EMPTY",
      ["2001"] = "ICON2001",
    }, {
      set_texture_keep_size = function() end,
    })

    _with_patches({
      { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
      { key = "all_roles", value = nil },
    }, function()
      state.gameplay_loop_ports = require("src.ui.ports").build(state)
      modal_presenter.push_popup(state, {
        title = "道具卡",
        body = "测试",
        image_ref = 2001,
        auto_close_seconds = 0.1,
      })
      state.ui.input_blocked = true
      modal_timeout.step_default({}, state, 0.2)
    end)

    _assert_eq(state.ui.popup_active, false, "popup should auto close under input blocked")
    _assert_eq(nodes["卡牌展示屏"].visible, false, "popup root should hide after timeout")
  end)

  it("test_popup_defer_policy_queues_and_replays_in_order", function()
    local popup_presenter = require("src.ui.coord.popup")
    local state = {
      ui = ui_view.build_ui_state(),
      ui_dirty = false,
    }
    local shown = {}
    local hide_calls = 0
    _with_patches({
      { target = popup_presenter, key = "show", value = function(_, payload)
        shown[#shown + 1] = payload and payload.title or ""
      end },
      { target = popup_presenter, key = "hide", value = function()
        hide_calls = hide_calls + 1
      end },
      { target = popup_presenter, key = "switch_popup_canvas", value = function() end },
    }, function()
      modal_presenter.push_popup(state, { title = "A", body = "A" })
      modal_presenter.push_popup(state, { title = "B", body = "B" }, { policy = "defer" })
      _assert_eq(#shown, 1, "defer popup should not replace active popup immediately")
      _assert_eq(state.ui.popup_queue and #state.ui.popup_queue or 0, 1, "defer popup should be queued")
      modal_presenter.close_popup(state)
    end)

    _assert_eq(hide_calls, 1, "close should hide current popup once")
    _assert_eq(#shown, 2, "queued popup should be shown after close")
    _assert_eq(shown[1], "A", "first popup title should be A")
    _assert_eq(shown[2], "B", "queued popup title should be B")
  end)

  it("test_popup_close_keeps_roll_canvas_during_action_anim", function()
    local canvas = require("src.ui.coord.canvas_coordinator")
    local original_switch = canvas.switch
    local state = {
      ui = ui_view.build_ui_state(),
      ui_model = { current_player_id = 1 },
      game = {
        turn = {
          phase = "wait_action_anim",
          action_anim = { kind = "roll", seq = 2 },
        },
      },
    }
    local events = {}
    local switch_targets = {}
    state.ui.popup_active = true
    state.ui.popup_kind = "item_card"
    state.ui.popup_payload = { kind = "item_card", title = "道具卡", body = "测试" }

    _with_patches({
      { target = popup_renderer, key = "hide", value = function() end },
      { target = ui_events, key = "send_to_all", value = function(event_name)
        events[#events + 1] = event_name
      end },
      { target = canvas, key = "switch", value = function(ui, target)
        switch_targets[#switch_targets + 1] = target
        return original_switch(ui, target)
      end },
    }, function()
      modal_presenter.close_popup(state)
    end)

    _assert_eq(switch_targets[#switch_targets], dice_nodes.canvas,
      "roll action anim should restore dice canvas after popup close")
    for _, event_name in ipairs(events) do
      luassert.truthy(event_name ~= ui_events.hide[dice_nodes.canvas], "popup close during roll action anim must not hide dice canvas")
    end
  end)

  -- 回归钉(机会卡传送黑市):弹窗打开时黑市屏还没开,黑市屏在弹窗存活期间才打开
  -- (landing hold 释放后 replay 的抽卡弹窗正是这个时序)。弹窗关闭必须按「当前」
  -- market_active 回黑市屏,而不是按弹窗打开时捕获的返回屏切回基础屏——否则黑市
  -- canvas 被藏而 market_active 仍为 true,reconcile 认为已开,永不补开。
  it("test_popup_close_returns_to_market_canvas_opened_during_popup", function()
    local canvas = require("src.ui.coord.canvas_coordinator")
    local original_switch = canvas.switch
    local market_nodes = require("src.ui.schema.market")
    local state = {
      ui = ui_view.build_ui_state(),
      ui_model = { current_player_id = 1 },
      game = { turn = { phase = "wait_choice" } },
    }
    local events = {}
    local switch_targets = {}
    state.ui.popup_active = true
    state.ui.popup_kind = "chance_card"
    state.ui.popup_payload = { kind = "chance_card", title = "机会卡", body = "测试" }
    state.ui.market_active = true

    _with_patches({
      { target = popup_renderer, key = "hide", value = function() end },
      { target = ui_events, key = "send_to_all", value = function(event_name)
        events[#events + 1] = event_name
      end },
      { target = canvas, key = "switch", value = function(ui, target)
        switch_targets[#switch_targets + 1] = target
        return original_switch(ui, target)
      end },
    }, function()
      modal_presenter.close_popup(state)
    end)

    _assert_eq(switch_targets[#switch_targets], market_nodes.canvas,
      "popup close must return to market canvas when market screen is active")
    for _, event_name in ipairs(events) do
      luassert.truthy(event_name ~= ui_events.hide[market_nodes.canvas], "popup close must not hide an active market canvas")
    end
  end)

  it("test_popup_renderer_switch_popup_canvas_restores_client_role_nil", function()
    local canvas = require("src.ui.coord.canvas_coordinator")
    local manager = _with_role_cycling_manager(nil, function()
      popup_renderer.switch_popup_canvas({
        ui = {},
        ui_model = {},
      }, "card", canvas.CANVAS_POPUP, canvas.CANVAS_BASE)
    end)

    _assert_eq(manager.client_role, nil, "popup renderer should restore client_role to nil")
  end)

  it("test_market_modal_renderer_open_restores_client_role_nil", function()
    local manager = _with_role_cycling_manager({
      { target = market_view, key = "refresh_market", value = function() return true end },
    }, function()
      local state = {
        ui = {},
        ui_model = {},
        pending_choice_selected_option_id = nil,
      }
      local choice = {
        options = { { id = 1 } },
        allow_cancel = true,
        cancel_label = "取消",
      }
      market_modal_renderer.open_market_panel(state, choice, 10, nil)
    end)

    _assert_eq(manager.client_role, nil, "market modal renderer should restore client_role to nil")
  end)

  -- #583 复跑器:双角色扇出下跑真实 open_market_panel,捕获 per-role canvas 切换
  -- 与数据刷新次数;ui_overrides 直接铺进 state.ui(如 popup_active / item_atlas)。
  local function _run_open_market_panel(ui_overrides)
    local canvas = require("src.ui.coord.canvas_coordinator")
    local item_atlas_nodes = require("src.ui.schema.item_atlas")
    local switches = {}
    local refresh_calls = 0
    local state = {
      ui = ui_overrides or {},
      ui_model = {},
      pending_choice_selected_option_id = nil,
    }
    local choice = {
      options = { { id = 1 } },
      allow_cancel = true,
      cancel_label = "取消",
    }
    _with_role_cycling_manager({
      { target = market_view, key = "refresh_market", value = function()
        refresh_calls = refresh_calls + 1
        return true
      end },
      { target = canvas, key = "switch_for_role", value = function(_, target, role)
        switches[#switches + 1] = { target = target, role_id = role and role.id or nil }
      end },
    }, function()
      market_modal_renderer.open_market_panel(state, choice, 10, nil)
    end)
    return state, switches, refresh_calls, item_atlas_nodes
  end

  local function _switch_target_for(switches, role_id)
    for _, s in ipairs(switches) do
      if s.role_id == role_id then
        return s.target
      end
    end
    return nil
  end

  -- #583:弹窗存活期黑市开屏/重建不抢任何角色的 canvas(只刷新数据 + 置
  -- market_active)——收屏回屏按关闭时刻 market_active 把买家带回黑市屏。
  it("test_open_market_panel_skips_canvas_switch_while_popup_active", function()
    local canvas = require("src.ui.coord.canvas_coordinator")
    local state, switches, refresh_calls = _run_open_market_panel({ popup_active = true })

    _assert_eq(#switches, 0, "market open must not steal any role canvas while a popup is alive")
    _assert_eq(refresh_calls, 1, "operator data refresh should still run during popup")
    _assert_eq(state.ui.market_active, true,
      "market_active must be set during popup so popup close resolves back to market canvas")
    luassert.truthy(canvas.CANVAS_MARKET ~= nil, "sanity: market canvas constant available")
  end)

  -- #583:弹窗存活期黑市重建连 panel interrupt 也不跑——行动者面板早在首开/移动
  -- 打断时已清场,弹窗期重跑只会在行动者身份缺失时误关旁观者面板。
  it("test_open_market_panel_during_popup_leaves_bystander_panel_alone", function()
    require("src.ui.screens.item_atlas") -- 确保 item_atlas 的 panel closer 已注册(模块装载副作用)
    local state = _run_open_market_panel({
      popup_active = true,
      item_atlas = { open = true, role_id = 2 },
    })

    _assert_eq(state.ui.item_atlas.open, true,
      "bystander atlas panel must stay open when market rebuilds during a popup")
  end)

  -- #583:旁观者开着道具图鉴时,黑市开屏不再把他拽到基础屏——行动者进黑市,
  -- 旁观者留在自己的面板 canvas(与弹窗收屏的旁观者回屏分道同口径)。
  it("test_open_market_panel_keeps_bystander_on_own_panel_canvas", function()
    local canvas = require("src.ui.coord.canvas_coordinator")
    local _, switches, _, item_atlas_nodes = _run_open_market_panel({
      current_action_role_id = 1,
      item_atlas = { open = true, role_id = 2 },
    })

    _assert_eq(_switch_target_for(switches, 1), canvas.CANVAS_MARKET,
      "operator should land on market canvas")
    _assert_eq(_switch_target_for(switches, 2), item_atlas_nodes.canvas,
      "bystander with item atlas open should stay on atlas canvas, not be yanked to base")
  end)

  -- 对照钉:旁观者没有开着任何面板时,黑市开屏仍把他切回基础屏(既有语义不变)。
  it("test_open_market_panel_switches_panelless_bystander_to_base", function()
    local canvas = require("src.ui.coord.canvas_coordinator")
    local _, switches = _run_open_market_panel({})

    _assert_eq(_switch_target_for(switches, 1), canvas.CANVAS_MARKET,
      "operator should land on market canvas")
    _assert_eq(_switch_target_for(switches, 2), canvas.CANVAS_BASE,
      "bystander without an open panel should fall back to base canvas")
  end)

  -- #202:礼包码屏不再注册 panel_interrupt 的 closer——操作者本人的礼包码屏
  -- 黑市开屏时保持开着(不再被清场收掉),操作者照常进黑市屏。
  it("test_open_market_panel_keeps_the_operator_s_gift_code_screen_open", function()
    local canvas = require("src.ui.coord.canvas_coordinator")
    local state, switches = _run_open_market_panel({
      current_action_role_id = 1,
      gift_code = { open = true, role_id = 1 },
    })

    _assert_eq(state.ui.gift_code.open, true,
      "market open must not close the operator's gift code screen")
    _assert_eq(_switch_target_for(switches, 1), canvas.CANVAS_MARKET,
      "the operator still lands on the market canvas")
  end)

  -- #202:旁观者开着礼包码屏时黑市开屏,留在礼包码 canvas(#583 面板回屏口径)。
  it("test_open_market_panel_keeps_gift_code_bystander_on_its_canvas", function()
    local gift_code_nodes = require("src.ui.schema.gift_code")
    local _, switches = _run_open_market_panel({
      current_action_role_id = 1,
      gift_code = { open = true, role_id = 2 },
    })

    _assert_eq(_switch_target_for(switches, 2), gift_code_nodes.canvas,
      "bystander with the gift code screen open should stay on the gift code canvas")
  end)

  it("test_event_log_ports_sync_restores_client_role_nil", function()
    local ui_event_state = require("src.ui.coord.event_state")
    local ui_view_service = require("src.ui.coord.ui_runtime")
    local ports = event_log_ports_module.build()

    local manager = _with_role_cycling_manager({
      { target = runtime_port, key = "resolve_role_id", value = function(role)
        return role and role.id or nil
      end },
      { target = ui_event_state, key = "resolve_event_log_enabled", value = function(_, role_id)
        return role_id == 1
      end },
      { target = ui_view_service, key = "set_event_log_visible_for_role", value = function() end },
      { target = ui_view_service, key = "set_event_log_for_role", value = function() end },
    }, function()
      local state = {
        ui = ui_view.build_ui_state(),
        _debug_log_enabled_by_role = {},
        _debug_log_seq_by_role = {},
      }
      ports.sync_event_log(state)
    end)

    _assert_eq(manager.client_role, nil, "event log ports sync should restore client_role to nil")
  end)


end)
