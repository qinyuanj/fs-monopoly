require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- choice_helpers.lua 直测:覆盖 resolve_canvas_for_screen 的固定画布映射及基础屏回落、
-- hide_choice_screens 的状态清理、set_option_node 的 touch_enabled 赋值。
local support = require("test.support.shared_support")
local _with_patches = support.with_patches

local choice_helpers = require("src.ui.coord.choice_helpers")
local canvas = require("src.ui.coord.canvas_coordinator")
local ui_controls = require("src.ui.render.support.ui_controls")
local runtime = require("src.ui.render.support.runtime_ui")
local runtime_state = require("src.ui.state.runtime")
describe("TestChoiceHelpers", function()
-- resolve_canvas_for_screen:已知选择屏返回其固定画布
it("test_resolve_canvas_returns_registered_canvas", function()
  local result = choice_helpers.resolve_canvas_for_screen("target")
  luassert.is.equal(canvas.CANVAS_TARGET_CHOICE, result)
end)

-- resolve_canvas_for_screen:未知 key 回落 CANVAS_BASE
it("test_resolve_canvas_falls_back_to_base", function()
  local result = choice_helpers.resolve_canvas_for_screen("unknown")
  luassert.is.equal(canvas.CANVAS_BASE, result)
end)

-- hide_choice_screens: 清理 choice_active 和 active_choice_screen_key
it("test_hide_choice_screens_clears_state", function()
  local reset_calls = {}
  local ui = {
    choice_screens = {
      a = { root = "a_root" },
      b = { root = "b_root" },
    },
    choice_active = true,
    active_choice_screen_key = "some_key",
  }

  _with_patches({
    { target = ui_controls, key = "reset_choice_screen", value = function(_, screen)
      reset_calls[#reset_calls + 1] = screen.root
    end },
  }, function()
    choice_helpers.hide_choice_screens(ui)
  end)

  luassert.is.equal(2, #reset_calls, "should reset both choice screens")
  luassert.is.equal(false, ui.choice_active, "choice_active must be false after hide")
  luassert.is.equal(nil, ui.active_choice_screen_key, "active_choice_screen_key must be nil after hide")
end)

-- hide_choice_screens: choice_screens 为 nil 时不报错
it("test_hide_choice_screens_handles_nil_screens", function()
  local ui = {
    choice_active = true,
    active_choice_screen_key = "x",
  }
  _with_patches({
    { target = ui_controls, key = "reset_choice_screen", value = function() end },
  }, function()
    choice_helpers.hide_choice_screens(ui)
  end)
  luassert.is.equal(false, ui.choice_active)
  luassert.is_nil(ui.active_choice_screen_key)
end)

-- set_option_node: option 非 nil 时 touch_enabled 为 true
it("test_set_option_node_enables_touch_for_valid_option", function()
  local control_state = nil
  local set_button_calls = {}

  local ui = {
    set_button = function(_, node_name, label)
      set_button_calls[#set_button_calls + 1] = { node_name, label }
    end,
  }

  _with_patches({
    { target = ui_controls, key = "set_control_state", value = function(_, node_name, state)
      control_state = state
    end },
  }, function()
    choice_helpers.set_option_node(ui, "btn_1", { id = 1, label = "选项A" })
  end)

  luassert.is.equal(true, control_state.visible, "visible must be true when option exists")
  luassert.is.equal(true, control_state.touch_enabled, "touch_enabled must be true when option exists")
  luassert.is.equal(1, #set_button_calls, "set_button must be called once")
end)

-- set_option_node: option 为 nil 时 touch_enabled 为 false
it("test_set_option_node_disables_touch_for_nil_option", function()
  local control_state = nil
  local set_button_calls = {}

  local ui = {
    set_button = function(_, node_name, label)
      set_button_calls[#set_button_calls + 1] = { node_name, label }
    end,
  }

  _with_patches({
    { target = ui_controls, key = "set_control_state", value = function(_, node_name, state)
      control_state = state
    end },
  }, function()
    choice_helpers.set_option_node(ui, "btn_x", nil)
  end)

  luassert.is.equal(false, control_state.visible, "visible must be false when option is nil")
  luassert.is.equal(false, control_state.touch_enabled, "touch_enabled must be false when option is nil")
  luassert.is.equal(0, #set_button_calls, "set_button must not be called for nil option")
end)

-- switch_modal_canvas 覆盖（杀掉 L50 can_operate 判定四件套 + get_ui_model→nil 幸存者）：
-- 可操作角色切到目标画布，不可操作角色回落 CANVAS_BASE

local function _switch_model_for(role)
  return { current_player_id = "r1", item_slots_by_player_id = { r1 = {}, r2 = {} } }
end

local function _patch_switch_deps(with_calls)
  return {
    { target = runtime, key = "for_each_role_or_global",
      value = function(fn) fn("r1") end },
    { target = runtime, key = "resolve_role_id", value = function(role) return role end },
    { target = runtime_state, key = "get_ui_model", value = _switch_model_for },
    { target = runtime, key = "set_client_role", value = function() end },
    { target = canvas, key = "switch_for_role",
      value = function(_, target, role) with_calls[#with_calls + 1] = { target, role } end },
    { target = canvas, key = "switch", value = function() end },
  }
end

it("test_switch_modal_canvas_uses_target_canvas_when_role_can_operate", function()
  local calls = {}
  local ui = {}
  local state = { ui = ui }
  _with_patches(_patch_switch_deps(calls), function()
    choice_helpers.switch_modal_canvas(state, canvas.CANVAS_MARKET)
  end)
  luassert.is.equal(1, #calls, "one role should switch canvas")
  luassert.is.equal(canvas.CANVAS_MARKET, calls[1][1],
    "can-operate role should switch to the target canvas")
  luassert.is.equal("r1", calls[1][2], "role should be forwarded to switch_for_role")
end)

it("test_switch_modal_canvas_falls_back_to_base_when_role_cannot_operate", function()
  local calls = {}
  local ui = {}
  local state = { ui = ui }
  _with_patches({
    { target = runtime, key = "for_each_role_or_global",
      value = function(fn) fn("r2") end },
    { target = runtime, key = "resolve_role_id", value = function(role) return role end },
    { target = runtime_state, key = "get_ui_model",
      value = function() return { current_player_id = "r1", item_slots_by_player_id = { r2 = {} } } end },
    { target = runtime, key = "set_client_role", value = function() end },
    { target = canvas, key = "switch_for_role",
      value = function(_, target, role) calls[#calls + 1] = { target, role } end },
    { target = canvas, key = "switch", value = function() end },
  }, function()
    choice_helpers.switch_modal_canvas(state, canvas.CANVAS_MARKET)
  end)
  luassert.is.equal(canvas.CANVAS_BASE, calls[1][1],
    "role that cannot operate should get the base canvas")
end)

end)
