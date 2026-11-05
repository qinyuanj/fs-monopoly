require("test.bootstrap").install_package_paths()
local luassert = assert
local game_defaults = require("src.app.game_defaults")

describe("TestGameDefaults", function()

local function _test_identifies_class_like_tables()
  luassert.is_false(game_defaults.is_class_like(nil))
  luassert.is_false(game_defaults.is_class_like(42))
  luassert.is_false(game_defaults.is_class_like("string"))
  luassert.is_false(game_defaults.is_class_like({}))
  luassert.is_false(game_defaults.is_class_like({ __name = "Foo" }))
  luassert.is_true(game_defaults.is_class_like({
    __name = "MyClass",
    new = function() end,
  }))
  local instance = setmetatable({
    __name = "Instance",
    new = function() end,
  }, {
    __newindex = function() end,
  })
  luassert.is_false(game_defaults.is_class_like(instance))
end

local function _test_build_player_by_id_handles_missing_players_and_ids()
  luassert.is_nil(next(game_defaults.build_player_by_id(nil)))
  local indexed = game_defaults.build_player_by_id({
    { id = 1, name = "A" },
    { name = "NoId" },
    { id = 2, name = "B" },
  })
  luassert.is.equal("A", indexed[1].name)
  luassert.is.equal("B", indexed[2].name)
  local count = 0
  for _ in pairs(indexed) do count = count + 1 end
  luassert.is.equal(2, count)
end

local function _test_build_initial_turn_returns_expected_defaults()
  local turn = game_defaults.build_initial_turn()
  luassert.is.equal(1, turn.current_player_index)
  luassert.is.equal(0, turn.turn_count)
  luassert.is.equal("start", turn.phase)
  luassert.is_false(turn.countdown_active)
  luassert.is.equal(0, turn.countdown_seconds)
  luassert.is_nil(turn.pending_choice)
  luassert.is.equal(0, turn.choice_seq)
  luassert.is.equal(0, turn.move_anim_seq)
  luassert.is_nil(turn.move_anim)
  luassert.is.equal(0, turn.action_anim_seq)
  luassert.is_nil(turn.action_anim)
  luassert.is.same({}, turn.action_anim_queue)
  luassert.is_false(turn.landing_visual_hold_active)
  luassert.is_false(turn.landing_visual_release_pending)
  luassert.is_false(turn.move_followup_pending)
  luassert.is_false(turn.detained_wait_active)
  luassert.is.equal(0, turn.detained_wait_seconds)
  luassert.is.equal(0, turn.detained_wait_elapsed)
  luassert.is_false(turn.inter_turn_wait_active)
  luassert.is.equal(0, turn.inter_turn_wait_seconds)
  luassert.is.equal(0, turn.inter_turn_wait_elapsed)
  luassert.is_false(turn.no_action_notice_active)
  luassert.is_nil(turn.no_action_notice_player_id)
  luassert.is_nil(turn.no_action_notice_text)
  luassert.is.same({}, turn.item_phase)
  luassert.is.same({}, turn.used_effect_groups)
  luassert.is.equal("", turn.item_phase_active)
  luassert.is_nil(turn.market_prompt)
  luassert.is_nil(turn.post_action)
end

local function _test_init_tile_state_resets_only_land_tiles()
  local board = { path = {
    { type = "land", owner_id = 7, level = 3 },
    { type = "special", owner_id = 9, level = 2 },
  } }
  game_defaults.init_tile_state(board)
  luassert.is_nil(board.path[1].owner_id)
  luassert.is.equal(0, board.path[1].level)
  luassert.is.equal(9, board.path[2].owner_id)
  luassert.is.equal(2, board.path[2].level)
end

it("test_identifies_class_like_tables", _test_identifies_class_like_tables)
it("test_build_player_by_id_handles_missing_players_and_ids", _test_build_player_by_id_handles_missing_players_and_ids)
it("test_build_initial_turn_returns_expected_defaults", _test_build_initial_turn_returns_expected_defaults)
it("test_init_tile_state_resets_only_land_tiles", _test_init_tile_state_resets_only_land_tiles)
end)
