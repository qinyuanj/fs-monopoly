local monopoly_event = require("src.foundation.events")
local event_feed = require("src.rules.ports.event_feed")
local event_kinds = require("src.config.gameplay.event_kinds")

local resolver = {}

function resolver.resolve(game, player, card, context)
  if card.negative and game:player_has_angel(player) then
    local text = player.name .. " 天使保护，负面机会卡无效"
    monopoly_event.emit(monopoly_event.chance.applied, {
      player = player,
      card = card,
      effect = card.effect,
      text = text,
    })
    event_feed.publish(game, {
      kind = event_kinds.chance_card,
      text = text,
    })
    monopoly_event.emit(monopoly_event.feedback.angel_immune_blocked, {
      player_id = player.id,
    })
    return nil
  end

  local registries = assert(game.registries, "missing game.registries")
  local chance_handlers = assert(registries.chances, "missing chance handlers")
  local handler = chance_handlers[card.effect]
  assert(handler ~= nil, "未知机会卡效果:" .. tostring(card.effect))

  return handler(game, player, card, context)
end

return resolver

