local constants = require("src.config.content.constants")
local item_ids = require("src.config.gameplay.item_ids")
local inventory = require("src.rules.items.inventory")
local coin_settlement = require("src.rules.commerce.coin_settlement")
local achievement_progress = require("src.rules.ports.achievement_progress")
local number_utils = require("src.foundation.number")
local land_events = require("src.rules.land.events")

local tax_rules = {}

function tax_rules.execute_tax_free_card(game, player_id)
  local player = game:find_player_by_id(player_id)
  -- 「持卡」不变量归 inventory 拥有:consume 缺卡时自己 assert,有卡时恒返回 true。
  -- 这里再包一层 assert 只是把同一个不变量写两遍,且用更差的消息盖住 inventory 的。
  inventory.consume(player, item_ids.tax_free)
  achievement_progress.item_used(game, player)
  return land_events.build("tax_free", {
    player = player,
    text = player.name .. " 出示免税卡，本次免税",
  })
end

function tax_rules.execute_pay_tax(game, player_id)
  local player = game:find_player_by_id(player_id)
  local cash = game:player_cash(player)
  -- 不再钳制 fee <= cash:余额经 add_player_cash 在 0 处钳制、绝不为负,
  -- 而 tax_rate 由 config_sanity 约束在 (0, 1],故 floor(cash*rate) <= cash 恒成立。
  local fee = math.floor(cash * constants.tax_rate)

  local settled = coin_settlement.charge(game, player, fee, {
    reason = player.name .. " 支付税金后破产",
    defer_bankruptcy = true,
  })
  achievement_progress.tax_paid(game, player, fee)
  local result = land_events.build("tax_paid", {
    player = player,
    amount = fee,
    text = player.name .. " 在税务局支付税金 " .. number_utils.format_integer_part(fee),
  })
  if settled.bankrupt then
    result.bankrupt_reason = settled.reason
  end
  return result
end

return tax_rules

