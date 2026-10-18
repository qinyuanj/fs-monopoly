local board_query = require("src.rules.board.query")
local property_value = require("src.rules.commerce.property_value")
local target_query = require("src.rules.items.target_query")

local board_utils = {}

board_utils.queue_walk = board_query.queue_walk
board_utils.indices_in_range = board_query.indices_in_range
board_utils.total_invested = property_value.total_invested
board_utils.find_best_tile = target_query.find_best_tile

return board_utils

