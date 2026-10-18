-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local _with_patches = support.with_patches

local policy = require("src.ui.coord.event_actor_policy")
local local_actor_resolver = require("src.ui.render.support.local_actor_resolver")
local tip_queue = require("src.foundation.tips")
local logger = require("src.foundation.log")


describe("TestEventActorPolicy", function()

it("test_classifies_actor_bound_intents_and_ui_buttons", function()
  local actor_types = {
    "toggle_action_log", "open_skin_panel", "open_gallery_panel",
    "skin_panel_action", "item_atlas_action", "skin_gallery_action",
    "choice_select", "choice_cancel", "complete_optional_action_phase",
    "market_confirm", "market_page_prev", "market_page_next", "market_tab_select",
  }

  _assert_eq(policy.requires_event_actor(nil), false, "nil intent should not require actor")
  _assert_eq(policy.requires_event_actor("bad"), false, "non-table intent should not require actor")
  for _, intent_type in ipairs(actor_types) do
    _assert_eq(policy.requires_event_actor({ type = intent_type }), true,
      intent_type .. " should require an event actor")
  end
  _assert_eq(policy.requires_event_actor({ type = "market_select" }), false,
    "market_select only changes UI selection and should not require actor")
  _assert_eq(policy.requires_event_actor({ type = "ui_button", id = "next" }), true,
    "next button should require actor")
  _assert_eq(policy.requires_event_actor({ type = "ui_button", id = "auto" }), true,
    "auto button should require actor")
  -- 道具槽点击已不是 ui_button：intent 自成一类，槽位号随 intent 携带
  _assert_eq(policy.requires_event_actor({ type = "item_slot_click", slot_index = 12 }), true,
    "item_slot_click should require an event actor")
  _assert_eq(policy.requires_event_actor({ type = "ui_button", id = "item_slot_12" }), false,
    "item_slot_N button is no longer a command and falls back to the generic ui_button")
  _assert_eq(policy.requires_event_actor({ type = "ui_button", id = 12 }), false,
    "unknown button id should fall back to the generic ui_button")
end)

it("test_classifies_local_only_actor_resolution_intents", function()
  local local_types = {
    "toggle_action_log", "open_skin_panel", "open_gallery_panel",
    "skin_panel_action", "item_atlas_action", "skin_gallery_action",
  }

  _assert_eq(policy.uses_local_actor(nil), false, "nil intent should not use local actor")
  _assert_eq(policy.uses_local_actor("bad"), false, "non-table intent should not use local actor")
  for _, intent_type in ipairs(local_types) do
    _assert_eq(policy.uses_local_actor({ type = intent_type }), true,
      intent_type .. " should use local actor resolution")
  end
  _assert_eq(policy.uses_local_actor({ type = "choice_select" }), false,
    "choice_select should use turn-bound actor resolution")
  _assert_eq(policy.uses_local_actor({ type = "market_confirm" }), false,
    "market_confirm should use turn-bound actor resolution")
  _assert_eq(policy.uses_local_actor({ type = "ui_button", id = "auto" }), true,
    "auto button should use local actor resolution")
  _assert_eq(policy.uses_local_actor({ type = "ui_button", id = "next" }), false,
    "next button should use turn-bound actor resolution")
  -- 道具槽点击者是"谁按的"，不是当前回合玩家；是否越权由 turn 侧裁定
  _assert_eq(policy.uses_local_actor({ type = "item_slot_click", slot_index = 1 }), true,
    "item_slot_click should use local actor resolution")
end)

it("test_resolves_local_and_turn_bound_actor_ids_through_the_correct_resolver", function()
  local calls = {}

  _with_patches({
    { target = local_actor_resolver, key = "resolve_from_event", value = function(state, data)
      calls[#calls + 1] = "local:" .. tostring(state.name) .. ":" .. tostring(data.name)
      return 7
    end },
    { target = local_actor_resolver, key = "resolve_turn_bound", value = function(state, data)
      calls[#calls + 1] = "turn:" .. tostring(state.name) .. ":" .. tostring(data.name)
      return 8
    end },
  }, function()
    _assert_eq(policy.resolve_actor_role_id({ name = "s" }, { type = "open_skin_panel" }, { name = "d" }), 7,
      "skin panel should resolve from local event")
    _assert_eq(policy.resolve_actor_role_id({ name = "s" }, { type = "ui_button", id = "auto" }, { name = "d" }), 7,
      "auto should resolve from local event")
    _assert_eq(policy.resolve_actor_role_id({ name = "s" }, { type = "choice_select" }, { name = "d" }), 8,
      "choice_select should resolve from turn-bound actor")
    _assert_eq(policy.resolve_actor_role_id({ name = "s" }, { type = "ui_button", id = "next" }, { name = "d" }), 8,
      "next should resolve from turn-bound actor")
    _assert_eq(policy.resolve_actor_role_id({ name = "s" }, { type = "item_slot_click", slot_index = 1 }, { name = "d" }), 7,
      "item_slot_click should resolve the clicking role from the local event")
  end)

  _assert_eq(table.concat(calls, ","), "local:s:d,local:s:d,turn:s:d,turn:s:d,local:s:d",
    "policy should call the expected resolver for each intent")
end)

it("test_attaches_preserves_allows_optional_and_rejects_missing_actors", function()
  local tips = {}
  local warns = {}

  _with_patches({
    { target = local_actor_resolver, key = "resolve_from_event", value = function(_, data)
      return data and data.actor or nil
    end },
    { target = local_actor_resolver, key = "resolve_turn_bound", value = function(_, data)
      return data and data.turn_actor or nil
    end },
    { target = tip_queue, key = "enqueue", value = function(payload)
      tips[#tips + 1] = payload
    end },
    { target = logger, key = "warn", value = function(...)
      warns[#warns + 1] = table.concat({ ... }, "|")
    end },
  }, function()
    local preset = { type = "choice_select", actor_role_id = 99 }
    _assert_eq(policy.attach_event_actor({}, preset, {}), true, "pre-set actor should pass")
    _assert_eq(preset.actor_role_id, 99, "pre-set actor should not be overwritten")

    local optional = { type = "open_skin_panel" }
    _assert_eq(policy.attach_event_actor({}, optional, {}), true,
      "optional open_skin_panel should pass without actor")
    _assert_eq(optional.actor_role_id, nil, "optional missing actor should stay nil")

    local local_intent = { type = "skin_panel_action" }
    _assert_eq(policy.attach_event_actor({}, local_intent, { actor = 7 }), true,
      "local actor should attach")
    _assert_eq(local_intent.actor_role_id, 7, "local actor id should be written")

    local turn_intent = { type = "choice_cancel" }
    _assert_eq(policy.attach_event_actor({}, turn_intent, { turn_actor = 8 }), true,
      "turn-bound actor should attach")
    _assert_eq(turn_intent.actor_role_id, 8, "turn-bound actor id should be written")

    local rejected = { type = "ui_button", id = "next" }
    _assert_eq(policy.attach_event_actor({}, rejected, {}), false,
      "required missing actor should be rejected")
    _assert_eq(rejected.actor_role_id, nil, "rejected intent should not gain actor")
  end)

  _assert_eq(#tips, 1, "only the rejected required actor should enqueue tip")
  _assert_eq(tips[1].text, "当前操作缺少玩家上下文，已忽略", "missing actor tip text should be stable")
  _assert_eq(tips[1].duration, 2.0, "missing actor tip duration should be fixed")
  _assert_eq(tips[1].dedupe_key, "missing_actor:ui_button:next", "missing actor dedupe key should include type and id")
  _assert_eq(tips[1].blocks_inter_turn, false, "missing actor tip should not block inter-turn")
  _assert_eq(tips[1].source, "ui.missing_actor", "missing actor source should be stable")
  _assert_eq(#warns, 1, "missing actor rejection should warn once")
  -- 精确钉整条 warn(#262,kills warn 第二处 tostring(intent.id) -> nil)。
  _assert_eq(warns[1], "ui intent rejected: missing actor_role_id|ui_button|next",
    "warning should carry the failure label, intent type, and intent id")
end)


end)
