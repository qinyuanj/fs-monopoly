require("test.bootstrap").install_package_paths()

local luassert = assert
local guard = require("test.guards.lib.choice_touch_guard")

-- 选择屏装饰节点吸触摸的回归门禁(9e9ae37):遥控骰子屏的面板/选项区/标题/正文压住
-- 基础_取消按钮。合成用例喂 check 验证能变红;真实仓库用例放在本 spec 而不是共享的
-- test_guard_runner,guards 车道按 test_ 前缀自动发现。

local _NODES = {
  ["甲屏"] = "ECanvas",
  ["甲_灰底"] = "EImage",
  ["甲_面板"] = "EImage",
  ["甲_标题"] = "ELabel",
  ["甲_选项"] = "EButton",
}

local function _screen(overrides)
  local screen = {
    key = "demo",
    uses_option_screen = true,
    schema = {},
    descriptor = {
      root = "甲屏",
      underlay = "甲_灰底",
      option_buttons = { "甲_选项" },
      passthrough_nodes = { "甲_面板", "甲_标题" },
    },
  }
  for key, value in pairs(overrides or {}) do
    screen[key] = value
  end
  return screen
end

local function _rule(overrides)
  local rule = { prefixes = { "甲_" }, exempt = {}, pending_device_check = {} }
  for key, value in pairs(overrides or {}) do
    rule[key] = value
  end
  return rule
end

local function _check(screen, rule, nodes)
  return guard.check({
    nodes = nodes or _NODES,
    screens = { screen or _screen() },
    rules = { demo = rule or _rule() },
  })
end

local function _with_descriptor(fields)
  local descriptor = {
    root = "甲屏",
    underlay = "甲_灰底",
    option_buttons = { "甲_选项" },
    passthrough_nodes = { "甲_面板", "甲_标题" },
  }
  for key, value in pairs(fields) do
    descriptor[key] = value
  end
  return _screen({ descriptor = descriptor })
end

local function _assert_single(violations, ...)
  local joined = table.concat(violations, "\n")
  assert(#violations == 1, "expected exactly 1 violation:\n" .. joined)
  for _, fragment in ipairs({ ... }) do
    assert(violations[1]:find(fragment, 1, true), "missing fragment " .. fragment .. ":\n" .. joined)
  end
end

local function _without(list, name)
  local out = {}
  for _, item in ipairs(list) do
    if item ~= name then
      out[#out + 1] = item
    end
  end
  return out
end

describe("TestChoiceTouchGuard", function()
  it("test_passes_when_every_decoration_is_listed_in_passthrough", function()
    luassert.is.same({}, _check())
  end)

  it("test_buttons_canvas_and_underlay_need_no_listing", function()
    local nodes = { ["甲屏"] = "ECanvas", ["甲_灰底"] = "EImage", ["甲_选项"] = "EButton" }
    local violations = _check(_with_descriptor({ passthrough_nodes = {} }), nil, nodes)
    luassert.is.same({}, violations)
  end)

  it("test_flags_a_decoration_missing_from_passthrough", function()
    local violations = _check(_with_descriptor({ passthrough_nodes = { "甲_标题" } }))
    _assert_single(violations, "demo", "甲_面板", "passthrough")
  end)

  it("test_dropping_a_real_remote_passthrough_entry_turns_red", function()
    local input = guard.load_input()
    for _, screen in ipairs(input.screens) do
      local descriptor = screen.descriptor
      descriptor.passthrough_nodes = _without(descriptor.passthrough_nodes or {}, "遥控骰子_面板")
    end
    _assert_single(guard.check(input), "remote", "遥控骰子_面板")
  end)

  it("test_schema_passthrough_not_wired_into_the_descriptor_is_flagged", function()
    local screen = _with_descriptor({ passthrough_nodes = {} })
    screen.schema = { passthrough = { "甲_面板", "甲_标题" } }
    luassert.is.equal(2, #_check(screen))
  end)

  it("test_judges_buttons_by_node_type_not_by_name", function()
    local nodes = { ["甲屏"] = "ECanvas", ["甲_下一页按钮"] = "ELabel" }
    local screen = _with_descriptor({ underlay = false, option_buttons = {}, passthrough_nodes = {} })
    _assert_single(_check(screen, nil, nodes), "甲_下一页按钮")
  end)

  it("test_a_grey_node_not_declared_as_underlay_still_counts_as_decoration", function()
    local screen = _with_descriptor({ underlay = false })
    _assert_single(_check(screen), "甲_灰底")
  end)

  it("test_schema_declared_node_outside_the_prefix_belongs_to_the_canvas", function()
    local nodes = { ["甲屏"] = "ECanvas", ["甲_灰底"] = "EImage", ["甲_面板"] = "EImage",
      ["甲_标题"] = "ELabel", ["甲_选项"] = "EButton", ["孤儿背景"] = "EImage" }
    local screen = _screen({ schema = { background = "孤儿背景" } })
    _assert_single(_check(screen, nil, nodes), "孤儿背景")
  end)

  it("test_exempt_or_pending_entry_with_a_reason_passes", function()
    local screen = _with_descriptor({ passthrough_nodes = {} })
    local rule = _rule({
      exempt = { ["甲_面板"] = "开屏路径已关触摸" },
      pending_device_check = { ["甲_标题"] = "待真机确认是否压住按钮" },
    })
    luassert.is.same({}, _check(screen, rule))
  end)

  it("test_exempt_entry_without_a_reason_is_flagged", function()
    local screen = _with_descriptor({ passthrough_nodes = { "甲_标题" } })
    _assert_single(_check(screen, _rule({ exempt = { ["甲_面板"] = "  " } })), "甲_面板", "理由")
  end)

  it("test_pending_entry_without_a_reason_is_flagged", function()
    local screen = _with_descriptor({ passthrough_nodes = { "甲_标题" } })
    _assert_single(_check(screen, _rule({ pending_device_check = { ["甲_面板"] = "" } })), "甲_面板", "理由")
  end)

  it("test_stale_entry_for_a_renamed_node_is_flagged", function()
    _assert_single(_check(nil, _rule({ exempt = { ["甲_旧名"] = "改名前的理由" } })), "甲_旧名", "过期")
  end)

  it("test_entry_already_covered_by_passthrough_is_flagged_as_stale", function()
    local rule = _rule({ pending_device_check = { ["甲_面板"] = "已修好没销账" } })
    _assert_single(_check(nil, rule), "甲_面板", "过期")
  end)

  it("test_passthrough_naming_an_unknown_node_is_flagged", function()
    local screen = _with_descriptor({ passthrough_nodes = { "甲_面板", "甲_标题", "甲_不存在" } })
    _assert_single(_check(screen), "甲_不存在", "UIManagerNodes")
  end)

  it("test_passthrough_must_not_swallow_a_button", function()
    local screen = _with_descriptor({ passthrough_nodes = { "甲_面板", "甲_标题", "甲_选项" } })
    _assert_single(_check(screen), "甲_选项", "按钮")
  end)

  it("test_passthrough_on_a_screen_outside_option_screen_is_flagged_as_not_applied", function()
    _assert_single(_check(_screen({ uses_option_screen = false })), "demo", "_option_screen")
  end)

  it("test_new_choice_screen_without_rules_is_flagged", function()
    local violations = guard.check({ nodes = _NODES, screens = { _screen() }, rules = {} })
    _assert_single(violations, "demo", "未登记")
  end)

  it("test_rules_for_a_removed_screen_are_flagged", function()
    local violations = guard.check({ nodes = _NODES, screens = {}, rules = { demo = _rule() } })
    _assert_single(violations, "demo", "过期")
  end)

  it("test_prefix_matching_no_node_is_flagged_instead_of_passing_empty", function()
    local rule = _rule({ prefixes = { "甲_", "乙_" } })
    _assert_single(_check(nil, rule), "乙_", "前缀")
  end)

  it("test_load_input_discovers_exactly_the_four_choice_screens", function()
    local keys = {}
    for _, screen in ipairs(guard.load_input().screens) do
      keys[#keys + 1] = screen.key
    end
    table.sort(keys)
    luassert.is.same({ "player", "remote", "secondary_confirm", "target" }, keys)
  end)

  it("test_real_repo_passes", function()
    local result = guard.run()
    luassert.is_true(result.ok, result.error)
  end)
end)
