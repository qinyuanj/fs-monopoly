local executor = require("src.rules.items.executor")
local flow_context = require("src.rules.items.use_flow_context")
local flow_result = require("src.rules.items.use_flow_result")
local flow_validation = require("src.rules.items.use_flow_validation")
local resolvers = require("src.rules.items.use_flow_resolvers")
local tables = require("src.foundation.tables")

local use_flow = {}

function use_flow.begin_item_use(game, actor_id, item_id, context)
  local player = flow_context.resolve_actor(game, actor_id)
  local resolved_context = tables.copy_table(context)
  local invalid = flow_validation.validate_begin(game, player, item_id, resolved_context)
  if invalid ~= nil then
    return invalid
  end

  resolved_context.reject_reason_fallback = resolved_context.reject_reason_fallback or "no_candidates"
  local raw_result = executor.use_item(game, player, item_id, resolved_context)
  return flow_result.normalize_effect(raw_result, player, item_id)
end

function use_flow.resolve_item_use_choice(game, choice, action, context)
  local resolved_context = tables.copy_table(context)
  local meta, player, item_id, invalid = flow_validation.validate_choice(game, choice, action, resolved_context)
  if invalid ~= nil then
    return invalid
  end

  return resolvers.resolve(game, choice, action, resolved_context, meta, player, item_id)
end

return use_flow

