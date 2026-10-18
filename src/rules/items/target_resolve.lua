local logger = require("src.foundation.log")

local target_resolve = {}

local function _target_in_candidates(candidates, target_id)
  for _, cand in ipairs(candidates) do
    if cand.id == target_id then
      return true
    end
  end
  return false
end

function target_resolve.resolve_valid_target(game, player, item_id, context, resolve_candidates)
  local target = game:find_player_by_id(context.target_id)
  if not target or target.id == player.id or target.eliminated then
    logger.warn("目标玩家无效:", tostring(context.target_id))
    return nil
  end
  local candidates = resolve_candidates(game, player, item_id)
  if not _target_in_candidates(candidates, target.id) then
    logger.warn("目标玩家不在可选列表中:", tostring(context.target_id))
    return nil
  end
  return target
end

return target_resolve

