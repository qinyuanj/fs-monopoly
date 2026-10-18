require("test.bootstrap").install_package_paths()
-- luacheck: ignore 143 (busted injects the verified luassert object)
local luassert = assert
local support = require("test.support.shared_support")
local default_map = require("src.config.content.default_map")
local target_layout = require("src.rules.board.target_layout")

local function _new_game()
  return support.new_game({ map = default_map })
end

local function _option(g, tile_id)
  local idx = luassert.truthy(g.board:index_of_tile_id(tile_id), "missing tile id " .. tostring(tile_id))
  return { id = idx, tile_id = tile_id }
end

local function _slot_tile_ids(dense_options, slot_layout)
  local by_slot = {}
  for i, opt in ipairs(dense_options) do
    by_slot[slot_layout[i]] = opt.tile_id
  end
  return by_slot
end

-- Direct-geometry scenarios. The mock board exposes an empty movement map, so
-- direction.collect_forward/backward_indices return empty sets and every
-- candidate is classified purely by manhattan geometry relative to the start
-- tile: a larger row is "backward", a smaller row is "forward". That makes the
-- slot fill / overflow ordering fully deterministic.
local function _mock_board(tiles)
  return {
    map = {
      outer_next = {},
      outer_prev = {},
      neighbors = setmetatable({}, { __index = function() return {} end }),
      entry_points = {},
      direction = function() return "right" end,
    },
    get_tile = function(_, idx) return tiles[idx] end,
    index_of_tile_id = function(_, id) return id end,
  }
end

local function _row_tiles(start_row, deltas)
  local tiles = { [1] = { id = 1, row = start_row, col = 0 } }
  local options = {}
  for offset, delta in ipairs(deltas) do
    local idx = offset + 1
    tiles[idx] = { id = idx, row = start_row + delta, col = 0 }
    options[offset] = { id = idx }
  end
  return tiles, options
end

local function _dense_ids(dense_options)
  local ids = {}
  for i, opt in ipairs(dense_options) do
    ids[i] = opt.id
  end
  return ids
end

local function _assert_list_eq(actual, expected, label)
  luassert.truthy(#actual == #expected,
    label .. ": expected length " .. tostring(#expected) .. " got " .. tostring(#actual))
  for i = 1, #expected do
    luassert.truthy(actual[i] == expected[i],
      label .. "[" .. tostring(i) .. "]: expected " .. tostring(expected[i]) .. " got " .. tostring(actual[i]))
  end
end

local player = { position = 1, status = nil }


describe("TestTargetLayout", function()
  it("test_centers_the_players_own_tile_and_orders_neighbors_by_direction_and_distance", function()
    local g = _new_game()
    local p = g:current_player()
    g:update_player_position(p, g.board:index_of_tile_id(42))

    local options = {}
    for _, tile_id in ipairs({ 42, 3, 4, 31, 45, 2, 5, 1 }) do
      options[#options + 1] = _option(g, tile_id)
    end

    local dense_options, slot_layout = target_layout.arrange_target_options(g.board, p, options)
    local by_slot = _slot_tile_ids(dense_options, slot_layout)

    luassert.truthy(#dense_options == 7, "seven UI slots should be filled (one candidate overflows)")
    luassert.truthy(by_slot[4] == 42, "player's own tile should occupy the center slot")
    luassert.truthy(by_slot[3] == 3 and by_slot[2] == 2 and by_slot[1] == 1, "backward neighbors should fill outward from center in distance order")
    luassert.truthy(by_slot[5] == 4 and by_slot[6] == 45 and by_slot[7] == 31, "forward neighbors should fill outward from center in distance order")
    luassert.truthy(by_slot[nil] == nil, "no slot should be assigned past the overflow candidate")
  end)

  it("test_omits_the_players_own_tile_from_slots_when_it_is_not_among_the_options", function()
    local g = _new_game()
    local p = g:current_player()
    g:update_player_position(p, g.board:index_of_tile_id(42))

    local options = { _option(g, 3), _option(g, 4) }
    local dense_options, slot_layout = target_layout.arrange_target_options(g.board, p, options)
    local by_slot = _slot_tile_ids(dense_options, slot_layout)

    luassert.truthy(#dense_options == 2, "only the two supplied candidates should be arranged")
    luassert.truthy(by_slot[4] == nil, "center slot should stay empty when the player's tile is not offered")
    luassert.truthy(by_slot[3] == 3, "sole backward candidate should sit closest to center")
    luassert.truthy(by_slot[5] == 4, "sole forward candidate should sit closest to center")
  end)

  it("test_spills_surplus_backward_candidates_outward_into_empty_forward_slots", function()
    -- Five backward candidates (rows 11..15) fill slots 3,2,1 then overflow into
    -- forward slots 5,6; there is no sixth slot so the layout stops at slot 6.
    local tiles, options = _row_tiles(10, { 1, 2, 3, 4, 5 })
    local dense, layout = target_layout.arrange_target_options(_mock_board(tiles), player, options)
    _assert_list_eq(_dense_ids(dense), { 4, 3, 2, 5, 6 }, "backward overflow dense ids")
    _assert_list_eq(layout, { 1, 2, 3, 5, 6 }, "backward overflow slot layout")
  end)

  it("test_spills_surplus_forward_candidates_inward_into_empty_backward_slots", function()
    -- Five forward candidates (rows 9..5) fill slots 5,6,7 then overflow into
    -- backward slots 3,2; slot 1 stays empty because the queue is exhausted.
    local tiles, options = _row_tiles(10, { -1, -2, -3, -4, -5 })
    local dense, layout = target_layout.arrange_target_options(_mock_board(tiles), player, options)
    _assert_list_eq(_dense_ids(dense), { 6, 5, 2, 3, 4 }, "forward overflow dense ids")
    _assert_list_eq(layout, { 2, 3, 5, 6, 7 }, "forward overflow slot layout")
  end)

  it("test_does_not_overwrite_a_filled_forward_slot_when_backward_candidates_overflow", function()
    -- Four backward candidates plus one distant forward candidate: the forward
    -- one claims slot 5 in the primary pass, so the backward overflow must skip
    -- slot 5 and land in slot 6 rather than clobbering it.
    local tiles, options = _row_tiles(10, { 1, 2, 3, 4, -5 })
    local dense, layout = target_layout.arrange_target_options(_mock_board(tiles), player, options)
    _assert_list_eq(_dense_ids(dense), { 4, 3, 2, 6, 5 }, "mixed overflow dense ids")
    _assert_list_eq(layout, { 1, 2, 3, 5, 6 }, "mixed overflow slot layout")
  end)

  it("test_keeps_a_candidate_colocated_with_the_start_tile_by_flooring_its_distance_to_1", function()
    -- A candidate sharing the start tile's position has manhattan distance 0;
    -- it must be floored to distance 1 so it survives the distance-1..max walk
    -- instead of being dropped into an unwalked distance-0 bucket.
    local tiles = {
      [1] = { id = 1, row = 10, col = 0 },
      [2] = { id = 2, row = 10, col = 0 },
    }
    local dense, layout = target_layout.arrange_target_options(_mock_board(tiles), player, { { id = 2 } })
    _assert_list_eq(_dense_ids(dense), { 2 }, "co-located dense ids")
    _assert_list_eq(layout, { 5 }, "co-located slot layout")
  end)

  it("test__center_out_order_errors_on_missing_player_position", function()
    local p_no_pos = { name = "no_pos" }
    local ok, err = pcall(target_layout.arrange_target_options, _mock_board({}), p_no_pos, {})
    luassert.truthy(not ok, "missing position should error")
    luassert.truthy(type(err) == "string" and err:find("missing player.position", 1, true), "error should mention missing player.position, got: " .. tostring(err))
  end)

  it("test_arrange_target_options_errors_on_nil_board_with_expected_message", function()
    local ok, err = pcall(target_layout.arrange_target_options, nil, player, {})
    luassert.truthy(not ok, "nil board should error")
    luassert.truthy(type(err) == "string" and err:find("missing board", 1, true), "error should mention missing board, got: " .. tostring(err))
  end)

  it("test_arrange_target_options_errors_on_nil_player_with_expected_message", function()
    local ok, err = pcall(target_layout.arrange_target_options, _mock_board({}), nil, {})
    luassert.truthy(not ok, "nil player should error")
    luassert.truthy(type(err) == "string" and err:find("missing player", 1, true), "error should mention missing player, got: " .. tostring(err))
  end)

  it("test_arrange_asserts_missing_start_tile_with_message", function()
    -- #293:missing start tile 断言消息未测。
    local ok, err = pcall(target_layout.arrange_target_options,
      _mock_board({}, { get_tile = function() return nil end }), { position = 1 }, {})
    luassert.truthy(not ok, "unresolvable start tile should error")
    luassert.truthy(type(err) == "string" and err:find("missing start tile", 1, true) ~= nil, "error should mention the start tile, got: " .. tostring(err))
  end)


end)
