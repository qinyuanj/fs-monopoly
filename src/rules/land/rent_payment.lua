local rent_resolver = require("src.rules.land.rent_resolver")
local coin_settlement = require("src.rules.commerce.coin_settlement")
local number_utils = require("src.foundation.number")
local land_events = require("src.rules.land.events")

local rent_payment = {}

local function _compute_deity_rent(poor_active, rich_active, initial_rent)
  local rent = initial_rent
  local multiplier = 1
  if poor_active then
    rent = rent * 2
    multiplier = multiplier * 2
  end
  if rich_active then
    rent = rent * 2
    multiplier = multiplier * 2
  end
  return rent, multiplier
end

local function _build_breakdown_parts(breakdown, poor_active, rich_active)
  local parts = {}
  if breakdown.count > 1 then
    parts[#parts + 1] = "连片"
  end
  if poor_active then parts[#parts + 1] = "穷神" end
  if rich_active then parts[#parts + 1] = "财神" end
  return parts
end

local function _build_multiplier_text(breakdown_parts)
  if #breakdown_parts == 0 then return nil end
  return "（" .. table.concat(breakdown_parts, "、") .. "）"
end

local function _skipped_mountain_result(skip, tile)
  return {
    ok = false,
    event = "rent_skipped_mountain",
    payload = {
      owner = skip.owner,
      tile = tile,
      text = skip.owner.name .. " 在深山，租金不收取",
    },
  }
end

local function _apply_bankruptcy(result, player, owner, rent, moved)
  result.event = "rent_bankrupt"
  result.payload.amount = rent
  result.payload.text = player.name .. " 余额不足，实际支付租金 "
    .. number_utils.format_integer_part(moved) .. " 金币后破产"
  result.bankrupt_reason = player.name .. " 资金不足，欠付(" .. owner.name .. ") "
    .. number_utils.format_integer_part(rent) .. " 破产"
  return result
end

local function _build_rent_paid(game, player, owner, tile)
  local board = game.board
  local idx = assert(board:index_of_tile_id(tile.id), "missing tile index: " .. tostring(tile.id))
  local breakdown = rent_resolver.contiguous_breakdown(game, board, idx, owner.id)
  local poor_active = game:player_has_deity(player, "poor")
  local rich_active = game:player_has_deity(owner, "rich")
  local rent, deity_multiplier = _compute_deity_rent(poor_active, rich_active, breakdown.total_rent)
  local multiplier_text = _build_multiplier_text(_build_breakdown_parts(breakdown, poor_active, rich_active))
  local text = player.name .. " 向 " .. owner.name .. " 支付租金 "
    .. number_utils.format_integer_part(rent) .. " 金币" .. (multiplier_text or "")
  return land_events.build("rent_paid", {
    player = player,
    owner = owner,
    tile = tile,
    amount = rent,
    single_rent = breakdown.single_rent,
    contiguous_count = breakdown.count,
    deity_multiplier = deity_multiplier,
    text = text,
    multiplier_text = multiplier_text,
  }), rent
end

function rent_payment.execute_pay_rent(game, player_id, tile_id)
  local player = game:find_player_by_id(player_id)
  local tile = game.board:get_tile_by_id(tile_id)
  local owner, _, skip = rent_resolver.resolve_rent_owner(game, tile)
  if skip and skip.reason == "mountain" then
    return _skipped_mountain_result(skip, tile)
  end
  if not owner then
    return { ok = false, reason = "no_owner" }
  end

  local result, rent = _build_rent_paid(game, player, owner, tile)

  local settled = coin_settlement.transfer(game, player, owner, rent, {
    defer_bankruptcy = true,
  })
  if settled.moved >= rent then
    return result
  end
  return _apply_bankruptcy(result, player, owner, rent, settled.moved)
end

return rent_payment

