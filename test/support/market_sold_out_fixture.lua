require("test.bootstrap")

local inventory = require("src.rules.items.inventory")

local _SOLD_OUT_CASH = 120000
local _SOLD_OUT_TILE_ID = 27
local _SOLD_OUT_ITEM_ID = 2002
local _SOLD_OUT_ITEM_COUNT = 2
local _SOLD_OUT_PRODUCT_IDS = { 2002, 2003, 2004, 2005, 2012 }

local function apply_market_sold_out(game)
  local player = assert(game.players[1], "market_sold_out fixture requires player 1")
  game:set_player_cash(player, _SOLD_OUT_CASH)

  local board_index = game.board:index_of_tile_id(_SOLD_OUT_TILE_ID)
  assert(board_index ~= nil, "market_sold_out tile not on board: " .. tostring(_SOLD_OUT_TILE_ID))
  game:update_player_position(player, board_index)

  player.inventory:clear()
  for _ = 1, _SOLD_OUT_ITEM_COUNT do
    local ok = inventory.give(player, _SOLD_OUT_ITEM_ID, { game = game })
    assert(ok == true, "market_sold_out fixture failed to grant item " .. tostring(_SOLD_OUT_ITEM_ID))
  end

  for _, product_id in ipairs(_SOLD_OUT_PRODUCT_IDS) do
    game.market_limits[product_id] = 0
  end
end

return {
  apply = apply_market_sold_out,
}
