require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
local direction = require("src.rules.board.direction")

local function next_id(neighbors, facing)
  return direction.resolve_forward_next_id({ outer_next = {}, entry_points = {} },
    1, neighbors, facing, nil, false, nil)
end

describe("TestBoardForwardFallback", function()
  it("chooses_known_directions_in_navigation_priority_order", function()
    luassert.equal(10, next_id({ up = 10, right = 20, down = 30, left = 40 }))
    luassert.equal(20, next_id({ right = 20, down = 30, left = 40 }))
    luassert.equal(30, next_id({ down = 30, left = 40 }))
    luassert.equal(40, next_id({ left = 40 }))
  end)

  it("prefers_a_non_returning_neighbor_when_facing_is_unavailable", function()
    luassert.equal(20, next_id({ up = 10, right = 20 }, "down"))
  end)

  it("returns_back_when_it_is_the_only_neighbor", function()
    luassert.equal(10, next_id({ up = 10 }, "down"))
  end)

  it("returns_no_destination_for_an_empty_neighborhood", function()
    luassert.is_nil(next_id({}))
  end)

  it("prefers_known_directions_to_unknown_names", function()
    luassert.equal(10, next_id({ down = 10, aardvark = 20 }))
    luassert.equal(30, next_id({ left = 30, aardvark = 40 }))
  end)

  it("orders_unknown_directions_by_name", function()
    luassert.equal(10, next_id({ warp = 20, portal = 10 }))
  end)
end)
