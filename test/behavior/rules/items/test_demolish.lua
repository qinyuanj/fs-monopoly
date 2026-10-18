require("test.bootstrap").install_package_paths()
-- luacheck: ignore 143 (busted injects the verified luassert object)
local luassert = assert
-- Merged demolish tests (expand phase target).
-- Sources:
--   * test/behavior/rules/test_demolish_closure.lua
--   * test/behavior/rules/items/test_demolish_apply_mutation.lua
--   * test/behavior/rules/items/test_demolish_choice_mutation.lua
--   * test/behavior/rules/items/test_clear_obstacles_branch_walk.lua

-- ============================================================================
-- Shared helpers
-- ============================================================================
local support = require("test.support.shared_support")
local default_map = require("src.config.content.default_map")
local item_ids = require("src.config.gameplay.item_ids")
local event_kinds = require("src.config.gameplay.event_kinds")
local _config_reset = require("test.support.config_reset")

local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _tile_state = support.tile_state

local function _game(players)
  return support.new_game({ map = default_map, players = players or { "P1", "P2", "P3", "P4" } })
end

local function _capture_events(game)
  local recorded = {}
  game.event_feed_port = {
    publish = function(_, _, event)
      recorded[#recorded + 1] = event
      return true
    end,
  }
  return recorded
end

local function _first_event(recorded, kind)
  for _, event in ipairs(recorded) do
    if event.kind == kind then
      return event
    end
  end
  return nil
end

local function _enemy_building(game, idx, level)
  local tile = game.board:get_tile(idx)
  game:set_tile_owner(tile, 2)
  game:set_tile_level(tile, level)
  return tile
end

local function _with_anim_gate(game)
  game.ui_port = support.build_ui_port({ wait_action_anim = true })
  game.anim_gate_port = { wait_move_anim = false, wait_action_anim = true }
end

-- ============================================================================
-- Demolish facade closure pins
-- ============================================================================
local demolish = require("src.rules.items.demolish")



-- demolish.find_target / score_fn boundaries -----------------------------

describe("TestDemolishFacade", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_find_target_picks_the_highest_invested_enemy_building_in_range", function()
    local g = _game()
    local p = g:current_player()
    _enemy_building(g, 3, 1) -- lower invested
    _enemy_building(g, 4, 3) -- higher invested
    _assert_eq(demolish.find_target(g, p, 10), 4, "should target the more valuable building")
  end)

  it("test_find_target_returns_nil_when_no_enemy_building_exists", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    _assert_eq(demolish.find_target(g, p, 10), nil, "no eligible tile -> nil")
  end)

  it("test_find_target_skips_the_players_own_land", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    local tile = g.board:get_tile(3)
    g:set_tile_owner(tile, p.id) -- owned by acting player
    g:set_tile_level(tile, 3)
    _assert_eq(demolish.find_target(g, p, 10), nil, "own land must not be a target")
  end)

  it("test_find_target_skips_enemy_land_with_no_building_level_0", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    _enemy_building(g, 3, 0)
    _assert_eq(demolish.find_target(g, p, 10), nil, "level 0 land must not be a target")
  end)

  it("test_find_target_skips_enemy_land_without_a_level_field", function()
    -- #293:`(st.level or 0) > 0` 的 `0`→`1` 变异只在 level 缺失(而非 0)时可分。
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    local tile = g.board:get_tile(3)
    g:set_tile_owner(tile, 2)
    _assert_eq(demolish.find_target(g, p, 10), nil,
      "enemy land with no level must not be a target")
  end)

-- demolish.apply + _build_demolish_msg (missile / injure branch) ----------

  it("test_missile_destroying_a_vacant_building_omits_the_casualty_suffix", function()
    local g = _game()
    local p = g:current_player()
    local tile = _enemy_building(g, 2, 2)
    local recorded = _capture_events(g)

    local res = demolish.apply(g, p, 2, { item_id = item_ids.missile, injure = true, title = "导弹卡" })

    _assert_eq(res.ok, true, "missile apply succeeds")
    _assert_eq(_tile_state(g, tile).level, 0, "building destroyed")
    local event = _first_event(recorded, event_kinds.demolish)
    luassert.truthy(event ~= nil, "missile should publish a demolish event when nobody is hit")
    _assert_eq(
      event.text,
      p.name .. " 发射导弹轰炸 " .. tile.name .. "，建筑被摧毁",
      "hit==0 must not append the casualty suffix"
    )
  end)

  it("test_missile_blocked_by_an_angel_owner_keeps_the_casualty_suffix_but_drops_the_destroy_clause", function()
    local g = _game()
    local p = g:current_player()
    local tile = _enemy_building(g, 3, 2)
    g:set_player_deity(g.players[2], "angel", 3) -- owner immune -> building survives
    g:update_player_position(g.players[3], 3) -- a non-immune occupant gets hit
    local recorded = _capture_events(g)

    local res = demolish.apply(g, p, 3, { item_id = item_ids.missile, injure = true, title = "导弹卡" })

    _assert_eq(res.ok, true, "missile apply succeeds")
    _assert_eq(_tile_state(g, tile).level, 2, "angel-protected building is not destroyed")
    local event = _first_event(recorded, event_kinds.demolish)
    luassert.truthy(event ~= nil, "missile should publish a demolish event for the casualty")
    _assert_eq(
      event.text,
      p.name .. " 发射导弹轰炸 " .. tile.name .. "，1 名玩家送医",
      "no destroy means no '建筑被摧毁' clause, but the casualty suffix stays"
    )
  end)

  it("test_missile_without_an_anim_gate_relocates_the_occupant_immediately_no_followup", function()
    local g = _game()
    local p = g:current_player()
    _enemy_building(g, 3, 2)
    local occupant = g.players[2]
    g:update_player_position(occupant, 3)
    _capture_events(g)

    local res = demolish.apply(g, p, 3, { item_id = item_ids.missile, injure = true, title = "导弹卡" })

    _assert_eq(res.ok, true, "missile apply succeeds")
    _assert_eq(res.after_action_anim, nil, "no anim gate means no deferred followup")
    _assert_eq(occupant.position, g.board:find_first_by_type("hospital"), "occupant relocates to hospital now")
    luassert.truthy(g:detention_remaining(occupant) > 0, "hospital stay applied immediately without a gate")
  end)

  it("test_missile_hitting_an_occupied_enemy_building_destroys_it_and_hospitalises_the_occupant", function()
    local g = _game()
    local p = g:current_player()
    local tile = _enemy_building(g, 11, 2)
    local occupant = g.players[2]
    g:update_player_position(occupant, 11)
    local recorded = _capture_events(g)
    local hospital = g.board:find_first_by_type("hospital")

    local res = demolish.apply(g, p, 11, { item_id = item_ids.missile, injure = true, title = "导弹卡" })

    _assert_eq(res.ok, true, "missile apply succeeds")
    _assert_eq(_tile_state(g, tile).level, 0, "occupied enemy building is destroyed")
    _assert_eq(occupant.position, hospital, "occupant relocates to hospital")
    luassert.truthy(g:detention_remaining(occupant) > 0, "occupant is held in hospital")
    luassert.truthy(_first_event(recorded, event_kinds.demolish) ~= nil, "a demolish event is published")
  end)

  it("test_missile_with_an_anim_gate_defers_via_followup_and_carries_target_ids", function()
    local g = _game({ "P1", "P2", "P3" })
    g.ui_port = support.build_ui_port({ wait_action_anim = true })
    g.anim_gate_port = { wait_move_anim = false, wait_action_anim = true }
    local p = g:current_player()
    _enemy_building(g, 3, 2)
    g:update_player_position(g.players[2], 3)

    local res = demolish.apply(g, p, 3, { item_id = item_ids.missile, injure = true, title = "导弹卡" })

    local anim = g.turn.action_anim
    luassert.truthy(anim and anim.kind == "missile", "missile queues a missile anim")
    _assert_eq(#(anim.target_player_ids or {}), 1, "exactly one casualty is carried on the anim")
    _assert_eq(anim.target_player_ids[1], g.players[2].id, "the occupant id is carried")
    luassert.truthy(res.after_action_anim ~= nil, "anim gate defers hospital effects to the followup")
    _assert_eq(res.after_action_anim.next_state, "move_followup", "followup routes through move_followup")
  end)

-- demolish.apply + _build_demolish_msg (monster / non-injure branch) ------

  it("test_monster_destroying_an_enemy_building_publishes_the_monster_destroy_text", function()
    local g = _game()
    local p = g:current_player()
    local tile = _enemy_building(g, 3, 2)
    local recorded = _capture_events(g)

    demolish.apply(g, p, 3, { item_id = item_ids.monster, injure = false })

    _assert_eq(_tile_state(g, tile).level, 0, "building destroyed")
    local event = _first_event(recorded, event_kinds.demolish)
    luassert.truthy(event ~= nil, "monster should publish a demolish event")
    _assert_eq(event.text, p.name .. " 释放怪兽拆毁 " .. tile.name .. " 的建筑", "monster destroy text")
  end)

  it("test_monster_fully_blocked_by_an_angel_publishes_no_demolish_event", function()
    local g = _game()
    local p = g:current_player()
    local tile = _enemy_building(g, 3, 2)
    g:set_player_deity(g.players[2], "angel", 3)
    local recorded = _capture_events(g)

    demolish.apply(g, p, 3, { item_id = item_ids.monster, injure = false })

    _assert_eq(_tile_state(g, tile).level, 2, "angel-protected building survives")
    _assert_eq(_first_event(recorded, event_kinds.demolish), nil, "fully blocked: no demolish text published")
  end)

  it("test_monster_destroys_owned_but_empty_land_before_checking_immunity", function()
    local g = _game()
    local p = g:current_player()
    local tile = _enemy_building(g, 3, 0)
    g:set_player_deity(g.players[2], "angel", 3) -- immune, but must be bypassed
    local recorded = _capture_events(g)

    demolish.apply(g, p, 3, { item_id = item_ids.monster, injure = false })

    local event = _first_event(recorded, event_kinds.demolish)
    luassert.truthy(event ~= nil, "empty owned land is destroyed without an immunity check")
    _assert_eq(event.text, p.name .. " 释放怪兽拆毁 " .. tile.name .. " 的建筑", "monster destroy text")
    _assert_eq(_first_event(recorded, event_kinds.item_immune), nil, "immunity branch is bypassed for empty land")
    -- kills _try_destroy_building 快捷臂 set_tile_level(tile, 0) 的 0 -> 1。
    _assert_eq(_tile_state(g, tile).level, 0, "empty land reset keeps level 0")
  end)

-- demolish.use dispatch --------------------------------------------------

  it("test_use_returns_false_when_there_is_no_target", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    local res = demolish.use(g, p, 3, function() return true end, { item_id = item_ids.monster, is_computer_controlled = true })
    _assert_eq(res, false, "no target -> false")
  end)

  it("test_human_use_opens_a_demolish_choice_excluding_the_current_tile", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    _enemy_building(g, 3, 2)
    local choice = demolish.use(g, p, 3, nil, { item_id = item_ids.monster, injure = false, title = "怪兽卡" })
    luassert.truthy(choice and choice.waiting, "human use waits on a choice")
    local spec = choice.intent and choice.intent.choice_spec
    luassert.truthy(spec and spec.kind == "demolish_target", "opens demolish_target choice")
    local ids = {}
    for _, option in ipairs(spec.options) do ids[option.id] = true end
    luassert.truthy(ids[3], "the enemy building is offered")
    _assert_eq(ids[p.position], nil, "the acting player's own tile is never offered")
  end)

  it("test_ai_use_consumes_the_item_then_applies_the_demolition", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    local tile = _enemy_building(g, 3, 2)
    local consumed
    local res = demolish.use(g, p, 3, function(_, id) consumed = id; return true end,
      { item_id = item_ids.monster, injure = false, is_computer_controlled = true })
    _assert_eq(consumed, item_ids.monster, "consume_fn is called with the item id")
    luassert.truthy(type(res) == "table" and res.ok == true, "ai use applies and reports ok")
    _assert_eq(_tile_state(g, tile).level, 0, "building destroyed by ai use")
  end)

  it("test_ai_use_aborts_without_applying_when_consume_fails", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    local tile = _enemy_building(g, 3, 2)
    local res = demolish.use(g, p, 3, function() return false end,
      { item_id = item_ids.monster, injure = false, is_computer_controlled = true })
    _assert_eq(res, false, "failed consume -> false")
    _assert_eq(_tile_state(g, tile).level, 2, "building untouched when consume fails")
  end)

-- ============================================================================
-- Demolish facade — human choice spec / immune filter / anim patch
-- ============================================================================
end)


describe("TestDemolishFacadeHumanChoiceImmuneFilterAnimPatch", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_human_choice_carries_the_demolish_target_route_key_and_cancel_affordance", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    _enemy_building(g, 3, 2)
    local choice = demolish.use(g, p, 3, nil, { item_id = item_ids.monster, injure = false, title = "怪兽卡" })
    local spec = choice.intent.choice_spec
    _assert_eq(spec.route_key, "target", "route_key pins the dispatch key")
    _assert_eq(spec.allow_cancel, true, "human demolish choice is cancelable")
    _assert_eq(spec.cancel_label, "取消", "cancel label text is pinned")
    _assert_eq(spec.title, "怪兽卡：选择目标格子", "explicit title flows into the choice title")
  end)

  it("test_human_choice_falls_back_to_the_default_title_when_opts_title_is_absent", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    _enemy_building(g, 3, 2)
    local choice = demolish.use(g, p, 3, nil, { item_id = item_ids.monster, injure = false })
    _assert_eq(
      choice.intent.choice_spec.title,
      "选择目标：选择目标格子",
      "nil title resolves to the '选择目标' default"
    )
  end)

  it("test_human_choice_excludes_the_tile_under_the_acting_player_even_if_enemy_owned", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    _enemy_building(g, 3, 2)
    g:update_player_position(p, 3) -- acting player stands on an enemy building
    _enemy_building(g, 4, 2) -- a different in-range target keeps the choice open
    local choice = demolish.use(g, p, 3, nil, { item_id = item_ids.monster, injure = false })
    local ids = {}
    for _, option in ipairs(choice.intent.choice_spec.options) do ids[option.id] = true end
    _assert_eq(ids[3], nil, "idx == player.position is excluded (the 'or position' guard)")
    luassert.truthy(ids[4], "a separate in-range enemy building is still offered")
  end)

  it("test_human_choice_excludes_self_owned_land_and_building_less_enemy_land", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    local lands = {}
    for idx = 1, 60 do
      local tile = g.board:get_tile(idx)
      if tile and tile.type == "land" and idx ~= p.position then
        lands[#lands + 1] = idx
        if #lands == 3 then break end
      end
    end
    luassert.truthy(#lands == 3, "map must expose three land tiles")
    local self_idx, empty_idx, target_idx = lands[1], lands[2], lands[3]

    local own = g.board:get_tile(self_idx)
    g:set_tile_owner(own, p.id)
    g:set_tile_level(own, 3) -- owned by the acting player
    _enemy_building(g, empty_idx, 0) -- enemy land with no building
    _enemy_building(g, target_idx, 2) -- valid target

    local choice = demolish.use(g, p, 60, nil, { item_id = item_ids.monster, injure = false })
    local ids = {}
    for _, option in ipairs(choice.intent.choice_spec.options) do ids[option.id] = true end
    _assert_eq(ids[self_idx], nil, "self-owned land excluded (owner ~= player.id clause)")
    _assert_eq(ids[empty_idx], nil, "level-0 enemy land excluded (level > 0 clause)")
    luassert.truthy(ids[target_idx], "the valid enemy building is offered")
  end)

  it("test_missile_spares_an_angel_immune_occupant_from_relocation", function()
    local g = _game({ "P1", "P2", "P3" })
    local p = g:current_player()
    _enemy_building(g, 3, 2) -- owned by player 2
    local immune = g.players[2]
    local casualty = g.players[3]
    g:update_player_position(immune, 3)
    g:update_player_position(casualty, 3)
    g:set_player_deity(immune, "angel", 3) -- occupant immune to the missile
    _capture_events(g)
    local hospital = g.board:find_first_by_type("hospital")

    demolish.apply(g, p, 3, { item_id = item_ids.missile, injure = true, title = "导弹卡" })

    _assert_eq(immune.position, 3, "immune occupant is filtered out and not relocated")
    _assert_eq(casualty.position, hospital, "the non-immune occupant is relocated to hospital")
  end)

  it("test_missile_with_an_anim_gate_patches_the_queued_anims_to_index_to_the_hospital", function()
    local g = _game({ "P1", "P2", "P3" })
    g.ui_port = support.build_ui_port({ wait_action_anim = true })
    g.anim_gate_port = { wait_move_anim = false, wait_action_anim = true }
    local p = g:current_player()
    _enemy_building(g, 3, 2)
    g:update_player_position(g.players[2], 3)
    local hospital = g.board:find_first_by_type("hospital")

    demolish.apply(g, p, 3, { item_id = item_ids.missile, injure = true, title = "导弹卡" })

    local anim = g.turn.action_anim
    luassert.truthy(anim and anim.kind == "missile", "missile anim is queued")
    _assert_eq(anim.to_index, hospital, "the matching queued anim is patched to the hospital index")
  end)

  it("test_monster_on_a_non_land_tile_is_fully_blocked_no_event_but_the_monster_anim_kind_stays", function()
    local g = _game({ "P1", "P2" })
    g.ui_port = support.build_ui_port({ wait_action_anim = true })
    g.anim_gate_port = { wait_move_anim = false, wait_action_anim = true }
    local p = g:current_player()
    local non_land_idx = nil
    for idx = 1, 60 do
      local tile = g.board:get_tile(idx)
      if tile and tile.type ~= "land" then non_land_idx = idx; break end
    end
    luassert.truthy(non_land_idx, "map must have a non-land tile")
    local recorded = _capture_events(g)

    local res = demolish.apply(g, p, non_land_idx, { item_id = item_ids.monster, injure = false })

    _assert_eq(res.ok, true, "apply still reports ok on a non-land target")
    _assert_eq(
      _first_event(recorded, event_kinds.demolish),
      nil,
      "non-land + no-injure is fully blocked (destroyed stays false) -> no demolish text"
    )
    _assert_eq(g.turn.action_anim.kind, "monster", "the monster anim kind is carried even when nothing is destroyed")
  end)

  it("test_missile_injure_with_zero_casualties_does_not_defer_a_hospital_followup", function()
    local g = _game({ "P1", "P2" })
    g.ui_port = support.build_ui_port({ wait_action_anim = true })
    g.anim_gate_port = { wait_move_anim = false, wait_action_anim = true }
    local p = g:current_player()
    _enemy_building(g, 3, 2) -- destroyable, but nobody is standing on it
    _capture_events(g)

    local res = demolish.apply(g, p, 3, { item_id = item_ids.missile, injure = true, title = "导弹卡" })

    _assert_eq(res.ok, true, "missile apply succeeds")
    _assert_eq(res.after_action_anim, nil, "hit == 0 means no relocation and no deferred followup")
  end)

  it("test_missile_destroying_nothing_and_hitting_nobody_is_fully_blocked_no_demolish_text", function()
    local g = _game()
    local p = g:current_player()
    local tile = _enemy_building(g, 3, 2)
    g:set_player_deity(g.players[2], "angel", 3) -- owner immune -> building survives
    local recorded = _capture_events(g) -- nobody stands on tile 3 -> hit == 0

    local res = demolish.apply(g, p, 3, { item_id = item_ids.missile, injure = true, title = "导弹卡" })

    _assert_eq(res.ok, true, "missile apply succeeds")
    _assert_eq(_tile_state(g, tile).level, 2, "angel-protected building survives")
    _assert_eq(
      _first_event(recorded, event_kinds.demolish),
      nil,
      "no destroy AND zero casualties = fully blocked -> no demolish text"
    )
  end)

  it("test_monster_on_a_level_1_angel_building_respects_immunity_no_le_0_destroy_shortcut", function()
    local g = _game()
    local p = g:current_player()
    local tile = _enemy_building(g, 3, 1) -- exactly level 1
    g:set_player_deity(g.players[2], "angel", 3)
    local recorded = _capture_events(g)

    demolish.apply(g, p, 3, { item_id = item_ids.monster, injure = false })

    _assert_eq(_tile_state(g, tile).level, 1, "level-1 building is protected by immunity, not destroyed")
    _assert_eq(_first_event(recorded, event_kinds.demolish), nil, "fully blocked, no demolish text")
  end)

  it("test_missile_relocation_tolerates_an_absent_turn_context_without_crashing", function()
    local g = _game()
    local p = g:current_player()
    _enemy_building(g, 3, 2)
    g:update_player_position(g.players[2], 3)
    _capture_events(g)
    g.turn = nil -- no active turn context

    local ok = pcall(function()
      return demolish.apply(g, p, 3, { item_id = item_ids.missile, injure = true, title = "导弹卡" })
    end)
    luassert.truthy(ok, "apply must not crash patching anim targets when game.turn is absent")
  end)

  it("test_human_choice_with_a_single_in_range_target_offers_exactly_one_option", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    _enemy_building(g, 3, 2) -- the only enemy building in range

    local choice = demolish.use(g, p, 3, nil, { item_id = item_ids.monster, injure = false })
    local count = 0
    for _, option in ipairs(choice.intent.choice_spec.options) do
      if option.id == 3 then count = count + 1 end
    end
    _assert_eq(count, 1, "the single target is offered exactly once (no fallback double-push)")
  end)

-- ============================================================================
-- Direct demolish_apply mutation pins
-- ============================================================================
end)
local demolish_apply = require("src.rules.items.demolish_apply")
local achievement_progress = require("src.rules.ports.achievement_progress")



describe("TestDemolishApplyMutationPins", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_monster_destroying_an_enemy_building_publishes_the_demolish_event_l93_not_destroyed", function()
    local g = _game()
    local p = g:current_player()
    local tile = _enemy_building(g, 3, 2)
    local recorded = _capture_events(g)

    demolish_apply.apply(g, p, 3, { item_id = item_ids.monster, injure = false })

    _assert_eq(_tile_state(g, tile).level, 0, "building destroyed")
    local event = _first_event(recorded, event_kinds.demolish)
    luassert.truthy(event ~= nil, "monster destroy must publish a demolish event; L93 'not' removal suppresses it")
    _assert_eq(event.text, p.name .. " 释放怪兽拆毁 " .. tile.name .. " 的建筑", "monster destroy text")
  end)

  it("test_monster_on_a_level_1_angel_building_respects_immunity_l19_le_0_boundary", function()
    local g = _game()
    local p = g:current_player()
    local tile = _enemy_building(g, 3, 1)
    g:set_player_deity(g.players[2], "angel", 3)
    local recorded = _capture_events(g)

    demolish_apply.apply(g, p, 3, { item_id = item_ids.monster, injure = false })

    _assert_eq(_tile_state(g, tile).level, 1, "level-1 building is protected by immunity, not destroyed")
    _assert_eq(_first_event(recorded, event_kinds.demolish), nil,
      "fully blocked: no demolish text; the '<= 1' mutant would destroy and publish")
  end)

  it("test_missile_destroying_a_building_does_not_record_a_monster_demolish_achievement_l78_and", function()
    local g = _game()
    local p = g:current_player()
    _enemy_building(g, 3, 2) -- owner (player 2) is not immune -> destroyed, owner returned
    _capture_events(g)

    local saved = achievement_progress.monster_demolished_building
    local calls = 0
    achievement_progress.monster_demolished_building = function() calls = calls + 1 end

    local ok, err = pcall(function()
      demolish_apply.apply(g, p, 3, { item_id = item_ids.missile, injure = true, title = "导弹卡" })
    end)

    achievement_progress.monster_demolished_building = saved
    luassert.truthy(ok, "apply must not error: " .. tostring(err))
    _assert_eq(calls, 0,
      "missile kind must not record a monster-demolish; L78 'or' mutation fires it on destroyed_owner alone")
  end)

  it("test_monster_destroying_a_building_does_record_the_monster_demolish_achievement_l78_kind_match", function()
    local g = _game()
    local p = g:current_player()
    _enemy_building(g, 3, 2)
    _capture_events(g)

    local saved = achievement_progress.monster_demolished_building
    local calls = 0
    achievement_progress.monster_demolished_building = function() calls = calls + 1 end

    demolish_apply.apply(g, p, 3, { item_id = item_ids.monster, injure = false })

    achievement_progress.monster_demolished_building = saved
    _assert_eq(calls, 1, "monster destroying an owned building records exactly one achievement")
  end)

  it("test_action_anim_duration_falls_back_to_1_0_when_config_seconds_is_nil_l12_or_1_0", function()
    local timing_name = "src.config.gameplay.timing"
    local apply_name = "src.rules.items.demolish_apply"
    local saved_timing = package.loaded[timing_name]
    local saved_apply = package.loaded[apply_name]

    local real_timing = require(timing_name)
    local mock = {}
    for k, v in pairs(real_timing) do mock[k] = v end
    mock.action_anim_default_seconds = nil -- force the `or` fallback

    package.loaded[timing_name] = mock
    package.loaded[apply_name] = nil
    local reloaded = require(apply_name)

    local ok, err = pcall(function()
      local g = _game()
      local p = g:current_player()
      _with_anim_gate(g)
      _enemy_building(g, 3, 2)
      _capture_events(g)
      reloaded.apply(g, p, 3, { item_id = item_ids.monster, injure = false })
      _assert_eq(g.turn.action_anim.duration, 1.0,
        "nil config seconds must fall back to 1.0 via `or`; the `and` mutant yields nil")
    end)

    package.loaded[apply_name] = saved_apply
    package.loaded[timing_name] = saved_timing
    if not ok then error(err) end
  end)

-- ============================================================================
-- Direct demolish_choice mutation pins
-- ============================================================================
end)
local demolish_choice = require("src.rules.items.demolish_choice")

local function _zero_value_enemy(game, idx)
  local tile = _enemy_building(game, idx, 1)
  tile.price = 0
  tile.upgrade_costs = {}
  return tile
end



describe("TestDemolishChoiceMutationPins", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_find_target_keeps_a_zero_invested_enemy_building_l23_value_lt_0_boundary", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    luassert.truthy(p.id ~= 2, "acting player must differ from the enemy owner id 2")

    local target_idx = nil
    for idx = 1, 60 do
      local tile = g.board:get_tile(idx)
      if tile and tile.type == "land" and idx ~= p.position then
        target_idx = idx
        break
      end
    end
    luassert.truthy(target_idx, "map must expose a land tile away from the player")
    _zero_value_enemy(g, target_idx)

    local picked = demolish_choice.find_target(g, p, 60)
    _assert_eq(picked, target_idx,
      "value == 0 must be kept (0 < 0 is false); '<= 0' and '< 1' mutants would return nil")
  end)

  it("test_find_target_still_returns_nil_when_there_is_no_eligible_enemy_building", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    _assert_eq(demolish_choice.find_target(g, p, 60), nil, "no eligible tile -> nil")
  end)

  it("test_build_human_choice_rejects_the_fallback_best_idx_that_is_the_players_own_tile_l30_or", function()
    local g = _game({ "P1", "P2" })
    local p = g:current_player()
    luassert.truthy(p.id ~= 2, "acting player must differ from the enemy owner id 2")

    local pos_idx = nil
    for idx = 1, 60 do
      local tile = g.board:get_tile(idx)
      if tile and tile.type == "land" then
        pos_idx = idx
        break
      end
    end
    luassert.truthy(pos_idx, "map must expose a land tile")
    g:update_player_position(p, pos_idx)
    _enemy_building(g, pos_idx, 2) -- enemy building directly under the player

    local choice = demolish_choice.build_human_choice(g, p, 60, pos_idx,
      { item_id = item_ids.monster, injure = false, title = "怪兽卡" })

    _assert_eq(choice, nil,
      "the player's own tile must never become an option; the 'and' mutant accepts it and returns a choice")
  end)

-- ============================================================================
-- Clear obstacles branch walk
-- ============================================================================
end)
local action_anim_port = require("src.foundation.ports.action_anim")
local post_effects = require("src.rules.items.post_effects")
local obstacle_clear = require("src.rules.items.obstacle_clear")
local obstacle_clear_tiles = require("src.rules.items.obstacle_clear_tiles")
local runtime_constants = require("src.config.gameplay.runtime_constants")
local Board = require("src.rules.board")

local function _new_game()
  return support.new_game({ map = default_map })
end

local function _capture_anim_payload(game, fn)
  local captured = nil
  game.anim_gate_port = { wait_action_anim = true }
  game.queue_action_anim = function(_, payload)
    captured = payload
  end
  support.with_patches({
    {
      target = action_anim_port,
      key = "queue",
      value = function(_, payload)
        captured = payload
        return true
      end,
    },
  }, fn)
  return captured
end



describe("TestClearObstaclesBranchWalk", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_linear_path_produces_single_branch_with_12_entries", function()
    local g = _new_game()
    local p = g:current_player()

    g:update_player_position(p, 1)
    g:set_player_status(p, "move_dir", "left")

    g.board:place_roadblock(3)
    g.board:place_roadblock(7)
    g.board:place_roadblock(10)

    local context = {}
    local payload = _capture_anim_payload(g, function()
      post_effects.apply_post(g, p, item_ids.clear_obstacles, context)
    end)

    luassert.truthy(type(payload) == "table", "payload should be a table")
    luassert.truthy(type(payload.branches) == "table", "payload must have 'branches' field (new contract) — got " .. tostring(payload.branches))
    _assert_eq(#payload.branches, 1, "linear path should produce exactly 1 branch")

    local branch = payload.branches[1]
    luassert.truthy(type(branch) == "table", "branch should be a table")
    _assert_eq(#branch, 12, "linear branch should have exactly 12 entries (full distance)")

    local obstacle_relative_positions = { 2, 6, 9 }
    for _, rel_pos in ipairs(obstacle_relative_positions) do
      luassert.truthy(type(branch[rel_pos]) == "table", "branch entry at position " .. rel_pos .. " should be a table")
      luassert.truthy(branch[rel_pos].has_obstacle == true, "branch entry at relative position " .. rel_pos .. " should have has_obstacle=true")
    end

    luassert.truthy(branch[1].has_obstacle == false, "branch[1] (index 2, no obstacle) should have has_obstacle=false")

    for i, entry in ipairs(branch) do
      luassert.truthy(type(entry) == "table" and entry.tile_index ~= nil, "branch entry " .. i .. " must have tile_index field")
    end
  end)

  it("test_forked_path_produces_two_branches", function()
    local g = _new_game()
    local p = g:current_player()

    local fork_approach_index = 4
    g:update_player_position(p, fork_approach_index)
    g:set_player_status(p, "move_dir", "left")

    local context = {}
    local payload = _capture_anim_payload(g, function()
      post_effects.apply_post(g, p, item_ids.clear_obstacles, context)
    end)

    luassert.truthy(type(payload) == "table", "payload should be a table")
    luassert.truthy(type(payload.branches) == "table", "payload must have 'branches' field (new contract) — got " .. tostring(payload.branches))
    luassert.truthy(#payload.branches >= 2, "forked path should produce at least 2 branches, got " .. tostring(#payload.branches))

    for b_idx, branch in ipairs(payload.branches) do
      luassert.truthy(type(branch) == "table", "branch " .. b_idx .. " should be a table")
      luassert.truthy(#branch > 0, "branch " .. b_idx .. " should be non-empty")
      for e_idx, entry in ipairs(branch) do
        luassert.truthy(type(entry) == "table", "branch " .. b_idx .. " entry " .. e_idx .. " should be a table")
        luassert.truthy(entry.tile_index ~= nil, "branch " .. b_idx .. " entry " .. e_idx .. " must have tile_index")
        luassert.truthy(type(entry.has_obstacle) == "boolean", "branch " .. b_idx .. " entry " .. e_idx .. " must have boolean has_obstacle")
      end
    end
  end)

  it("test_dead_end_stops_at_board_edge", function()
    local g = _new_game()
    local p = g:current_player()

    local tiles = {}
    local tile_lookup = {}
    local neighbors_map = {}
    local ids = {101, 102, 103, 104, 105, 106}
    for i, id in ipairs(ids) do
      local t = { id = id, name = "T" .. i, type = "land", row = i, col = 1 }
      tiles[i] = t
      tile_lookup[id] = t
      neighbors_map[id] = {}
    end
    for i = 1, #ids - 1 do
      neighbors_map[ids[i]]["right"] = ids[i + 1]
      neighbors_map[ids[i + 1]]["left"] = ids[i]
    end

    local synthetic_board = Board:new({
      tile_lookup = tile_lookup,
      path = tiles,
      branches = {},
      map = {
        neighbors = neighbors_map,
        outer_next = {},
        outer_prev = {},
        entry_points = {},
        start_id = ids[1],
        direction = function(from_id, to_id)
          local from_pos = 0
          local to_pos = 0
          for i, id in ipairs(ids) do
            if id == from_id then from_pos = i end
            if id == to_id then to_pos = i end
          end
          return to_pos > from_pos and "right" or "left"
        end,
      },
      overlays = {
        roadblocks = {},
        mines = {},
      },
    })

    local original_board = g.board
    g.board = synthetic_board

    p.position = 1
    g:set_player_status(p, "move_dir", "right")

    local context = {}
    local payload = _capture_anim_payload(g, function()
      post_effects.apply_post(g, p, item_ids.clear_obstacles, context)
    end)

    g.board = original_board

    luassert.truthy(type(payload) == "table", "payload should be a table")
    luassert.truthy(type(payload.branches) == "table", "payload must have 'branches' field (new contract) — got " .. tostring(payload.branches))
    _assert_eq(#payload.branches, 1, "dead-end path should produce exactly 1 branch")

    local branch = payload.branches[1]
    luassert.truthy(type(branch) == "table", "branch should be a table")
    _assert_eq(#branch, 5,
      "dead-end branch should stop at board edge with 5 entries, not padded to 12")
  end)

  it("test_duration_is_positive_number_in_payload", function()
    local g = _new_game()
    local p = g:current_player()

    g:update_player_position(p, 1)
    g:set_player_status(p, "move_dir", "left")

    local context = {}
    local payload = _capture_anim_payload(g, function()
      post_effects.apply_post(g, p, item_ids.clear_obstacles, context)
    end)

    luassert.truthy(type(payload) == "table", "payload should be a table")
    luassert.truthy(type(payload.branches) == "table", "payload must have 'branches' field (new contract) — got " .. tostring(payload.branches))
    luassert.truthy(type(payload.duration) == "number", "payload.duration must be a number, got " .. type(payload.duration))
    luassert.truthy(payload.duration > 0, "payload.duration must be positive, got " .. tostring(payload.duration))
    luassert.truthy(payload.duration >= 0.1 and payload.duration <= 30, "payload.duration out of reasonable range [0.1, 30]: " .. tostring(payload.duration))
  end)

end)


local function _build_board(ids, neighbors_map)
  local tiles = {}
  local tile_lookup = {}
  for i, id in ipairs(ids) do
    local t = { id = id, name = "T" .. id, type = "land", row = i, col = 1 }
    tiles[i] = t
    tile_lookup[id] = t
  end
  return Board:new({
    tile_lookup = tile_lookup,
    path = tiles,
    branches = {},
    map = {
      neighbors = neighbors_map,
      outer_next = {},
      outer_prev = {},
      entry_points = {},
      start_id = ids[1],
    },
    overlays = { roadblocks = {}, mines = {} },
  })
end

local function _chain(ids)
  local neigh = {}
  for _, id in ipairs(ids) do neigh[id] = {} end
  for i = 1, #ids - 1 do
    neigh[ids[i]].right = ids[i + 1]
    neigh[ids[i + 1]].left = ids[i]
  end
  return neigh
end

local function _seat_player(g, board, move_dir)
  g.board = board
  local p = g:current_player()
  p.position = 1
  g:set_player_status(p, "move_dir", move_dir)
  return p
end

local function _run_handle(g, p, cfg, queue_return)
  local captured, result = nil, nil
  support.with_patches({
    {
      target = action_anim_port,
      key = "queue",
      value = function(_, payload)
        captured = payload
        return queue_return
      end,
    },
  }, function()
    result = obstacle_clear.handle(g, p, cfg, {})
  end)
  return captured, result
end

local function _install_event_capture(g)
  local events = {}
  g.event_feed_port = {
    publish = function(_, _, event)
      events[#events + 1] = event
      return true
    end,
  }
  return events
end

local function _has_cleared_event(events)
  for _, event in ipairs(events) do
    if event.kind == event_kinds.obstacle_cleared then
      return true
    end
  end
  return false
end

describe("TestClearObstaclesMutationSurvivors", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_payload_reports_exact_roadblock_and_mine_counts", function()
    local g = _new_game()
    local board = _build_board({ 60, 61, 62, 63, 64 }, _chain({ 60, 61, 62, 63, 64 }))
    board:place_roadblock(2)
    board:place_roadblock(4)
    board:place_mine(3)
    local p = _seat_player(g, board, "right")

    local payload = _run_handle(g, p, { distance = 12 }, true)

    luassert.truthy(type(payload) == "table", "handle should queue a payload")
    _assert_eq(payload.roadblock_cleared, 2, "two roadblocks on the path must be counted exactly")
    _assert_eq(payload.mine_cleared, 1, "one mine on the path must be counted exactly")
  end)

  it("test_no_obstacles_reports_zero_counts_and_publishes_no_cleared_event", function()
    local g = _new_game()
    local events = _install_event_capture(g)
    local board = _build_board({ 80, 81, 82 }, _chain({ 80, 81, 82 }))
    local p = _seat_player(g, board, "right")

    local payload = _run_handle(g, p, { distance = 12 }, true)

    _assert_eq(payload.roadblock_cleared, 0, "no roadblocks means zero roadblock_cleared")
    _assert_eq(payload.mine_cleared, 0, "no mines means zero mine_cleared")
    _assert_eq(_has_cleared_event(events), false,
      "no obstacles cleared must not publish an obstacle_cleared event")
  end)

  it("test_single_obstacle_publishes_cleared_event", function()
    local g = _new_game()
    local events = _install_event_capture(g)
    local board = _build_board({ 70, 71, 72 }, _chain({ 70, 71, 72 }))
    board:place_roadblock(2)
    local p = _seat_player(g, board, "right")

    _run_handle(g, p, { distance = 12 }, true)

    _assert_eq(_has_cleared_event(events), true,
      "clearing exactly one obstacle must publish an obstacle_cleared event")
  end)

  it("test_empty_reachable_set_uses_default_duration", function()
    local g = _new_game()
    local board = _build_board({ 90 }, { [90] = {} })
    local p = _seat_player(g, board, "right")

    local payload = _run_handle(g, p, { distance = 12 }, true)

    _assert_eq(#payload.branches, 0, "no reachable tiles yields no branches")
    _assert_eq(payload.duration, 1.0,
      "empty branches must fall back to the default action-anim duration")
  end)

  it("test_short_branch_duration_uses_path_timing", function()
    local g = _new_game()
    local board = _build_board({ 100, 101, 102, 103 }, _chain({ 100, 101, 102, 103 }))
    local p = _seat_player(g, board, "right")

    local payload = _run_handle(g, p, { distance = 12 }, true)

    local expected = 3 * (3.0 / runtime_constants.robot_speed)
    luassert.truthy(payload.duration <= 1.0, "a 3-tile branch must compute a duration at or below the 1.0s default, got " .. tostring(payload.duration))
    luassert.truthy(math.abs(payload.duration - expected) < 1e-6, "duration should equal longest_branch * step_time, got " .. tostring(payload.duration))
  end)

  it("test_cfg_distance_limits_branch_length", function()
    local g = _new_game()
    local ids = { 110, 111, 112, 113, 114 }
    local board = _build_board(ids, _chain(ids))
    local p = _seat_player(g, board, "right")

    local payload = _run_handle(g, p, { distance = 2 }, true)

    _assert_eq(#payload.branches, 1, "linear board yields a single branch")
    _assert_eq(#payload.branches[1], 2, "cfg.distance=2 must cap the branch at two tiles")
  end)

  it("test_handle_marks_action_anim_when_queue_accepts", function()
    local g = _new_game()
    local ids = { 200, 201, 202 }
    local board = _build_board(ids, _chain(ids))
    local p = _seat_player(g, board, "right")

    local _, result = _run_handle(g, p, { distance = 12 }, true)

    luassert.truthy(type(result) == "table", "queued handle should return a table result")
    _assert_eq(result.ok, true, "queued handle result must report ok=true")
    _assert_eq(result.action_anim, true, "queued handle result must report action_anim=true")
  end)

  it("test_handle_returns_true_when_queue_declines", function()
    local g = _new_game()
    local ids = { 210, 211, 212 }
    local board = _build_board(ids, _chain(ids))
    local p = _seat_player(g, board, "right")

    local _, result = _run_handle(g, p, { distance = 12 }, false)

    _assert_eq(result, true, "when queue returns falsy, handle must return the bare true value")
  end)

  it("test_first_tile_dead_end_still_records_one_branch", function()
    local g = _new_game()
    local board = _build_board({ 10, 11 }, { [10] = { right = 11 } })
    local p = _seat_player(g, board, "right")

    local payload = _run_handle(g, p, { distance = 12 }, true)

    _assert_eq(#payload.branches, 1, "an immediate dead end must still append exactly one branch")
    _assert_eq(#payload.branches[1], 1, "the branch holds the single reachable tile")
  end)

  it("test_first_tile_only_back_neighbor_records_one_branch", function()
    local g = _new_game()
    local board = _build_board({ 20, 21 }, { [20] = { right = 21 }, [21] = { left = 20 } })
    local p = _seat_player(g, board, "right")

    local payload = _run_handle(g, p, { distance = 12 }, true)

    _assert_eq(#payload.branches, 1, "a back-only first tile must append exactly one branch")
    _assert_eq(#payload.branches[1], 1, "the branch holds the single reachable tile")
  end)

  it("test_mid_walk_dangling_neighbor_records_branch", function()
    local g = _new_game()
    local board = _build_board({ 30, 31, 32 }, {
      [30] = { right = 31 },
      [31] = { left = 30, right = 32 },
      [32] = { left = 31, right = 999 },
    })
    local p = _seat_player(g, board, "right")

    local payload = _run_handle(g, p, { distance = 12 }, true)

    _assert_eq(#payload.branches, 1, "a mid-walk dangling edge must append exactly one branch")
    _assert_eq(#payload.branches[1], 2, "the branch holds the two reachable tiles before the edge")
  end)

  it("test_first_tile_fork_produces_two_independent_branches", function()
    local g = _new_game()
    local board = _build_board({ 40, 41, 42, 43 }, {
      [40] = { right = 41 },
      [41] = { left = 40, up = 42, down = 43 },
      [42] = { down = 41 },
      [43] = { up = 41 },
    })
    local p = _seat_player(g, board, "right")

    local payload = _run_handle(g, p, { distance = 12 }, true)

    _assert_eq(#payload.branches, 2, "a first-tile fork must yield two branches")
    local endpoints = {}
    for _, branch in ipairs(payload.branches) do
      _assert_eq(#branch, 2, "each fork branch must stay length 2 (no shared-path corruption)")
      endpoints[branch[#branch].tile_index] = true
    end
    luassert.truthy(endpoints[3] and endpoints[4], "the two branches must end on distinct fork tiles")
  end)

  it("test_mid_walk_fork_produces_two_independent_branches", function()
    local g = _new_game()
    local board = _build_board({ 50, 51, 52, 53, 54 }, {
      [50] = { right = 51 },
      [51] = { left = 50, right = 52 },
      [52] = { left = 51, up = 53, down = 54 },
      [53] = { down = 52 },
      [54] = { up = 52 },
    })
    local p = _seat_player(g, board, "right")

    local payload = _run_handle(g, p, { distance = 12 }, true)

    _assert_eq(#payload.branches, 2, "a mid-walk fork must yield two branches")
    local endpoints = {}
    for _, branch in ipairs(payload.branches) do
      _assert_eq(#branch, 3, "each fork branch must stay length 3 (no shared-path corruption)")
      endpoints[branch[#branch].tile_index] = true
    end
    luassert.truthy(endpoints[4] and endpoints[5], "the two branches must end on distinct fork tiles")
  end)

  it("test_resolve_initial_dirs_turns_around_via_opposite_when_facing_blocked", function()
    local result = obstacle_clear_tiles.resolve_initial_dirs({ up = 5, down = 6 }, "left")

    luassert.truthy(type(result) == "table", "blocked facing must still return a forward-dir table")
    _assert_eq(#result, 2, "both non-back neighbors must be exposed")
    _assert_eq(result[1], "down", "forward dirs must be sorted ascending")
    _assert_eq(result[2], "up", "forward dirs must be sorted ascending")
  end)
end)
