local Class = require("src.foundation.class")

---地块类，代表棋盘上的一个地块
local tile = Class("Tile")

function tile:init(cfg)
  self.id = cfg.id
  self.name = cfg.name
  self.type = cfg.type
  self.price = cfg.price or 0
  self.upgrade_costs = cfg.upgrade_costs or {}
  self.rents = cfg.rents or {}
  self.row = cfg.row
  self.col = cfg.col
  self.build_row = cfg.build_row
  self.build_col = cfg.build_col
  self.owner_id = nil
  self.level = 0
end

function tile.get_state(game, land_tile)
  assert(land_tile and land_tile.type == "land", "Tile.GetState requires land tile")
  return { owner_id = land_tile.owner_id, level = land_tile.level }
end

return tile

