local dirty_tracker = require("src.state.dirty_tracker")
local game_state = require("src.state.game_state")
local turn_runtime = require("src.turn.scheduler")
local bootstrap = require("src.rules.bootstrap")
local game_factory = require("src.app.game_factory")
local phase_registry = require("src.turn.phases.registry")
local status_ops = require("src.player.actions.status")
local balance_ops = require("src.player.actions.balance")
local deity_ops = require("src.player.actions.deity")
local location_ops = require("src.player.actions.location")
local game_victory = require("src.rules.endgame")
local skin_ownership_seam = require("src.ui.seams.skin_ownership")
local skin_ownership = require("src.rules.skin_ownership")
local game_defaults = require("src.app.game_defaults")

local function _install_class_mixin(target_class, source_table, source_name)
  for key, fn in pairs(source_table) do
    assert(target_class[key] == nil, "compose_game mixin collision: " .. tostring(source_name) .. "." .. tostring(key))
    target_class[key] = fn
  end
end

local _player_state_groups = {
  { name = "status_ops", source = status_ops },
  { name = "balance_ops", source = balance_ops },
  { name = "deity_ops", source = deity_ops },
  { name = "location_ops", source = location_ops },
}

for _, group in ipairs(_player_state_groups) do
  _install_class_mixin(game_state, group.source, group.name)
end

game_state.check_victory = game_victory.check_victory

-- 皮肤归属 ui seam 装配(#244 / #204):seam 是纯接口壳,规则层皮肤归属模块在
-- 组合根注入,与 mixin 安装同住 compose_game(ADR 0001)。
skin_ownership_seam.install(skin_ownership)

local composition_root = {}

local function _assemble(opts, game_or_class)
  assert(opts ~= nil, "missing assemble opts")

  local board = game_factory.build_board(opts)
  local players = game_factory.build_players(opts)

  game_defaults.init_tile_state(board)

  local dirty = dirty_tracker.new()

  for _, p in ipairs(players) do
    p.inventory._on_change = function()
      dirty_tracker.mark_inventory(dirty)
    end
  end

  local registries = bootstrap.create_registries()
  local phases = phase_registry.build_default_phases()
  local game = game_or_class
  if game_defaults.is_class_like(game_or_class) then
    game = game_or_class:new(opts)
  end
  assert(game, "CompositionRoot.Assemble requires game instance or class")

  game_defaults.apply_game_defaults(game, opts, board, players, dirty)

  game.registries = registries
  game.effect_registry = registries.effects

  game:rebuild()
  game.turn_runtime = turn_runtime:new(game, phases)

  return game
end

function composition_root.new_game(opts, game_class)
  local target_game_class = game_class or game_state
  local game = target_game_class:new(opts)
  if type(game) ~= "table" or type(game.rebuild) ~= "function" then
    return game
  end
  return _assemble(opts, game)
end

return composition_root

