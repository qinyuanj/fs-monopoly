local auto_runner = require("src.turn.policies.auto_runner")
local composition_root = require("src.app.compose_game")
local app = require("src.state.game_state")
local tiles_cfg = require("src.config.content.tiles")
local default_map = require("src.config.content.default_map")
local timing = require("src.config.gameplay.timing")
local default_ports = require("src.turn.output.default_ports")
local logger = require("src.foundation.log")
local fallback_registry = require("src.rules.choice.fallback_registry")
local roster_roles = require("src.app.roster_roles")
local roster_debug = require("src.app.roster_debug")

local function _choice_id(choice)
  return choice and choice.id
end

local function _cancel_fallback(_, choice)
  return { type = "choice_cancel", choice_id = _choice_id(choice) }
end

local function _register_default_choice_fallbacks()
  fallback_registry.register("market_buy", _cancel_fallback)
  fallback_registry.register("item_target_tile", _cancel_fallback)
  fallback_registry.register("item_target_player", _cancel_fallback)
  fallback_registry.register("steal_target", _cancel_fallback)
end

_register_default_choice_fallbacks()

local max_player_count = 4
local M = {}

function M.build_game_factory(state, opts)
  assert(state ~= nil, "missing state")
  opts = opts or {}
  local auto_all = opts.auto_all == true
  return function()
    local role_roster = roster_roles.build_startup_roster(max_player_count)
    local forced_ai = roster_roles.build_startup_ai_map(role_roster)
    local auto_players = roster_debug.build_auto_players(role_roster)
    logger.info("[Eggy]", "使用四槽角色驱动初始化，角色数量:", tostring(#role_roster))
    local created_game = composition_root.new_game(default_ports.resolve_game_opts({
      role_roster = role_roster,
      ai = forced_ai,
      auto_all = auto_all,
      auto_players = auto_players,
      map = default_map,
      tiles = tiles_cfg,
    }), app)
    created_game.startup_synthetic_players = roster_roles.build_synthetic_player_specs(role_roster)
    return created_game
  end
end

function M.build_auto_runner()
  return auto_runner:new({
    interval = timing.auto_decision_delay_seconds,
  })
end

return M

