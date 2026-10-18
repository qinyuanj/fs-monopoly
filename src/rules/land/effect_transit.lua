local event_kinds = require("src.config.gameplay.event_kinds")
local constants = require("src.config.content.constants")
local inventory = require("src.rules.items.inventory")
local gain_reveal = require("src.rules.items.gain_reveal")
local achievement_progress = require("src.rules.ports.achievement_progress")
local event_feed = require("src.rules.ports.event_feed")
local number_utils = require("src.foundation.number")

local M = {}

M.executors = {
  start_reward = {
    can_apply = function(ctx)
      return ctx.tile and ctx.tile.type == "start" and ctx.on_landing
    end,
    apply = function(ctx)
      local player = ctx.player
      local move_result = ctx.move_result or {}
      if move_result.passed_start and move_result.passed_start > 0 then return end
      local bonus = constants.pass_start_bonus
      if ctx.game:player_has_deity(player, "rich") then
        bonus = bonus * 2
      end
      ctx.game:add_player_cash(player, bonus)
      achievement_progress.cash_received(ctx.game, player, bonus)
      event_feed.publish(ctx.game, {
        kind = event_kinds.transit,
        text = player.name .. " 停在起点，获得 " .. number_utils.format_integer_part(bonus) .. " 金币",
      })
    end,
  },
  item_draw_and_give = {
    can_apply = function(ctx)
      return ctx.game and ctx.player and ctx.tile and ctx.tile.type == "item"
    end,
    apply = function(ctx)
      local player = ctx.player
      local cfg = inventory.draw_random()
      assert(cfg ~= nil, "missing drawn item cfg")
      local ok = inventory.give(player, cfg.id, { game = ctx.game })
      if ok then
        gain_reveal.queue(ctx.game, player, cfg.id, { source = "item_tile" })
      end
    end,
  },
}

return M

