local market_service = require("src.rules.market")
local auto_play_port = require("src.rules.ports.auto_play")

local module = {}

module.executors = {
  market = {
    can_apply = function(ctx)
      return ctx.tile and ctx.tile.type == "market"
    end,
    apply = function(ctx)
      if auto_play_port.is_computer_controlled(ctx.game, ctx.player) then
        market_service.auto.execute(ctx.game, ctx.player)
        return nil
      end

      local buyable = market_service.query.list_available(ctx.player, ctx.game)
      if #buyable == 0 then
        return nil
      end

      local spec, intent = market_service.choice.build(ctx.player, ctx.game)
      if intent then
        return { intent = intent }
      end

      return {
        waiting = true,
        reason = "market_choice",
        intent = {
          kind = "need_choice",
          choice_spec = spec,
        },
      }
    end,
  },
}

return module

