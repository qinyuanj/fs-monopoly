local inventory = require("src.rules.items.inventory")
local item_ids = require("src.config.gameplay.item_ids")
local event_kinds = require("src.config.gameplay.event_kinds")
local coin_settlement = require("src.rules.commerce.coin_settlement")
local event_feed = require("src.rules.ports.event_feed")
local number_utils = require("src.foundation.number")
local achievement_progress = require("src.rules.ports.achievement_progress")
local angel_feedback = require("src.rules.items.angel_feedback")

local target_cash_effects = {}

local function _should_emit_share_wealth_cash_receive(context)
  local mode = context and context.share_wealth_cash_receive_mode or nil
  if mode == "item_target_player_only" then
    return false
  end
  return not (context and context.suppress_cash_receive_anim == true)
end

local function _emit_ready(should_emit, game, method)
  return should_emit and type(game[method]) == "function"
end

-- 转账形态:负差额的一方付给另一方。
local function _apply_transfer_delta(game, user, target, deltas)
  local user_delta = deltas.user
  local target_delta = deltas.target
  if user_delta < 0 then
    game:transfer_player_cash(user, target, -user_delta)
  elseif target_delta < 0 then
    game:transfer_player_cash(target, user, -target_delta)
  end
end

local function _apply_share_wealth_cash(game, user, target, deltas, next_values, should_emit)
  if _emit_ready(should_emit, game, "transfer_player_cash") then
    _apply_transfer_delta(game, user, target, deltas)
    return
  end
  if _emit_ready(should_emit, game, "add_player_cash") then
    game:add_player_cash(user, deltas.user)
    game:add_player_cash(target, deltas.target)
    return
  end
  game:set_player_cash(user, next_values.user)
  game:set_player_cash(target, next_values.target)
end

target_cash_effects.share_wealth = {
  apply = function(game, user, target, context)
    if game:angel_immune_to_item(target, item_ids.share_wealth) then
      angel_feedback.publish(game, target, "均富")
      return true
    end
    local user_cash = game:player_cash(user)
    local target_cash = game:player_cash(target)
    local total = user_cash + target_cash
    local half = math.floor(total / 2)
    local user_delta = half - user_cash
    local target_delta = (total - half) - target_cash
    local should_emit_cash_receive = _should_emit_share_wealth_cash_receive(context)
    _apply_share_wealth_cash(game, user, target, {
      user = user_delta,
      target = target_delta,
    }, {
      user = half,
      target = total - half,
    }, should_emit_cash_receive)
    if user_delta > 0 then
      achievement_progress.cash_received(game, user, user_delta)
    end
    if target_delta > 0 then
      achievement_progress.cash_received(game, target, target_delta)
    end
    event_feed.publish(game, {
      kind = event_kinds.equality_card,
      text = user.name .. " 使用均富卡，与 " .. target.name .. " 平分资金",
    })
    return true
  end,
}

target_cash_effects.tax = {
  apply = function(game, user, target)
    if game:angel_immune_to_item(target, item_ids.tax) then
      angel_feedback.publish(game, target, "查税")
      return true
    end
    local tax_free_idx = inventory.find_index(target, item_ids.tax_free)
    if tax_free_idx then
      inventory.remove_by_index(target, tax_free_idx)
      event_feed.publish(game, {
        kind = event_kinds.tax_immune,
        text = target.name .. " 使用免税卡抵消查税",
      })
      return true
    end
    local fee = math.floor(game:player_cash(target) * 0.5)
    coin_settlement.charge(game, target, fee, {
      reason = target.name .. " 支付查税费用后破产",
    })
    achievement_progress.tax_paid(game, target, fee)
    event_feed.publish(game, {
      kind = event_kinds.tax_card,
      text = user.name .. " 使用查税卡，" .. target.name .. " 支付 " .. number_utils.format_integer_part(fee) .. " 税金",
    })
    return true
  end,
}

return target_cash_effects

