require("test.bootstrap").install_package_paths()
-- luacheck: ignore 143 (busted injects the verified luassert object)
local luassert = assert
-- luacheck: ignore 211
-- Manual roadblock / demolish target-selection tests.
-- Extracted verbatim from test_item.lua (formerly the
-- _roadblock_and_demolish_tests helper array wired far from its definitions).
--
local support = require("test.support.shared_support")
local default_map = require("src.config.content.default_map")
local function _new_game()
  return support.new_game({ map = default_map })
end
local _open_choice = support.open_choice
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _assert_tile_id_sequence = support.assert_tile_id_sequence
local executor = require("src.rules.items.executor")
local choice_resolver = require("src.rules.choice.resolver")
local item_ids = require("src.config.gameplay.item_ids")
local roadblock = require("src.rules.items.roadblock")
local _config_reset = require("test.support.config_reset")



describe("TestItemRoadblockAndDemolish", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_roadblock_manual_choice_shows_seven_tiles_with_tile_names_only", function()
    local g = _new_game()
    local p = g:current_player()
    local item_id = item_ids.roadblock
    local expected = roadblock.manual_candidates(g, p, 3)
    p.inventory:add({ id = item_id })

    local res = executor.use_item(g, p, item_id, { is_computer_controlled = false })
    luassert.truthy(type(res) == "table" and res.waiting, "manual roadblock should open choice")

    local pending = res.intent.choice_spec
    luassert.truthy(pending and pending.kind == "roadblock_target", "roadblock should open target choice")
    _assert_eq(#pending.options, 7, "manual roadblock should expose seven nearest unique options")

    local expected_ids = {}
    for _, cand in ipairs(expected) do
      expected_ids[cand.idx] = cand.tile.name
    end
    for i, opt in ipairs(pending.options) do
      luassert.truthy(expected_ids[opt.id] ~= nil, "roadblock option at " .. i .. " should be a valid candidate")
      _assert_eq(opt.label, expected_ids[opt.id], "roadblock option should show tile name only at " .. i)
    end

    luassert.truthy(pending.target_slot_layout ~= nil, "roadblock choice should include target_slot_layout")
    _assert_eq(#pending.target_slot_layout, 7, "target_slot_layout should map all seven options")
  end)

  it("test_roadblock_manual_choice_allows_current_tile", function()
    local g = _new_game()
    local p = g:current_player()
    local item_id = item_ids.roadblock
    local current_idx = p.position
    p.inventory:add({ id = item_id })

    local res = executor.use_item(g, p, item_id, { is_computer_controlled = false })
    luassert.truthy(type(res) == "table" and res.waiting, "manual roadblock should wait for target choice")
    local pending = _open_choice(g, res.intent.choice_spec)

    local center_slot = 4
    local self_option = nil
    for i, slot in ipairs(pending.target_slot_layout) do
      if slot == center_slot then
        self_option = pending.options[i]
        break
      end
    end
    luassert.truthy(self_option ~= nil, "center slot should have an option")
    _assert_eq(self_option.id, current_idx, "center slot should target current tile")

    choice_resolver.resolve(g, pending, { option_id = current_idx })
    _assert_eq(g.board:has_roadblock(current_idx), true, "manual roadblock should allow current tile placement")
  end)

  it("test_roadblock_manual_choice_hongkong_keeps_nearest_slots_ordered", function()
    local g = _new_game()
    local p = g:current_player()
    local item_id = item_ids.roadblock
    g:update_player_position(p, 7)
    p.inventory:add({ id = item_id })

    local candidate_names = {
      "深圳路",
      "广州路",
      "澳门路",
      "医院",
      "道具卡",
      "海口路",
      "南宁路",
    }

    local candidates = roadblock.manual_candidates(g, p, 3)
    _assert_eq(#candidates, 7, "hongkong roadblock candidates should still expose seven slots")
    for index, expected_name in ipairs(candidate_names) do
      _assert_eq(candidates[index].tile.name, expected_name, "hongkong candidate name mismatch at slot " .. index)
    end

    local arranged_names = {
      "海口路",
      "道具卡",
      "广州路",
      "深圳路",
      "澳门路",
      "医院",
      "南宁路",
    }

    local res = executor.use_item(g, p, item_id, { is_computer_controlled = false })
    luassert.truthy(type(res) == "table" and res.waiting, "manual roadblock should open choice at hongkong")
    local pending = _open_choice(g, res.intent.choice_spec)
    for index, expected_name in ipairs(arranged_names) do
      _assert_eq(pending.options[index].label, expected_name, "pending roadblock option label mismatch at slot " .. index)
    end
    _assert_eq(pending.options[1].id, 4, "haikou should be at backward-far slot")
  end)

  it("test_roadblock_manual_choice_hongkong_nearest_haikou_slot_places_correctly", function()
    local g = _new_game()
    local p = g:current_player()
    local item_id = item_ids.roadblock
    g:update_player_position(p, 7)
    p.inventory:add({ id = item_id })

    local res = executor.use_item(g, p, item_id, { is_computer_controlled = false })
    luassert.truthy(type(res) == "table" and res.waiting, "manual roadblock should wait for target choice at hongkong")
    local pending = _open_choice(g, res.intent.choice_spec)

    _assert_eq(pending.options[1].id, 4, "haikou should be at backward-far slot")
    choice_resolver.resolve(g, pending, { option_id = pending.options[1].id })

    _assert_eq(g.board:has_roadblock(4), true, "haikou slot should place roadblock on haikou")
    _assert_eq(g.board:has_roadblock(10), false, "haikou slot should not incorrectly place roadblock on nanning")
  end)

  it("test_roadblock_manual_candidates_expose_nearest_unique_tiles_at_intersection", function()
    local g = _new_game()
    local p = g:current_player()
    g:update_player_position(p, g.board:index_of_tile_id(45))
    g:set_player_status(p, "move_dir", nil)

    local candidates = roadblock.manual_candidates(g, p, 3)
    local expected_names = {
      "机会卡",
      "重庆路",
      "道具卡",
      "海口路",
      "广州路",
      "天津路",
      "台北路",
    }

    _assert_eq(#candidates, #expected_names, "intersection roadblock ui should expose seven nearest unique target tiles")
    for index, expected_name in ipairs(expected_names) do
      _assert_eq(candidates[index].tile.name, expected_name, "intersection candidate name mismatch at slot " .. index)
    end
  end)

  it("test_roadblock_manual_candidates_use_shared_manhattan_range_at_branch", function()
    local g = _new_game()
    local p = g:current_player()
    g:update_player_position(p, g.board:index_of_tile_id(42))

    local candidates = roadblock.manual_candidates(g, p, 3)
    local expected_ids = { 42, 3, 4, 45, 2, 5, 31 }

    _assert_tile_id_sequence(candidates, expected_ids, "branch roadblock candidate sequence mismatch")
  end)

  it("test_demolish_manual_choice_uses_manhattan_range_at_branch", function()
    local g = _new_game()
    local p = g:current_player()
    local item_id = item_ids.monster
    g:update_player_position(p, g.board:index_of_tile_id(42))
    p.inventory:add({ id = item_id })

    local target_ids = { 3, 4, 31, 5, 2, 1 }
    local target_indices = {}
    for _, tile_id in ipairs(target_ids) do
      local tile_ref = luassert.truthy(g.board:get_tile(g.board:index_of_tile_id(tile_id)), "missing target tile")
      g:set_tile_owner(tile_ref, g.players[2].id)
      g:set_tile_level(tile_ref, 1)
      target_indices[#target_indices + 1] = g.board:index_of_tile_id(tile_id)
    end

    local res = executor.use_item(g, p, item_id, { is_computer_controlled = false })
    luassert.truthy(type(res) == "table" and res.waiting == true, "monster manual use should open choice")
    local pending = res.intent.choice_spec
    luassert.truthy(pending and pending.kind == "demolish_target", "monster manual use should expose demolish target choice")

    local option_ids = {}
    for _, option in ipairs(pending.options or {}) do
      option_ids[#option_ids + 1] = option.id
    end
    for _, target_idx in ipairs(target_indices) do
      luassert.truthy(support.list_contains(option_ids, target_idx), "demolish manual choice should include index " .. tostring(target_idx))
    end
  end)

  it("test_roadblock_ai_uses_auto_candidates_only", function()
    local g = _new_game()
    local p = g:current_player()
    local item_id = item_ids.roadblock
    p.inventory:add({ id = item_id })

    local res = executor.use_item(g, p, item_id, { is_computer_controlled = true })
    local ok = (type(res) == "table" and type(res.ok) ~= "nil") and res.ok or res
    _assert_eq(ok, true, "ai roadblock should apply immediately")
    _assert_eq(g.board:has_roadblock(p.position), false, "ai roadblock should not place on current tile")
  end)


end)
