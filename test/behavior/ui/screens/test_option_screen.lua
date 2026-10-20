require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- screens/_option_screen 开屏 helper 规约(#262 基线复核发现的欠账):
-- 灰底触摸放行、确定/取消按钮的可见/可用/文案、allow_cancel 三态。
local support = require("test.support.shared_support")
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _with_patches = support.with_patches
local option_screen = require("src.ui.screens._option_screen")
local openers = require("src.ui.coord.choice_openers")
local modal_state = require("src.ui.state.modal")

-- openers/modal_state 全桩:open_screen 给 ui 触摸捕获 + screen 节点名,
-- set_action_button 全参捕获,open_choice 记选择面。
local function _drive(choice, screen_overrides)
  local captured = { touch = {}, buttons = {}, opened = nil }
  local ui = {
    set_touch_enabled = function(_, name, enabled)
      captured.touch[name] = enabled
    end,
  }
  local screen = { underlay = "underlay_node", confirm = "confirm_node", cancel = "cancel_node" }
  for key, value in pairs(screen_overrides or {}) do
    screen[key] = value
  end

  _with_patches({
    { target = openers, key = "open_screen", value = function()
      return ui, screen
    end },
    { target = openers, key = "resolve_player_or_remote_options", value = function()
      return { { id = 10 } }
    end },
    { target = openers, key = "fill_option_nodes", value = function()
      return { 10 }, 10
    end },
    { target = openers, key = "set_action_button", value = function(_, button, visible, enabled, label)
      captured.buttons[button] = { visible = visible, enabled = enabled, label = label }
    end },
    { target = modal_state, key = "open_choice", value = function(_, choice_id, option_ids, selected)
      captured.opened = { choice_id = choice_id, option_ids = option_ids, selected = selected }
    end },
  }, function()
    option_screen.open({}, "player_choice", choice or {}, 7)
  end)
  return captured
end

describe("TestOptionScreen", function()
it("test_opens_with_underlay_touch_through_and_armed_confirm_cancel_buttons", function()
  -- kills L13 false->true、L17 双 true->false 与 "确定"->nil、
  -- L18 ~=->==、L19 "取消"->nil。
  local captured = _drive({})

  _assert_eq(captured.touch.underlay_node, false, "the underlay must let clicks pass through")
  _assert_eq(captured.buttons.confirm_node.visible, true, "confirm should be visible")
  _assert_eq(captured.buttons.confirm_node.enabled, true, "confirm should be enabled")
  _assert_eq(captured.buttons.confirm_node.label, "确定", "confirm label should be 确定")
  _assert_eq(captured.buttons.cancel_node.visible, true, "cancel should default to visible")
  _assert_eq(captured.buttons.cancel_node.enabled, true, "cancel should default to enabled")
  _assert_eq(captured.buttons.cancel_node.label, "取消", "cancel label should default to 取消")
  _assert_eq(captured.opened.choice_id, 7, "open_choice should carry the choice id")
  _assert_eq(captured.opened.selected, 10, "open_choice should carry the selection")
end)

it("test_underlay_touch_policy_differs_per_screen", function()
  -- #177:遥控骰子与玩家选择共享本 helper;仅遥控骰子开灰底触摸(点背景关闭),
  -- 玩家选择灰底保持穿透到基础屏取消按钮。
  local remote = require("src.ui.screens.remote_choice").descriptor()
  local player = require("src.ui.screens.player_choice").descriptor()

  local remote_captured = _drive({}, remote)
  local player_captured = _drive({}, player)

  _assert_eq(remote_captured.touch[remote.underlay], true, "remote underlay must catch clicks")
  _assert_eq(player_captured.touch[player.underlay], false, "player underlay must stay touch-through")
end)

it("test_disarms_the_cancel_button_when_the_choice_disallows_cancel", function()
  -- kills L18 ~=->== 与 false->true:allow_cancel=false 必须双双落 false;
  -- 自带 cancel_label 时必须用自带文案(kills L19 or->and)。
  local captured = _drive({ allow_cancel = false, cancel_label = "返回" })

  _assert_eq(captured.buttons.cancel_node.visible, false, "disallowed cancel should hide")
  _assert_eq(captured.buttons.cancel_node.enabled, false, "disallowed cancel should disable")
  _assert_eq(captured.buttons.cancel_node.label, "返回", "choice-provided cancel label should win")
end)


end)
