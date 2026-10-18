local completions = require("src.rules.choice_handlers.item_completions")
local normalize = require("src.rules.choice_handlers.item_normalize")
local phase_handlers = require("src.rules.choice_handlers.item_phase_handlers")

local function _handle_flow_choice(game, choice, action, complete, resolve_item_use_choice, context)
  local result = resolve_item_use_choice(game, choice, action, context)
  local player = result.actor or normalize.validate_item_player(game, choice.kind, choice.meta)
  if result.ok ~= true then
    return { stay = true, reason = result.reason }
  end
  if result.waiting then
    return { stay = true }
  end
  return complete.followup_completion(game, choice, player, result)
end

local function _build_flow_handlers(helpers, kind, handler_opts)
  local complete = completions.build(helpers)
  local resolve_item_use_choice = helpers.resolve_item_use_choice

  local function _handle(game, choice, action)
    return _handle_flow_choice(game, choice, action, complete, resolve_item_use_choice)
  end

  return {
    [kind] = completions.item_target_handler(kind, _handle, complete, handler_opts),
  }
end

local function _build_demolish_handlers(helpers)
  return _build_flow_handlers(helpers, "demolish_target")
end

local function _build_roadblock_handlers(helpers)
  return _build_flow_handlers(helpers, "roadblock_target")
end

local function _build_target_player_handlers(helpers)
  return _build_flow_handlers(helpers, "item_target_player")
end

local function _build_remote_dice_handlers(helpers)
  return _build_flow_handlers(helpers, "remote_dice_value", {
    normalize_meta = normalize.remote_dice_meta,
    meta_validator = normalize.validate_remote_dice_meta,
  })
end

local M = {}

local _handler_builders = {
  phase_handlers.build,
  _build_demolish_handlers,
  _build_roadblock_handlers,
  _build_target_player_handlers,
  _build_remote_dice_handlers,
}

function M.register(registry, helpers)
  for _, builder in ipairs(_handler_builders) do
    local handlers = builder(helpers)
    for kind, handler in pairs(handlers) do
      registry[kind] = handler
    end
  end
end

return M

