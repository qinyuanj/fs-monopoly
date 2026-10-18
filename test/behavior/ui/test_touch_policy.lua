-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
-- luacheck: ignore 211
local support = require("test.support.shared_support")
local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local _build_asset_context = support.build_asset_context
local _with_patches = support.with_patches
local ui_view = require("src.ui.coord.ui_runtime")
local ui_touch_policy = require("src.ui.input.touch")
local base_nodes = require("src.ui.schema.base")
local base_contract = require("src.ui.schema.base_contract")
local market_ui = require("src.ui.schema.market_layout")
local ids = require("test.fixtures.item_slot_ids")

describe("TestTouchPolicy", function()

it("test_apply_input_lock_keeps_auto_controls_enabled", function()
  -- 槽位 touch 预置成 true，模拟刷新阶段已把持卡槽位打开：输入锁**不得**把它关回去。
  local touch = { [ids.slot[1]] = true }
  local visible = {}
  local state = {
    ui_model = {
      current_player_id = 1,
      item_slots_by_player = { [1] = { 2001 } },
      panel = {
        auto_label = "托管",
        auto_label_by_player = { [1] = "托管" },
      },
    },
    ui = {
      input_blocked = true,
      item_slots = ids.slots(1),
      base_hidden_nodes = { "基础_行动按钮", ids.slot[1] },
      base_hidden_labels = {},
      auto_control_nodes = { "基础_托管按钮", "基础_托管文本" },
      choice_screens = {
        player = { option_buttons = {} },
        target = {},
        remote = { option_buttons = {} },
        secondary_confirm = { body = "通用二次确认_文本", cancel = "通用二次确认_取消", confirm = "通用二次确认_确定按钮" },
      },
      set_touch_enabled = function(_, name, enabled)
        touch[name] = enabled
      end,
      set_visible = function(_, name, value)
        visible[name] = value
      end,
      set_button = function() end,
    },
  }
  local roles = {
    { get_roleid = function() return 1 end },
  }

  _with_patches({
    { key = "all_roles", value = roles },
  }, function()
    ui_view.apply_input_lock(state)
  end)

  luassert.truthy(touch["基础_行动按钮"] == false, "action button should stay blocked")
  luassert.truthy(touch["基础_托管按钮"] == true, "auto button should stay enabled")
  luassert.truthy(touch["基础_托管文本"] == false, "auto label should stay non-clickable")
  luassert.truthy(touch[base_nodes.skin_button] == true, "skin button should stay enabled")
  luassert.truthy(touch[base_nodes.gallery_button] == true, "gallery button should stay enabled")
  luassert.truthy(touch[base_nodes.action_log_button] == true, "action log button should stay enabled")
  luassert.truthy(touch[base_nodes.end_button] == false, "optional end button should stay blocked")
  luassert.truthy(visible[ids.slot[1]] == true, "item slot should stay visible when locked")
  -- 输入锁不关道具槽 touch：槽位是「全时段可点、点了必有反馈」口径(#162)。
  -- 点击本身不推进状态——item_slot_click 在 turn 闸上豁免，裁定后要么发提示
  -- 要么转成 choice_select 再过一次闸。锁死 touch 会把移动动画等阶段位里的
  -- 点击变成零反馈，正是重做前 lock 与该口径互相打架的地方。
  luassert.truthy(touch[ids.slot[1]] == true, "input lock must not swallow item slot clicks")
end)

it("test_apply_input_lock_leaves_auxiliary_controls_enabled_when_unlocked", function()
  local touch = {}
  local state = {
    ui = {
      input_blocked = false,
      auto_control_nodes = { base_nodes.auto_button, base_nodes.auto_label },
      set_touch_enabled = function(_, name, enabled)
        touch[name] = enabled
      end,
    },
  }

  ui_view.apply_input_lock(state)

  luassert.truthy(touch[base_nodes.auto_button] == true, "unlocked auto button should remain touchable")
  luassert.truthy(touch[base_nodes.auto_label] == false, "auto label should stay non-clickable")
  luassert.truthy(touch[base_nodes.action_log_button] == true, "unlocked action log should remain touchable")
  luassert.truthy(touch[base_nodes.skin_button] == true, "unlocked skin button should remain touchable")
  luassert.truthy(touch[base_nodes.gallery_button] == true, "unlocked gallery button should remain touchable")
end)

it("test_apply_input_lock_noops_without_touch_hook", function()
  local visible_called = false
  local state = {
    ui = {
      input_blocked = true,
      set_visible = function()
        visible_called = true
      end,
    },
  }

  ui_view.apply_input_lock(state)

  luassert.truthy(visible_called == false, "input lock should not mutate visibility without touch hook")
end)

it("test_apply_input_lock_tolerates_missing_visible_hook", function()
  local touch = {}
  local state = {
    ui = {
      input_blocked = true,
      item_slots = {},
      base_hidden_nodes = { base_nodes.action_button, base_nodes.end_button },
      choice_screens = {
        player = { option_buttons = {} },
        target = {},
        remote = { option_buttons = {} },
        building = {},
      },
      set_touch_enabled = function(_, name, enabled)
        touch[name] = enabled
      end,
    },
  }

  ui_view.apply_input_lock(state)

  luassert.truthy(touch[base_nodes.action_button] == false, "action button should still be blocked")
  luassert.truthy(touch[base_nodes.end_button] == false, "end button should still be blocked")
end)

it("test_apply_input_lock_keeps_auto_button_enabled_when_role_unmapped", function()
  local touch = {}
  local state = {
    ui_model = {
      current_player_id = 1,
      item_slots_by_player = {},
      panel = {
        auto_label = "托管",
      },
    },
    ui = {
      input_blocked = true,
      item_slots = ids.slots(1),
      base_hidden_nodes = { "基础_行动按钮", ids.slot[1] },
      base_hidden_labels = {},
      auto_control_nodes = { "基础_托管按钮", "基础_托管文本" },
      choice_screens = {
        player = { option_buttons = {} },
        target = {},
        remote = { option_buttons = {} },
        secondary_confirm = { body = "通用二次确认_文本", cancel = "通用二次确认_取消", confirm = "通用二次确认_确定按钮" },
      },
      set_touch_enabled = function(_, name, enabled)
        touch[name] = enabled
      end,
      set_visible = function() end,
      set_button = function() end,
    },
  }
  local roles = {
    { get_roleid = function() return 1 end },
  }

  _with_patches({
    { key = "all_roles", value = roles },
  }, function()
    ui_view.apply_input_lock(state)
  end)

  luassert.truthy(touch["基础_托管按钮"] == true, "auto button should stay enabled when role mapping is missing")
  luassert.truthy(touch["基础_托管文本"] == false, "auto label should stay non-clickable when role mapping is missing")
end)

it("test_apply_input_lock_disables_always_show_controls_when_market_active", function()
  local touch = {}
  local state = {
    ui_model = {
      current_player_id = 1,
      item_slots_by_player = {},
      panel = {
        auto_label = "托管",
      },
    },
    ui = {
      input_blocked = true,
      market_active = true,
      item_slots = ids.slots(1),
      base_hidden_nodes = { "基础_行动按钮", ids.slot[1] },
      base_hidden_labels = {},
      auto_control_nodes = { "基础_托管按钮", "基础_托管文本" },
      choice_screens = {
        player = { option_buttons = {} },
        target = {},
        remote = { option_buttons = {} },
        secondary_confirm = { body = "通用二次确认_文本", cancel = "通用二次确认_取消", confirm = "通用二次确认_确定按钮" },
      },
      set_touch_enabled = function(_, name, enabled)
        touch[name] = enabled
      end,
      set_visible = function() end,
      set_button = function() end,
    },
  }
  local roles = {
    { get_roleid = function() return 1 end },
  }

  _with_patches({
    { key = "all_roles", value = roles },
  }, function()
    ui_view.apply_input_lock(state)
  end)

  luassert.truthy(touch["基础_托管按钮"] == false, "auto button should yield touch priority while market is active")
  luassert.truthy(touch["基础_托管文本"] == false, "auto label should stay non-clickable while market is active")
  luassert.truthy(touch["基础_行动日志图标"] == false, "action log toggle should yield touch priority while market is active")
  luassert.truthy(touch[base_nodes.skin_button] == false, "skin button should yield touch priority while market is active")
  luassert.truthy(touch[base_nodes.gallery_button] == false, "gallery button should yield touch priority while market is active")
end)

it("test_apply_input_lock_keeps_market_cancel_enabled_when_market_active", function()
  local touch = {}
  local state = {
    ui = {
      input_blocked = true,
      market_active = true,
      item_slots = {},
      base_hidden_nodes = {},
      choice_screens = {
        player = { option_buttons = {} },
        target = {},
        remote = { option_buttons = {} },
        building = {},
      },
      set_touch_enabled = function(_, name, enabled)
        touch[name] = enabled
      end,
      set_visible = function() end,
    },
  }

  ui_view.apply_input_lock(state)

  _assert_eq(touch[market_ui.confirm_button], false, "market buy should stay blocked during post-purchase input lock")
  _assert_eq(touch[market_ui.cancel_button], true, "market close should stay touchable so it can end the market flow")
  _assert_eq(touch[market_ui.cancel_button_alt], true, "alternate market cancel should stay touchable too")
  for _, name in ipairs(market_ui.item_buttons) do
    _assert_eq(touch[name], false, "market item buttons must be disabled by the input lock (kills `or {}` -> `and {}` and false -> true)")
  end
end)

it("test_apply_input_lock_preserves_skin_entry_visibility_decided_by_panel_refresh", function()
  local visible = {
    [base_nodes.auto_button] = true,
    [base_nodes.auto_label] = true,
    [base_nodes.action_log_button] = true,
    [base_nodes.skin_button] = true,
    [base_nodes.skin_label] = true,
    [base_nodes.gallery_button] = true,
  }
  local state = {
    ui_model = {
      current_player_id = 2,
      item_slots_by_player = { [1] = {}, [2] = {} },
      panel = {
        auto_label = "托管",
        auto_label_by_player = { [1] = "托管", [2] = "托管" },
      },
    },
    ui = {
      input_blocked = true,
      item_slots = ids.slots(1),
      base_hidden_nodes = {
        base_nodes.action_button,
        base_nodes.auto_button,
        base_nodes.auto_label,
        base_nodes.action_log_button,
        base_nodes.skin_button,
        base_nodes.skin_label,
        base_nodes.gallery_button,
        ids.slot[1],
      },
      base_hidden_labels = {},
      auto_control_nodes = { base_nodes.auto_button, base_nodes.auto_label },
      choice_screens = {
        player = { option_buttons = {} },
        target = {},
        remote = { option_buttons = {} },
        secondary_confirm = { body = "通用二次确认_文本", cancel = "通用二次确认_取消", confirm = "通用二次确认_确定按钮" },
      },
      set_touch_enabled = function() end,
      set_visible = function(_, name, value)
        visible[name] = value
      end,
      set_button = function() end,
    },
  }

  ui_view.apply_input_lock(state)

  luassert.truthy(visible[base_nodes.action_button] == false, "input lock should still hide action button")
  luassert.truthy(visible[ids.slot[1]] == true, "input lock should still force item slots visible")
  luassert.truthy(visible[base_nodes.skin_button] == true,
    "input lock must not override the panel refresh decision for skin button visibility")
  luassert.truthy(visible[base_nodes.skin_label] == true,
    "input lock must not override the panel refresh decision for skin label visibility")
  luassert.truthy(visible[base_nodes.gallery_button] == true,
    "input lock must not hide the gallery entry")
  luassert.truthy(visible[base_nodes.auto_button] == true,
    "input lock must not hide the auto entry")
  luassert.truthy(visible[base_nodes.auto_label] == true,
    "input lock must not hide the auto label")
  luassert.truthy(visible[base_nodes.action_log_button] == true,
    "input lock must not hide the action log entry")
end)

it("test_apply_input_lock_tolerates_false_choice_screens", function()
  local touch = {}
  local state = {
    ui = {
      input_blocked = true,
      item_slots = {},
      base_hidden_nodes = {},
      choice_screens = false,
      set_touch_enabled = function(_, name, enabled)
        touch[name] = enabled
      end,
      set_visible = function() end,
    },
  }

  ui_view.apply_input_lock(state)

  luassert.truthy(touch[base_nodes.action_button] == false, "locked action button should still be blocked")
  luassert.truthy(touch[base_nodes.end_button] == false, "locked end button should still be blocked")
end)

it("test_ui_view_render_auto_button_keeps_local_touch_when_unmapped_role_exists", function()
  local touch_logs = {}
  local state = {
    runtime_asset_context = _build_asset_context({ ["Empty"] = "EMPTY", ["2001"] = "ICON2001" }),
    ui = {
      item_slots = ids.slots(1),
      base_hidden_nodes = { "基础_行动按钮", ids.slot[1] },
      base_hidden_labels = {},
      auto_control_nodes = { "基础_托管按钮", "基础_托管文本" },
      set_label = function() end,
      set_visible = function() end,
      set_touch_enabled = function(_, name, enabled)
        local role = UIManager and UIManager.client_role or nil
        local role_id = role and role.get_roleid and role.get_roleid() or 0
        touch_logs[role_id] = touch_logs[role_id] or {}
        touch_logs[role_id][name] = enabled
      end,
      query_node = function()
        return {}
      end,
    },
  }
  local ui_model = {
    panel = {
      turn_label = "倒计时:0",
      auto_label = "托管",
      auto_label_by_player = {
        [1] = "托管",
      },
      player_rows = {
        { name = "P1", avatar = nil, cash = "", land_count = "", total_assets = "" },
        { name = "P2", avatar = nil, cash = "", land_count = "", total_assets = "" },
        { name = "P3", avatar = nil, cash = "", land_count = "", total_assets = "" },
        { name = "P4", avatar = nil, cash = "", land_count = "", total_assets = "" },
      },
    },
    board = { players = {} },
    current_player_id = 1,
    delegated_by_player = { [1] = false },
    item_slots_by_player = { [1] = { 2001 } },
  }
  local local_role = {
    get_roleid = function()
      return 1
    end,
  }
  local unmapped_role = {
    get_roleid = function()
      return 99
    end,
  }

  _with_patches({
    { key = "all_roles", value = { local_role, unmapped_role } },
    { key = "UIManager", value = {
      client_role = local_role,
      query_nodes_by_name = function()
        return { {} }
      end,
    } },
  }, function()
    ui_view.refresh_panel(state, ui_model)
  end)

  luassert.truthy(touch_logs[1] and touch_logs[1]["基础_托管按钮"] == true, "local role auto button should stay enabled")
  luassert.truthy(touch_logs[99] and touch_logs[99]["基础_托管按钮"] == false, "unmapped role auto button should stay disabled")
end)

it("test_ui_touch_policy_auto_controls_touch", function()
  local touch = {}
  local ui = {
    auto_control_nodes = { "基础_托管按钮", "基础_托管文本" },
    set_touch_enabled = function(_, name, enabled)
      touch[name] = enabled
    end,
  }

  ui_touch_policy.set_auto_controls_touch(ui, true)
  _assert_eq(touch["基础_托管按钮"], true, "auto button should be clickable when enabled")
  _assert_eq(touch["基础_托管文本"], false, "auto label should stay non-clickable")
  _assert_eq(touch["基础_托管按钮特效"], false, "auto effect should stay non-clickable")

  ui_touch_policy.set_auto_controls_touch(ui, false)
  _assert_eq(touch["基础_托管按钮"], false, "auto button should be non-clickable when disabled")
  _assert_eq(touch["基础_托管文本"], false, "auto label should stay non-clickable when disabled")
  _assert_eq(touch["基础_托管按钮特效"], false, "auto effect should stay non-clickable when disabled")
end)

it("test_set_many_touch_enabled_noops_when_ui_lacks_hook", function()
  -- Pins L7 guard `not ui or not ui.set_touch_enabled`: an `and` mutant proceeds and
  -- calls the missing hook instead of returning cleanly.
  local ok = pcall(function()
    ui_touch_policy.set_many_touch_enabled({}, { base_nodes.action_button }, true)
  end)
  luassert.truthy(ok, "set_many_touch_enabled should noop when ui has no set_touch_enabled hook")
end)

it("test_set_auto_controls_touch_noops_when_ui_lacks_hook", function()
  -- Pins L41 guard mirror.
  local ok = pcall(function()
    ui_touch_policy.set_auto_controls_touch({}, true)
  end)
  luassert.truthy(ok, "set_auto_controls_touch should noop when ui has no set_touch_enabled hook")
end)

it("test_set_action_log_toggle_touch_noops_when_ui_lacks_hook", function()
  -- Pins L51 guard mirror.
  local ok = pcall(function()
    ui_touch_policy.set_action_log_toggle_touch({}, true)
  end)
  luassert.truthy(ok, "set_action_log_toggle_touch should noop when ui has no set_touch_enabled hook")
end)

it("test_set_auto_controls_touch_drives_ui_auto_control_nodes_when_no_override", function()
  -- Pins L22 second `or`: `controls or ui.auto_control_nodes or default`; an `and` mutant
  -- would drop the resolved node list and fall through to the default node set.
  local touch = {}
  local ui = {
    auto_control_nodes = { "自定义_托管节点" },
    set_touch_enabled = function(_, name, enabled)
      touch[name] = enabled
    end,
  }

  ui_touch_policy.set_auto_controls_touch(ui, false)

  _assert_eq(touch["自定义_托管节点"], false,
    "should drive ui.auto_control_nodes rather than the built-in default node set")
end)

it("test_set_auto_controls_touch_skips_effect_fallback_when_effect_in_controls", function()
  -- Pins L34 `auto_effect_seen = true`: a `false` mutant re-touches auto_effect through the
  -- fallback branch, doubling the number of writes to that node.
  local counts = {}
  local ui = {
    set_touch_enabled = function(_, name, _enabled)
      counts[name] = (counts[name] or 0) + 1
    end,
  }

  ui_touch_policy.set_auto_controls_touch(ui, true, { base_nodes.auto_button, base_nodes.auto_effect })

  _assert_eq(counts[base_nodes.auto_effect], 1,
    "auto_effect present in controls should be touched exactly once (no fallback write)")
end)

it("test_set_action_log_toggle_touch_falls_back_to_default_target", function()
  -- Pins L56 `toggle_targets or { action_log_button }`: an `and` mutant breaks the nil-config
  -- fallback and iterates a nil target list.
  local touch = {}
  local ui = {
    set_touch_enabled = function(_, name, enabled)
      touch[name] = enabled
    end,
  }

  _with_patches({
    { target = base_contract.action_log, key = "toggle_targets", value = nil },
  }, function()
    ui_touch_policy.set_action_log_toggle_touch(ui, true)
  end)

  _assert_eq(touch[base_nodes.action_log_button], true,
    "nil toggle_targets should fall back to the default action-log button")
end)

it("test_set_choice_screen_locked_blocks_all_targets", function()
  -- Pins the L75 guard `not ...` terms: any removed `not` short-circuits to an early return,
  -- leaving the choice-screen targets un-locked.
  local touch = {}
  local ui = {
    set_touch_enabled = function(_, name, enabled)
      touch[name] = enabled
    end,
  }
  local screen = {
    option_buttons = { "选项_1", "选项_2" },
    under_button = "下注按钮",
    confirm = "确认按钮",
    cancel = "取消按钮",
  }

  ui_touch_policy.set_choice_screen_locked(ui, screen)

  _assert_eq(touch["选项_1"], false, "option button should be locked")
  _assert_eq(touch["选项_2"], false, "option button should be locked")
  _assert_eq(touch["下注按钮"], false, "under button should be locked")
  _assert_eq(touch["确认按钮"], false, "confirm should be locked")
  _assert_eq(touch["取消按钮"], false, "cancel should be locked")
end)

it("test_set_choice_screen_locked_noops_without_screen", function()
  -- Pins the L75 guard `or not screen`: an `and` mutant proceeds and indexes a nil screen.
  local ui = { set_touch_enabled = function() end }
  local ok = pcall(function()
    ui_touch_policy.set_choice_screen_locked(ui, nil)
  end)
  luassert.truthy(ok, "set_choice_screen_locked should noop when screen is nil")
end)

it("test_set_choice_screen_locked_noops_when_ui_lacks_hook", function()
  -- Pins the L75 guard `or not ui.set_touch_enabled`: an `and` mutant proceeds and calls the
  -- missing hook while locking the under button.
  local ok = pcall(function()
    ui_touch_policy.set_choice_screen_locked({}, { under_button = "下注按钮" })
  end)
  luassert.truthy(ok, "set_choice_screen_locked should noop when ui has no set_touch_enabled hook")
end)

it("test_set_many_touch_enabled_noops_when_names_is_not_a_table", function()
  -- Pins the `type(names) ~= "table"` guard: names may arrive as a bare node name.
  local calls = {}
  local ui = {
    set_touch_enabled = function(_, name, value)
      calls[#calls + 1] = { name = name, value = value }
    end,
  }
  ui_touch_policy.set_many_touch_enabled(ui, "基础_行动按钮", true)
  _assert_eq(#calls, 0, "a non-table names argument must touch nothing")
end)

it("test_set_many_touch_enabled_skips_nil_holes_and_coerces_enabled", function()
  local calls = {}
  local ui = {
    set_touch_enabled = function(_, name, value)
      calls[#calls + 1] = { name = name, value = value }
    end,
  }
  -- 表里带空洞：nil 槽位跳过；enabled 非 true 一律落 false。
  ui_touch_policy.set_many_touch_enabled(ui, { "a", false, "b" }, "truthy-but-not-true")
  _assert_eq(#calls, 2, "nil/false holes are skipped")
  _assert_eq(calls[1].name, "a", "first name")
  _assert_eq(calls[1].value, false, "enabled coerced with == true")
  _assert_eq(calls[2].name, "b", "second name")
end)


end)
