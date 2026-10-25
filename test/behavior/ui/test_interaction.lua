-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local control = require("src.player.control")
local _new_game = support.new_game
local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local _bind_ui_runtime = support.bind_ui_runtime
local _with_patches = support.with_patches
local dispatch = require("src.turn.actions.action_dispatcher")
local ui_intent_dispatcher = require("src.ui.input.intent_dispatcher")
local canvas_event_router = require("src.ui.coord.canvas_event_router")
local ui_view = require("src.ui.coord.ui_runtime")
-- 文件加载期捕获(与 canvas_event_router 同代引用):套件运行期若有测试重载
-- event_bindings,函数内 require 会拿到新表,补丁打不到路由器持有的旧表(#285 同款顺序耦合)。
local event_bindings = require("src.ui.coord.event_bindings")
local market_modal_renderer = require("src.ui.screens.market")
local logger = require("src.foundation.log")
local presentation_ports = require("src.ui.ports")
local runtime_state = require("src.state.runtime")

local _build_role_with_events = support.build_role_with_events
local _has_event = support.has_event

local function _new_listenable_node()
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

-- 事件路由测试的公共环境补丁:node_map 惰性建节点,可用 extra 追加/覆盖。
local function _router_env_patches(node_map, extra, all_roles)
  local patches = {
    { key = "all_roles", value = all_roles },
    { key = "GlobalAPI", value = { show_tips = function() end } },
    { key = "UIManager", value = {
      EVENT = { CLICK = "click" },
      query_nodes_by_name = function(name)
        local node = node_map[name] or _new_listenable_node()
        node_map[name] = node
        return { node }
      end,
      client_role = nil,
    } },
  }
  for _, patch in ipairs(extra or {}) do
    patches[#patches + 1] = patch
  end
  return patches
end

-- turn_action_port 捕获型 state;返回 state 与捕获的 action 列表。
local function _make_dispatch_state(fields)
  local captured = {}
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
  }
  for key, value in pairs(fields or {}) do
    state[key] = value
  end
  return state, captured
end

local function _assert_panel_opens_without_event_actor(opts)
  local base_nodes = require("src.ui.schema.base")
  local coord_module = require(opts.coord_module_path)
  local ui_events = require("src.ui.coord.ui_events")

  local tips = {}
  local events = {}
  local role = _build_role_with_events(1, events)
  local button_node_name = base_nodes[opts.button_node_key]
  local node_map = {
    [button_node_name] = _new_listenable_node(),
  }

  _with_patches(_router_env_patches(node_map, {
    { target = logger, key = "warn", value = function() end },
    { target = ui_events, key = "roles", value = { role } },
    { target = require("src.foundation.tips"), key = "enqueue", value = function(payload)
      tips[#tips + 1] = payload and payload.text or ""
    end },
  }), function()
    -- 皮肤商店屏已无模块态(#204),只对仍有测试复位入口的屏复位。
    if type(coord_module.reset_for_tests) == "function" then
      coord_module.reset_for_tests()
    end
    local state = {
      ui = ui_view.build_ui_state(),
    }
    _bind_ui_runtime(state)
    canvas_event_router.bind(state, function()
      return {}
    end)
    node_map[button_node_name]._listener_cb({})

    local panel_state = state.ui[opts.panel_state_key]
    _assert_eq(panel_state and panel_state.open, true,
      opts.button_label .. " should open panel even when click payload lacks actor role")
    _assert_eq(_has_event(events, opts.canvas_event_name), true,
      opts.button_label .. " should show " .. opts.canvas_label .. " when actor role is unavailable")
  end)

  for _, text in ipairs(tips) do
    _assert_eq(text ~= "当前操作缺少玩家上下文，已忽略", true,
      opts.panel_label .. " open should not be rejected for missing actor")
  end
end

describe("TestInteraction", function()

after_each(function()
  -- 部分用例结尾把共享端口基线拆到未配置态,必须装回,否则 mutate 车道窄 suite 子集会撞空端口(#217)。
  support.restore_runtime_services()
end)

-- toggle_action_log 公共补丁:GameAPI/UIManager 假件,all_roles 可选。
local function _toggle_log_patches(opts, extra)
  local role = opts.role
  local patches = {
    { key = "all_roles", value = opts.all_roles },
    { key = "GameAPI", value = opts.game_api or {
      get_role = function(role_id)
        if role_id == 101 then
          return role
        end
        return nil
      end,
    } },
    { key = "UIManager", value = {
      client_role = nil,
      query_nodes_by_name = function()
        return { { visible = false } }
      end,
    } },
  }
  for _, patch in ipairs(extra or {}) do
    patches[#patches + 1] = patch
  end
  return patches
end

local function _toggle_log_state(fields)
  local loop_ports, view_command_port = support.build_presentation_ports()
  local state = {
    ui = ui_view.build_ui_state(),
    gameplay_loop_ports = loop_ports,
    view_command_port = view_command_port,
  }
  for key, value in pairs(fields or {}) do
    state[key] = value
  end
  return state
end

local function _toggle_log_intent()
  return { type = "toggle_action_log", actor_role_id = 101 }
end

it("test_ui_intent_dispatcher_routes_market_select_and_popup_confirm_to_view_side", function()
  local selected_option = nil
  local closed = 0
  local loop_ports, view_command_port = support.build_presentation_ports()
  local state = {
    ui = {
      input_blocked = false,
    },
    gameplay_loop_ports = loop_ports,
    view_command_port = view_command_port,
  }
  local game = {}

  _with_patches({
    { target = market_modal_renderer, key = "select_market_option", value = function(_, option_id)
      selected_option = option_id
    end },
    { target = require("src.ui.coord.popup_presenter"), key = "close_popup", value = function()
      closed = closed + 1
    end },
  }, function()
    ui_intent_dispatcher.dispatch(state, game, {
      type = "market_select",
      option_id = 99,
    }, {})
    ui_intent_dispatcher.dispatch(state, game, {
      type = "popup_confirm",
    }, {})
  end)

  _assert_eq(selected_option, 99, "market_select should update selected option")
  _assert_eq(closed, 1, "popup_confirm should close popup once")
end)

it("test_ui_intent_dispatcher_toggle_action_log_uses_actor_role_context", function()
  local state = _toggle_log_state()
  local game = {}
  local role = _build_role_with_events(101, {})
  _with_patches(_toggle_log_patches({ role = role, all_roles = { role } }), function()
    ui_intent_dispatcher.dispatch(state, game, _toggle_log_intent(), {})
    _assert_eq(state.ui.debug_visible_by_role[101], true, "toggle_action_log should enable action_log for actor role")
    _assert_eq(UIManager.client_role, nil, "toggle_action_log should restore client role")

    ui_intent_dispatcher.dispatch(state, game, _toggle_log_intent(), {})
    _assert_eq(state.ui.debug_visible_by_role[101], false, "toggle_action_log second click should disable action_log")
    _assert_eq(UIManager.client_role, nil, "toggle_action_log second click should restore client role")
  end)
end)

it("test_ui_intent_dispatcher_toggle_action_log_ignores_block_without_game", function()
  local dispatch_calls = 0
  local state = _toggle_log_state({
    turn_action_port = {
      dispatch_action = function()
        dispatch_calls = dispatch_calls + 1
      end,
      should_block_action = function()
        return true
      end,
    },
  })
  local role = _build_role_with_events(101, {})

  _with_patches(_toggle_log_patches({ role = role, all_roles = { role } }), function()
    ui_intent_dispatcher.dispatch(state, nil, _toggle_log_intent(), {})
  end)

  _assert_eq(dispatch_calls, 0, "toggle_action_log should not dispatch gameplay action")
  _assert_eq(state.ui.debug_visible_by_role[101], true, "toggle_action_log should bypass block without game")
end)

it("test_ui_intent_dispatcher_toggle_action_log_resolves_role_via_game_api", function()
  local events = {}
  local state = _toggle_log_state()
  local role = _build_role_with_events(101, events)

  _with_patches(_toggle_log_patches({ role = role, all_roles = nil }), function()
    ui_intent_dispatcher.dispatch(state, {}, _toggle_log_intent(), {})
  end)

  luassert.truthy(_has_event(events, "显示日志屏"), "toggle_action_log should send 显示日志屏 via GameAPI role fallback")
  _assert_eq(state.ui.debug_visible_by_role[101], true, "toggle_action_log should enable role debug state")
end)

it("test_ui_intent_dispatcher_toggle_action_log_warns_when_role_event_channel_missing", function()
  local warn_count = 0
  local state = _toggle_log_state()
  local ok = false

  _with_patches(_toggle_log_patches({ all_roles = nil, game_api = {} }, {
    { target = logger, key = "warn", value = function(...)
      if tostring((...)) == "toggle_action_log missing role event channel:" then
        warn_count = warn_count + 1
      end
    end },
  }), function()
    ok = pcall(function()
      ui_intent_dispatcher.dispatch(state, {}, _toggle_log_intent(), {})
    end)
  end)

  luassert.truthy(ok == true, "toggle_action_log should not crash when role event channel is missing")
  _assert_eq(state.ui.debug_visible_by_role[101], true, "toggle_action_log should still toggle debug state")
  _assert_eq(warn_count, 1, "toggle_action_log should warn once when role cannot send ui event")
end)

it("test_ui_intent_dispatcher_auto_button_actor_resolution_scenarios", function()
  -- 显式 actor 优先于本地 role;本地 role 缺失回退 intent actor;两者皆缺拒发。
  local scenarios = {
    {
      client_role = { get_roleid = function() return 1 end },
      intent_actor = 2,
      expect_actor = 2,
      message = "auto dispatch should keep explicit actor role id",
    },
    {
      client_role = nil,
      intent_actor = 2,
      expect_actor = 2,
      message = "auto dispatch should fallback to intent actor when local role missing",
    },
    {
      client_role = nil,
      intent_actor = nil,
      expect_actor = nil,
      message = "auto dispatch should be rejected when actor role is missing",
    },
  }

  for _, scenario in ipairs(scenarios) do
    local state, captured = _make_dispatch_state({
      ui = {
        input_blocked = false,
      },
    })

    _with_patches({
      { key = "UIManager", value = { client_role = scenario.client_role } },
    }, function()
      ui_intent_dispatcher.dispatch(state, {}, {
        type = "ui_button",
        id = "auto",
        actor_role_id = scenario.intent_actor,
      }, {})
    end)

    _assert_eq(captured[1] and captured[1].actor_role_id, scenario.expect_actor, scenario.message)
    -- 拒绝场景必须一条都不送达;放行场景恰好一条。期望来自场景表,无条件断言。
    _assert_eq(#captured, scenario.expect_actor == nil and 0 or 1, scenario.message)
  end
end)

it("test_ui_intent_dispatcher_auto_button_honors_intent_actor_during_other_turn", function()
  local g = _new_game()
  g.turn.current_player_index = 1
  local state = {
    turn_action_port = {
      dispatch_action = function(game, state_ctx, action, opts)
        return dispatch.dispatch_action(game, state_ctx, action, opts)
      end,
      should_block_action = function()
        return false
      end,
    },
    ui = {
      input_blocked = false,
    },
  }
  local local_role = {
    get_roleid = function()
      return 2
    end,
  }
  local before_1 = control.is_delegated(g.players[1])
  local before_2 = control.is_delegated(g.players[2])

  _with_patches({
    { key = "UIManager", value = { client_role = local_role } },
  }, function()
    ui_intent_dispatcher.dispatch(state, g, {
      type = "ui_button",
      id = "auto",
      actor_role_id = 1,
    }, {})
  end)

  _assert_eq(control.is_delegated(g.players[1]), not before_1, "auto click should toggle explicit actor role auto state")
  _assert_eq(control.is_delegated(g.players[2]), before_2, "auto click should not be rewritten to local role")
end)

it("test_ui_event_router_rejects_next_without_trusted_actor", function()
  -- current_player_id 不是可信 actor 来源:无 event/client/cached actor 一律拒发;
  -- 拒发经 reject_missing_actor 无条件弹一次提示。
  -- vacuous-branch 修平时实测:场景一(current_player_id 在场但解析失败)同样弹 1 次,
  -- 原 expect_tips = 0 是从未被断言的空转数据,先按实测钉 1;若产品意图是
  -- 「有 current_player_id 就不弹」,应另开单改实现。
  local base_nodes = require("src.ui.schema.base")
  local scenarios = {
    { current_player_id = "2", expect_tips = 1,
      message = "next click without event/client/cached actor should not dispatch" },
    { current_player_id = nil, expect_tips = 1,
      message = "next click without actor context should be rejected" },
  }

  for _, scenario in ipairs(scenarios) do
    local show_tip_calls = 0
    local node_map = {
      [base_nodes.action_button] = _new_listenable_node(),
    }

    _with_patches(_router_env_patches(node_map, {
      { target = logger, key = "warn", value = function() end },
      { key = "GlobalAPI", value = { show_tips = function()
        show_tip_calls = show_tip_calls + 1
      end } },
    }), function()
      local state, captured = _make_dispatch_state({
        ui_model = { current_player_id = scenario.current_player_id },
      })
      _bind_ui_runtime(state)
      canvas_event_router.bind(state, function()
        return {}
      end)
      node_map[base_nodes.action_button]._listener_cb({})

      _assert_eq(#captured, 0, scenario.message)
    end)
    -- expect_tips 由场景表钉死(0 或 1),无条件断言:0 场景也真的验证「不弹提示」。
    _assert_eq(show_tip_calls, scenario.expect_tips,
      "next click tip count must match scenario expectation")
  end
end)

it("test_ui_event_router_opens_skin_panel_without_event_actor", function()
  _assert_panel_opens_without_event_actor({
    coord_module_path = "src.ui.screens.skin_panel",
    button_node_key = "skin_button",
    panel_state_key = "skin_panel",
    canvas_event_name = "显示皮肤商店",
    button_label = "skin button",
    panel_label = "skin panel",
    canvas_label = "the skin shop canvas",
  })
end)

it("test_ui_event_router_opens_gallery_panel_without_event_actor", function()
  _assert_panel_opens_without_event_actor({
    coord_module_path = "src.ui.screens.item_atlas",
    button_node_key = "gallery_button",
    panel_state_key = "item_atlas",
    canvas_event_name = "显示道具图鉴",
    button_label = "gallery button",
    panel_label = "gallery panel",
    canvas_label = "the atlas canvas",
  })
end)

it("test_ui_event_router_item_atlas_arrows_move_pages", function()
  local item_atlas = require("src.ui.screens.item_atlas")
  local item_atlas_nodes = require("src.ui.schema.item_atlas")

  local function make_catalog(count)
    local catalog = {}
    for index = 1, count do
      catalog[index] = { id = "item_" .. tostring(index) }
    end
    return catalog
  end

  local events = {}
  local role = _build_role_with_events(1, events)
  local node_map = {
    [item_atlas_nodes.page_next] = _new_listenable_node(),
    [item_atlas_nodes.page_prev] = _new_listenable_node(),
  }

  _with_patches(_router_env_patches(node_map, {
    { target = logger, key = "warn", value = function() end },
  }, { role }), function()
    item_atlas.configure_catalog_for_tests(make_catalog(16))
    local state = {
      ui = ui_view.build_ui_state(),
    }
    _bind_ui_runtime(state)
    item_atlas.open(state, 1)
    canvas_event_router.bind(state, function()
      return {}
    end)

    node_map[item_atlas_nodes.page_next]._listener_cb({ role = role })
    _assert_eq(state.ui.item_atlas.page_index, 2,
      "clicking atlas next button through the router should advance to page 2")

    node_map[item_atlas_nodes.page_prev]._listener_cb({ role = role })
    _assert_eq(state.ui.item_atlas.page_index, 1,
      "clicking atlas prev button through the router should return to page 1")
  end)
  item_atlas.reset_for_tests()
end)

it("test_ui_event_router_turn_bound_actor_without_identity_is_rejected", function()
  -- #341:turn-bound 事件解析不出身份(data.role 缺失、client_role 缺位、缓存退路
  -- 已拆)→ intent 拒收(warn + 缺失玩家上下文提示),不得拿上次点击者缓存顶替。
  local base_nodes = require("src.ui.schema.base")
  local node_map = {
    [base_nodes.action_button] = _new_listenable_node(),
  }
  local captured
  local warns = {}
  local tips = {}

  _with_patches(_router_env_patches(node_map, {
    {
      target = logger,
      key = "warn",
      value = function(...)
        warns[#warns + 1] = table.concat({ ... }, " ")
      end,
    },
    {
      target = require("src.foundation.tips"),
      key = "enqueue",
      value = function(payload)
        tips[#tips + 1] = payload and payload.text or ""
        return true
      end,
    },
  }), function()
    local state
    state, captured = _make_dispatch_state({
      ui_model = { current_player_id = "2" },
    })
    _bind_ui_runtime(state)
    canvas_event_router.bind(state, function()
      return {}
    end)
    node_map[base_nodes.action_button]._listener_cb({})
  end)

  _assert_eq(#captured, 0, "turn-bound click without identity must not dispatch")
  _assert_eq(#warns >= 1, true, "rejected actor must leave a warn")
  _assert_eq(#tips >= 1, true, "rejected actor must enqueue the missing-actor tip")
end)

it("test_local_actor_resolver_client_role_resolves_without_writing_any_cache", function()
  local local_actor_resolver = require("src.ui.render.support.local_actor_resolver")
  local client_role = {
    get_roleid = function()
      return 3
    end,
  }

  _with_patches({
    { key = "all_roles", value = nil },
    { key = "GlobalAPI", value = { show_tips = function() end } },
    { key = "UIManager", value = { client_role = client_role } },
  }, function()
    local state = {
      ui_model = {
        current_player_id = "2",
      },
    }
    _bind_ui_runtime(state)
    local resolved = local_actor_resolver.resolve_turn_bound(state)
    _assert_eq(resolved, 3, "turn-bound actor resolution should keep explicit client role ahead of current_player_id")
    _assert_eq(state.local_actor_role_id, nil,
      "resolution must not write the retired local actor cache (#601)")
  end)
end)

it("test_camera_follow_uses_current_player_display_fallback_without_caching_actor", function()
  local camera_sync = require("src.ui.ports.ui_sync")._camera
  local runtime_ports = require("src.foundation.ports.runtime_ports")
  local reset_calls = 0
  local follow_target = nil
  local role = {
    reset_camera = function()
      reset_calls = reset_calls + 1
      return true
    end,
  }
  local state = {
    game = {
      turn = { current_player_index = 2 },
      players = {
        { id = 1 },
        { id = 2 },
      },
    },
  }

  runtime_ports.configure({
    resolve_role = function(role_id)
      if role_id == 2 then
        return role
      end
      return nil
    end,
    resolve_camera_helper = function()
      return {
        follow = function(player_id)
          follow_target = player_id
          return true
        end,
      }
    end,
  })

  local ok, err = pcall(function()
    _assert_eq(camera_sync.follow_camera(state, 2), true,
      "camera should use current player as display fallback when local actor is unknown")
    _assert_eq(follow_target, 2, "camera helper should still follow current player")
    _assert_eq(reset_calls, 1, "camera should reset current player's camera to self")
    _assert_eq(state.local_actor_role_id, nil,
      "camera display fallback must not write the retired local actor cache (#601)")
  end)
  runtime_ports.reset_for_tests()
  if not ok then
    error(err)
  end
end)

it("test_ui_event_router_injects_actor_for_market_confirm_and_cancel", function()
  local market_nodes = require("src.ui.schema.market")
  local node_map = {
    [market_nodes.confirm] = _new_listenable_node(),
    [market_nodes.close] = _new_listenable_node(),
  }
  local captured

  _with_patches(_router_env_patches(node_map), function()
    local state
    state, captured = _make_dispatch_state({
      ui_model = {
        current_player_id = "3",
        choice = {
          id = 12,
          kind = "market_buy",
          route_key = "market",
          allow_cancel = true,
          options = { { id = 34, label = "X" } },
        },
        market = {
          choice_id = 12,
          options = { { id = 34, label = "X" } },
        },
      },
      pending_choice_selected_option_id = 34,
    })
    _bind_ui_runtime(state)
    canvas_event_router.bind(state, function()
      return {}
    end)
    -- 身份随事件数据携带(#341):匿名点击不再回落缓存注入 actor。
    local role3 = { get_roleid = function() return 3 end }
    node_map[market_nodes.confirm]._listener_cb({ role = role3 })
    node_map[market_nodes.close]._listener_cb({ role = role3 })
  end)

  _assert_eq(captured[1] and captured[1].type, "choice_select", "market_confirm should dispatch choice_select")
  _assert_eq(captured[1] and captured[1].choice_id, 12, "market_confirm should keep choice id")
  _assert_eq(captured[1] and captured[1].option_id, 34, "market_confirm should keep option id")
  _assert_eq(captured[1] and captured[1].actor_role_id, 3, "market_confirm should inject actor_role_id")
  _assert_eq(captured[2] and captured[2].type, "choice_cancel", "market_close should dispatch choice_cancel")
  _assert_eq(captured[2] and captured[2].choice_id, 12, "market_close should keep choice id")
  _assert_eq(captured[2] and captured[2].actor_role_id, 3, "market_close should inject actor_role_id")
end)

it("test_ui_event_router_market_background_click_equals_close_click_for_operator_and_spectator", function()
  -- #178 点背景关闭:操作者与旁观者点黑市背景,派发的意图(含 actor)与点关闭按钮逐字段一致,
  -- 权限由回合层对同一 choice_cancel 的同一校验裁定。
  local market_nodes = require("src.ui.schema.market")
  local node_map = {
    [market_nodes.close] = _new_listenable_node(),
    [market_nodes.background] = _new_listenable_node(),
  }
  local captured

  _with_patches(_router_env_patches(node_map), function()
    local state
    state, captured = _make_dispatch_state({
      ui_model = {
        current_player_id = "3",
        choice = {
          id = 12,
          kind = "market_buy",
          route_key = "market",
          allow_cancel = true,
          options = { { id = 34, label = "X" } },
        },
        market = {
          choice_id = 12,
          options = { { id = 34, label = "X" } },
        },
      },
    })
    _bind_ui_runtime(state)
    canvas_event_router.bind(state, function()
      return {}
    end)
    local operator = { get_roleid = function() return 3 end }
    local spectator = { get_roleid = function() return 4 end }
    node_map[market_nodes.close]._listener_cb({ role = operator })
    node_map[market_nodes.background]._listener_cb({ role = operator })
    node_map[market_nodes.close]._listener_cb({ role = spectator })
    node_map[market_nodes.background]._listener_cb({ role = spectator })
  end)

  _assert_eq(#captured, 4, "every close/background click must reach the dispatcher")
  _assert_eq(captured[1].type, "choice_cancel", "operator close dispatches choice_cancel")
  _assert_eq(captured[1].actor_role_id, 3, "operator close carries operator actor")
  luassert.same(captured[1], captured[2], "operator background click must equal operator close click")
  _assert_eq(captured[3].actor_role_id, 4, "spectator close carries spectator actor")
  luassert.same(captured[3], captured[4], "spectator background click must equal spectator close click")
end)

it("test_ui_event_router_optional_end_button_blocked_when_choice_modal_open", function()
  local base_nodes = require("src.ui.schema.base")
  local modal = require("src.ui.coord.modal")
  local role = { get_roleid = function() return 5 end }
  local closed = 0
  local dispatched = {}
  local node_map = {
    [base_nodes.action_button] = _new_listenable_node(),
    [base_nodes.end_button] = _new_listenable_node(),
  }
  local action_node = node_map[base_nodes.action_button]
  local end_node = node_map[base_nodes.end_button]

  _with_patches(_router_env_patches(node_map, {
    { target = modal, key = "close_choice_modal", value = function(ctx)
      closed = closed + 1
      _assert_eq(ctx.ui.choice_active, true, "close callback should receive router state")
    end },
  }), function()
    local state = {
      ui = ui_view.build_ui_state(),
      ui_model = {
        choice = {
          id = 11,
          kind = "item_phase_passive",
        },
      },
      turn_action_port = {
        should_block_action = function()
          return false
        end,
        dispatch_action = function(_, state_arg, action, opts)
          dispatched[#dispatched + 1] = action
          _assert_eq(type(opts.on_close_choice), "function",
            "router should pass close-choice dispatch option")
          opts.on_close_choice(state_arg)
        end,
      },
    }
    state.ui.choice_active = true
    _bind_ui_runtime(state)

    canvas_event_router.bind(state, function()
      return {}
    end)
    action_node._listener_cb({ role = role })
    end_node._listener_cb({ role = role })
  end)

  _assert_eq(#dispatched, 0, "optional end button should not dispatch while a choice modal is open")
  _assert_eq(closed, 0, "choice modal should stay open when end button is blocked")
end)

it("test_ui_event_router_optional_landing_end_button_dispatches_completion_intent", function()
  local route_base = require("src.ui.input.route_base")
  local base_nodes = require("src.ui.schema.base")
  local state = {
    ui_runtime = {
      ui_model = {
        choice = {
          id = 12,
          kind = "landing_optional_effect",
          allow_cancel = true,
        },
      },
    },
  }
  local specs = route_base.build(state)
  local end_spec = nil
  local action_spec = nil
  for _, spec in ipairs(specs) do
    if spec.name == base_nodes.end_button then end_spec = spec end
    if spec.name == base_nodes.action_button then action_spec = spec end
  end

  local action_intent = action_spec and action_spec.build_intent()
  local end_intent = end_spec and end_spec.build_intent()

  _assert_eq(action_intent, nil, "landing optional phase should not route through action button")
  _assert_eq(end_intent and end_intent.type, "complete_optional_action_phase",
    "landing optional end button should dispatch completion intent")
  _assert_eq(end_intent and end_intent.choice_id, nil,
    "landing optional end button should not expose choice id")
end)

it("test_route_base_non_cancelable_optional_choice_routes_no_base_progression", function()
  local route_base = require("src.ui.input.route_base")
  local base_nodes = require("src.ui.schema.base")
  local state = {
    ui_runtime = {
      ui_model = {
        choice = {
          id = 13,
          kind = "item_phase_passive",
          allow_cancel = false,
        },
      },
    },
    ui = {
      input_blocked = false,
    },
  }
  local action_spec = nil
  local end_spec = nil
  for _, spec in ipairs(route_base.build(state)) do
    if spec.name == base_nodes.action_button then action_spec = spec end
    if spec.name == base_nodes.end_button then end_spec = spec end
  end

  _assert_eq(action_spec and action_spec.build_intent(), nil,
    "non-cancelable optional choice should not route through action button")
  _assert_eq(end_spec and end_spec.build_intent(), nil,
    "non-cancelable optional choice should not dispatch optional completion")
end)

it("test_route_base_input_lock_blocks_optional_end_intent", function()
  local route_base = require("src.ui.input.route_base")
  local base_nodes = require("src.ui.schema.base")
  local state = {
    ui_runtime = {
      ui_model = {
        choice = {
          id = 14,
          kind = "item_phase_passive",
          allow_cancel = true,
        },
      },
    },
    ui = {
      input_blocked = true,
    },
  }
  local end_spec = nil
  for _, spec in ipairs(route_base.build(state)) do
    if spec.name == base_nodes.end_button then
      end_spec = spec
    end
  end

  _assert_eq(end_spec and end_spec.build_intent(), nil,
    "input lock should block optional end button dispatch")
end)

it("test_ui_sync_ports_rebuilds_model_before_reopening_choice", function()
  local ui_sync_ports = require("src.ui.ports.ui_sync")
  local runtime_state_local = require("src.state.runtime")
  local rebuilt = {
    choice = { id = 42, kind = "remote", route_key = "remote", options = { { id = 1, label = "A" } } },
    market = { choice_id = 42 },
  }
  local state = {
    ui = ui_view.build_ui_state(),
    ui_model = {
      choice = { id = 1 },
    },
  }
  local opened_choice = nil
  local opened_market = nil

  _with_patches({
    { target = require("src.ui.ports.ui_sync")._choice_state, key = "should_reconcile", value = function()
      return true
    end },
    { target = require("src.ui.ports.ui_sync")._model, key = "build_model", value = function()
      return rebuilt
    end },
    { target = require("src.ui.coord.modal"), key = "open_choice_modal", value = function(_, choice, market)
      opened_choice = choice
      opened_market = market
    end },
  }, function()
    ui_sync_ports.build({
      get_ui_state = function(current_state)
        return current_state.ui
      end,
      log_once = function() end,
      build_log_prefix = function() return "[test]" end,
    }).on_pending_choice({}, state, { id = 42 })
  end)

  _assert_eq(runtime_state_local.get_ui_model(state), rebuilt, "ui sync should cache rebuilt model before reopening")
  _assert_eq(opened_choice, rebuilt.choice, "ui sync should reopen with rebuilt choice view")
  _assert_eq(opened_market, rebuilt.market, "ui sync should reopen with rebuilt market view")
  _assert_eq(runtime_state_local.is_ui_dirty(state), true, "ui sync should mark ui dirty when pending choice arrives")
end)

it("test_ui_sync_ports_defers_pending_choice_during_wait_landing_visual", function()
  local ui_sync_ports = require("src.ui.ports.ui_sync")
  local rebuilt = {
    current_player_id = 1,
    choice = { id = 43, kind = "market_buy", route_key = "market", owner_role_id = 1, options = { { id = 1, label = "A" } } },
    market = { choice_id = 43 },
  }
  local state = {
    ui = ui_view.build_ui_state(),
    ui_model = rebuilt,
  }
  local game = {
    turn = {
      phase = "wait_landing_visual",
      current_player_index = 1,
    },
    players = {
      [1] = { id = 1, name = "P1", auto = false, is_ai = false },
    },
  }
  local opened = 0

  function game:find_player_by_id(player_id)
    return self.players[player_id]
  end

  _with_patches({
    { target = require("src.ui.ports.ui_sync")._model, key = "build_model", value = function()
      return rebuilt
    end },
    { target = require("src.ui.coord.modal"), key = "open_choice_modal", value = function()
      opened = opened + 1
    end },
  }, function()
    ui_sync_ports.build({
      get_ui_state = function(current_state)
        return current_state.ui
      end,
      log_once = function() end,
      build_log_prefix = function() return "[test]" end,
    }).on_pending_choice(game, state, rebuilt.choice)
  end)

  _assert_eq(opened, 0, "on_pending_choice should defer market modal during wait_landing_visual")
end)

it("test_event_log_view_global_and_role_paths_preserve_state", function()
  local event_log_view = require("src.ui.coord.event_log_view")
  local runtime_ui = require("src.ui.render.support.runtime_ui")
  local state = {
    ui = ui_view.build_ui_state(),
  }
  local role = {
    get_roleid = function()
      return 7
    end,
  }
  local calls = {}

  state.ui.set_event_log = function(_, text)
    calls[#calls + 1] = { kind = "log", text = text }
  end
  state.ui.set_event_log_visible = function(_, visible)
    calls[#calls + 1] = { kind = "visible", value = visible }
  end

  _with_patches({
    { target = runtime_ui, key = "get_client_role", value = function() return nil end },
  }, function()
    event_log_view.set_event_log(state, "all")
    _assert_eq(event_log_view.set_event_log_visible(state, true), true, "global event log path should succeed without role")
  end)

  _with_patches({
    { target = runtime_ui, key = "resolve_role_id", value = function()
      return 7
    end },
  }, function()
    _assert_eq(event_log_view.set_event_log_visible_for_role(state, role, false), true,
      "role event log path should persist visibility by role")
    event_log_view.set_event_log_for_role(state, role, "role only")
  end)

  _assert_eq(state.ui.debug_visible, true, "global path should keep ui.debug_visible in sync")
  _assert_eq(state.ui.debug_visible_by_role[7], false, "role path should persist event log visibility by role")
  _assert_eq(state.ui.debug_log_enabled_by_role[7], false, "role path should persist event log flag by role")
  _assert_eq(calls[1].text, "all", "global log path should pass through text")
  _assert_eq(calls[#calls].text, "role only", "role log path should pass through text")
end)

it("test_event_log_view_tolerates_missing_ui_and_unresolved_roles", function()
  local event_log_view = require("src.ui.coord.event_log_view")
  local runtime_ui = require("src.ui.render.support.runtime_ui")
  local role = { get_roleid = function() return 7 end }

  _assert_eq(event_log_view.set_event_log_visible_for_role({}, role, true), false,
    "role path without ui should return false")
  _assert_eq(event_log_view.set_event_log_visible({}, true), false,
    "global path without ui should return false")

  _with_patches({
    { target = runtime_ui, key = "resolve_role_id", value = function() return nil end },
  }, function()
    local state = { ui = { set_event_log_visible = function() end } }
    _assert_eq(event_log_view.set_event_log_visible_for_role(state, role, true), false,
      "unresolved role id should return false")
  end)
end)

it("test_event_log_view_routes_to_role_path_when_a_client_role_exists", function()
  local event_log_view = require("src.ui.coord.event_log_view")
  local runtime_ui = require("src.ui.render.support.runtime_ui")
  local visible_writes = {}
  local role = { get_roleid = function() return 7 end }
  local state = {
    ui = {
      set_event_log_visible = function(_, visible)
        visible_writes[#visible_writes + 1] = visible
      end,
    },
  }

  _with_patches({
    { target = runtime_ui, key = "get_client_role", value = function() return role end },
    { target = runtime_ui, key = "resolve_role_id", value = function() return 7 end },
  }, function()
    _assert_eq(event_log_view.set_event_log_visible(state, true), true,
      "a client role should route the global call into the role path")
  end)

  luassert.truthy(#visible_writes == 1 and visible_writes[1] == true,
    "the role path should drive the host visibility hook")
end)

it("test_actor_context_and_host_runtime_fallbacks", function()
  local actor_context = require("src.ui.coord.actor_context")
  local host_runtime_local = require("src.host")
  local runtime_ui = require("src.ui.render.support.runtime_ui")
  local runtime_context = require("src.host.context")
  local listed_role = {
    get_roleid = function()
      return 3
    end,
  }
  local fallback_role = {
    get_roleid = function()
      return 4
    end,
  }
  local client_role = {
    get_roleid = function()
      return 99
    end,
  }
  local handler = function() end
  local registered = nil

  _with_patches({
    { target = require("src.host.role_resolver"), key = "resolve_roles", value = function()
      return { listed_role }
    end },
    { target = require("src.host.role_resolver"), key = "resolve_role_with", value = function(role_id)
      if role_id == 4 then
        return fallback_role
      end
      return nil
    end },
    { target = runtime_ui, key = "get_client_role", value = function()
      return client_role
    end },
    { target = runtime_ui, key = "resolve_role_id", value = function(role)
      return role and role.get_roleid and role:get_roleid() or nil
    end },
    { target = runtime_context, key = "current", value = function()
      return {
        env = {
          LuaAPI = {
            global_register_custom_event = function(event_name, fn)
              registered = { name = event_name, handler = fn }
            end,
          },
        },
      }
    end },
  }, function()
    _assert_eq(actor_context.resolve_role_by_id(nil), client_role, "nil role id should fall back to client role")
    _assert_eq(actor_context.resolve_role_by_id(3), listed_role, "actor context should prefer resolved role list")
    local resolved_fallback = actor_context.resolve_role_by_id(4)
    if resolved_fallback == nil then
      error("actor context should fall back to resolve_role")
    end
    _assert_eq(resolved_fallback:get_roleid(), 4, "actor context should fall back to resolve_role")
    local synthetic = actor_context.resolve_role_by_id(5)
    if synthetic == nil or type(synthetic.get_roleid) ~= "function" then
      error("actor context should synthesize missing roles")
    end
    _assert_eq(synthetic:get_roleid(), 5, "synthetic role should preserve requested role id")
    _assert_eq(host_runtime_local.register_custom_event("evt", handler), true,
      "host runtime should register custom event when LuaAPI exists")
  end)

  if registered == nil then
    error("host runtime should keep registered event payload")
  end
  _assert_eq(registered.name, "evt", "host runtime should pass event name through")
  _assert_eq(registered.handler, handler, "host runtime should pass handler through")
  _assert_eq(host_runtime_local.register_custom_event(nil, handler), false,
    "host runtime should reject invalid event name")
end)

it("test_choice_ui_state_gate_honors_room_seated_owner_only", function()
  -- 门控不吃 current_player 回退:只有落在房间席位名册内的 owner 才开共享确认 UI。
  -- 判定源是 resolve_roles 名册(#444);client_role 不参与,点击者缓存已随 #601 退役(#341)。
  local choice_ui_state = require("src.ui.ports.ui_sync")._choice_state
  local runtime_ui = require("src.ui.render.support.runtime_ui")
  local runtime_ports = require("src.foundation.ports.runtime_ports")

  local function _resolve_gate(opts)
    local players = {
      { id = 1, is_ai = false, auto = false },
      { id = 2, is_ai = false, auto = false },
    }
    local state = {
      ui = ui_view.build_ui_state(),
    }
    _bind_ui_runtime(state)
    runtime_state.set_ui_model(state, {
      current_player_id = opts.current_player_id,
    })
    local choice = {
      id = opts.choice_id,
      kind = "market_buy",
      route_key = "market",
      owner_role_id = 2,
    }
    local game = {
      turn = {
        current_player_index = opts.current_player_id,
        phase = "wait_choice",
      },
      players = players,
    }
    game.find_player_by_id = function(_, role_id)
      for _, player in ipairs(players) do
        if player.id == role_id then
          return player
        end
      end
      return nil
    end

    local gate
    _with_patches({
      {
        target = runtime_ui,
        key = "get_client_role",
        value = function()
          return opts.client_role_id and { get_roleid = function() return opts.client_role_id end } or nil
        end,
      },
      -- 席位名册即房间席位:owner_role_id=2 落在名册内才开面板。单字段 patch
      -- 而非 runtime_ports.configure:后者整表替换,会清空同表其他端口。
      {
        target = runtime_ports,
        key = "resolve_roles",
        value = function()
          return { { get_roleid = function() return opts.seated_role_id end } }
        end,
      },
    }, function()
      gate = choice_ui_state.resolve_gate_state(game, state, choice)
    end)
    return gate
  end

  -- owner_role_id 恒为 2。#444 后门控只问「owner 是否本进程服务的席位」:
  -- 名册只坐 1 时拒(且 current_player=2 的展示态不得越权放行),名册坐 2 时放行。
  -- client_role 两例都给了值且与 owner 不一致/一致,用来钉死它不再参与判定。
  local unseated = _resolve_gate({ client_role_id = 1, seated_role_id = 1, current_player_id = 2, choice_id = 12 })
  _assert_eq(unseated.served_owner, false, "choice gate should reject current player fallback for an unseated owner")
  _assert_eq(unseated.expects_ui, false, "shared market choice should stay hidden when owner has no room seat")

  local seated = _resolve_gate({ client_role_id = 1, seated_role_id = 2, current_player_id = 1, choice_id = 13 })
  _assert_eq(seated.served_owner, true, "choice gate should honor an owner seated in the room roster")
  _assert_eq(seated.expects_ui, true, "seated owner should still open shared confirm UI")
end)

-- #210：展示端口装配不提供 clock 分组；回合时钟由回合层基础 clock 委派
-- foundation runtime_ports，装配后的回合端口照常拿到宿主时钟。
it("test_presentation_ports_leave_clock_to_turn_base_runtime_clock", function()
  local runtime_ports = require("src.foundation.ports.runtime_ports")
  local gameplay_loop_ports = require("src.turn.loop.ports")
  local ui_ports = presentation_ports.build()
  _assert_eq(ui_ports.clock, nil, "presentation ports should not provide a clock group")

  local resolved = gameplay_loop_ports.resolve(ui_ports)
  runtime_ports.configure({
    wall_now_seconds = function() return 12.5 end,
    wall_diff_seconds = function() return 0.25 end,
  })
  local ok, err = pcall(function()
    _assert_eq(resolved.clock.wall_now_seconds(), 12.5, "turn clock should read the runtime wall clock")
    _assert_eq(resolved.clock.wall_diff_seconds(3, 1), 0.25, "turn clock diff should use the runtime wall diff")
  end)
  support.restore_runtime_services()
  assert(ok, err)
end)

it("test_view_command_ports_toggle_action_log_tolerates_missing_ui_and_actor", function()
  local view_command_ports = require("src.ui.ports.view_command")
  local ports = view_command_ports.build()

  _assert_eq(ports.dispatch({}, { type = "toggle_action_log", actor_role_id = 1 }), true,
    "toggle_action_log should return true even when ui is missing")

  local warn_calls = {}
  _with_patches({
    { target = logger, key = "warn", value = function(...)
      warn_calls[#warn_calls + 1] = table.concat({ ... }, " ")
    end },
  }, function()
    local result = ports.dispatch({ ui = {} }, { type = "toggle_action_log" })
    _assert_eq(result, true, "toggle_action_log should return true even when actor_role_id is missing")
    _assert_eq(#warn_calls >= 1, true, "toggle_action_log should warn when actor_role_id is missing")
  end)
end)


	-- canvas_event_router.bind 传入 dispatch_opts.on_close_choice 回调,
	-- 必须在 dispatch 侧触发以验证 modal.close_choice_modal 连通性,
	-- 否则 require("src.ui.coord.modal") 被置 nil 的突变体无法被杀死。
	it("test_ui_event_router_dispatch_close_choice_modal_callback", function()
	  local market_nodes = require("src.ui.schema.market")
	  local modal_module = require("src.ui.coord.modal")
	  local node_map = {
	    [market_nodes.confirm] = _new_listenable_node(),
	  }
	  local closed_choice = false

	  _with_patches(_router_env_patches(node_map, {
	    { target = modal_module, key = "close_choice_modal", value = function(ctx)
	      closed_choice = true
	      _assert_eq(ctx ~= nil, true, "close_choice_modal should receive router state ctx")
	    end },
	  }), function()
	    local state = {
	      ui = ui_view.build_ui_state(),
	      ui_model = {
	        current_player_id = "3",
	        choice = {
	          id = 15,
	          kind = "market_buy",
	          route_key = "market",
	          allow_cancel = true,
	          options = { { id = 34, label = "X" } },
	        },
	        market = {
	          choice_id = 15,
	          options = { { id = 34, label = "X" } },
	        },
	      },
	      pending_choice_selected_option_id = 34,
	      turn_action_port = {
	        dispatch_action = function(_, state_arg, action, opts)
	          local on_close = opts and opts.on_close_choice
	          if on_close then
	            on_close(state_arg)
	          end
	        end,
	        should_block_action = function()
	          return false
	        end,
	      },
	    }
	    _bind_ui_runtime(state)
	    canvas_event_router.bind(state, function()
	      return {}
	    end)
	    -- 身份随事件数据携带(#341):匿名点击不再回落缓存注入 actor。
	    node_map[market_nodes.confirm]._listener_cb({ role = { get_roleid = function() return 3 end } })
	  end)

	  _assert_eq(closed_choice, true,
	    "on_close_choice dispatch callback should invoke modal.close_choice_modal")
	end)

		-- action_log_button 路由的 bind_client_role 必须为 false,
	-- 否则 route_name ~= base_nodes.action_log_button 的 ~= 变 == 的突变体无法被杀死。
	it("test_ui_event_router_action_log_button_no_client_role_bind", function()
	  local base_nodes = require("src.ui.schema.base")
	  local action_log_opts = nil
	  local action_log_registered = false

	  -- 直接补丁:canvas_event_router 内的 ui_event_bindings 与 event_bindings 指向同一 module 表,
	  -- 替换表上的 register_node_click 即可截获所有调用。
	  local orig_register = event_bindings.register_node_click
	  event_bindings.register_node_click = function(cache, route_name, callback, registered, listeners, opts)
	    if route_name == base_nodes.action_log_button and not action_log_registered then
	      action_log_opts = opts
	      action_log_registered = true
	    end
	  end

	  local ok, err = pcall(function()
	    local state = {
	      ui = ui_view.build_ui_state(),
	    }
	    _bind_ui_runtime(state)

	    -- canvas_event_router.bind 会调用 enable_action_log_toggle_touch,
	    -- 需要 UIManager 和 GlobalAPI 存在(仅使用 _with_patches 环境即可)。
	    _with_patches({
	      { key = "UIManager", value = { EVENT = { CLICK = "click" }, query_nodes_by_name = function()
	        return {}
	      end } },
	      { key = "GlobalAPI", value = { show_tips = function() end } },
	    }, function()
	      canvas_event_router.bind(state, function()
	        return {}
	      end)
	    end, { skip_runtime_context_refresh = true })
	  end)

	  event_bindings.register_node_click = orig_register

	  if not ok then
	    error(err)
	  end

	  _assert_eq(action_log_registered, true,
	    "register_node_click should be called for action_log_button route")
	  _assert_eq(action_log_opts and action_log_opts.bind_client_role, false,
	    "action_log_button should not bind client role (bind_client_role must be false)")
	end)
end)
