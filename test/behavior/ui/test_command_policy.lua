-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end

local command_policy = require("src.ui.input.command_policy")


describe("TestCommandPolicy", function()

it("test_describes_turn_optional_end_and_panel_command_meaning_from_one_seam", function()
  local action_reason = command_policy.reason({ type = "ui_button", id = "next" })
  local optional_end_reason = command_policy.reason({ type = "complete_optional_action_phase" })

  _assert_eq(command_policy.game_handler({ type = "ui_button", id = "next" }), "basic",
    "action button should route as a basic turn action")
  _assert_eq(command_policy.game_handler({ type = "complete_optional_action_phase" }), "basic",
    "optional end should route through the explicit optional completion turn seam")
  _assert_eq(action_reason, "action_button", "action button reason should be stable")
  _assert_eq(optional_end_reason, "complete_optional_action_phase",
    "optional end reason should be stable")
  luassert.truthy(action_reason ~= optional_end_reason,
    "action button and optional end command meanings must be distinct")
  _assert_eq(command_policy.dispatches_before_game({ type = "open_skin_panel" }), true,
    "skin panel opener should be handled before game dispatch")
  _assert_eq(command_policy.panel_id({ type = "open_skin_panel" }), "skin",
    "skin panel opener should declare the skin panel block id")
  _assert_eq(command_policy.requires_event_actor({ type = "open_skin_panel" }), true,
    "skin panel opener should require an actor when one can be resolved")
  _assert_eq(command_policy.uses_local_actor({ type = "open_skin_panel" }), true,
    "skin panel opener should resolve actor from local event context")
  _assert_eq(command_policy.is_optional_event_actor({ type = "open_skin_panel" }), true,
    "skin panel opener should tolerate missing actor context")
  _assert_eq(command_policy.reason({ type = "open_skin_panel" }), "open_skin_panel",
    "command reason should stay stable for diagnostics")
end)

it("test_describes_cancel_ui_button_with_stable_reason", function()
  _assert_eq(command_policy.reason({ type = "ui_button", id = "cancel" }), "cancel_button",
    "cancel button reason should be stable")
  _assert_eq(command_policy.game_handler({ type = "ui_button", id = "cancel" }), "basic",
    "cancel button should route as basic turn action")
  _assert_eq(command_policy.requires_event_actor({ type = "ui_button", id = "cancel" }), true,
    "cancel button should require a turn actor")
  _assert_eq(command_policy.uses_local_actor({ type = "ui_button", id = "cancel" }), false,
    "cancel button should resolve actor from turn context")
end)

it("test_routes_every_view_command_through_a_port_handler_with_the_same_meaning", function()
  local view_commands = {
    "toggle_action_log",
    "open_skin_panel",
    "open_gallery_panel",
    "skin_panel_action",
    "item_atlas_action",
    "skin_gallery_action",
    "market_select",
    "popup_confirm",
  }

  for _, intent_type in ipairs(view_commands) do
    local intent = { type = intent_type }
    _assert_eq(command_policy.port_handler(intent), intent_type,
      intent_type .. " should declare a port handler matching the command meaning")
  end

  _assert_eq(command_policy.dispatches_before_game({ type = "market_select" }), false,
    "market selection should remain behind input-block and game dispatch checks")
  _assert_eq(command_policy.requires_event_actor({ type = "market_select" }), false,
    "market selection should not require current-player actor attachment")
  _assert_eq(command_policy.dispatches_before_game({ type = "skin_panel_action" }), true,
    "skin panel actions should remain view commands handled before game dispatch")
  _assert_eq(command_policy.uses_local_actor({ type = "skin_panel_action" }), true,
    "skin panel actions should use local actor context across canvas and host paths")
end)


end)
