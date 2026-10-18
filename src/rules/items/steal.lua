local event_kinds = require("src.config.gameplay.event_kinds")
local inventory = require("src.rules.items.inventory")
local item_ids = require("src.config.gameplay.item_ids")
local timing = require("src.config.gameplay.timing")
local action_anim_port = require("src.foundation.ports.action_anim")
local event_feed = require("src.rules.ports.event_feed")
local gain_reveal = require("src.rules.items.gain_reveal")

local steal = {}
local action_anim_duration = timing.action_anim_default_seconds

local function _fail_popup(game, stealer, target)
  local msg = target.name .. " 没有任何道具"
  local log_text = stealer.name .. " 使用偷窃卡，" .. msg
  event_feed.publish(game, {
    kind = event_kinds.steal,
    text = log_text,
    tip = true,
    tip_duration = action_anim_duration,
    tip_dedupe_key = "steal_fail:" .. tostring(stealer.id) .. ":" .. tostring(target.id),
    blocks_inter_turn = false,
    source = "rules.items.steal",
  })
  return {
    ok = false,
  }
end

-- commit:结算台账注入的单次消耗能力(道具使用流程必经);
-- 缺省回退为直接自耗,仅服务不经流程的独立单测调用。
local function _consume_steal_card(player, commit)
  if commit ~= nil then
    return commit()
  end
  return inventory.consume(player, item_ids.steal)
end

-- 背包已满不阻止偷窃:满背包必然含偷窃卡自身,自耗先腾出空洞,偷来的
-- 道具按「填编号最小空洞」入包——没有更早
-- 的洞时恰好落进偷窃卡腾出的那一格;双方其余卡的槽位均不变。
function steal.steal_nth_occupied(game, player, target, nth, commit)
  if inventory.count(target) == 0 then
    return _fail_popup(game, player, target)
  end
  _consume_steal_card(player, commit)
  local stolen = inventory.remove_nth_occupied(target, nth or 1)
  assert(stolen ~= nil, "missing stolen item")
  assert(inventory.add(player, stolen) == true, "add stolen item failed")
  local name = inventory.item_name(stolen.id)
  local log_text = player.name .. " 使用偷窃卡，从 " .. target.name .. " 偷走道具 " .. name
  event_feed.publish(game, {
    kind = event_kinds.steal,
    text = log_text,
    tip = true,
    tip_duration = action_anim_duration,
    tip_dedupe_key = "steal_success:" .. tostring(player.id) .. ":" .. tostring(target.id) .. ":" .. tostring(stolen.id),
    blocks_inter_turn = false,
    source = "rules.items.steal",
  })
  local queued = action_anim_port.queue(game, {
    kind = "item_target_player",
    player_id = player.id,
    target_player_id = target.id,
    item_id = item_ids.steal,
    item_name = "偷窃卡",
    duration = action_anim_duration,
  })
  gain_reveal.queue(game, player, stolen.id, { source = "steal" })
  return {
    ok = true,
    stolen = stolen,
    action_anim = queued,
    item_consumed = true,
  }
end

function steal.steal_random_item(game, player, target, commit)
  local count = inventory.count(target)
  if count == 0 then
    return _fail_popup(game, player, target)
  end
  local rng = assert(game and game.rng, "missing game.rng for steal")
  assert(type(rng.next_int) == "function", "missing game.rng.next_int for steal")
  return steal.steal_nth_occupied(game, player, target, rng:next_int(1, count), commit)
end

return steal

--[[ mutate4lua-manifest
version=4
projectHash=85860adbd7401f6e
scope.0.id=chunk:src/rules/items/steal.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=88
scope.0.semanticHash=6891f17f3ee42a8b
scope.1.id=function:_fail_popup
scope.1.kind=function
scope.1.startLine=12
scope.1.endLine=27
scope.1.semanticHash=6553dd3752c9cd7d
scope.2.id=function:_consume_steal_card
scope.2.kind=function
scope.2.startLine=31
scope.2.endLine=36
scope.2.semanticHash=51001ae7df9c0745
scope.3.id=function:steal.steal_nth_occupied
scope.3.kind=function
scope.3.startLine=41
scope.3.endLine=75
scope.3.semanticHash=2c014307deb7c0cd
scope.4.id=function:steal.steal_random_item
scope.4.kind=function
scope.4.startLine=77
scope.4.endLine=85
scope.4.semanticHash=46ff986d2f1e94e2
]]
