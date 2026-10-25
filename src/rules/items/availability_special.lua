-- 特殊道具可用性判定(自 availability 拆出):目标类/租金响应类道具的候选解析
-- 与拒绝原因谓词。全部为纯查询,无状态;供 availability.can_offer_in_phase 组门。
local auto_play_port = require("src.rules.ports.auto_play")
local effects = require("src.rules.items.post_effects")
local item_ids = require("src.config.gameplay.item_ids")
local demolish = require("src.rules.items.demolish")
local roadblock = require("src.rules.items.roadblock")
local property_query = require("src.rules.board.property_query")
local property_value = require("src.rules.commerce.property_value")

local special = {}

local target_item_set = {}
for _, target_item_id in ipairs(effects.target_item_ids()) do
  target_item_set[target_item_id] = true
end

-- 租金响应类道具(强征/免费):无道具阶段窗口,可用性由租金上下文判定。
local RENT_RESPONSE_ITEM = {
  [item_ids.strong] = true,
  [item_ids.free_rent] = true,
}

local function _resolve_roadblock_candidates(game, player)
  if auto_play_port.is_computer_controlled(game, player) then
    return roadblock.auto_candidates(game, player, 3)
  end
  return roadblock.manual_candidates(game, player, 3)
end

local function _item_registry(game)
  local registries = game and game.registries or nil
  return registries and registries.items or nil
end

local function _has_target_candidates(registry)
  return type(registry) == "table" and type(registry.target_candidates) == "function"
end

local function _can_offer_target_item(game, player, item_id)
  local registry = _item_registry(game)
  if not _has_target_candidates(registry) then
    return false
  end
  local candidates = registry:target_candidates(game, player, item_id)
  return type(candidates) == "table" and #candidates > 0
end

local function _board_of(game)
  return game and game.board or nil
end

local function _player_position(player)
  return player and player.position or nil
end

local function _land_tile(board, player_position)
  local tile_ref = board and board:get_tile(player_position) or nil
  if tile_ref and tile_ref.type == "land" then
    return tile_ref
  end
  return nil
end

local function _resolve_rent_response_tile(game, player)
  return _land_tile(_board_of(game), _player_position(player))
end

local function _resolve_rent_response_context(game, player)
  local tile_ref = _resolve_rent_response_tile(game, player)
  if tile_ref == nil then
    return nil
  end
  local owner, state = property_query.resolve_rent_owner(game, tile_ref)
  return {
    tile_ref = tile_ref,
    player_id = player and player.id or nil,
    owner = owner,
    state = state,
    total_value = property_value.total_invested(tile_ref, state and state.level),
  }
end

local function _is_rent_response_available(ctx)
  local owner = ctx and ctx.owner or nil
  return owner ~= nil and owner.id ~= ctx.player_id
end

local function _can_afford_strong_card(game, player, ctx)
  local total_value = assert(ctx and ctx.total_value, "missing rent response total value")
  return game:player_cash(player) >= total_value
end

local function _can_offer_rent_response(game, player, item_id)
  local ctx = _resolve_rent_response_context(game, player)
  if not _is_rent_response_available(ctx) then
    return false
  end
  if item_id ~= item_ids.strong then
    return true
  end
  -- #205:现金不足是独立拒绝原因,与「不站在对手地上」的无目标区分开。
  if not _can_afford_strong_card(game, player, ctx) then
    return false, "insufficient_funds"
  end
  return true
end

local function _can_offer_roadblock(game, player)
  local candidates = _resolve_roadblock_candidates(game, player)
  return type(candidates) == "table" and #candidates > 0
end

local function _can_offer_demolish(game, player)
  return demolish.find_target(game, player, 3) ~= nil
end

local function _can_offer_special_item(game, player, item_id)
  if item_id == item_ids.roadblock then
    return _can_offer_roadblock(game, player)
  end

  if item_id == item_ids.monster then
    return _can_offer_demolish(game, player)
  end

  if target_item_set[item_id] then
    return _can_offer_target_item(game, player, item_id)
  end

  -- 租金响应类道具(strong/free_rent)不在此处分支:rent_denial_reason 是唯一的
  -- 租金上下文门禁(#205 分类顺序),经条件门会让 rent 门禁的集合成员判定变成
  -- 可观测不到效用的冗余(变异幸存实锤)。
  return nil
end

-- 租金响应门禁:租金响应类道具先看租金上下文(无上下文=无目标;现金不足=独立
-- 原因,#205),非租金响应道具或上下文成立时返回 nil(放行)。
function special.rent_denial_reason(game, player, item_id)
  if not RENT_RESPONSE_ITEM[item_id] then
    return nil
  end
  local rent_offer, rent_reason = _can_offer_rent_response(game, player, item_id)
  if rent_offer then
    return nil
  end
  return rent_reason or "special_condition_failed"
end

-- 特殊条件门禁:特殊道具条件不成立时返回拒绝原因,否则 nil(放行)。
function special.condition_denial_reason(game, player, item_id)
  local special_offer, special_reason = _can_offer_special_item(game, player, item_id)
  if special_offer == nil or special_offer then
    return nil
  end
  return special_reason or "special_condition_failed"
end

return special

