-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
local event_intents = require("src.ui.input.event_intents")

-- warn_label 用 spec_synthetic：负路径 warn 文案带保留前缀，
-- 由 test/support/behavior_warns_data.lua 白名单整体豁免。

local function _assert_eq(a, b, msg)
  luassert.truthy(a == b, tostring(msg) .. ": expected " .. tostring(b) .. " got " .. tostring(a))
end

local function _make_state(opts)
  opts = opts or {}
  return {
    ui_runtime = {
      ui_model = opts.model,
      pending_choice_selected_option_id = opts.selected_option,
      choice_visible_option_ids = opts.visible_ids,
    },
  }
end

describe("TestEventIntents", function()

it("test_returns_nil_when_no_choice_in_model", function()
  local state = _make_state({ model = {} })
  local result = event_intents.choice_confirm_intent(state, "spec_synthetic")
  luassert.truthy(result == nil, "should return nil when no choice")
end)

it("test_returns_choice_select_with_pending_option", function()
  local state = _make_state({
    model = { choice = { id = "c1" } },
    selected_option = "opt_a",
  })
  local result = event_intents.choice_confirm_intent(state, "spec_synthetic")
  luassert.truthy(result ~= nil, "should return intent")
  _assert_eq(result.type, "choice_select", "type")
  _assert_eq(result.choice_id, "c1", "choice_id")
  _assert_eq(result.option_id, "opt_a", "option_id")
end)

it("test_falls_back_to_first_visible_option_when_no_pending", function()
  local state = _make_state({
    model = { choice = { id = "c2" } },
    visible_ids = { "first", "second" },
  })
  local result = event_intents.choice_confirm_intent(state, "spec_synthetic")
  luassert.truthy(result ~= nil, "should return intent")
  _assert_eq(result.option_id, "first", "should use first visible option")
end)

it("test_returns_nil_when_no_pending_and_no_visible_options", function()
  local state = _make_state({
    model = { choice = { id = "c3" } },
  })
  local result = event_intents.choice_confirm_intent(state, "spec_synthetic")
  luassert.truthy(result == nil, "should return nil when no option available")
end)

it("test_returns_nil_when_no_choice", function()
  local state = _make_state({ model = {} })
  luassert.truthy(event_intents.choice_cancel_intent(state, "spec_synthetic") == nil,
    "should return nil without choice")
end)

it("test_returns_cancel_intent_when_allowed", function()
  local state = _make_state({ model = { choice = { id = "c1" } } })
  local result = event_intents.choice_cancel_intent(state, "spec_synthetic")
  luassert.truthy(result ~= nil, "should return intent")
  _assert_eq(result.type, "choice_cancel", "type")
  _assert_eq(result.choice_id, "c1", "choice_id")
end)

it("test_returns_nil_when_cancel_disallowed", function()
  local state = _make_state({ model = { choice = { id = "c1", allow_cancel = false } } })
  luassert.truthy(event_intents.choice_cancel_intent(state, "spec_synthetic") == nil,
    "should return nil when allow_cancel is false")
end)

it("test_returns_the_option_id_carried_directly_on_the_payload", function()
  local choice = { id = "c1", options = { { id = "o1" } } }
  local result = event_intents.resolve_option_id(choice, { option_id = "opt_a" }, nil)
  _assert_eq(result, "opt_a", "payload option_id wins over index lookup")
end)

it("test_falls_back_to_the_choice_option_at_the_payload_index", function()
  local choice = { id = "c1", options = { { id = "o1" }, { id = "o2" } } }
  local result = event_intents.resolve_option_id(choice, { index = 2 }, nil)
  _assert_eq(result, "o2", "option resolved by index")
end)

it("test_returns_nil_when_the_payload_carries_neither_an_option_id_nor_an_index", function()
  local choice = { id = "c1", options = { { id = "o1" } } }
  luassert.truthy(event_intents.resolve_option_id(choice, {}, nil) == nil,
    "should return nil for an empty payload")
end)

it("test_returns_nil_when_no_choice_2", function()
  local state = _make_state({ model = {} })
  luassert.truthy(event_intents.choice_select_intent(state, 1, "spec_synthetic") == nil,
    "should return nil without choice")
end)

it("test_returns_select_intent_by_index_via_visible_ids", function()
  local state = _make_state({
    model = { choice = { id = "c1", options = {} } },
    visible_ids = { "opt_x", "opt_y" },
  })
  local result = event_intents.choice_select_intent(state, 1, "spec_synthetic")
  luassert.truthy(result ~= nil, "should return intent")
  _assert_eq(result.type, "choice_select", "type")
  _assert_eq(result.option_id, "opt_x", "option_id")
end)

it("test_returns_select_intent_by_index_via_choice_options", function()
  local state = _make_state({
    model = { choice = { id = "c1", options = { { id = "o1" }, { id = "o2" } } } },
  })
  local result = event_intents.choice_select_intent(state, 2, "spec_synthetic")
  luassert.truthy(result ~= nil, "should return intent")
  _assert_eq(result.option_id, "o2", "option_id from choice options")
end)

it("test_resolve_option_id_rejects_missing_choice_and_payload_with_messages", function()
  -- #293: L44/L45 assert 消息变异(消息串翻 nil)——缺 choice / 缺 payload 必须
  -- 报出标识消息。
    local support = require("test.support.shared_support")
  local logger = require("src.foundation.log")
  local state = _make_state({})
  support.with_patches({
    { target = logger, key = "warn", value = function() end },
  }, function()
    luassert.has_error(function()
      event_intents.resolve_option_id(nil, { option_id = "o1" }, state)
    end, "missing choice")
    luassert.has_error(function()
      event_intents.resolve_option_id({ id = "c1" }, nil, state)
    end, "missing payload")
  end)
end)

it("test_choice_select_does_not_warn_when_choice_present", function()
  -- #293: L60 _resolve_choice_or_warn 的 not 变异(choice 存在时也 warn)——有
  -- choice 的路径必须零告警。
  local support = require("test.support.shared_support")
  local logger = require("src.foundation.log")
  local warns = {}
  local choice = { id = "c1", options = { { id = "o1" } } }
  local state = _make_state({ model = { choice = choice } })
  support.with_patches({
    { target = logger, key = "warn", value = function(...) warns[#warns + 1] = table.concat({ ... }, " ") end },
  }, function()
    local result = event_intents.choice_select_intent(state, 1, "spec_synthetic")
    _assert_eq(result and result.option_id, "o1", "select intent should resolve the option")
    _assert_eq(#warns, 0, "a present choice must not warn")
  end)
end)

it("test_choice_select_warns_missing_option_with_index", function()
  -- #293: L84 的日志字符串与 tostring(index) 变异——索引解析不出 option 时
  -- 告警必须带上索引。
  local support = require("test.support.shared_support")
  local logger = require("src.foundation.log")
  local warns = {}
  local choice = { id = "c1", options = {} }
  local state = _make_state({ model = { choice = choice } })
  support.with_patches({
    { target = logger, key = "warn", value = function(...) warns[#warns + 1] = table.concat({ ... }, " ") end },
  }, function()
    local result = event_intents.choice_select_intent(state, 7, "spec_synthetic")
    _assert_eq(result, nil, "an unresolvable index yields no intent")
    _assert_eq(#warns, 1, "an unresolvable index must warn")
    luassert.truthy(warns[1]:find("missing option", 1, true) ~= nil, "warn must identify 'missing option'")
    luassert.truthy(warns[1]:find("7", 1, true) ~= nil, "warn must carry the missing index")
  end)
end)


end)
