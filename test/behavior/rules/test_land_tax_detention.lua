require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- luacheck: ignore 211
local support = require("test.support.shared_support")
local default_map = require("src.config.content.default_map")
local constants = require("src.config.content.constants")
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local function _new_game()
  return support.new_game({ map = default_map })
end

local _config_reset = require("test.support.config_reset")



describe("TestLandTaxDetention", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_apply_tax_with_pending_tax_free_skips_payment", function()
    local land = require("src.rules.land.executors")
    local g = _new_game()
    local p = g:current_player()
    g:set_player_cash(p, 10000)
    g:set_player_status(p, "pending_tax_free", true)

    local before_cash = g:player_cash(p)
    -- 地图必有税格(同文件 L83 同一 idiom):找不到当场红,不空转。
    local tax_idx = assert(g.board:find_first_by_type("tax"), "missing tax tile")
    g:update_player_position(p, tax_idx)
    local tile = g.board:get_tile(tax_idx)
    land.executors.tax.apply({ game = g, player = p, tile = tile })
    luassert.truthy(g:player_cash(p) == before_cash, "_apply_tax should skip payment when pending_tax_free is set")
    luassert.truthy(g:has_pending_tax_free(p) == false, "_apply_tax should clear pending_tax_free after use")
  end)

  it("test_apply_tax_without_tax_free_card_prompts_choice", function()
    local land = require("src.rules.land.executors")
    local g = _new_game()
    local p = g:current_player()
    g:set_player_cash(p, 10000)
    g:set_player_status(p, "pending_tax_free", false)
    p.inventory:clear()

    -- 地图必有税格(同文件 L83 同一 idiom):找不到当场红,不空转。
    local tax_idx = assert(g.board:find_first_by_type("tax"), "missing tax tile")
    g:update_player_position(p, tax_idx)
    local tile = g.board:get_tile(tax_idx)
    local res = land.executors.tax.apply({ game = g, player = p, tile = tile })
    -- Should return waiting intent for tax choice when player has tax_free card
    -- or pay tax directly if no card
    luassert.truthy(res == nil or (type(res) == "table" and res.waiting), "_apply_tax should either pay tax or prompt choice")
  end)

  it("test_apply_tax_charges_player_even_with_angel", function()
    local land = require("src.rules.land.executors")
    local g = _new_game()
    local p = g:current_player()
    g:set_player_cash(p, 10000)
    g:set_player_deity(p, "angel")

    local tax_idx = assert(g.board:find_first_by_type("tax"), "missing tax tile")
    g:update_player_position(p, tax_idx)
    local tile = g.board:get_tile(tax_idx)
    land.executors.tax.apply({ game = g, player = p, tile = tile })

    _assert_eq(g:player_cash(p), 10000 - math.floor(10000 * constants.tax_rate), "angel should not block tax office")
  end)

  it("test_hospital_and_mountain_detain_player_even_with_angel", function()
    local land = require("src.rules.land.executors")
    local g = _new_game()
    local p = g:current_player()

    g:set_player_deity(p, "angel")
    local hospital_idx = assert(g.board:find_first_by_type("hospital"), "missing hospital")
    g:update_player_position(p, hospital_idx)
    land.executors.hospital.apply({ game = g, player = p, tile = g.board:get_tile(hospital_idx) })
    luassert.truthy(g:detention_remaining(p) > 0, "angel should not block hospital stay")

    g:set_player_status(p, "stay_turns", 0)
    g:set_player_deity(p, "angel")
    local mountain_idx = assert(g.board:find_first_by_type("mountain"), "missing mountain")
    g:update_player_position(p, mountain_idx)
    land.executors.mountain.apply({ game = g, player = p, tile = g.board:get_tile(mountain_idx) })
    luassert.truthy(g:detention_remaining(p) > 0, "angel should not block mountain stay")
  end)


end)
