require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local compose_game = require("src.app.compose_game")
local gameplay_loop = require("src.turn.loop.init")
local constants = require("src.config.content.constants")
local map_cfg = require("src.config.content.default_map")
local tiles_cfg = require("src.config.content.tiles")
local _config_reset = require("test.support.config_reset")

-- #208 / #206 A:不经开局名册(roster)的装配路径里，现金为负的玩家同样要被淘汰。
-- 装配只走组合根 + 一次 headless tick(无 state)，与 headless 车道一致。
local function _new_headless_game()
  local game = compose_game.new_game({
    players = { "P1", "P2", "P3" },
    ai = {},
    auto_all = false,
    map = map_cfg,
    tiles = tiles_cfg,
  })
  -- 无 UI 的 headless 局不等动画；动画门是宿主侧边界，按 headless 口径注入。
  game.anim_gate_port = { wait_move_anim = false, wait_action_anim = false }
  gameplay_loop.tick(game, nil, 0)
  return game
end

describe("TestHeadlessBankruptcyElimination", function()
  before_each(function()
    _config_reset.reset_all()
  end)

  it("eliminates a player who cannot pay land rent", function()
    local game = _new_headless_game()
    local owner, payer = game.players[1], game.players[2]
    local idx, tile = support.first_land_tile(game.board)
    game:set_tile_owner(tile, owner.id)
    game:set_tile_level(tile, 3)
    game:set_player_property(owner, tile.id, true)
    game:set_player_cash(payer, 10)
    game:update_player_position(payer, idx)

    support.resolve_landing(game, payer, tile, {})

    luassert.is_true(payer.eliminated, "rent payer with non-positive cash is eliminated")
    luassert.is_false(owner.eliminated, "rent owner stays in the game")
  end)

  it("eliminates a player whose coin settlement leaves non-positive cash", function()
    local game = _new_headless_game()
    local payer = game.players[1]
    game:set_player_cash(payer, 5)
    local pay_cash = game.registries.chances.handlers.pay_cash

    pay_cash(game, payer, { effect = "pay_cash", target = "self", amount = 100 })

    luassert.is_true(payer.eliminated, "chance-card payer with non-positive cash is eliminated")
    luassert.are.equal(0, game:player_cash(payer))
  end)

  it("eliminates a player who cannot pay the hospital fee", function()
    local game = _new_headless_game()
    local patient = game.players[1]
    game:set_player_cash(patient, math.floor(constants.hospital_fee / 2))
    game:set_player_status(patient, "pending_location_effect", "hospital")

    game:player_apply_hospital_effects(patient)

    luassert.is_true(patient.eliminated, "patient with non-positive cash after the fee is eliminated")
    luassert.are.equal(0, game:player_cash(patient))
  end)
end)
