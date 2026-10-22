-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
-- canvas_coordinator.lua 直测:覆盖调试画布路径、choice 画布解析、
-- switch_for_role 角色解析分支、switch_by_role_id nil ui 守卫,
-- 以及收屏回屏共用的 role/global 分发与面板回屏回落。

local coordinator = require("src.ui.coord.canvas_coordinator")
local ui_events = require("src.ui.coord.ui_events")
local gift_code_nodes = require("src.ui.schema.gift_code")

describe("TestCanvasCoordinator", function()

local function _spy_sender()
  local calls = {}
  local function send(event_name, payload)
    calls[#calls + 1] = {event_name, payload}
  end
  return send, calls
end

-- spy 记录里事件名的槽位:send_to_all(event, payload) 在 c[1],
-- send_to_role(role, event, payload) 在 c[2]。
local function _has_event(calls, event_name, field)
  for _, c in ipairs(calls) do
    if c[field or 1] == event_name then
      return true
    end
  end
  return false
end

-- resolve_popup_return_canvas: market_active 优先
it("test_resolve_popup_returns_market_when_active", function()
  local ui = { market_active = true }
  luassert.is.same( coordinator.CANVAS_MARKET,coordinator.resolve_popup_return_canvas(ui))
end)

-- resolve_popup_return_canvas: choice_active 次优先
it("test_resolve_popup_returns_choice_canvas_for_valid_key", function()
  local ui = { market_active = false, choice_active = true, active_choice_screen_key = "player" }
  luassert.is.same( coordinator.CANVAS_PLAYER_CHOICE,coordinator.resolve_popup_return_canvas(ui))
end)

-- resolve_popup_return_canvas: choice_active 但 key 无效 → 回落 base
it("test_resolve_popup_returns_base_when_choice_key_invalid", function()
  local ui = { market_active = false, choice_active = true, active_choice_screen_key = "unknown" }
  luassert.is.same( coordinator.CANVAS_BASE,coordinator.resolve_popup_return_canvas(ui))
end)

-- resolve_popup_return_canvas: 无 market 无 choice → base
it("test_resolve_popup_returns_base_when_nothing_active", function()
  local ui = { market_active = false }
  luassert.is.same( coordinator.CANVAS_BASE,coordinator.resolve_popup_return_canvas(ui))
end)

-- resolve_popup_return_canvas: choice_active=false 时 guard 返回 nil
-- 覆盖 _resolve_choice_canvas 中 not ui or not ui.choice_active 的 or 分支
it("test_resolve_popup_ignores_choice_when_not_active", function()
  local ui = { market_active = false, choice_active = false, active_choice_screen_key = "player" }
  luassert.is.same( coordinator.CANVAS_BASE,coordinator.resolve_popup_return_canvas(ui))
end)

-- resolve_canvas_after_popup 委托给 resolve_popup_return_canvas
it("test_resolve_canvas_after_popup_delegates", function()
  local ui = { market_active = true }
  luassert.is.same( coordinator.CANVAS_MARKET,coordinator.resolve_canvas_after_popup(ui))
end)

-- switch_by_role_id: nil ui 提前返回,任何画布事件都不发出
it("test_switch_by_role_id_nil_ui_returns_early", function()
  local send_all, all_calls = _spy_sender()
  local send_role, role_calls = _spy_sender()
  local orig_all = ui_events.send_to_all
  local orig_role = ui_events.send_to_role
  ui_events.send_to_all = send_all
  ui_events.send_to_role = send_role

  coordinator.switch_by_role_id(nil, "target", "role1")

  ui_events.send_to_all = orig_all
  ui_events.send_to_role = orig_role

  luassert.is.same( 0,#all_calls)
  luassert.is.same( 0,#role_calls)
end)

-- switch: 带 debug_visible_by_role 的 ui 保留调试画布
it("test_switch_keeps_debug_canvas_when_debug_visible", function()
  local send, calls = _spy_sender()
  local orig_send = ui_events.send_to_all
  ui_events.send_to_all = send

  local ui = { debug_visible_by_role = { ["r1"] = true } }
  coordinator.switch(ui, coordinator.CANVAS_BASE)

  ui_events.send_to_all = orig_send

  -- debug 画布不应被隐藏:查 hide 调用中无 CANVAS_DEBUG
  for _, c in ipairs(calls) do
    local event_name = c[1]
    luassert.is_not.same( ui_events.hide[coordinator.CANVAS_DEBUG],event_name)
  end
end)

-- switch: 无 debug 可见时调试画布被隐藏
it("test_switch_hides_debug_canvas_when_debug_not_visible", function()
  local send, calls = _spy_sender()
  local orig_send = ui_events.send_to_all
  ui_events.send_to_all = send

  local ui = {}
  coordinator.switch(ui, coordinator.CANVAS_BASE)

  ui_events.send_to_all = orig_send

  -- debug 画布被隐藏
  luassert.truthy(
    _has_event(calls, ui_events.hide[coordinator.CANVAS_DEBUG]),
    "debug canvas should be hidden when not visible"
  )
end)

-- switch: debug_visible_by_role 不是 table 时走安全路径,调试画布照常隐藏
it("test_switch_with_non_table_debug_by_role", function()
  local send, calls = _spy_sender()
  local orig_send = ui_events.send_to_all
  ui_events.send_to_all = send

  local ui = { debug_visible_by_role = "not_a_table" }
  coordinator.switch(ui, coordinator.CANVAS_BASE)

  ui_events.send_to_all = orig_send

  luassert.truthy(
    _has_event(calls, ui_events.hide[coordinator.CANVAS_DEBUG]),
    "debug canvas should be hidden when debug_visible_by_role is not a table"
  )
end)

-- switch: debug_visible_by_role 是 table 但所有值为 false → 调试画布被隐藏
it("test_switch_with_debug_table_all_false", function()
  local send, calls = _spy_sender()
  local orig_send = ui_events.send_to_all
  ui_events.send_to_all = send

  local ui = { debug_visible_by_role = { ["r1"] = false, ["r2"] = false } }
  coordinator.switch(ui, coordinator.CANVAS_BASE)

  ui_events.send_to_all = orig_send

  luassert.truthy(
    _has_event(calls, ui_events.hide[coordinator.CANVAS_DEBUG]),
    "debug canvas should be hidden when all entries are false"
  )
end)

-- switch_for_role: 带 get_roleid 的角色 + 匹配的 debug 条目 → 保留调试画布
-- 覆盖 _keep_debug_for_role 全部内部判断 (type/~=/table/role_id_utils.read/==/true)
it("test_switch_for_role_keeps_debug_for_get_roleid_match", function()
  local role = {
    get_roleid = function() return "debug_role_1" end,
    send_ui_custom_event = function(_, _) end,
  }
  local send, calls = _spy_sender()
  local orig_send = ui_events.send_to_role
  ui_events.send_to_role = send

  local ui = { debug_visible_by_role = { ["debug_role_1"] = true } }
  coordinator.switch_for_role(ui, coordinator.CANVAS_BASE, role)

  ui_events.send_to_role = orig_send

  -- 调试画布不被隐藏(spy 记录里 c[1] 是 role,c[2] 才是事件名)
  local hide_debug = ui_events.hide[coordinator.CANVAS_DEBUG]
  for _, c in ipairs(calls) do
    luassert.is_not.same( hide_debug,c[2])
  end
end)

-- switch_for_role: 角色无 get_roleid 方法时用 tostring fallback
-- 覆盖 runtime.resolve_role_id 返回 nil → or tostring(role) 路径
-- 以及 _keep_debug_for_role 中 type(debug_by_role)=nil 的 ~= 判断
it("test_switch_for_role_falls_back_to_tostring", function()
  local role = { send_ui_custom_event = function(_, _) end }
  local send, calls = _spy_sender()
  local orig_send = ui_events.send_to_role
  ui_events.send_to_role = send

  -- role 无 get_roleid → resolve_role_id 返回 nil → 用 tostring(role)
  local ui = {}
  coordinator.switch_for_role(ui, coordinator.CANVAS_BASE, role)

  ui_events.send_to_role = orig_send

  -- base canvas show 事件应该被调用
  luassert.truthy(#calls >= 2, "should send base and permanent show events")
end)

-- switch_for_role: 用 __tostring 元方法使 tostring fallback 匹配 debug 条目
-- 覆盖 L115 的 tostring(role) 和 or→and 突变体
it("test_switch_for_role_tostring_fallback_matches_debug_entry", function()
  local role = { send_ui_custom_event = function(_, _) end }
  -- 设置 __tostring 使 tostring(role) 返回可预测值
  setmetatable(role, { __tostring = function() return "known_role_string" end })

  local send, calls = _spy_sender()
  local orig_send = ui_events.send_to_role
  ui_events.send_to_role = send

  local ui = { debug_visible_by_role = { ["known_role_string"] = true } }
  coordinator.switch_for_role(ui, coordinator.CANVAS_BASE, role)

  ui_events.send_to_role = orig_send

  -- tostring(role) = "known_role_string" 匹配 debug 条目 → 保留调试画布
  local hide_debug = ui_events.hide[coordinator.CANVAS_DEBUG]
  for _, c in ipairs(calls) do
    luassert.is_not.same( hide_debug,c[2])
  end
end)

-- switch_for_role: debug_visible_by_role 不是 table → 不走调试保留,调试画布被隐藏
it("test_switch_for_role_non_table_debug_by_role", function()
  local role = { send_ui_custom_event = function(_, _) end }
  local send, calls = _spy_sender()
  local orig_send = ui_events.send_to_role
  ui_events.send_to_role = send

  local ui = { debug_visible_by_role = 123 }
  coordinator.switch_for_role(ui, coordinator.CANVAS_BASE, role)

  ui_events.send_to_role = orig_send

  -- send_to_role(role, event, payload):spy 记录里 c[1] 是 role,事件名在 c[2]
  luassert.truthy(
    _has_event(calls, ui_events.hide[coordinator.CANVAS_DEBUG], 2),
    "debug canvas should be hidden when debug_visible_by_role is not a table"
  )
end)

-- switch_by_role_id: runtime_ports.resolve_role 返回 nil 时回落 switch,走 send_to_all 广播
it("test_switch_by_role_id_falls_back_when_no_role_resolved", function()
  local send, calls = _spy_sender()
  local orig_send = ui_events.send_to_all
  ui_events.send_to_all = send

  -- 用一个不存在的 role_id → resolve_role 返回 nil → 走 switch 分支
  local ui = {}
  coordinator.switch_by_role_id(ui, coordinator.CANVAS_BASE, "__nonexistent_role__")

  ui_events.send_to_all = orig_send

  -- 回落 switch 的证据:base 画布 show 事件经 send_to_all 广播发出
  luassert.truthy(
    _has_event(calls, ui_events.show[coordinator.CANVAS_BASE]),
    "fallback to switch should broadcast the base canvas show event"
  )
end)

-- switch_role_or_global: 有角色对象时按角色发
it("test_switch_role_or_global_sends_to_the_role", function()
  local role = {
    get_roleid = function() return 1 end,
    send_ui_custom_event = function(_, _) end,
  }
  local send, calls = _spy_sender()
  local orig_send = ui_events.send_to_role
  ui_events.send_to_role = send

  coordinator.switch_role_or_global({}, coordinator.CANVAS_BASE, role)

  ui_events.send_to_role = orig_send

  luassert.truthy(
    _has_event(calls, ui_events.show[coordinator.CANVAS_BASE], 2),
    "with a role the canvas switch must be sent per role"
  )
end)

-- switch_role_or_global: 无角色(全局扇出)时广播
it("test_switch_role_or_global_broadcasts_without_a_role", function()
  local send, calls = _spy_sender()
  local orig_send = ui_events.send_to_all
  ui_events.send_to_all = send

  coordinator.switch_role_or_global({}, coordinator.CANVAS_BASE, nil)

  ui_events.send_to_all = orig_send

  luassert.truthy(
    _has_event(calls, ui_events.show[coordinator.CANVAS_BASE]),
    "without a role the canvas switch must broadcast to everyone"
  )
end)

-- resolve_role_panel_canvas_or_base: 开着面板回面板 canvas,没开回基础屏
it("test_resolve_role_panel_canvas_or_base_falls_back_to_base", function()
  local ui = { gift_code = { open = true, role_id = 2 } }
  luassert.is.equal(gift_code_nodes.canvas,
    coordinator.resolve_role_panel_canvas_or_base(ui, 2))
  luassert.is.equal(coordinator.CANVAS_BASE,
    coordinator.resolve_role_panel_canvas_or_base(ui, 1))
end)

end)
