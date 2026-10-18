-- Static routing definitions for ui_button intents (per-id overrides plus the
-- generic fallback) consumed by command_definitions. Split out of
-- command_definitions.lua to keep each data module under the mutation-site
-- split threshold. 道具槽点击已不是 ui_button，见 command_definitions_commands。

local UI_BUTTONS = {
  next = {
    reason = "action_button",
    game_handler = "basic",
    requires_event_actor = true,
    actor_source = "turn",
  },
  auto = {
    reason = "auto_button",
    game_handler = "basic",
    requires_event_actor = true,
    actor_source = "local",
  },
  cancel = {
    reason = "cancel_button",
    game_handler = "basic",
    requires_event_actor = true,
    actor_source = "turn",
  },
}

local GENERIC_UI_BUTTON = {
  reason = "ui_button",
  game_handler = "basic",
}

return {
  UI_BUTTONS = UI_BUTTONS,
  GENERIC_UI_BUTTON = GENERIC_UI_BUTTON,
}

