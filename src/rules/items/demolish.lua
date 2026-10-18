local logger = require("src.foundation.log")
local demolish_apply = require("src.rules.items.demolish_apply")
local demolish_choice = require("src.rules.items.demolish_choice")

local demolish = {}

demolish.find_target = demolish_choice.find_target
demolish.apply = demolish_apply.apply

local function _human_demolish_choice(game, player, distance, best_idx, opts)
  if opts.is_computer_controlled then
    return nil
  end
  return demolish_choice.build_human_choice(game, player, distance, best_idx, opts)
end

local function _consume_demolish_item(player, consume_fn, item_id)
  if consume_fn and not consume_fn(player, item_id) then
    return false
  end
  return true
end

local function _resolve_demolish_target(game, player, distance, opts)
  local best_idx = demolish.find_target(game, player, distance)
  if best_idx ~= nil then
    return best_idx
  end
  -- migrated as DEV: internal target-selection failure, not player-facing game fact
  logger.info((opts.title or "拆除类道具") .. " 无可用目标")
  return nil
end

local function _apply_demolish_target(game, player, distance, consume_fn, opts, best_idx)
  local choice = _human_demolish_choice(game, player, distance, best_idx, opts)
  if choice then
    return choice
  end

  if not _consume_demolish_item(player, consume_fn, opts.item_id) then
    return false
  end
  return demolish.apply(game, player, best_idx, opts)
end

function demolish.use(game, player, distance, consume_fn, opts)
  opts = opts or {}
  local best_idx = _resolve_demolish_target(game, player, distance, opts)
  if best_idx == nil then
    return false
  end
  return _apply_demolish_target(game, player, distance, consume_fn, opts, best_idx)
end

return demolish

