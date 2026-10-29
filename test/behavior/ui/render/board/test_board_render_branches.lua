-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local function _assert_eq(actual, expected, message) luassert.is.equal(expected, actual, message) end
local _with_patches = support.with_patches
local vec3 = require("test.fixtures.vec3")

local anchors = require("src.ui.render.board.anchors")
local tile_renderer = require("src.ui.render.board.tile")
local building_effects = require("src.ui.render.board.building_effects")
local placement = require("src.ui.render.board.placement")
local placement_snap = require("src.ui.render.board.placement_snap")
local visual_sync = require("src.ui.render.board.visual_sync")
local board_geometry = require("src.config.gameplay.camera_follow")
local overlay_runtime = require("src.ui.render.anim.overlay_runtime")
local tiles_cfg = require("src.config.content.tiles")

if not math.Vector3 then
  function math.Vector3(x, y, z)
    return { x = x, y = y, z = z }
  end
end

local function _vector3_patch()
  return {
    target = math,
    key = "Vector3",
    value = function(x, y, z)
      return vec3.with_sub_length(x, y, z)
    end,
  }
end

local function _capture_render_tile(calls)
  return {
    target = tile_renderer,
    key = "render_tile",
    value = function(unit, tile_id, owner_id, owner_name, level, contiguous_rent)
      calls[#calls + 1] = {
        unit = unit,
        tile_id = tile_id,
        owner_id = owner_id,
        owner_name = owner_name,
        level = level,
        contiguous_rent = contiguous_rent,
      }
    end,
  }
end

local function _scene_with_tile_positions(positions)
  local tiles = {}
  for i, pos in ipairs(positions) do
    tiles[i] = {
      get_position = function()
        return { x = pos.x, y = pos.y, z = pos.z }
      end,
    }
  end
  return { tiles = tiles }
end

local function _land_tile_id()
  for _, cfg in ipairs(tiles_cfg) do
    if cfg.type == "land" then
      return cfg.id
    end
  end
  return 1
end

local function _tile_unit_stub(captured)
  return {
    get_child_by_name = function(name)
      return {
        set_billboard_text = function(text)
          captured[name] = text
        end,
        set_paint_area_color = function(_, color)
          captured[name] = color
        end,
      }
    end,
  }
end

describe("TestBoardRenderBranches", function()

  it("test_ensure_tile_anchors_leaves_tile_spacing_unset_when_neighbouring_tiles_share_a_position", function()
    local state = {}
    local board = {
      tile_states = {},
      tiles = {
        { id = "chance_a", type = "chance" },
        { id = "chance_b", type = "chance" },
      },
    }
    local scene = _scene_with_tile_positions({
      { x = 5, y = 0, z = 5 },
      { x = 5, y = 0, z = 5 },
    })
    local logged = {}

    _with_patches({ _vector3_patch(), _capture_render_tile({}) }, function()
      anchors.ensure_tile_anchors(state, board, scene, 2, function(_, _, key)
        logged[#logged + 1] = key
      end, function()
        return "presentation_board_sync"
      end)
    end)

    _assert_eq(state.tile_spacing, nil,
      "zero distance between every tile pair should leave tile spacing unset")
    _assert_eq(state.tile_positions[2].x, 5, "anchors should still cache tile positions")
    _assert_eq(logged[1], "tiles_ready", "anchors should still emit the ready log")
  end)

  it("test_ensure_tile_anchors_forwards_owner_name_level_and_contiguous_rent_from_tile_state", function()
    local state = {}
    local board = {
      players = {
        { id = "role_1", name = "Ada" },
      },
      tile_states = {
        land_a = { owner_id = "role_1", level = 2, contiguous_rent = 150 },
      },
      tiles = {
        { id = "land_a", type = "land" },
        { id = "chance_b", type = "chance" },
      },
    }
    local scene = _scene_with_tile_positions({
      { x = 0, y = 0, z = 0 },
      { x = 10, y = 0, z = 0 },
    })
    local calls = {}

    _with_patches({ _vector3_patch(), _capture_render_tile(calls) }, function()
      anchors.ensure_tile_anchors(state, board, scene, 2, function() end, function()
        return "presentation_board_sync"
      end)
    end)

    _assert_eq(calls[1].owner_name, "Ada", "owned tile should resolve the owner name from board players")
    _assert_eq(calls[1].level, 2, "owned tile should forward its level")
    _assert_eq(calls[1].contiguous_rent, 150, "owned tile should forward its contiguous rent")
    _assert_eq(calls[2].owner_id, nil, "tile without state should render without an owner")
    _assert_eq(calls[2].level, nil, "tile without state should render without a level")
    _assert_eq(calls[2].contiguous_rent, nil, "tile without state should render without a contiguous rent")
  end)

  it("test_ensure_tile_anchors_asserts_when_a_land_tile_has_no_board_tile_state", function()
    local state = {}
    local board = {
      tile_states = {},
      tiles = {
        { id = "land_a", type = "land" },
      },
    }
    local scene = _scene_with_tile_positions({ { x = 0, y = 0, z = 0 } })
    local ok, err

    _with_patches({ _vector3_patch(), _capture_render_tile({}) }, function()
      ok, err = pcall(anchors.ensure_tile_anchors, state, board, scene, 1, function() end, function()
        return "presentation_board_sync"
      end)
    end)

    _assert_eq(ok, false, "a land tile without board state must assert")
    luassert.truthy(tostring(err):find("missing board tile state", 1, true) ~= nil, "assertion should name the missing board tile state, got: " .. tostring(err))
  end)

  it("test_render_tile_asserts_on_an_unknown_tile_id_and_on_an_unusable_tile_unit", function()
    local captured = {}
    local unknown_ok, unknown_err = pcall(tile_renderer.render_tile, _tile_unit_stub(captured), "no_such_tile")
    _assert_eq(unknown_ok, false, "an unknown tile id must assert")
    luassert.truthy(tostring(unknown_err):find("missing tile cfg", 1, true) ~= nil, "assertion should name the missing tile cfg, got: " .. tostring(unknown_err))

    local unit_ok, unit_err = pcall(tile_renderer.render_tile, {}, _land_tile_id())
    _assert_eq(unit_ok, false, "a unit without get_child_by_name must assert")
    luassert.truthy(tostring(unit_err):find("invalid tile unit", 1, true) ~= nil, "assertion should name the invalid tile unit, got: " .. tostring(unit_err))
  end)

  it("test_clear_building_units_destroys_the_existing_unit_group_and_blanks_the_billboard", function()
    local destroyed = {}
    local billboards = {}
    local scene = {
      building_unit_groups = { [2] = { group = "g2" } },
      building_txt = {
        [2] = {
          set_billboard_text = function(text)
            billboards[#billboards + 1] = text
          end,
        },
      },
    }
    local deps = {
      host_runtime = {
        destroy_unit_with_children = function(unit, with_children)
          destroyed[#destroyed + 1] = { unit = unit, with_children = with_children }
        end,
      },
    }

    local handled = building_effects.clear_building_units(scene, 2, deps)

    _assert_eq(handled, true, "clearing a building should report handled")
    _assert_eq(destroyed[1].unit.group, "g2", "the existing unit group should be destroyed")
    _assert_eq(destroyed[1].with_children, true, "the group should be destroyed with its children")
    _assert_eq(scene.building_unit_groups[2], nil, "the destroyed group slot should be released")
    _assert_eq(billboards[1], "  ", "the building billboard should be blanked")
  end)

  it("test_clear_building_units_stays_a_noop_when_the_slot_holds_neither_a_group_nor_a_billboard", function()
    local destroyed = 0
    local scene = { building_unit_groups = {}, building_txt = {} }
    local deps = {
      host_runtime = {
        destroy_unit_with_children = function()
          destroyed = destroyed + 1
        end,
      },
    }

    local handled = building_effects.clear_building_units(scene, 3, deps)

    _assert_eq(handled, true, "clearing an empty slot should still report handled")
    _assert_eq(destroyed, 0, "an empty slot should not destroy any unit")
  end)

  it("test_build_snapshot_encodes_position_and_elimination_and_drops_keys_from_the_previous_snapshot", function()
    local first = placement.build_snapshot({
      { id = 1, name = "P1", position = 3, eliminated = false },
      { id = 2, name = "P2", position = 7, eliminated = true },
    })

    _assert_eq(first[1], "3:0", "an active player should encode position and a zero elimination flag")
    _assert_eq(first[2], "7:1", "an eliminated player should encode a one elimination flag")

    -- The module double-buffers its snapshot tables; three calls force a buffer
    -- reuse so stale keys from two calls ago must be cleared, not inherited.
    placement.build_snapshot({ { id = 1, name = "P1", position = 4, eliminated = false } })
    local third = placement.build_snapshot({ { id = 1, name = "P1", position = 5, eliminated = false } })

    _assert_eq(third[1], "5:0", "the reused buffer should hold the current player entry")
    _assert_eq(third[2], nil, "the reused buffer should drop players absent from the current roster")
  end)

  -- 角色站位与覆盖物共用同一个地面高度读法:地面坐标只有下标分量时两边都要读得到,
  -- 否则角色与地雷会再次各算各的高度(eb27598 的教训)。
  it("test_min_player_y_and_overlay_height_read_the_same_ground_y", function()
    local overlay_compute = require("src.ui.render.anim.overlay_compute")
    local scene = {
      ground = { get_position = function() return { [1] = 0.0, [2] = 1.5, [3] = 0.0 } end },
      tiles = { [1] = { get_position = function() return { x = 3.0, y = 9.0, z = 4.0 } end } },
    }
    local min_y
    _with_patches({
      { target = board_geometry, key = "player_min_ground_offset", value = 0.5 },
    }, function()
      min_y = placement_snap.resolve_min_player_y(scene)
    end)
    local mine_pos = overlay_compute.overlay_pos_for_tile({ board_scene = scene }, "mine", 1)

    _assert_eq(min_y, 2.0, "player floor should be ground y + configured offset")
    luassert.truthy(math.abs(mine_pos.y - 2.159) < 1e-6, "mine height should come from the same ground y, got " .. tostring(mine_pos.y))
  end)

  it("test_resolve_min_player_y_adds_the_configured_offset_to_the_ground_height", function()
    local scene = {
      ground = {
        get_position = function()
          return { x = 0, y = 2, z = 0 }
        end,
      },
    }
    local configured

    _with_patches({
      { target = board_geometry, key = "player_min_ground_offset", value = 1.25 },
    }, function()
      configured = placement_snap.resolve_min_player_y(scene)
    end)

    _assert_eq(configured, 3.25, "a configured offset should be added to the ground height")
  end)

  it("test_sync_tile_visual_reports_unhandled_when_neither_a_cached_nor_a_scene_tile_unit_exists", function()
    local board = {
      index_of_tile_id = function(_, tile_id)
        return tile_id == 1 and 1 or nil
      end,
      get_tile_by_id = function(_, tile_id)
        return { id = tile_id, type = "land", owner_id = nil, level = 0 }
      end,
    }
    local state = {
      game = { board = board },
      board_scene = {},
    }
    local render_calls = 0

    _with_patches({
      {
        target = tile_renderer,
        key = "render_tile",
        value = function()
          render_calls = render_calls + 1
        end,
      },
    }, function()
      _assert_eq(visual_sync.sync_tile_visual(state, 1), false,
        "a tile with no unit and no building groups should report unhandled")
    end)

    _assert_eq(render_calls, 0, "no tile unit means the renderer must not be called")
  end)

  it("test_sync_tile_visual_skips_contiguous_rent_for_an_ownerless_tile_262", function()
    -- kills _resolve_contiguous_rent 的 or->and:无主地块不许建 rent 表,
    -- 变异体会以 nil owner 调 build_rent_for_owner。
    local contiguous_count = require("src.ui.view.contiguous_count")
    local board = {
      index_of_tile_id = function(_, tile_id)
        return tile_id == 1 and 1 or nil
      end,
      get_tile_by_id = function(_, tile_id)
        return { id = tile_id, type = "land", owner_id = nil, level = 0 }
      end,
    }
    local state = {
      game = { board = board },
      board_scene = {},
      tile_units = { [1] = {} },
    }
    local rent_calls = 0

    _with_patches({
      { target = tile_renderer, key = "render_tile", value = function() end },
      { target = contiguous_count, key = "build_rent_for_owner", value = function()
        rent_calls = rent_calls + 1
        return {}
      end },
    }, function()
      visual_sync.sync_tile_visual(state, 1)
    end)

    _assert_eq(rent_calls, 0, "an ownerless tile must not build a contiguous rent table")
  end)

  it("test_sync_tile_visual_passes_shared_deps_to_clear_building_units_262", function()
    -- kills clear 路径 shared.deps(state) 调用 -> nil。
    local board = {
      index_of_tile_id = function(_, tile_id)
        return tile_id == 1 and 1 or nil
      end,
      get_tile_by_id = function(_, tile_id)
        return { id = tile_id, type = "land", owner_id = nil, level = 0 }
      end,
    }
    local state = {
      game = { board = board },
      board_scene = { buildings = {}, building_unit_groups = {} },
      tile_units = { [1] = {} },
      presentation_runtime = { marker = "deps_marker" },
    }
    local cleared_deps = "unset"

    _with_patches({
      { target = tile_renderer, key = "render_tile", value = function() end },
      { target = building_effects, key = "clear_building_units", value = function(_, _, deps)
        cleared_deps = deps
      end },
    }, function()
      visual_sync.sync_tile_visual(state, 1)
    end)

    _assert_eq(cleared_deps ~= "unset" and cleared_deps and cleared_deps.marker or nil, "deps_marker",
      "clear_building_units must receive the shared deps, not nil")
  end)

  it("test_sync_overlay_visual_spawns_the_roadblock_and_mine_overlays_for_their_own_kinds", function()
    local board = {
      has_roadblock = function()
        return true
      end,
      has_mine = function()
        return true
      end,
    }
    local state = { game = { board = board }, board_scene = { tiles = {}, ground = { get_position = function() return math.Vector3(0.0, 0.0, 0.0) end } } }
    local spawned = {}

    _with_patches({
      {
        target = overlay_runtime,
        key = "spawn_overlay",
        value = function(_, kind, idx)
          spawned[#spawned + 1] = kind .. ":" .. tostring(idx)
        end,
      },
      {
        target = overlay_runtime,
        key = "clear_overlay",
        value = function(_, kind)
          spawned[#spawned + 1] = "cleared:" .. kind
        end,
      },
    }, function()
      _assert_eq(visual_sync.sync_overlay_visual(state, 4), true, "overlay sync should report handled")
    end)

    _assert_eq(spawned[1], "roadblock:4", "a roadblocked tile should spawn the roadblock overlay")
    _assert_eq(spawned[2], "mine:4", "a mined tile should spawn the mine overlay")
  end)

  it("test_sync_overlay_visual_clears_an_overlay_when_the_queued_trigger_anim_targets_another_tile", function()
    local board = {
      has_roadblock = function()
        return false
      end,
      has_mine = function()
        return false
      end,
    }
    local state = {
      game = {
        board = board,
        turn = {
          action_anim = { kind = "mine_trigger", tile_index = 9 },
          action_anim_queue = {
            { kind = "roadblock_trigger", tile_index = 9 },
          },
        },
      },
      board_scene = {},
    }
    local cleared = {}

    _with_patches({
      {
        target = overlay_runtime,
        key = "clear_overlay",
        value = function(_, kind, idx)
          cleared[#cleared + 1] = kind .. ":" .. tostring(idx)
        end,
      },
    }, function()
      visual_sync.sync_overlay_visual(state, 1)
    end)

    _assert_eq(cleared[1], "roadblock:1",
      "a queued trigger for another tile must not hold the roadblock overlay of this tile")
    _assert_eq(cleared[2], "mine:1",
      "a current trigger anim for another tile must not hold the mine overlay of this tile")
  end)

  it("test_sync_overlay_visual_passes_shared_deps_to_clear_overlay_262", function()
    -- kills clear 路径 shared.deps(state) 调用 -> nil。
    local board = {
      has_roadblock = function()
        return false
      end,
      has_mine = function()
        return false
      end,
    }
    local state = {
      game = { board = board },
      board_scene = {},
      presentation_runtime = { marker = "deps_marker" },
    }
    local cleared_deps = {}

    _with_patches({
      {
        target = overlay_runtime,
        key = "clear_overlay",
        value = function(_, kind, _, deps)
          cleared_deps[#cleared_deps + 1] = { kind = kind, deps = deps }
        end,
      },
    }, function()
      visual_sync.sync_overlay_visual(state, 1)
    end)

    _assert_eq(#cleared_deps, 2, "both overlay kinds should be cleared")
    for _, call in ipairs(cleared_deps) do
      _assert_eq(call.deps and call.deps.marker or nil, "deps_marker",
        "clear_overlay for " .. call.kind .. " must receive the shared deps, not nil")
    end
  end)

  it("test_sync_many_reports_unhandled_for_an_empty_payload", function()
    local state = { game = { board = {} }, board_scene = {} }

    _assert_eq(visual_sync.sync_many(state, {}), false, "an empty payload should sync nothing")
    _assert_eq(visual_sync.sync_many(state, nil), false, "a nil payload should sync nothing")
  end)

  -- 变异幸存者补杀：_collect_tile_ids 中 tile ~= nil and tile.id ~= nil 的 and->or
  it("test_collect_tile_ids_asserts_when_tile_has_no_id", function()
    local state = {}
    local board = {
      tile_states = {},
      tiles = {
        { id = "land_a", type = "land" },
        {}, -- 无 id 字段，非 nil 所以 ipairs 不会停
      },
    }
    local scene = _scene_with_tile_positions({
      { x = 0, y = 0, z = 0 },
      { x = 10, y = 0, z = 0 },
    })
    local ok, err

    _with_patches({ _vector3_patch(), _capture_render_tile({}) }, function()
      ok, err = pcall(anchors.ensure_tile_anchors, state, board, scene, 2, function() end, function()
        return "test"
      end)
    end)

    _assert_eq(ok, false, "a tile without id must assert")
    luassert.truthy(tostring(err):find("missing tile id", 1, true) ~= nil, "assertion should name the missing tile id, got: " .. tostring(err))
  end)

  -- 变异幸存者补杀：_assert_vector 中 3 个 and->or 位点
  -- 传入 pos.x=nil 的残缺坐标，原断言失败，变异体短路通过
  it("test_assert_vector_asserts_when_position_coordinate_is_nil", function()
    local state = {}
    local board = {
      tile_states = {},
      tiles = {
        { id = "chance_a", type = "chance" },
        { id = "chance_b", type = "chance" },
      },
    }
    -- 第二个 tile 的 get_position 返回残缺向量（x=nil）
    local scene = {
      tiles = {
        {
          get_position = function() return { x = 0, y = 0, z = 0 } end,
        },
        {
          get_position = function() return { x = nil, y = 5, z = 5 } end,
        },
      },
    }
    local ok, err

    _with_patches({ _vector3_patch(), _capture_render_tile({}) }, function()
      ok, err = pcall(anchors.ensure_tile_anchors, state, board, scene, 2, function() end, function()
        return "test"
      end)
    end)

    _assert_eq(ok, false, "a position with nil coordinate must assert")
    luassert.truthy(tostring(err):find("missing tile position", 1, true) ~= nil, "assertion should name the missing tile position, got: " .. tostring(err))
  end)

  -- 变异幸存者补杀：_tile_gap_distance/_calc_tile_spacing 中 +->-、1->0、-->+、/->* 四个算术位点
  -- 三块地砖非均匀间距，验证 spacing 精确值
  it("test_ensure_tile_anchors_computes_tile_spacing", function()
    local state = {}
    local board = {
      tile_states = {},
      tiles = {
        { id = "chance_a", type = "chance" },
        { id = "chance_b", type = "chance" },
        { id = "chance_c", type = "chance" },
      },
    }
    -- 非均匀坐标：(0,3,0)→(4,7,0)→(14,7,10)
    -- dist(1,2) = √(4²+4²+0²) = √32, dist(2,3) = √(10²+0²+10²) = √200
    -- spacing = ((√32+√200)/2)*0.28 ≈ 2.7718585822512665
    local scene = _scene_with_tile_positions({
      { x = 0, y = 3, z = 0 },
      { x = 4, y = 7, z = 0 },
      { x = 14, y = 7, z = 10 },
    })

    _with_patches({ _vector3_patch(), _capture_render_tile({}) }, function()
      anchors.ensure_tile_anchors(state, board, scene, 3, function() end, function()
        return "test"
      end)
    end)

    local expected = (math.sqrt(32) + math.sqrt(200)) / 2 * 0.28
    _assert_eq(state.tile_spacing, expected,
      "tile spacing should be the average gap scaled by 0.28")
  end)

  -- 变异幸存者补杀：_calc_tile_spacing 中 dist > 0 的 0->1
  -- 地砖间距落在 (0, 1) 区间时应计入 spacing；变异体用 >1 会漏掉
  it("test_ensure_tile_anchors_includes_small_gaps_in_spacing", function()
    local state = {}
    local board = {
      tile_states = {},
      tiles = {
        { id = "chance_a", type = "chance" },
        { id = "chance_b", type = "chance" },
        { id = "chance_c", type = "chance" },
      },
    }
    -- 第二个 tile 与第一个间距 0.4（<1 但 >0），原逻辑计入 spacing
    -- dist(1,2)=0.4, dist(2,3)=9.6, avg=(0.4+9.6)/2=5, spacing=5*0.28=1.4
    local scene = _scene_with_tile_positions({
      { x = 0, y = 0, z = 0 },
      { x = 0.4, y = 0, z = 0 },
      { x = 10, y = 0, z = 0 },
    })

    _with_patches({ _vector3_patch(), _capture_render_tile({}) }, function()
      anchors.ensure_tile_anchors(state, board, scene, 3, function() end, function()
        return "test"
      end)
    end)

    _assert_eq(state.tile_spacing ~= nil, true,
      "small gaps (0 < dist < 1) should produce non-nil spacing")
  end)

  -- L87 dist > 0 的 0->1 补杀:既有 small_gaps 测试里 9.6 的间距让变异体
  -- 仍能算出 spacing;全部间距落在 (0,1] 时变异体(>1)必须漏掉所有间距。
  it("test_ensure_tile_anchors_includes_all_small_gaps_in_spacing", function()
    local state = {}
    local board = {
      tile_states = {},
      tiles = {
        { id = "chance_a", type = "chance" },
        { id = "chance_b", type = "chance" },
        { id = "chance_c", type = "chance" },
      },
    }
    -- 全部相邻间距 0.4 与 0.4,均落在 (0,1] 区间
    local scene = _scene_with_tile_positions({
      { x = 0, y = 0, z = 0 },
      { x = 0.4, y = 0, z = 0 },
      { x = 0.8, y = 0, z = 0 },
    })

    _with_patches({ _vector3_patch(), _capture_render_tile({}) }, function()
      anchors.ensure_tile_anchors(state, board, scene, 3, function() end, function()
        return "test"
      end)
    end)

    _assert_eq(state.tile_spacing ~= nil, true,
      "every gap inside (0, 1] should still produce spacing")
  end)

  -- L103/L104 消息换 nil:缺 scene.tiles 表 / tiles 数量不足必须钉死报错。
  it("test_ensure_tile_anchors_asserts_on_missing_or_insufficient_tiles", function()
    local state = {}
    local board = {
      tile_states = {},
      tiles = {},
    }

    luassert.has_error(function()
      anchors.ensure_tile_anchors(state, board, { tiles = nil }, 1, function() end, function()
        return "test"
      end)
    end, "missing board_scene.tiles")

    luassert.has_error(function()
      anchors.ensure_tile_anchors(state, board, { tiles = {} }, 1, function() end, function()
        return "test"
      end)
    end, "insufficient board_scene.tiles")
  end)

  -- L36 contiguous_rent > 0 的 >->=:零连片租金必须回落按级租金,不能显示 0。
  it("test_render_tile_with_zero_contiguous_rent_falls_back_to_level_rent", function()
    local captured = {}
    local unit = _tile_unit_stub(captured)
    tile_renderer.render_tile(unit, _land_tile_id(), "role_1", "Ada", 1, 0)
    _assert_eq(captured["price"] ~= "Ada", true,
      "zero contiguous rent should still show the level rent")
  end)

  -- L65 set_paint_area_color 的 1->0:拥有者颜色必须涂在槽位 1。
  it("test_render_tile_paints_color_on_slot_one", function()
    local slot_index = nil
    local unit = {
      get_child_by_name = function(name)
        if name == "color" then
          return {
            set_paint_area_color = function(index)
              slot_index = index
            end,
          }
        end
        return {
          set_billboard_text = function() end,
        }
      end,
    }
    tile_renderer.render_tile(unit, _land_tile_id(), "role_1", "Ada", 0, nil)
    _assert_eq(slot_index, 1, "owner color should paint on slot one")
  end)

  -- L23/L32/L58/L68 消息参数换 nil:land 节点缺失时消息拼接会 concat 报错,
  -- 必须钉死 "missing <node> node" 消息。
  it("test_render_tile_asserts_on_missing_land_nodes", function()
    local land_id = _land_tile_id()

    local name_missing = {
      get_child_by_name = function()
        return nil
      end,
    }
    luassert.has_error(function()
      tile_renderer.render_tile(name_missing, land_id, nil, nil, 0, nil)
    end, "missing name node")

    local price_missing = {
      get_child_by_name = function(name)
        if name == "name" then
          return { set_billboard_text = function() end }
        end
        return {}
      end,
    }
    luassert.has_error(function()
      tile_renderer.render_tile(price_missing, land_id, nil, nil, 0, nil)
    end, "missing price node")

    local color_missing = {
      get_child_by_name = function(name)
        if name == "name" or name == "price" then
          return { set_billboard_text = function() end }
        end
        return nil
      end,
    }
    luassert.has_error(function()
      tile_renderer.render_tile(color_missing, land_id, "role_1", nil, 0, nil)
    end, "missing color node")
  end)


  it("test_sync_overlay_visual_real_spawn_path_reaches_host_runtime", function()
    -- 不 patch spawn_overlay:真实路径的 _assert_overlay_slot(scene 非 nil)与
    -- assert(pos 非 nil)必须在测试中存活,否则 spawn 侧位点(spawn_overlay 的
    -- scene/unit_id/pos/deps 实参)全部不可观测——spy 替换只杀得到调用个数。
    -- roadblock 与 mine 均走 unit 路径:Data.Prefab.group 无"地雷"条目,
    -- group_id 恒为 nil(该位点等价,见 TSV);roadblock scale 为 4x。
    local prefab = require("Data.Prefab")
    local calls = {}
    local host_runtime = {
      create_unit_with_scale = function(unit_id, pos, q, scale)
        calls[#calls + 1] = { "unit", unit_id, pos, scale }
        return "unit_handle"
      end,
      create_unit_group = function(group_id, pos, q)
        calls[#calls + 1] = { "group", group_id, pos }
        return "group_handle"
      end,
      destroy_unit_with_children = function() end,
      destroy_unit = function() end,
    }
    local board = {
      has_roadblock = function()
        return true
      end,
      has_mine = function()
        return true
      end,
    }
    local state = {
      game = { board = board },
      board_scene = { tiles = {}, ground = { get_position = function() return math.Vector3(0.0, 0.0, 0.0) end } },
      presentation_runtime = { host_runtime = host_runtime },
    }

    local ok = visual_sync.sync_overlay_visual(state, 4)
    _assert_eq(ok, true, "real spawn path should report handled")
    _assert_eq(#calls, 2, "both overlays should reach the host runtime")
    _assert_eq(calls[1][1], "unit", "roadblock overlay should spawn a unit, not a group")
    _assert_eq(calls[1][2], prefab.unit["路障"], "roadblock unit id should come from the prefab unit table")
    _assert_eq(calls[1][4] and calls[1][4].x or nil, 4.0, "roadblock scale should stay 4x")
    _assert_eq(calls[2][1], "unit", "mine overlay should also spawn a unit (prefab.group has no 地雷)")
    _assert_eq(calls[2][2], prefab.unit["地雷A"], "mine unit id should come from the prefab unit table")
    -- 地雷高度从地面起算:地面 y=0 时 pos.y 即地雷离地高度(#339 普通格标定折算)。
    _assert_eq(calls[2][3] and calls[2][3].y or nil, 0.659, "mine spawn should sit at the calibrated height above ground")
  end)


end)
