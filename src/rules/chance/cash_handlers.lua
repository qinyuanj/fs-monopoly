local angel_feedback = require("src.rules.items.angel_feedback")
local coin_settlement = require("src.rules.commerce.coin_settlement")

local cash_handlers = {}

function cash_handlers.register(handlers, common)
  local deps = common.dependencies()

  local function _apply_to_all_players(game, fn)
    for _, p in ipairs(game.players) do
      if not p.eliminated then
        fn(p)
      end
    end
  end

  handlers.add_cash = function(game, player, card)
    if card.target == "all" then
      _apply_to_all_players(game, function(p)
        local delta = common.adjust_chance_delta(game, p, card.amount)
        common.apply_cash_change(game, p, delta)
        common.emit_event(game, deps.monopoly_event.chance.applied, {
          player = p,
          card = card,
          effect = card.effect,
          text = "￥ " .. p.name .. " 获得 " .. deps.number_utils.format_integer_part(delta) .. " 金币",
        })
      end)
      return
    end

    local delta = common.adjust_chance_delta(game, player, card.amount)
    common.apply_cash_change(game, player, delta)
    common.emit_event(game, deps.monopoly_event.chance.applied, {
      player = player,
      card = card,
      effect = card.effect,
      text = "￥ " .. player.name .. " 获得 " .. deps.number_utils.format_integer_part(delta) .. " 金币",
    })
  end

  local function _apply_payment(game, target, card, compute_fee, reason_label, text_label)
    local fee = compute_fee(game, target, card)
    local delta = common.adjust_chance_delta(game, target, -fee)
    local reason = target.name .. " " .. reason_label .. " " .. common.abs_value(delta) .. " 后破产"
    coin_settlement.charge(game, target, common.abs_value(delta), { reason = reason })
    common.emit_event(game, deps.monopoly_event.chance.applied, {
      player = target,
      card = card,
      effect = card.effect,
      text = "￥ " .. target.name .. " " .. text_label .. " " .. deps.number_utils.format_integer_part(common.abs_value(delta)) .. " 金币",
    })
  end

  local function _dispatch_payment(game, player, card, compute_fee, reason_label, text_label)
    if card.target == "all" then
      _apply_to_all_players(game, function(p)
        if card.negative and game:player_has_angel(p) then
          angel_feedback.publish(game, p, "机会卡扣费")
          return
        end
        _apply_payment(game, p, card, compute_fee, reason_label, text_label)
      end)
      return
    end
    _apply_payment(game, player, card, compute_fee, reason_label, text_label)
  end

  local function _fee_flat(_, _, card) return card.amount end
  local function _fee_percent(game, target, card)
    return math.floor(game:player_cash(target) * (card.percent / 100))
  end

  handlers.pay_cash = function(game, player, card)
    _dispatch_payment(game, player, card, _fee_flat, "支付机会卡费用", "支付")
  end

  handlers.percent_pay_cash = function(game, player, card)
    _dispatch_payment(game, player, card, _fee_percent, "按比例支付机会卡费用", "按比例支付")
  end

  local function _pay_other(game, player, other, fee)
    if game:player_is_in_mountain(other) then
      return
    end
    -- payer 侧**故意不守恒**,别顺手改成 coin_settlement.transfer(工单 #126)。
    -- charge 在 0 处钳制并返回实付额,但这里刻意丢弃返回值,下一行把**全额 fee**
    -- 无条件记给收款人 —— payer 余额不足时,差额是被**铸出来**的。
    -- (对照 collect_from_others:那边用 transfer,守恒、按流动性封顶。)
    -- 语义:破产玩家仍须让每个收款人拿满,先付清再淘汰,而不是让先收到的人拿满、
    -- 后面的人分不到。回归护栏在 test/support/scenario_suites/bankruptcy/cases.lua:148
    -- (P1=15、每人收 10:P2 拿满 10,P3 时 P1 只剩 5 却仍断言 P3 到账 10)。
    -- 改用 transfer 会让那条断言当场变红。
    coin_settlement.charge(game, player, fee, {
      reason = player.name .. " 向他人支付后破产",
      cash_opts = { suppress_cash_receive_anim = true },
    })
    common.apply_cash_change(game, other, fee, { suppress_cash_receive_anim = true })
  end

  handlers.pay_others = function(game, player, card)
    for _, other in ipairs(game.players) do
      if player.eliminated then
        break
      end
      if other.id ~= player.id and not other.eliminated then
        local fee = math.abs(common.adjust_chance_delta(game, player, -card.amount))
        _pay_other(game, player, other, fee)
      end
    end
    common.emit_event(game, deps.monopoly_event.chance.applied, {
      player = player,
      card = card,
      effect = card.effect,
      text = "￥ " .. player.name .. " 向每位玩家支付 " .. deps.number_utils.format_integer_part(card.amount),
    })
  end

  local function _collect_from_other(game, other, player, fee)
    if game:player_is_in_mountain(player) then
      return 0
    end
    local settled = coin_settlement.transfer(game, other, player, fee, {
      reason = other.name .. " 被收款资金不足破产",
      cash_opts = { suppress_cash_receive_anim = true },
    })
    return settled.moved
  end

  handlers.collect_from_others = function(game, player, card)
    local total_collected = 0
    for _, other in ipairs(game.players) do
      if other.id ~= player.id and not other.eliminated then
        local fee = common.adjust_chance_delta(game, player, card.amount)
        total_collected = total_collected + _collect_from_other(game, other, player, fee)
      end
    end
    if total_collected > 0 then
      common.queue_action_anim(game, {
        kind = "cash_receive",
        player_id = player.id,
        amount = total_collected,
      })
    end
    common.emit_event(game, deps.monopoly_event.chance.applied, {
      player = player,
      card = card,
      effect = card.effect,
      text = "￥ " .. player.name .. " 收取每位玩家 " .. deps.number_utils.format_integer_part(card.amount),
    })
  end
end

return cash_handlers

