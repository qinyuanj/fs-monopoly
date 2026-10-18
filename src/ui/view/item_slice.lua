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

--[[ mutate4lua-manifest
version=4
projectHash=be0d80030ad0735a
scope.0.id=chunk:src/ui/view/item_slice.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=99
scope.0.semanticHash=126b4a0e5e135f0a
scope.1.id=function:item_slice.resolve_slot_count
scope.1.kind=function
scope.1.startLine=7
scope.1.endLine=13
scope.1.semanticHash=f51f35681833414f
scope.2.id=function:_clear
scope.2.kind=function
scope.2.startLine=17
scope.2.endLine=21
scope.2.semanticHash=b6c04f8e080b736d
scope.3.id=function:_normalized_player_id
scope.3.kind=function
scope.3.startLine=23
scope.3.endLine=25
scope.3.semanticHash=6e8a930f39c3fdd1
scope.4.id=function:_player_items
scope.4.kind=function
scope.4.startLine=28
scope.4.endLine=31
scope.4.semanticHash=4ffbf8f51fb57782
scope.5.id=function:_fill_item_slots
scope.5.kind=function
scope.5.startLine=35
scope.5.endLine=47
scope.5.semanticHash=7177cdda64ce5206
scope.6.id=function:item_slice.build_item_slots_for_player
scope.6.kind=function
scope.6.startLine=51
scope.6.endLine=53
scope.6.semanticHash=b27cb60b477b665c
scope.7.id=function:item_slice.build_item_slots_by_player
scope.7.kind=function
scope.7.startLine=60
scope.7.endLine=71
scope.7.semanticHash=0a74b461754b430c
scope.8.id=function:item_slice.build_delegated_by_player
scope.8.kind=function
scope.8.startLine=73
scope.8.endLine=79
scope.8.semanticHash=79560ad6f3b30e42
scope.9.id=function:_pending_choice
scope.9.kind=function
scope.9.startLine=81
scope.9.endLine=83
scope.9.semanticHash=c250138038aa193a
scope.10.id=function:item_slice.resolve_item_choice_owner_id
scope.10.kind=function
scope.10.startLine=85
scope.10.endLine=96
scope.10.semanticHash=c2915cd5b98aff64
]]
