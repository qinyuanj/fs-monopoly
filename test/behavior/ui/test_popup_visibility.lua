require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- luacheck: ignore 211
local support = require("test.support.shared_support")
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _bind_ui_runtime = support.bind_ui_runtime
local _with_patches = support.with_patches
local runtime_port = require("src.ui.render.support.runtime_ui")
local modal_presenter = require("src.ui.coord.popup_presenter")

local _build_popup_view_state = support.build_popup_view_state
local _build_role_with_events = support.build_role_with_events
local _has_event = support.has_event
describe("TestPopupVisibility", function()
it("test_push_popup_sets_card_image_by_image_ref", function()
  local last_image_key = nil
  local card_node = {
    set_texture_keep_size = function(_, image_key)
      last_image_key = image_key
    end,
  }
  local state, nodes, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
    ["2001"] = "ICON2001",
  }, card_node)

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
  }, function()
    state.gameplay_loop_ports = require("src.ui.ports").build(state)
    modal_presenter.push_popup(state, {
      title = "道具卡",
      body = "测试",
      image_ref = 2001,
    })
  end)

  _assert_eq(last_image_key, "ICON2001", "popup card should use mapped image")
  _assert_eq(nodes["卡牌展示_图片"].visible, true, "popup card should be visible when image exists")
end)

it("test_push_popup_hides_card_and_clears_image_when_missing", function()
  local last_image_key = nil
  local card_node = {
    set_texture_keep_size = function(_, image_key)
      last_image_key = image_key
    end,
  }
  local state, nodes, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
    ["2001"] = "ICON2001",
  }, card_node)

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
  }, function()
    state.gameplay_loop_ports = require("src.ui.ports").build(state)
    modal_presenter.push_popup(state, {
      title = "道具卡",
      body = "测试",
      image_ref = 2001,
    })
    modal_presenter.push_popup(state, {
      title = "黑市",
      body = "测试2",
    })
  end)

  _assert_eq(last_image_key, "EMPTY", "popup card should reset to empty key when image missing")
  _assert_eq(nodes["卡牌展示_图片"].visible, false, "popup card should hide when image missing")
end)

it("test_popup_hidden_for_non_current_role", function()
  local state, _, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
  }, {
    set_texture_keep_size = function() end,
  })
  state.ui_model = {
    current_player_id = 1,
    item_slots_by_player = { [1] = {}, [2] = {} },
  }
  local role1_events = {}
  local role2_events = {}
  local roles = {
    _build_role_with_events(1, role1_events),
    _build_role_with_events(2, role2_events),
  }
  _bind_ui_runtime(state)

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = roles },
    { target = runtime_port, key = "for_each_role_or_global", value = function(fn)
      for _, role in ipairs(roles) do
        fn(role)
      end
    end },
    { target = runtime_port, key = "resolve_role_id", value = function(role)
      return role.get_roleid()
    end },
  }, function()
    modal_presenter.push_popup(state, {
      title = "黑市",
      body = "测试",
    })
  end)

  luassert.truthy(_has_event(role1_events, "显示卡牌展示屏"), "current role should see popup canvas")
  luassert.truthy(not _has_event(role2_events, "显示卡牌展示屏"), "non-current role should not see popup canvas")
end)

-- #142 反转旧 pin「卡牌弹窗时旁观者 canvas 不动」:机会卡抽卡展示走广播载荷
-- (rules 层 effect_chance 置 broadcast 标志),旁观 role 也切到卡牌展示屏。
it("test_broadcast_chance_popup_switches_spectator_to_popup_canvas", function()
  local state, _, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
  }, {
    set_texture_keep_size = function() end,
  })
  state.ui_model = {
    current_player_id = 1,
    item_slots_by_player = { [1] = {}, [2] = {} },
  }
  _bind_ui_runtime(state)
  local role1_events = {}
  local role2_events = {}
  local roles = {
    _build_role_with_events(1, role1_events),
    _build_role_with_events(2, role2_events),
  }

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = roles },
    { target = runtime_port, key = "for_each_role_or_global", value = function(fn)
      for _, role in ipairs(roles) do
        fn(role)
      end
    end },
    { target = runtime_port, key = "resolve_role_id", value = function(role)
      return role.get_roleid()
    end },
  }, function()
    modal_presenter.push_popup(state, {
      title = "机会卡",
      body = "测试",
      kind = "chance_card",
      broadcast = true,
    })
  end)

  luassert.truthy(_has_event(role1_events, "显示卡牌展示屏"), "current role should see popup canvas")
  luassert.truthy(_has_event(role2_events, "显示卡牌展示屏"),
    "spectator must be switched to popup canvas for broadcast chance card")
end)

it("test_non_broadcast_card_popup_keeps_spectator_canvas_untouched", function()
  -- 不带 broadcast 标志的普通卡牌弹窗维持旧语义:旁观者 canvas 不动。
  local state, _, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
  }, {
    set_texture_keep_size = function() end,
  })
  state.ui_model = {
    current_player_id = 1,
    item_slots_by_player = { [1] = {}, [2] = {} },
  }
  _bind_ui_runtime(state)
  local role1_events = {}
  local role2_events = {}
  local roles = {
    _build_role_with_events(1, role1_events),
    _build_role_with_events(2, role2_events),
  }

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = roles },
    { target = runtime_port, key = "for_each_role_or_global", value = function(fn)
      for _, role in ipairs(roles) do
        fn(role)
      end
    end },
    { target = runtime_port, key = "resolve_role_id", value = function(role)
      return role.get_roleid()
    end },
  }, function()
    modal_presenter.push_popup(state, {
      title = "道具卡",
      body = "测试",
      kind = "item_card",
    })
  end)

  luassert.truthy(_has_event(role1_events, "显示卡牌展示屏"), "current role should see popup canvas")
  luassert.truthy(not _has_event(role2_events, "显示卡牌展示屏"),
    "spectator must not be switched to popup canvas for non-broadcast card")
  luassert.truthy(not _has_event(role2_events, "显示基础屏"),
    "spectator canvas must remain untouched so opened atlas stays visible")
  luassert.truthy(not _has_event(role2_events, "隐藏道具图鉴"),
    "spectator atlas canvas must not be force-hidden during non-broadcast card popup")
end)

it("test_bankruptcy_popup_visible_for_all_roles", function()
  local state, _, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
  }, {
    set_texture_keep_size = function() end,
  })
  state.ui_model = {
    current_player_id = 1,
    item_slots_by_player = { [1] = {}, [2] = {} },
  }
  _bind_ui_runtime(state)
  local role1_events = {}
  local role2_events = {}
  local roles = {
    _build_role_with_events(1, role1_events),
    _build_role_with_events(2, role2_events),
  }

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = roles },
    { target = runtime_port, key = "for_each_role_or_global", value = function(fn)
      for _, role in ipairs(roles) do
        fn(role)
      end
    end },
    { target = runtime_port, key = "resolve_role_id", value = function(role)
      return role.get_roleid()
    end },
  }, function()
    modal_presenter.push_popup(state, {
      kind = "bankruptcy",
      text = "破产测试",
    })
  end)

  luassert.truthy(_has_event(role1_events, "显示破产展示屏"), "current role should see bankruptcy canvas")
  luassert.truthy(_has_event(role2_events, "显示破产展示屏"), "non-current role should see bankruptcy canvas")
end)

it("test_hide_bankruptcy_popup_hides_bankruptcy_root", function()
  local popup_controller = require("src.ui.coord.popup")
  local state, nodes, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
  }, {
    set_texture_keep_size = function() end,
  })

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
  }, function()
    state.gameplay_loop_ports = require("src.ui.ports").build(state)
    modal_presenter.push_popup(state, {
      kind = "bankruptcy",
      text = "破产测试",
    })
    popup_controller.hide(state)
  end)

  _assert_eq(nodes["破产展示屏"] and nodes["破产展示屏"].visible or false, false,
    "hide must close the bankruptcy screen root, not the card popup root")
end)

it("test_bankruptcy_popup_avatar_uses_native_size_path", function()
  local native_calls = 0
  local avatar_image_key = nil
  local state, _, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
  }, {
    set_texture_keep_size = function() end,
  })

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
    { target = runtime_port, key = "set_node_texture_native_size", value = function(_, image_key)
      native_calls = native_calls + 1
      avatar_image_key = image_key
    end },
  }, function()
    modal_presenter.push_popup(state, {
      kind = "bankruptcy",
      text = "破产测试",
      avatar_key = 2002,
    })
  end)

  _assert_eq(native_calls, 1, "bankruptcy popup avatar should use native-size path")
  _assert_eq(avatar_image_key, 2002, "bankruptcy popup avatar should forward payload image key")
end)

it("test_show_card_popup_shows_root_and_enables_dismiss_touch", function()
  -- kills L118 `set_visible(popup.root, true)` true->false 与
  -- L130 `set_popup_dismiss_touch(ui, true)` true->false(#262)。
  local popup_controller = require("src.ui.coord.popup")
  local state, nodes, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
  }, {
    set_texture_keep_size = function() end,
  })

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
    { target = runtime_port, key = "for_each_role_or_global", value = function(fn) fn(nil) end },
  }, function()
    popup_controller.show_popup(state, {
      title = "道具卡",
      body = "测试",
    })
  end)

  _assert_eq(nodes["卡牌展示屏"].visible, true, "card popup root must be visible after show")
  _assert_eq(nodes["卡牌展示_灰底"].disabled, false, "dismiss touch must be enabled after show")
end)

it("test_hide_card_popup_hides_root_and_disables_dismiss_touch", function()
  -- kills L156 `set_popup_dismiss_touch(ui, false)` false->true(#262)。
  local popup_controller = require("src.ui.coord.popup")
  local state, nodes, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
  }, {
    set_texture_keep_size = function() end,
  })

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
    { target = runtime_port, key = "for_each_role_or_global", value = function(fn) fn(nil) end },
  }, function()
    popup_controller.show_popup(state, {
      title = "道具卡",
      body = "测试",
    })
    popup_controller.hide(state)
  end)

  _assert_eq(nodes["卡牌展示屏"].visible, false, "card popup root must hide after hide")
  _assert_eq(nodes["卡牌展示_灰底"].disabled, true, "dismiss touch must be disabled after hide")
end)

it("test_bankruptcy_show_marks_root_visible", function()
  -- kills L108 `set_visible(screen.root, true)` true->false(#262):
  -- 既有 hide 用例只钉 hide 后 false,节点初始 visible 为 nil(falsy),
  -- show 从不置 true 也测不出来。
  local popup_controller = require("src.ui.coord.popup")
  local state, nodes, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
  }, {
    set_texture_keep_size = function() end,
  })

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
    { target = runtime_port, key = "for_each_role_or_global", value = function(fn) fn(nil) end },
  }, function()
    popup_controller.show_popup(state, {
      kind = "bankruptcy",
      text = "破产测试",
    })
  end)

  _assert_eq(nodes["破产展示屏"] and nodes["破产展示屏"].visible or false, true,
    "bankruptcy root must be visible after show")
end)

it("test_bankruptcy_show_hides_click_background_hint", function()
  -- #178:破产屏不做点背景关闭,只靠约 2 秒自动关闭;"点击背景关闭"提示必须隐藏。
  local popup_controller = require("src.ui.coord.popup")
  local state, nodes, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
  }, {
    set_texture_keep_size = function() end,
  })
  nodes["破产_关闭破产文本提示"] = { visible = true }

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
    { target = runtime_port, key = "for_each_role_or_global", value = function(fn) fn(nil) end },
  }, function()
    popup_controller.show_popup(state, {
      kind = "bankruptcy",
      text = "破产测试",
    })
  end)

  _assert_eq(nodes["破产_关闭破产文本提示"].visible, false,
    "bankruptcy click-background hint must be hidden on show")
end)

it("test_resolve_bankruptcy_text_prefers_payload_text", function()
  local popup_controller = require("src.ui.coord.popup")
  local state, _, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
  }, {
    set_texture_native_size = function() end,
  })
  local captured_text = nil

  state.ui.set_label = function(_, node_name, text)
    captured_text = text
  end

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
    { target = require("src.ui.render.support.runtime_ui"), key = "for_each_role_or_global", value = function(fn) fn(nil) end },
  }, function()
    popup_controller.show_popup(state, {
      kind = "bankruptcy",
      text = "自定义破产文本",
    })
  end)

  _assert_eq(captured_text, "自定义破产文本", "_resolve_bankruptcy_text should prefer payload.text")
end)

it("test_resolve_bankruptcy_text_falls_back_to_reason", function()
  local popup_controller = require("src.ui.coord.popup")
  local state, _, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
  }, {
    set_texture_native_size = function() end,
  })
  local captured_text = nil

  state.ui.set_label = function(_, node_name, text)
    captured_text = text
  end

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
    { target = require("src.ui.render.support.runtime_ui"), key = "for_each_role_or_global", value = function(fn) fn(nil) end },
  }, function()
    popup_controller.show_popup(state, {
      kind = "bankruptcy",
      reason = "破产原因说明",
    })
  end)

  _assert_eq(captured_text, "破产原因说明", "_resolve_bankruptcy_text should fall back to payload.reason")
end)

it("test_resolve_bankruptcy_text_falls_back_to_player_name", function()
  local popup_controller = require("src.ui.coord.popup")
  local state, _, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
  }, {
    set_texture_native_size = function() end,
  })
  local captured_text = nil

  state.ui.set_label = function(_, node_name, text)
    captured_text = text
  end

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
    { target = require("src.ui.render.support.runtime_ui"), key = "for_each_role_or_global", value = function(fn) fn(nil) end },
  }, function()
    popup_controller.show_popup(state, {
      kind = "bankruptcy",
      player_name = "测试玩家",
    })
  end)

  _assert_eq(captured_text, "测试玩家 破产出局", "_resolve_bankruptcy_text should append 破产出局 to player_name")
end)

it("test_resolve_bankruptcy_text_uses_default_when_all_missing", function()
  local popup_controller = require("src.ui.coord.popup")
  local state, _, query_nodes = _build_popup_view_state({
    ["Empty"] = "EMPTY",
  }, {
    set_texture_native_size = function() end,
  })
  local captured_text = nil

  state.ui.set_label = function(_, node_name, text)
    captured_text = text
  end

  _with_patches({
    { key = "UIManager", value = { query_nodes_by_name = query_nodes } },
    { key = "all_roles", value = nil },
    { target = require("src.ui.render.support.runtime_ui"), key = "for_each_role_or_global", value = function(fn) fn(nil) end },
  }, function()
    popup_controller.show_popup(state, {
      kind = "bankruptcy",
    })
  end)

  _assert_eq(captured_text, "破产出局", "_resolve_bankruptcy_text should return default when all fields missing")
end)


end)
