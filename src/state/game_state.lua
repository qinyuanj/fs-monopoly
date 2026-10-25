local game_state_players = require("src.state.player_state")
local game_state_tiles = require("src.state.board_state")
local game_state_turn = require("src.state.turn_state")
local Class = require("src.foundation.class")


local game = Class("Game")

local function _install_mixin(target, source, source_name)
  for key, fn in pairs(source) do
    assert(target[key] == nil, "game_state mixin collision: " .. tostring(source_name) .. "." .. tostring(key))
    target[key] = fn
  end
end

_install_mixin(game, game_state_players, "players")
_install_mixin(game, game_state_tiles, "board")
_install_mixin(game, game_state_turn, "turn")

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

