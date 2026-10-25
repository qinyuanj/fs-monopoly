local monopoly_event = require("src.foundation.events")
local event_feed = require("src.rules.ports.event_feed")
local event_kinds = require("src.config.gameplay.event_kinds")
local bankruptcy = require("src.rules.elimination.bankruptcy")

local land_events = {}
local emit = monopoly_event.emit

local _ef_kind_map = {
  rent_skipped_mountain = event_kinds.rent_immune,
  strong_card_used = event_kinds.item_used,
  free_rent_used = event_kinds.item_used,
  rent_paid = event_kinds.rent_paid,
  rent_bankrupt = event_kinds.bankruptcy,
  tax_free = event_kinds.tax_immune,
  tax_paid = event_kinds.tax_paid,
}

-- 落地事件结果的唯一构造口：与下方 apply 消费的形状同源。
-- extra 用于挂 bankrupt_reason 一类的旁路字段。
function land_events.build(event_key, payload, extra)
  local result = {
    ok = true,
    event = event_key,
    payload = payload,
  }
  if extra then
    for key, value in pairs(extra) do
      result[key] = value
    end
  end
  return result
end

local function _publish_to_feed(game, result, payload)
  local ef_kind = _ef_kind_map[result.event]
  if not ef_kind or type(payload.text) ~= "string" then
    return
  end
  event_feed.publish(game, {
    kind = ef_kind,
    text = payload.text,
  })
end

local function _emit_land_event(game, result, payload)
  local event_key = monopoly_event.land[result.event]
  assert(event_key ~= nil, "missing land event: " .. tostring(result.event))
  emit(event_key, payload)
  _publish_to_feed(game, result, payload)
end

function land_events.apply(game, result)
  if not result or not result.event then
    return
  end
  -- 山地免租(ok == false)不需要特判:_emit_land_event 本就不看 ok,按 result.event
  -- 查表拿到的正是同一个事件键,发事件与推 feed 的动作逐字相同。它的两个生产方
  -- (rent_payment / actions)都返回不带 bankrupt_reason 的定值表,所以原先那条
  -- 特判路径提前 return 跳过的破产分支本来也是空转。
  local payload = result.payload or {}
  _emit_land_event(game, result, payload)

  if result.bankrupt_reason then
    bankruptcy.eliminate(game, payload.player, { reason = result.bankrupt_reason })
  end
end

return land_events

