local items_cfg = require("src.config.content.items")
local weighted_draw = require("src.rules.items.weighted_draw")
local logger = require("src.foundation.log")
local event_kinds = require("src.config.gameplay.event_kinds")
local intent_output_port = require("src.rules.ports.intent_output")
local event_feed = require("src.rules.ports.event_feed")
local item_config = require("src.rules.items.config")
local auto_play_port = require("src.rules.ports.auto_play")

local inventory = {}

local cfg_by_id = item_config.cfg_by_id

function inventory.cfg(item_id)
  return cfg_by_id[item_id]
end

function inventory.item_name(item_id)
  local cfg = cfg_by_id[item_id]
  assert(cfg ~= nil, "missing item cfg: " .. tostring(item_id))
  return cfg.name
end

local function _inv(player)
  assert(player ~= nil, "missing player")
  assert(player.inventory ~= nil, "missing player.inventory")
  return player.inventory
end

function inventory.items(player)
  return assert(_inv(player).items, "missing inventory items")
end

function inventory.count(player)
  return _inv(player):count()
end

function inventory.is_full(player)
  return _inv(player):is_full()
end

function inventory.add(player, item)
  assert(item ~= nil, "missing item")
  return _inv(player):add(item)
end

function inventory.find_index(player, item_id)
  return _inv(player):find_index(function(it)
    return it.id == item_id
  end)
end

function inventory.consume(player, item_id)
  local inv = _inv(player)
  local idx = assert(inventory.find_index(player, item_id), "missing item: " .. tostring(item_id))
  inv:remove_by_index(idx)
  return true
end

function inventory.remove_by_index(player, idx)
  assert(idx ~= nil, "missing index")
  local inv = _inv(player)
  local items = inventory.items(player)
  assert(idx >= 1 and idx <= #items, "remove_by_index: index out of bounds: " .. tostring(idx))
  return inv:remove_by_index(idx)
end

-- 移除「第 N 张占用卡」:随机取卡语义经 nth-occupied 映射落槽,
-- 其余卡的槽位不变。
function inventory.remove_nth_occupied(player, n)
  assert(n ~= nil, "missing n")
  local inv = _inv(player)
  local slot = assert(inv:nth_occupied_slot(n), "remove_nth_occupied: no occupied slot: " .. tostring(n))
  return inv:remove_by_index(slot)
end

function inventory.clear(player)
  local inv = _inv(player)
  inv._suspend_on_change = true
  local items = {}
  for i = 1, inv.max_slots or #inv.items do
    items[i] = false
  end
  inv.items = items
  inv._suspend_on_change = false
end

function inventory.draw_random()
  local picked = weighted_draw.pick(items_cfg, 1, function(item)
    return item.weight or 0
  end, true)
  return picked[1] or items_cfg[1]
end

local function _notify_full(game, player, item_id)
  if not game then return end
  local popup_port = game.popup_port
  if popup_port == nil then return end
  if auto_play_port.is_computer_controlled(game, player) then
    return
  end
  intent_output_port.push_popup(game, {
    title = "道具",
    body = player.name .. " 背包已满，无法获得道具 " .. inventory.item_name(item_id),
  })
end

function inventory.give(player, item_id, context)
  if inventory.is_full(player) then
    -- migrated as DEV: capacity constraint diagnostic, not player-visible event feed
    logger.info(player.name .. " 的背包已满，无法获得道具 " .. item_id)
    if context and context.game then
      _notify_full(context.game, player, item_id)
    end
    return false
  end
  inventory.add(player, { id = item_id })
  event_feed.publish(context and context.game, {
    kind = event_kinds.item_acquired,
    text = player.name .. " 获得道具 " .. inventory.item_name(item_id),
  })
  return true
end

return inventory

--[[ mutate4lua-manifest
version=4
projectHash=a022260d2855ed8c
scope.0.id=chunk:src/rules/items/inventory.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=126
scope.0.semanticHash=a7c285e3343cbadb
scope.1.id=function:inventory.cfg
scope.1.kind=function
scope.1.startLine=14
scope.1.endLine=16
scope.1.semanticHash=fc8eda1d7903d2b1
scope.2.id=function:inventory.item_name
scope.2.kind=function
scope.2.startLine=18
scope.2.endLine=22
scope.2.semanticHash=a4caf465e8c74f53
scope.3.id=function:_inv
scope.3.kind=function
scope.3.startLine=24
scope.3.endLine=28
scope.3.semanticHash=36d78218d884f793
scope.4.id=function:inventory.items
scope.4.kind=function
scope.4.startLine=30
scope.4.endLine=32
scope.4.semanticHash=a654806fd60f54dc
scope.5.id=function:inventory.count
scope.5.kind=function
scope.5.startLine=34
scope.5.endLine=36
scope.5.semanticHash=560aac70ccfb3dac
scope.6.id=function:inventory.is_full
scope.6.kind=function
scope.6.startLine=38
scope.6.endLine=40
scope.6.semanticHash=560aac70ccfb3dac
scope.7.id=function:inventory.add
scope.7.kind=function
scope.7.startLine=42
scope.7.endLine=45
scope.7.semanticHash=864d550c8fa8925f
scope.8.id=function:inventory.find_index
scope.8.kind=function
scope.8.startLine=47
scope.8.endLine=51
scope.8.semanticHash=942555f322286496
scope.9.id=function:<anonymous>
scope.9.kind=function
scope.9.startLine=48
scope.9.endLine=50
scope.9.semanticHash=e47e5030d1adf782
scope.10.id=function:inventory.consume
scope.10.kind=function
scope.10.startLine=53
scope.10.endLine=58
scope.10.semanticHash=74352fe3a6bbc4f2
scope.11.id=function:inventory.remove_by_index
scope.11.kind=function
scope.11.startLine=60
scope.11.endLine=66
scope.11.semanticHash=4e58ff7ba5d1e897
scope.12.id=function:inventory.remove_nth_occupied
scope.12.kind=function
scope.12.startLine=70
scope.12.endLine=75
scope.12.semanticHash=50599fe5bcc20b43
scope.13.id=function:inventory.clear
scope.13.kind=function
scope.13.startLine=77
scope.13.endLine=86
scope.13.semanticHash=6483907446e62d98
scope.14.id=function:inventory.draw_random
scope.14.kind=function
scope.14.startLine=88
scope.14.endLine=93
scope.14.semanticHash=abeffe301a5a0409
scope.15.id=function:<anonymous>#2
scope.15.kind=function
scope.15.startLine=89
scope.15.endLine=91
scope.15.semanticHash=02a5d1f3afa31722
scope.16.id=function:_notify_full
scope.16.kind=function
scope.16.startLine=95
scope.16.endLine=106
scope.16.semanticHash=69ddfd2ef1f8afa2
scope.17.id=function:inventory.give
scope.17.kind=function
scope.17.startLine=108
scope.17.endLine=123
scope.17.semanticHash=aacb3be489f52a09
]]
