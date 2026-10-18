local event_kinds = require("src.config.gameplay.event_kinds")
local event_feed = require("src.rules.ports.event_feed")
local timing = require("src.config.gameplay.timing")
local action_anim_port = require("src.foundation.ports.action_anim")
local inventory = require("src.rules.items.inventory")
local item_ids = require("src.config.gameplay.item_ids")

local remote_dice = {}

function remote_dice.apply(game, player, dice_count, value)
  assert(dice_count ~= nil and dice_count >= 1, "invalid dice_count")
  local values = {}
  for i = 1, dice_count do
    values[i] = value
  end
  game:set_pending_remote_dice(player, values)
  event_feed.publish(game, {
    kind = event_kinds.remote_dice,
    text = player.name .. " 使用遥控骰子，设定点数 " .. table.concat(values, ","),
  })
  local queued = action_anim_port.queue(game, {
    kind = "item_use",
    player_id = player.id,
    item_id = item_ids.remote_dice,
    item_name = inventory.item_name(item_ids.remote_dice),
    duration = timing.remote_dice_wait_seconds or timing.action_anim_default_seconds or 1.0,
  })
  return { ok = true, action_anim = queued }
end

return remote_dice

