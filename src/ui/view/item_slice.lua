local role_id_utils = require("src.foundation.identity")
local choice_contract = require("src.config.choice.contract")
local tables = require("src.foundation.tables")

local item_slice = {}

function item_slice.resolve_slot_count(ui_runtime)
  local slot_count = 5
  if ui_runtime and type(ui_runtime.item_slots) == "table" and #ui_runtime.item_slots > 0 then
    slot_count = #ui_runtime.item_slots
  end
  return slot_count
end

local _empty_items = {}

local function _clear(map)
  for k in pairs(map) do
    map[k] = nil
  end
end

local function _normalized_player_id(player)
  return role_id_utils.normalize(player and player.id or nil)
end

-- 背包缺失 / items 不是表时统一落到共享空表，调用方无需再判空。
local function _player_items(player)
  return (player and player.inventory and type(player.inventory.items) == "table")
    and player.inventory.items or _empty_items
end

-- 稳定槽位:槽位 i 直映射背包第 i 格,不做密排压缩——
-- 空洞(false 占位)与无 id 条目渲染为空槽,后面的卡不补位。
local function _fill_item_slots(item_slots, items, slot_count)
  -- 复用池表需先清空:slot_count 缩小时不残留尾部残槽(#526)。
  _clear(item_slots)
  for i = 1, slot_count do
    local item = items[i]
    if item and item.id then
      item_slots[i] = item.id
    else
      item_slots[i] = nil
    end
  end
  return item_slots
end

local _standalone_item_slots = {}

function item_slice.build_item_slots_for_player(player, slot_count)
  return _fill_item_slots(_standalone_item_slots, _player_items(player), slot_count)
end

local _slots_by_player = {}
local _slots_pool = {}
local _delegated_by_player = {}


function item_slice.build_item_slots_by_player(players, slot_count)
  _clear(_slots_by_player)
  for _, player in ipairs(players or {}) do
    local player_id = _normalized_player_id(player)
    if player_id then
      local slots = tables.ensure_absent_field(_slots_pool, player_id)
      _fill_item_slots(slots, _player_items(player), slot_count)
      role_id_utils.write(_slots_by_player, player_id, slots)
    end
  end
  return _slots_by_player
end

function item_slice.build_delegated_by_player(player_control_by_player)
  _clear(_delegated_by_player)
  for player_id, entry in pairs(player_control_by_player or {}) do
    role_id_utils.write(_delegated_by_player, player_id, entry.is_delegated == true)
  end
  return _delegated_by_player
end

local function _pending_choice(game)
  return game and game.turn and game.turn.pending_choice or nil
end

function item_slice.resolve_item_choice_owner_id(game, choice, current_player_id)
  local owner_role_id = role_id_utils.normalize(current_player_id)
  local pending_owner_role_id = choice_contract.resolve_owner_role_id(_pending_choice(game))
  if pending_owner_role_id ~= nil then
    return pending_owner_role_id
  end
  local choice_owner_role_id = choice_contract.resolve_owner_role_id(choice)
  if choice_owner_role_id ~= nil then
    owner_role_id = choice_owner_role_id
  end
  return owner_role_id
end

return item_slice

