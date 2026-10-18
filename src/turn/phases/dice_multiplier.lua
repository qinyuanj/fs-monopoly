local event_kinds = require("src.config.gameplay.event_kinds")
local event_feed = require("src.rules.ports.event_feed")
local number_utils = require("src.foundation.number")

local dice_multiplier = {}

function dice_multiplier.apply_roll_total(game, raw_total, player)
  -- player_pending_dice_multiplier normalizes to >= 1, so multiplying is a
  -- no-op when no multiplier is pending.
  return raw_total * game:player_pending_dice_multiplier(player)
end

-- 加倍明细日志(#103):写明“骰面 N × 倍率 = 移动 M 步”,只进行动日志。
function dice_multiplier.publish_breakdown(game, player, raw_total, new_total, multiplier)
  event_feed.publish(game, {
    kind = event_kinds.dice_multiplier_breakdown,
    text = player.name
      .. " 骰面 "
      .. number_utils.format_integer_part(raw_total)
      .. " × "
      .. number_utils.format_integer_part(multiplier)
      .. " = 移动 "
      .. number_utils.format_integer_part(new_total)
      .. " 步",
  })
end

-- 守卫：倍数不加成时原样返回（未挂倍数 / 无原始步数 / 步数已被改动）。
local function _should_skip_multiplier(total, raw_total, pending_multiplier)
  return pending_multiplier <= 1 or raw_total == nil or total ~= raw_total
end

function dice_multiplier.apply_move_total(game, player, total, raw_total)
  local pending_multiplier = game:player_pending_dice_multiplier(player)
  if _should_skip_multiplier(total, raw_total, pending_multiplier) then
    return total
  end

  local new_total = raw_total * game:consume_pending_dice_multiplier(player)
  if game.last_turn then
    game.last_turn.total = new_total
  end
  dice_multiplier.publish_breakdown(game, player, raw_total, new_total, pending_multiplier)
  return new_total
end

return dice_multiplier

