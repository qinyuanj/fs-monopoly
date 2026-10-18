local demolish = require("src.rules.items.demolish")
local handlers = require("src.rules.items.handlers")
local remote_dice = require("src.rules.items.remote_dice")
local roadblock = require("src.rules.items.roadblock")
local settlement = require("src.rules.items.settlement")
local target_resolve = require("src.rules.items.target_resolve")
local intent_output_port = require("src.rules.ports.intent_output")
local flow_result = require("src.rules.items.use_flow_result")

local resolvers = {}

-- kind 描述符:一个 choice kind 三个事实——消耗时机、失败兜底 reason、
-- 纯 applier。判定/消耗/广播/兜底动画整体归 settlement,描述符只负责
-- 把选中的 option 翻译成一次 apply。
local kind_descriptors = {
  item_target_player = {
    consume = "after_success",
    fallback_reason = "invalid_target",
    apply = function(game, player, item_id, action, _, use_context, commit)
      local registries = assert(game.registries, "missing game.registries")
      local registry = assert(registries.items, "missing item registry")
      local target = target_resolve.resolve_valid_target(game, player, item_id, { target_id = action.option_id },
        function(target_game, target_player, target_item_id)
          return registry:target_candidates(target_game, target_player, target_item_id)
        end)
      if not target then
        return false
      end
      return handlers.apply_target_player(game, player, item_id, target, { is_computer_controlled = use_context.is_computer_controlled }, commit)
    end,
  },
  remote_dice_value = {
    consume = "before_apply",
    fallback_reason = "effect_rejected",
    apply = function(game, player, _, action, meta)
      local dice_count = meta.dice_count or game:player_dice_count(player)
      return remote_dice.apply(game, player, dice_count, action.option_id)
    end,
  },
  roadblock_target = {
    consume = "before_apply",
    fallback_reason = "effect_rejected",
    validate_option = function(game, player, _, action)
      return roadblock.is_ui_candidate(game, player, action.option_id)
    end,
    apply = function(game, player, _, action)
      local raw = roadblock.apply(game, player, action.option_id)
      intent_output_port.dispatch(game, raw)
      return raw
    end,
  },
  demolish_target = {
    consume = "before_apply",
    fallback_reason = "effect_rejected",
    apply = function(game, player, item_id, action, meta)
      local raw = demolish.apply(game, player, action.option_id, {
        injure = meta.injure,
        title = meta.title,
        item_id = item_id,
      })
      intent_output_port.dispatch(game, type(raw) == "table" and raw.intent or {})
      return raw
    end,
  },
}

function resolvers.resolve(game, choice, action, use_context, meta, player, item_id)
  local descriptor = kind_descriptors[choice.kind]
  if descriptor == nil then
    return flow_result.rejected("unsupported_choice_kind", {
      actor = player,
      actor_id = player.id,
      item_id = item_id,
      choice = choice,
    })
  end
  if descriptor.validate_option and not descriptor.validate_option(game, player, item_id, action) then
    return flow_result.rejected("invalid_target", {
      actor = player,
      actor_id = player.id,
      item_id = item_id,
    })
  end
  return settlement.execute(game, player, item_id, function(commit)
    return descriptor.apply(game, player, item_id, action, meta, use_context, commit)
  end, {
    consume = descriptor.consume,
    fallback_reason = descriptor.fallback_reason,
    choice = choice,
  })
end

return resolvers

