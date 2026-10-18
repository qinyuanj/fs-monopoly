local effects = require("src.rules.items.post_effects")
local item_ids = require("src.config.gameplay.item_ids")
local handlers = require("src.rules.items.handlers")
local Class = require("src.foundation.class")
local tables = require("src.foundation.tables")

local registry = Class("ItemRegistry")

local function _inject_target_candidates(context, resolve_target_candidates)
  local next_context = tables.copy_table(context)
  next_context.resolve_target_candidates = resolve_target_candidates
  return next_context
end

function registry:init()
  self.handlers = {}
end

local function _is_target_candidate(game, player, item_id, spec, candidate)
  if candidate.id == player.id or candidate.eliminated then
    return false
  end
  if game:angel_immune_to_item(candidate, item_id) then
    return false
  end
  return not spec.filter_target or spec.filter_target(game, player, candidate)
end

function registry:target_candidates(game, player, item_id)
  local spec = effects.get_target_spec(item_id)
  assert(spec ~= nil, "missing target spec: " .. tostring(item_id))

  if spec.require_user and not spec.require_user(game, player) then
    return {}
  end

  local candidates = {}
  for _, p in ipairs(game.players) do
    if _is_target_candidate(game, player, item_id, spec, p) then
      table.insert(candidates, p)
    end
  end
  return candidates
end

function registry:register(item_id, handler)
  self.handlers[item_id] = handler
end

function registry:register_defaults()
  self:register(item_ids.remote_dice, handlers.handle_remote_dice)
  self:register(item_ids.roadblock, handlers.handle_roadblock)
  self:register(item_ids.monster, handlers.handle_demolish)

  for _, id in ipairs(effects.target_item_ids()) do
    self:register(id, function(game, player, item_id, context)
      local next_context = _inject_target_candidates(context, function(target_game, target_player, target_item_id)
        return self:target_candidates(target_game, target_player, target_item_id)
      end)
      return handlers.handle_target_player_item(game, player, item_id, next_context)
    end)
  end
end

return registry

