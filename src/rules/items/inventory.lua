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

