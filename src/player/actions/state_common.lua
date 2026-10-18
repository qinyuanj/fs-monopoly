local constants = require("src.config.content.constants")
local dirty_tracker = require("src.state.dirty_tracker")

local common = {}

common.constants = constants

function common.player_status_table(player)
  player.status = player.status or {}
  return player.status
end

function common.mark_players(game)
  dirty_tracker.mark(game.dirty, "players")
end

return common

