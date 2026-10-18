local achievement = require("src.app.host_integrations.achievement")
local host_types = require("src.foundation.host_types")
local number_utils = require("src.foundation.number")
local role_resolver = require("src.host.role_resolver")

local achievement_runtime = {}

local events = {
  game_win = "游戏胜利",
  land_purchase = "买下地块",
  cash_received = "收取金币",
  tax_paid = "支付税金",
  item_used = "使用道具卡",
  chance_card = "抽到机会卡",
  market_item_bought = "黑市购买道具",
  contiguous_lands = "获得三个连续地块",
  monster_demolish = "被怪兽拆除房屋",
  typhoon_demolish = "被台风拆除房屋",
  building_upgraded = {
    [1] = "加盖1级建筑",
    [2] = "加盖2级建筑",
    [3] = "加盖3级建筑",
  },
  deity_attached = {
    angel = "被福神附身",
    rich = "被财神附身",
    poor = "被穷神附身",
  },
  location_effect = {
    hospital = "被送进医院",
    mountain = "被送进深山",
  },
}

-- role 是宿主对象，type() 返回宿主类名而不是 "table"（#266）。这个谓词还兼任
-- role_resolver.resolve_role_with 的筛子，恒假会让成就进度一条都写不进宿主。
local function _can_write_progress(role)
  return host_types.method(role, "add_achievement_progress") ~= nil
end

-- subject 可能是纯 Lua 的 player 表、宿主 Role，或直接就是 role_id。
local function _resolve_player_id(subject)
  if subject == nil then
    return nil
  end
  local role_id = host_types.field(subject, "role_id")
    or host_types.field(subject, "id")
    or host_types.call(subject, "get_roleid")
  return role_id or subject
end

local function _resolve_role(subject)
  if _can_write_progress(subject) then
    return subject
  end
  local player_id = _resolve_player_id(subject)
  if player_id == nil then
    return nil
  end
  return role_resolver.resolve_role_with(player_id, _can_write_progress)
end

local function _positive_amount(amount)
  local value = number_utils.to_integer(amount)
  if value == nil or value <= 0 then
    return nil
  end
  return value
end

local function _record(subject, event_name, amount)
  if event_name == nil then
    return false
  end
  local role = _resolve_role(subject)
  if role == nil then
    return false
  end
  return achievement.record_gameplay_event(event_name, amount, role)
end

local function _record_positive_amount(player, event_name, amount)
  local value = _positive_amount(amount)
  if value == nil then
    return false
  end
  return _record(player, event_name, value)
end

function achievement_runtime.record_event(subject, event_name, amount)
  return _record(subject, event_name, amount)
end

function achievement_runtime.game_won(_, player)
  return _record(player, events.game_win)
end

function achievement_runtime.land_purchased(_, player)
  return _record(player, events.land_purchase)
end

function achievement_runtime.cash_received(_, player, amount)
  return _record_positive_amount(player, events.cash_received, amount)
end

function achievement_runtime.tax_paid(_, player, amount)
  return _record_positive_amount(player, events.tax_paid, amount)
end

function achievement_runtime.item_used(_, player)
  return _record(player, events.item_used)
end

function achievement_runtime.chance_card_drawn(_, player)
  return _record(player, events.chance_card)
end

function achievement_runtime.market_item_bought(_, player)
  return _record(player, events.market_item_bought)
end

function achievement_runtime.building_upgraded(_, player, level)
  return _record(player, events.building_upgraded[number_utils.to_integer(level)])
end

function achievement_runtime.deity_attached(_, player, deity_type)
  return _record(player, events.deity_attached[deity_type])
end

function achievement_runtime.location_effect(_, player, effect)
  return _record(player, events.location_effect[effect])
end

function achievement_runtime.contiguous_lands(_, player)
  return _record(player, events.contiguous_lands)
end

function achievement_runtime.monster_demolished_building(_, player)
  return _record(player, events.monster_demolish)
end

function achievement_runtime.typhoon_demolished_building(_, player)
  return _record(player, events.typhoon_demolish)
end

function achievement_runtime.skin_equipped(_, role_id, skin)
  if type(skin) ~= "table" or type(skin.name) ~= "string" or skin.name == "" then
    return false
  end
  return _record(role_id, "使用" .. skin.name .. "皮肤")
end

function achievement_runtime.build_port()
  return {
    game_won = achievement_runtime.game_won,
    land_purchased = achievement_runtime.land_purchased,
    cash_received = achievement_runtime.cash_received,
    tax_paid = achievement_runtime.tax_paid,
    item_used = achievement_runtime.item_used,
    chance_card_drawn = achievement_runtime.chance_card_drawn,
    market_item_bought = achievement_runtime.market_item_bought,
    building_upgraded = achievement_runtime.building_upgraded,
    deity_attached = achievement_runtime.deity_attached,
    location_effect = achievement_runtime.location_effect,
    contiguous_lands = achievement_runtime.contiguous_lands,
    monster_demolished_building = achievement_runtime.monster_demolished_building,
    typhoon_demolished_building = achievement_runtime.typhoon_demolished_building,
    skin_equipped = achievement_runtime.skin_equipped,
  }
end

return achievement_runtime

