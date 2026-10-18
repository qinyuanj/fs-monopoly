require("test.bootstrap").install_package_paths()
-- luacheck: ignore 143 (busted injects the verified luassert object)
local luassert = assert
local support = require("test.support.shared_support")
local fixtures = require("test.support.gameplay_fixtures")
local property = require("test.support.property")
local config_reset = require("test.support.config_reset")
local gameplay_loop = require("src.turn.loop.init")
local loop_ports = require("src.turn.loop.ports")
local timing = require("src.config.gameplay.timing")

local function randomize_board(game, rng)
  for _, tile in ipairs(game.board.path) do
    if tile.type == "land" then
      local roll = rng:int(1, #game.players + 1)
      if roll <= #game.players then
        local owner = game.players[roll]
        game:set_tile_owner(tile, owner.id)
        game:set_player_property(owner, tile.id, true)
        game:set_tile_level(tile, rng:int(0, 3))
      end
    end
  end
end

local function replay_seed(seed)
  local rng = property.Rng.new(seed * 2654435761)
  math.randomseed(seed)
  local names, ai = {}, {}
  for index = 1, 2 + seed % 3 do
    names[index] = "P" .. index
    if index > 1 then ai[index] = true end
  end
  local game = support.new_game({ players = names, ai = ai })
  local state = fixtures.build_loop_state()
  local now = 0
  state.gameplay_loop_ports = loop_ports.resolve({
    ui_sync = {
      on_pending_choice = state.gameplay_loop_ports.ui_sync.on_pending_choice,
      resolve_choice_ui_state = state.gameplay_loop_ports.ui_sync.resolve_choice_ui_state,
    },
    clock = {
      wall_now_seconds = function() return now end,
      wall_diff_seconds = function(a, b) return (a or 0) - (b or 0) end,
      cpu_now_seconds = function() return now end,
      cpu_diff_seconds = function(a, b) return (a or 0) - (b or 0) end,
    },
  })
  gameplay_loop.set_game(state, game)
  for _, player in ipairs(game.players) do
    game:set_player_cash(player, rng:int(500, 6000))
  end
  randomize_board(game, rng)
  game:advance_turn()
  for _ = 1, 40000 do
    now = now + 1 / 30
    -- Propagate every frame error; reaching endgame cannot hide a failed strike.
    gameplay_loop.tick(game, state, 1 / 30)
    if game.finished then break end
  end
  luassert.is_true(game.finished, "seed " .. seed .. " must finish without frame errors")
end

describe("idle human missile regression seeds (#118)", function()
  before_each(function() config_reset.reset_all() end)

  for _, seed in ipairs({ 18, 107, 251, 279 }) do
    it("advances every production frame without errors for seed " .. seed, function()
      support.with_patches({
        { target = timing, key = "game_time_limit_seconds", value = 120 },
      }, function() replay_seed(seed) end)
    end)
  end
end)
