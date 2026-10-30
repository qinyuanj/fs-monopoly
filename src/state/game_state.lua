local game_state_players = require("src.state.player_state")
local game_state_tiles = require("src.state.board_state")
local game_state_turn = require("src.state.turn_state")
local Class = require("src.foundation.class")
local mixin = require("src.foundation.mixin")


local game = Class("Game")

mixin.install("game_state", game, game_state_players, "players")
mixin.install("game_state", game, game_state_tiles, "board")
mixin.install("game_state", game, game_state_turn, "turn")

function game:init(opts)
  self.auto_play_port = opts and opts.auto_play_port or self.auto_play_port
end

function game:advance_turn()
  if self.finished then
    return
  end
  local runtime = self.turn_runtime
  if runtime and runtime.run_turn then
    runtime:run_turn()
  end
  self:check_victory()
end

function game:dispatch_action(action)
  if self.finished then
    return
  end
  local runtime = self.turn_runtime
  if runtime and runtime.dispatch then
    runtime:dispatch(action)
  end
  self:check_victory()
end

function game:rebuild()
  local length = self.board:length()
  self.occupants = {}
  for i = 1, length do
    self.occupants[i] = {}
  end
  for _, player in ipairs(self.players) do
    if not player.eliminated then
      local idx = player.position
      player.position = idx
      table.insert(self.occupants[idx], player.id)
    end
  end
end

return game

