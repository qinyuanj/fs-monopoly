-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
---@diagnostic disable: need-check-nil, different-requires, undefined-field

local action_anim = require("src.ui.render.anim")
local host_runtime = require("src.host")
local ui_host_runtime = require("src.ui.seams.host_runtime")
local overlay_compute = require("src.ui.render.anim.overlay_compute")
local visual_sync = require("src.ui.render.board.visual_sync")
local overlay_runtime = require("src.ui.render.anim.overlay_runtime")
local logger = require("src.foundation.log")
local tip_queue = require("src.foundation.tips")
local runtime_context = require("src.host.context")
local unit_overlay = require("src.ui.render.anim.unit_overlay")
local support = require("test.support.ui_action_anim_support")

local _with_patches = support.with_patches

local function _assert_eq(actual, expected, message)
  luassert.truthy(actual == expected, (message or "assertion failed")
    .. " expected=" .. tostring(expected)
    .. " actual=" .. tostring(actual))
end

local function _reload_with(module_name, overrides, fn)
  local original_module = package.loaded[module_name]
  local originals = {}
  for key, value in pairs(overrides or {}) do
    originals[key] = package.loaded[key]
    package.loaded[key] = value
  end
  package.loaded[module_name] = nil

  local ok, result = pcall(function()
    return fn(require(module_name))
  end)

  package.loaded[module_name] = original_module
  for key, value in pairs(originals) do
    package.loaded[key] = value
  end
  if not ok then
    error(result)
  end
  return result
end

local function _drain_scheduled(queue, limit)
  local max_count = limit or math.huge
  local executed = 0
  while #queue > 0 and executed < max_count do
    local entry = table.remove(queue, 1)
    executed = executed + 1
    entry.callback()
  end
  return executed
end

local function _new_robot_handle(pos, records)
  local handle = {
    pos = pos,
    moves = {},
  }
  handle.set_position_smooth = function(next_pos)
    handle.pos = next_pos
    handle.moves[#handle.moves + 1] = next_pos
    records.moves[#records.moves + 1] = next_pos
  end
  handle.set_position = function(next_pos)
    handle.pos = next_pos
    handle.moves[#handle.moves + 1] = next_pos
    records.moves[#records.moves + 1] = next_pos
  end
  return handle
end

local function _new_non_table_robot_handle(_pos, records)
  local handle = coroutine.create(function() end)
  local original_mt = debug.getmetatable(handle)
  debug.setmetatable(handle, {
    __index = {
      set_position_smooth = function(next_pos)
        records.moves[#records.moves + 1] = next_pos
      end,
      set_position = function(next_pos)
        records.fallback_moves[#records.fallback_moves + 1] = next_pos
      end,
    },
  })
  return handle, original_mt
end

if not math.Vector3 then
  function math.Vector3(x, y, z)
    return { x = x, y = y, z = z }
  end
end

local function _with_overlay_patches(patches, fn)
  local function _refresh_runtime_ctx()
    local lua_api = {}
    if type(LuaAPI) == "table" then
      for key, value in pairs(LuaAPI) do
        lua_api[key] = value
      end
    end
    if type(SetTimeOut) == "function" then
      lua_api.call_delay_time = function(delay, cb)
        return SetTimeOut(delay, cb)
      end
    elseif type(lua_api.call_delay_time) ~= "function" then
      lua_api.call_delay_time = function(_, cb)
        if cb then
          cb()
          return true
        end
        return false
      end
    end
    runtime_context.set_current(runtime_context.new({
      GameAPI = GameAPI,
      LuaAPI = lua_api,
    }))
    tip_queue.configure_runtime({
      presenter = function(text, duration)
        if GlobalAPI and type(GlobalAPI.show_tips) == "function" then
          return GlobalAPI.show_tips(text, duration)
        end
        return false
      end,
      scheduler = function(delay, cb)
        return lua_api.call_delay_time(delay, cb)
      end,
      test_mode = logger.is_test_mode(),
    })
  end

  local originals = {}
  for i, patch in ipairs(patches) do
    local target = patch.target or _G
    originals[i] = { target = target, key = patch.key, value = target[patch.key] }
    target[patch.key] = patch.value
  end
  _refresh_runtime_ctx()
  local ok, err = xpcall(fn, debug.traceback)
  for i = #originals, 1, -1 do
    local patch = originals[i]
    patch.target[patch.key] = patch.value
  end
  _refresh_runtime_ctx()
  if not ok then
    error(err)
  end
end

local function _build_overlay_state()
  return {
    ui = {},
    board_scene = {
      ground = {
        get_position = function()
          return math.Vector3(0.0, 0.0, 0.0)
        end,
      },
      tiles = {
        [1] = {
          get_position = function()
            return math.Vector3(0.0, 0.0, 0.0)
          end,
        },
      },
      buildings = {
        [1] = {
          get_position = function()
            return math.Vector3(10.0, 0.0, 0.0)
          end,
        },
      },
    },
    game = {
      board = {
        get_tile = function()
          return { name = "测试地块" }
        end,
      },
      find_player_by_id = function()
        return { position = 1, name = "测试玩家" }
      end,
    },
  }
end

local function _make_host_unit(x, y, z)
  if type(newproxy) == "function" then
    local unit = newproxy(true)
    getmetatable(unit).__index = {
      get_position = function()
        return math.Vector3(x, y, z)
      end,
    }
    return unit
  end
  return {
    get_position = function()
      return math.Vector3(x, y, z)
    end,
  }
end

describe("TestActionAnimOverlayUnits", function()

  -- 真机实测(2026-10-29):地面单位 y=1.457,普通格锚点 y=0.116,起点等特殊格锚点 y=1.59,
  -- 角色在两种格子上都站在 1.747(地板是平的)。#339 在普通格标定的世界高度:
  -- 地雷/清障机器人 0.116+2.0=2.116,路障/导弹 0.116+1.0=1.116。覆盖物在特殊格上
  -- 必须与普通格同高,否则地雷会飘到角色头顶。
  local function _build_board_with_special_tile()
    local state = _build_overlay_state()
    state.board_scene.ground = _make_host_unit(0.0, 1.457, 0.0)
    state.board_scene.tiles[1] = _make_host_unit(3.0, 0.116, 4.0)
    state.board_scene.tiles[2] = _make_host_unit(8.0, 1.59, 9.0)
    return state
  end

  local function _assert_near(actual, expected, message)
    luassert.truthy(actual ~= nil and math.abs(actual - expected) < 1e-6,
      message .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
  end

  local function _capture_spawn_positions(state, fn)
    local positions = {}
    _with_overlay_patches({
      {
        target = overlay_runtime,
        key = "spawn_overlay",
        value = function(_scene, kind, tile_index, _group_id, _unit_id, pos)
          positions[kind .. ":" .. tostring(tile_index)] = pos
          return true
        end,
      },
      {
        target = overlay_runtime,
        key = "spawn_transient",
        value = function(_group_id, _unit_id, pos)
          positions.transient = pos
        end,
      },
    }, function()
      fn(state)
    end)
    return positions
  end

  it("test_mine_on_special_tile_sits_at_the_same_ground_height_as_on_a_normal_tile", function()
    local state = _build_board_with_special_tile()
    local positions = _capture_spawn_positions(state, function(s)
      unit_overlay.play_overlay(s, { kind = "mine", tile_index = 1 }, 0.2, {})
      unit_overlay.play_overlay(s, { kind = "mine", tile_index = 2 }, 0.2, {})
    end)

    _assert_near(positions["mine:1"].y, 2.116, "mine on a normal tile keeps the #339 calibrated height")
    _assert_near(positions["mine:2"].y, 2.116, "mine on a special tile must not ride the higher tile anchor")
    _assert_near(positions["mine:2"].x, 8.0, "mine keeps the tile x")
    _assert_near(positions["mine:2"].z, 9.0, "mine keeps the tile z")
  end)

  it("test_visual_sync_mine_on_special_tile_matches_the_placement_height", function()
    local state = _build_board_with_special_tile()
    state.game.board = {
      has_roadblock = function() return false end,
      has_mine = function() return true end,
    }
    local positions = _capture_spawn_positions(state, function(s)
      visual_sync.sync_overlay_visual(s, 2)
    end)

    _assert_near(positions["mine:2"].y, 2.116, "sync-spawned mine must match the placement height on a special tile")
  end)

  it("test_roadblock_and_missile_on_special_tile_sit_at_the_normal_tile_height", function()
    local state = _build_board_with_special_tile()
    state.game.board = {
      has_roadblock = function() return true end,
      has_mine = function() return false end,
    }
    local positions = _capture_spawn_positions(state, function(s)
      unit_overlay.play_overlay(s, { kind = "roadblock", tile_index = 1 }, 0.2, {})
      visual_sync.sync_overlay_visual(s, 2)
      unit_overlay.play_missile(s, { tile_index = 2 }, 0.2, { clear_overlay = function() end })
    end)

    _assert_near(positions["roadblock:1"].y, 1.116, "roadblock on a normal tile keeps the default height")
    _assert_near(positions["roadblock:2"].y, 1.116, "roadblock on a special tile must not ride the tile anchor")
    _assert_near(positions.transient.y, 1.116, "missile on a special tile must not ride the tile anchor")
  end)

  it("test_clear_obstacle_robot_on_special_tiles_flies_at_the_normal_tile_height", function()
    local prefab = require("Data.Prefab")
    local state = _build_board_with_special_tile()
    state.game.find_player_by_id = function()
      return { position = 2, name = "测试玩家" }
    end
    local records = { moves = {} }
    local spawned = {}
    local scheduled = {}

    _with_overlay_patches({
      { target = prefab.unit, key = "清障机器人", value = 4242 },
      {
        target = host_runtime,
        key = "create_unit_with_scale",
        value = function(_unit_id, pos)
          spawned[#spawned + 1] = pos
          return _new_robot_handle(pos, records)
        end,
      },
      { target = host_runtime, key = "destroy_unit", value = function() end },
    }, function()
      unit_overlay.play_clear_obstacles(state, {
        player_id = 1,
        branches = { { { tile_index = 1, has_obstacle = false } } },
      }, 1.0, {
        clear_overlay = function() end,
        schedule = function(delay, callback)
          scheduled[#scheduled + 1] = { delay = delay, callback = callback }
        end,
      })
      _drain_scheduled(scheduled)
    end)

    _assert_near(spawned[1].y, 2.116, "robot starting on a special tile must not ride the tile anchor")
    _assert_near(records.moves[1].y, 2.116, "robot stepping onto a normal tile keeps the calibrated height")
  end)

  it("test_action_anim_roadblock_overlay_uses_4x_scale", function()
    local state = support.build_min_state()
    local unit_calls = 0
    local group_calls = 0
    local captured_scale = nil
    local unit_handle = { _unit_id = 1 }

    state.presentation_runtime = {
      host_runtime = {
        create_unit_with_scale = function(_, _, _, scale)
          unit_calls = unit_calls + 1
          captured_scale = scale
          return unit_handle
        end,
        create_unit_group = function()
          group_calls = group_calls + 1
          return { _group_id = 1 }
        end,
      },
    }
    action_anim.play(state, { kind = "roadblock", tile_index = 1, duration = 0.2 })

    local entry = state.board_scene.overlay_units.roadblocks[1]
    luassert.truthy(entry ~= nil and entry.handle == unit_handle, "roadblock should publish the spawned unit in overlay state")
    -- lint-allow: call-count 注入的 host_runtime.create_unit_with_scale 是 GameAPI 创建封装边界,一次=引擎创建一个路障单位
    luassert.truthy(unit_calls == 1, "roadblock should spawn via unit path")
    -- lint-allow: call-count 注入的 host_runtime.create_unit_group 是 GameAPI 创建封装边界,零调用=引擎未建单位组
    luassert.truthy(group_calls == 0, "roadblock should not spawn via group path")
    luassert.truthy(captured_scale ~= nil, "roadblock should pass explicit scale")
    luassert.truthy(captured_scale.x == 4.0 and captured_scale.y == 4.0 and captured_scale.z == 4.0, "roadblock should use 4x scale")
  end)

  it("test_anim_unit_overlay_play_overlay_mine_spawns_via_runtime_with_ground_offset", function()
    local overlay = require("src.ui.render.anim.unit_overlay")
    local prefab = require("Data.Prefab")
    local state = support.build_min_state()
    local spawn_calls = {}
    local original_group = prefab.group["地雷A"]
    prefab.group["地雷A"] = 7777

    _with_patches({
      {
        target = overlay_runtime,
        key = "spawn_overlay",
        value = function(_scene, kind, tile_index, group_id, _unit_id, pos)
          spawn_calls[#spawn_calls + 1] = {
            kind = kind,
            tile_index = tile_index,
            group_id = group_id,
            pos = pos,
          }
        end,
      },
    }, function()
      overlay.play_overlay(state, { kind = "mine", tile_index = 1 }, 0.2, {})
    end)

    prefab.group["地雷A"] = original_group

    _assert_eq(#spawn_calls, 1, "mine overlay should spawn exactly once")
    _assert_eq(spawn_calls[1].kind, "mine", "mine overlay should pass the mine kind")
    _assert_eq(spawn_calls[1].tile_index, 1, "mine overlay should target the requested tile")
    _assert_eq(spawn_calls[1].group_id, 7777, "mine overlay should pass the resolved group id")
    luassert.truthy(spawn_calls[1].pos ~= nil, "mine overlay should pass a resolved ground position")
  end)

  it("test_anim_unit_overlay_play_overlay_mine_warns_and_skips_when_prefab_missing", function()
    local overlay = require("src.ui.render.anim.unit_overlay")
    local prefab = require("Data.Prefab")
    local state = support.build_min_state()
    local warns = 0

    _with_patches({
      { target = prefab.group, key = "地雷A", value = nil },
      { target = prefab.unit, key = "地雷A", value = nil },
      {
        target = logger,
        key = "warn",
        value = function()
          warns = warns + 1
        end,
      },
    }, function()
      overlay.play_overlay(state, { kind = "mine", tile_index = 1 }, 0.2, {})
    end)

    luassert.truthy(state.board_scene.overlay_units == nil, "missing mine prefab should leave overlay state without a generated mine")
    -- lint-allow: call-count logger.warn 即诊断输出,条数是被测行为的一部分
    luassert.truthy(warns == 1, "missing mine prefab should warn exactly once")
  end)

  it("test_action_anim_robot_overlay_uses_robot_scale_not_v3_one", function()
    local overlay = require("src.ui.render.anim.unit_overlay")
    local state = support.build_min_state({
      mutate = function(target)
        target.board_scene.tiles[2] = {
          get_position = function()
            return math.Vector3(10.0, 0.0, 0.0)
          end,
        }
        target.board_scene.tiles[3] = {
          get_position = function()
            return math.Vector3(20.0, 0.0, 0.0)
          end,
        }
        target.board_scene.tiles[4] = {
          get_position = function()
            return math.Vector3(20.0, 10.0, 0.0)
          end,
        }
      end,
    })
    local captured_scales = {}
    local scheduled_callbacks = {}

    local function _mock_create(_, pos, _, scale)
      captured_scales[#captured_scales + 1] = scale
      local records = { spawn_pos = pos, moves = {} }
      return _new_robot_handle(pos, records)
    end
    _with_patches({
      {
        target = host_runtime,
        key = "create_unit_with_scale",
        value = _mock_create,
      },
      {
        target = host_runtime,
        key = "acquire_unit",
        value = _mock_create,
      },
      {
        target = ui_host_runtime,
        key = "schedule",
        value = function(delay, callback)
          scheduled_callbacks[#scheduled_callbacks + 1] = {
            delay = delay,
            callback = callback,
          }
        end,
      },
      {
        target = host_runtime,
        key = "destroy_unit",
        value = function() end,
      },
      {
        target = host_runtime,
        key = "release_unit",
        value = function() end,
      },
      {
        target = host_runtime,
        key = "prewarm_unit",
        value = function() end,
      },
    }, function()
      overlay.play_clear_obstacles(state, {
        branches = {
          {
            { tile_index = 2, has_obstacle = false },
            { tile_index = 3, has_obstacle = true },
          },
          {
            { tile_index = 2, has_obstacle = false },
            { tile_index = 4, has_obstacle = true },
          },
        },
        player_id = 1,
        duration = 0.4,
      }, 0.4, {
        clear_overlay = function() end,
      })
      _drain_scheduled(scheduled_callbacks)
    end)

    luassert.truthy(#captured_scales >= 2, "root and fork robot should both be spawned via create_unit_with_scale")
    for i, scale in ipairs(captured_scales) do
      luassert.truthy(not (scale.x == 1.0 and scale.y == 1.0 and scale.z == 1.0), "robot scale must not be v3_one (1,1,1) — regression guard for spawn #" .. i)
      luassert.truthy(scale.x == 0.06 and scale.y == 0.94 and scale.z == 0.06, "robot scale must match robot_scale constant (0.06,0.94,0.06) for spawn #" .. i)
    end
  end)

  it("test_anim_unit_overlay_clear_obstacles_warns_and_skips_when_robot_prefab_missing", function()
    local overlay = require("src.ui.render.anim.unit_overlay")
    local prefab = require("Data.Prefab")
    local state = support.build_min_state()
    local create_calls = 0
    local warns = 0
    state.presentation_runtime = {
      host_runtime = {
        create_unit_with_scale = function()
          create_calls = create_calls + 1
          return { id = "robot" }
        end,
        destroy_unit = function() end,
        schedule = function() end,
      },
    }

    _with_patches({
      { target = prefab.unit, key = "清障机器人", value = nil },
      {
        target = logger,
        key = "warn",
        value = function()
          warns = warns + 1
        end,
      },
    }, function()
      overlay.play_clear_obstacles(state, {
        player_id = 1,
        branches = {},
      }, 0.1, {
        clear_overlay = function() end,
      })
    end)

    -- lint-allow: call-count 注入的 host_runtime.create_unit_with_scale 是 GameAPI 创建封装边界,零调用=引擎未生成机器人
    luassert.truthy(create_calls == 0, "missing robot prefab should skip spawning")
    -- lint-allow: call-count logger.warn 即诊断输出,条数是被测行为的一部分
    luassert.truthy(warns == 1, "missing robot prefab should warn exactly once")
  end)

  it("test_anim_unit_overlay_clear_obstacles_moves_non_table_host_robot_without_respawn", function()
    local overlay = require("src.ui.render.anim.unit_overlay")
    local state = support.build_min_state({
      mutate = function(target)
        target.board_scene.tiles[2] = {
          get_position = function()
            return math.Vector3(10.0, 0.0, 0.0)
          end,
        }
      end,
    })
    local create_calls = {}
    local destroy_calls = {}
    local scheduled_callbacks = {}
    local robot_records = { moves = {}, fallback_moves = {} }
    local handle, original_mt = _new_non_table_robot_handle(math.Vector3(0.0, 1.0, 0.0), robot_records)

    _with_patches({
      {
        target = host_runtime,
        key = "create_unit_with_scale",
        value = function(unit_id, pos)
          create_calls[#create_calls + 1] = {
            unit_id = unit_id,
            pos = pos,
          }
          return handle
        end,
      },
      {
        target = host_runtime,
        key = "destroy_unit",
        value = function(destroyed_handle)
          destroy_calls[#destroy_calls + 1] = destroyed_handle
        end,
      },
      {
        target = ui_host_runtime,
        key = "schedule",
        value = function(delay, callback)
          scheduled_callbacks[#scheduled_callbacks + 1] = {
            delay = delay,
            callback = callback,
          }
        end,
      },
    }, function()
      overlay.play_clear_obstacles(state, {
        branches = {
          {
            { tile_index = 2, has_obstacle = false },
          },
        },
        player_id = 1,
        duration = 0.3,
      }, 0.3, {
        clear_overlay = function() end,
      })
      _drain_scheduled(scheduled_callbacks)
    end)
    debug.setmetatable(handle, original_mt)

    luassert.truthy(#create_calls == 1, "non-table robot handle should move in place without respawn")
    luassert.truthy(#destroy_calls == 1, "non-table robot handle should be destroyed only after finishing the path")
    luassert.truthy(destroy_calls[1] == handle, "destroy should receive the moved host handle")
    luassert.truthy(#robot_records.moves == 1, "non-table robot handle should use set_position_smooth")
    luassert.truthy(#robot_records.fallback_moves == 0, "set_position fallback should not run after smooth move succeeds")
    luassert.truthy(robot_records.moves[1].x == 10.0 and robot_records.moves[1].y == 0.659 and robot_records.moves[1].z == 0.0, "non-table robot handle should move to the target tile overlay position")
  end)

  it("test_anim_unit_overlay_clear_obstacles_walks_per_step_then_clears_and_destroys", function()
    local overlay = require("src.ui.render.anim.unit_overlay")
    local state = support.build_min_state({
      mutate = function(target)
        target.board_scene.tiles[2] = {
          get_position = function()
            return math.Vector3(10.0, 0.0, 0.0)
          end,
        }
        target.board_scene.tiles[3] = {
          get_position = function()
            return math.Vector3(20.0, 0.0, 0.0)
          end,
        }
        target.board_scene.tiles[4] = {
          get_position = function()
            return math.Vector3(30.0, 0.0, 0.0)
          end,
        }
      end,
    })
    local cleared_calls = {}
    local unit_calls = {}
    local scheduled_callbacks = {}
    local destroyed_handles = {}
    local robot_records = {}

    local function _mock_robot_create(unit_id, pos)
      local records = { spawn_pos = pos, moves = {} }
      local handle = _new_robot_handle(pos, records)
      robot_records[#robot_records + 1] = records
      unit_calls[#unit_calls + 1] = {
        unit_id = unit_id,
        pos = pos,
        handle = handle,
      }
      return handle
    end
    local function _mock_robot_destroy(handle)
      destroyed_handles[#destroyed_handles + 1] = handle
    end
    _with_patches({
      {
        target = host_runtime,
        key = "create_unit_with_scale",
        value = _mock_robot_create,
      },
      {
        target = host_runtime,
        key = "acquire_unit",
        value = _mock_robot_create,
      },
      {
        target = ui_host_runtime,
        key = "schedule",
        value = function(delay, callback)
          scheduled_callbacks[#scheduled_callbacks + 1] = {
            delay = delay,
            callback = callback,
          }
        end,
      },
      {
        target = host_runtime,
        key = "destroy_unit",
        value = _mock_robot_destroy,
      },
      {
        target = host_runtime,
        key = "release_unit",
        value = function(_, handle)
          _mock_robot_destroy(handle)
        end,
      },
      {
        target = host_runtime,
        key = "prewarm_unit",
        value = function() end,
      },
    }, function()
      overlay.play_clear_obstacles(state, {
        branches = {
          {
            { tile_index = 2, has_obstacle = true },
            { tile_index = 3, has_obstacle = false },
            { tile_index = 4, has_obstacle = true },
          },
        },
        player_id = 1,
        duration = 0.6,
      }, 0.6, {
        clear_overlay = function(_, kind, tile_index)
          cleared_calls[#cleared_calls + 1] = kind .. ":" .. tostring(tile_index)
        end,
      })
      luassert.truthy(#unit_calls == 1, "single branch should create exactly one robot")
      luassert.truthy(unit_calls[1].pos.x == 0.0 and unit_calls[1].pos.y == 0.659 and unit_calls[1].pos.z == 0.0, "clear_obstacles robot unit should spawn above the acting player tile")
      luassert.truthy(#scheduled_callbacks == 1 and math.abs(scheduled_callbacks[1].delay - 0.2) < 0.0001, "single branch should schedule the first move using duration / path_len")
      luassert.truthy(#cleared_calls == 0, "single branch should not clear overlays before the first arrival")

      _drain_scheduled(scheduled_callbacks)
    end)

    luassert.truthy(#cleared_calls == 4, "single branch should clear roadblock and mine only on obstacle tiles after arrival")
    luassert.truthy(cleared_calls[1] == "roadblock:2", "clear_obstacles should clear roadblock for tile 2 (has_obstacle=true)")
    luassert.truthy(cleared_calls[2] == "mine:2", "clear_obstacles should clear mine for tile 2")
    luassert.truthy(cleared_calls[3] == "roadblock:4", "clear_obstacles should clear roadblock for tile 4 (has_obstacle=true)")
    luassert.truthy(cleared_calls[4] == "mine:4", "clear_obstacles should clear mine for tile 4")
    luassert.truthy(#destroyed_handles == 1, "single branch robot should be destroyed after finishing the path")
    luassert.truthy(#robot_records[1].moves == 3, "single branch robot should move once per tile in the branch")
  end)

  it("test_anim_unit_overlay_clear_obstacles_splits_at_fork_and_destroys_all_robots", function()
    local overlay = require("src.ui.render.anim.unit_overlay")
    local state = support.build_min_state({
      mutate = function(target)
        target.board_scene.tiles[2] = {
          get_position = function()
            return math.Vector3(10.0, 0.0, 0.0)
          end,
        }
        target.board_scene.tiles[3] = {
          get_position = function()
            return math.Vector3(20.0, 0.0, 0.0)
          end,
        }
        target.board_scene.tiles[4] = {
          get_position = function()
            return math.Vector3(20.0, 10.0, 0.0)
          end,
        }
        target.board_scene.tiles[5] = {
          get_position = function()
            return math.Vector3(30.0, 0.0, 0.0)
          end,
        }
        target.board_scene.tiles[6] = {
          get_position = function()
            return math.Vector3(30.0, 10.0, 0.0)
          end,
        }
      end,
    })
    local cleared_calls = {}
    local unit_calls = {}
    local scheduled_callbacks = {}
    local destroyed_handles = {}
    local robot_records = {}

    local function _mock_fork_create(unit_id, pos)
      local records = { spawn_pos = pos, moves = {} }
      local handle = _new_robot_handle(pos, records)
      robot_records[#robot_records + 1] = records
      unit_calls[#unit_calls + 1] = {
        unit_id = unit_id,
        pos = pos,
        handle = handle,
      }
      return handle
    end
    local function _mock_fork_destroy(handle)
      destroyed_handles[#destroyed_handles + 1] = handle
    end
    _with_patches({
      {
        target = host_runtime,
        key = "create_unit_with_scale",
        value = _mock_fork_create,
      },
      {
        target = host_runtime,
        key = "acquire_unit",
        value = _mock_fork_create,
      },
      {
        target = ui_host_runtime,
        key = "schedule",
        value = function(delay, callback)
          scheduled_callbacks[#scheduled_callbacks + 1] = {
            delay = delay,
            callback = callback,
          }
        end,
      },
      {
        target = host_runtime,
        key = "destroy_unit",
        value = _mock_fork_destroy,
      },
      {
        target = host_runtime,
        key = "release_unit",
        value = function(_, handle)
          _mock_fork_destroy(handle)
        end,
      },
      {
        target = host_runtime,
        key = "prewarm_unit",
        value = function() end,
      },
    }, function()
      overlay.play_clear_obstacles(state, {
        branches = {
          {
            { tile_index = 2, has_obstacle = false },
            { tile_index = 3, has_obstacle = true },
            { tile_index = 5, has_obstacle = false },
          },
          {
            { tile_index = 2, has_obstacle = false },
            { tile_index = 4, has_obstacle = true },
            { tile_index = 6, has_obstacle = false },
          },
        },
        player_id = 1,
        duration = 0.6,
      }, 0.6, {
        clear_overlay = function(_, kind, tile_index)
          cleared_calls[#cleared_calls + 1] = kind .. ":" .. tostring(tile_index)
        end,
      })
      luassert.truthy(#unit_calls == 1, "merged branches should start with one robot before the fork")
      luassert.truthy(#scheduled_callbacks == 1 and math.abs(scheduled_callbacks[1].delay - 0.2) < 0.0001, "first step should be scheduled with duration / longest_branch_len")
      luassert.truthy(#cleared_calls == 0, "overlays should not clear before robot reaches obstacle tiles")

      _drain_scheduled(scheduled_callbacks, 1)

      luassert.truthy(#unit_calls == 2, "robot should split only after reaching the fork tile")
      luassert.truthy(unit_calls[2].pos.x == 10.0 and unit_calls[2].pos.y == 0.659 and unit_calls[2].pos.z == 0.0, "forked robot should spawn at the fork position instead of the player start")

      _drain_scheduled(scheduled_callbacks)
    end)

    luassert.truthy(#cleared_calls == 4, "forked branches should clear only obstacle tiles across both branches")
    luassert.truthy(cleared_calls[1] == "roadblock:3", "first branch should clear roadblock on tile 3 after the split")
    luassert.truthy(cleared_calls[2] == "mine:3", "first branch should clear mine on tile 3 after the split")
    luassert.truthy(cleared_calls[3] == "roadblock:4", "second branch should clear roadblock on tile 4 after the split")
    luassert.truthy(cleared_calls[4] == "mine:4", "second branch should clear mine on tile 4 after the split")
    luassert.truthy(#destroyed_handles == 2, "every spawned robot should be destroyed after reaching its leaf")
    luassert.truthy(#robot_records[1].moves == 3, "primary robot should walk fork -> branch -> leaf")
    luassert.truthy(#robot_records[2].moves == 2, "forked robot should continue from split point to its leaf")
  end)

  it("test_anim_unit_overlay_play_missile_clears_overlays_and_spawns_transient", function()
    local overlay = require("src.ui.render.anim.unit_overlay")
    local prefab = require("Data.Prefab")
    local state = support.build_min_state()
    local cleared_calls = {}
    local transient_calls = {}

    state.presentation_runtime = {
      host_runtime = {
        create_unit_group = function(group_id, pos)
          transient_calls[#transient_calls + 1] = {
            group_id = group_id,
            pos = pos,
          }
          return { _group_id = group_id }
        end,
        create_unit = function(unit_id, pos)
          transient_calls[#transient_calls + 1] = {
            unit_id = unit_id,
            pos = pos,
          }
          return { _unit_id = unit_id }
        end,
        schedule = function() end,
      },
    }

    local original_group = prefab.group["导弹"]
    prefab.group["导弹"] = 9999

    _with_patches({
      {
        target = host_runtime,
        key = "create_unit_group",
        value = function(group_id, pos)
          transient_calls[#transient_calls + 1] = {
            group_id = group_id,
            pos = pos,
          }
          return { _group_id = group_id }
        end,
      },
      {
        target = host_runtime,
        key = "create_unit",
        value = function(unit_id, pos)
          transient_calls[#transient_calls + 1] = {
            unit_id = unit_id,
            pos = pos,
          }
          return { _unit_id = unit_id }
        end,
      },
    }, function()
      overlay.play_missile(state, {
        tile_index = 1,
      }, 0.5, {
        clear_overlay = function(_, kind, tile_index)
          cleared_calls[#cleared_calls + 1] = kind .. ":" .. tostring(tile_index)
        end,
      })
    end)

    prefab.group["导弹"] = original_group

    luassert.truthy(#cleared_calls == 2, "play_missile should clear roadblock and mine")
    luassert.truthy(cleared_calls[1] == "roadblock:1", "play_missile should clear roadblock first")
    luassert.truthy(cleared_calls[2] == "mine:1", "play_missile should clear mine second")
    luassert.truthy(#transient_calls >= 1, "play_missile should spawn at least one transient")
  end)

  it("test_anim_units_play_missile_stops_and_snaps_targets_before_followup", function()
    local units = require("src.ui.render.anim.units")
    local calls = {}
    local state = support.build_min_state({
      mutate = function(target)
        target.board_scene.units_by_player_id = {
          [2] = {
            get_position = function()
              return math.Vector3(0.0, 0.0, 0.0)
            end,
          },
        }
        target.board_scene.tiles[3] = {
          get_position = function()
            return math.Vector3(30.0, 0.0, 0.0)
          end,
        }
      end,
    })

    _with_patches({
      {
        target = require("src.ui.render.move_anim"),
        key = "prepare_player_for_snap",
        value = function(_, player_id, _anim, reason)
          calls[#calls + 1] = "prepare:" .. tostring(player_id) .. ":" .. tostring(reason)
        end,
      },
      {
        target = require("src.ui.render.move_anim"),
        key = "snap_player_to_index",
        value = function(_, player_id, to_index, _anim, reason)
          calls[#calls + 1] = "snap:" .. tostring(player_id) .. ":" .. tostring(to_index) .. ":" .. tostring(reason)
          return 0
        end,
      },
      {
        target = require("src.ui.render.anim.unit_overlay"),
        key = "play_missile",
        value = function()
          calls[#calls + 1] = "overlay"
        end,
      },
    }, function()
      units.play_missile(state, {
        tile_index = 1,
        target_player_ids = { 2 },
        to_index = 3,
      }, 0.5, {
        clear_overlay = function() end,
      })
    end)

    luassert.truthy(calls[1] == "prepare:2:missile", "missile should stop targets before overlay playback")
    luassert.truthy(calls[2] == "overlay", "missile should play strike overlay after stop phase")
    luassert.truthy(calls[3] == "snap:2:3:play_sequence_missile_target", "missile should snap targets after strike overlay starts")
  end)

  it("test_overlay_compute_reads_host_unit_position_without_table_guard", function()
    local state = _build_overlay_state()
    state.board_scene.tiles[1] = _make_host_unit(5.0, 6.0, 7.0)

    local pos = overlay_compute.overlay_pos_for_tile(state, "roadblock", 1)
    luassert.truthy(pos.x == 5.0, "overlay compute should preserve host unit x")
    luassert.truthy(pos.y == -0.341, "overlay height should come from the ground, not the tile anchor y")
    luassert.truthy(pos.z == 7.0, "overlay compute should preserve host unit z")
  end)

  it("test_visual_sync_overlay_uses_host_unit_position", function()
    local state = _build_overlay_state()
    state.board_scene.tiles[1] = _make_host_unit(12.0, 3.0, 4.0)
    state.game.board = {
      has_roadblock = function()
        return false
      end,
      has_mine = function()
        return true
      end,
    }
    local spawn_calls = {}

    _with_overlay_patches({
      {
        target = overlay_runtime,
        key = "spawn_overlay",
        value = function(scene, kind, tile_index, group_id, unit_id, pos)
          spawn_calls[#spawn_calls + 1] = {
            kind = kind,
            tile_index = tile_index,
            pos = pos,
          }
          return true
        end,
      },
    }, function()
      local handled = visual_sync.sync_overlay_visual(state, 1)
      luassert.truthy(handled == true, "visual sync should handle mine overlay")
    end)

    luassert.truthy(#spawn_calls == 1, "visual sync should spawn one mine overlay")
    luassert.truthy(spawn_calls[1].kind == "mine", "visual sync should spawn mine overlay")
    luassert.truthy(spawn_calls[1].pos.x == 12.0, "visual sync should pass host unit x")
    -- 地雷高度从地面(y=0)起算,与 tile 锚点 y=3.0 无关。
    luassert.truthy(spawn_calls[1].pos.y == 0.659, "visual sync should place the mine at the calibrated height above ground")
    luassert.truthy(spawn_calls[1].pos.z == 4.0, "visual sync should pass host unit z")
  end)

  it("test_overlay_runtime_spawn_overlay_preserves_group_and_unit_destroy_paths", function()
    local scene = {}
    local calls = {
      create_group = 0,
      destroy_group = 0,
      acquire_unit = 0,
      release_unit = 0,
    }
    local group_handle = { id = "group" }
    local unit_handle = { id = "unit" }

    _with_overlay_patches({
      {
        target = host_runtime,
        key = "create_unit_group",
        value = function()
          calls.create_group = calls.create_group + 1
          return group_handle
        end,
      },
      {
        target = host_runtime,
        key = "destroy_unit_with_children",
        value = function(handle)
          luassert.truthy(handle == group_handle, "group overlay should destroy with children")
          calls.destroy_group = calls.destroy_group + 1
        end,
      },
      {
        target = host_runtime,
        key = "acquire_unit",
        value = function()
          calls.acquire_unit = calls.acquire_unit + 1
          return unit_handle
        end,
      },
      {
        target = host_runtime,
        key = "release_unit",
        value = function(unit_id, handle)
          luassert.truthy(unit_id == 3002, "unit overlay should release with original unit id")
          luassert.truthy(handle == unit_handle, "unit overlay should release pooled handle")
          calls.release_unit = calls.release_unit + 1
        end,
      },
    }, function()
      local group_ok = overlay_runtime.spawn_overlay(scene, "roadblock", 1, 2001, nil, math.Vector3(1, 2, 3), nil, {
        host_runtime = host_runtime,
      })
      local unit_ok = overlay_runtime.spawn_overlay(scene, "roadblock", 1, nil, 3002, math.Vector3(1, 2, 3), nil, {
        host_runtime = host_runtime,
      })
      overlay_runtime.clear_overlay(scene, "roadblock", 1, {
        host_runtime = host_runtime,
      })

      luassert.truthy(group_ok == true, "group overlay should spawn")
      luassert.truthy(unit_ok == true, "unit overlay should replace group")
    end)

    luassert.truthy(calls.create_group == 1, "group overlay should create one group")
    luassert.truthy(calls.destroy_group == 1, "replacing group overlay should use group destroy path")
    luassert.truthy(calls.acquire_unit == 1, "unit overlay should acquire one pooled unit")
    luassert.truthy(calls.release_unit == 1, "clearing unit overlay should use pooled release path")
  end)

  it("test_overlay_runtime_spawn_transient_schedules_destroy_for_groups", function()
    local calls = {
      create_group = 0,
      destroy = 0,
      scheduled = 0,
    }

    _with_overlay_patches({
      {
        target = host_runtime,
        key = "create_unit_group",
        value = function(group_id, pos)
          calls.create_group = calls.create_group + 1
          return { id = group_id, pos = pos }
        end,
      },
      {
        target = host_runtime,
        key = "destroy_unit_with_children",
        value = function()
          calls.destroy = calls.destroy + 1
        end,
      },
      {
        target = host_runtime,
        key = "schedule",
        value = function(delay, fn)
          calls.scheduled = delay
          fn()
        end,
      },
    }, function()
      overlay_runtime.spawn_transient(2001, nil, math.Vector3(1, 2, 3), 0.5, {
        host_runtime = host_runtime,
      })
    end)

    luassert.truthy(calls.create_group == 1, "spawn_transient should create one transient group")
    luassert.truthy(calls.scheduled == 0.5, "spawn_transient should schedule delayed cleanup")
    luassert.truthy(calls.destroy == 1, "spawn_transient should destroy transient group after delay")
  end)

  it("test_anim_unit_overlay_play_overlay_roadblock_passes_resolved_unit_id", function()
    local overlay = require("src.ui.render.anim.unit_overlay")
    local prefab = require("Data.Prefab")
    local state = support.build_min_state()
    local captured = {}
    local original_unit = prefab.unit["路障"]
    prefab.unit["路障"] = 4242

    _with_patches({
      {
        target = overlay_runtime,
        key = "spawn_overlay",
        value = function(_scene, kind, _tile_index, _group_id, unit_id)
          captured[#captured + 1] = { kind = kind, unit_id = unit_id }
        end,
      },
    }, function()
      overlay.play_overlay(state, { kind = "roadblock", tile_index = 1 }, 0.2, {})
    end)

    prefab.unit["路障"] = original_unit

    luassert.truthy(#captured == 1, "roadblock overlay should spawn exactly once")
    luassert.truthy(captured[1].unit_id == 4242, "roadblock overlay should pass the resolved 路障 unit id, not the prefab.unit table")
  end)

  it("test_anim_unit_overlay_play_overlay_mine_passes_resolved_unit_id", function()
    local overlay = require("src.ui.render.anim.unit_overlay")
    local prefab = require("Data.Prefab")
    local state = support.build_min_state()
    local captured = {}
    local original_group = prefab.group["地雷A"]
    local original_unit = prefab.unit["地雷A"]
    prefab.group["地雷A"] = 7777
    prefab.unit["地雷A"] = 5151

    _with_patches({
      {
        target = overlay_runtime,
        key = "spawn_overlay",
        value = function(_scene, kind, _tile_index, _group_id, unit_id)
          captured[#captured + 1] = { kind = kind, unit_id = unit_id }
        end,
      },
    }, function()
      overlay.play_overlay(state, { kind = "mine", tile_index = 1 }, 0.2, {})
    end)

    prefab.group["地雷A"] = original_group
    prefab.unit["地雷A"] = original_unit

    luassert.truthy(#captured == 1, "mine overlay should spawn exactly once")
    luassert.truthy(captured[1].unit_id == 5151, "mine overlay should pass the resolved 地雷 unit id")
  end)

  it("test_anim_unit_overlay_play_missile_passes_resolved_unit_id", function()
    local overlay = require("src.ui.render.anim.unit_overlay")
    local prefab = require("Data.Prefab")
    local state = support.build_min_state()
    local captured = {}
    local original_unit = prefab.unit["导弹"]
    prefab.unit["导弹"] = 6363

    _with_patches({
      {
        target = overlay_runtime,
        key = "spawn_transient",
        value = function(_group_id, unit_id)
          captured[#captured + 1] = unit_id
        end,
      },
    }, function()
      overlay.play_missile(state, { tile_index = 1 }, 0.5, {
        clear_overlay = function() end,
      })
    end)

    prefab.unit["导弹"] = original_unit

    luassert.truthy(#captured == 1, "play_missile should spawn exactly one transient")
    luassert.truthy(captured[1] == 6363, "play_missile should pass the resolved 导弹 unit id, not the prefab.unit table")
  end)

  it("test_anim_unit_overlay_resolve_presentation_runtime_returns_runtime_not_state", function()
    local robot = require("src.ui.render.anim.unit_overlay_robot")
    local runtime_marker = { id = "presentation_runtime" }
    local state = { presentation_runtime = runtime_marker }
    luassert.truthy(robot.resolve_presentation_runtime(state) == runtime_marker, "should resolve the presentation_runtime value, not the state table")
    luassert.truthy(robot.resolve_presentation_runtime(nil) == nil, "nil state should resolve to a nil runtime")
    luassert.truthy(robot.resolve_presentation_runtime({}) == nil, "state without presentation_runtime should resolve to nil")
  end)

  it("test_anim_unit_overlay_clear_obstacles_uses_speed_fallback_when_duration_non_positive", function()
    local overlay = require("src.ui.render.anim.unit_overlay")
    local runtime_constants = require("src.config.gameplay.runtime_constants")
    local state = support.build_min_state({
      mutate = function(target)
        target.board_scene.tiles[2] = {
          get_position = function()
            return math.Vector3(10.0, 0.0, 0.0)
          end,
        }
      end,
    })
    local scheduled_callbacks = {}
    local function _mock_create(_, pos)
      return _new_robot_handle(pos, { moves = {} })
    end
    _with_patches({
      { target = host_runtime, key = "create_unit_with_scale", value = _mock_create },
      { target = host_runtime, key = "acquire_unit", value = _mock_create },
      {
        target = ui_host_runtime,
        key = "schedule",
        value = function(delay, callback)
          scheduled_callbacks[#scheduled_callbacks + 1] = { delay = delay, callback = callback }
        end,
      },
      { target = host_runtime, key = "destroy_unit", value = function() end },
      { target = host_runtime, key = "release_unit", value = function() end },
      { target = host_runtime, key = "prewarm_unit", value = function() end },
    }, function()
      overlay.play_clear_obstacles(state, {
        branches = { { { tile_index = 2, has_obstacle = false } } },
        player_id = 1,
        duration = 0,
      }, 0, { clear_overlay = function() end })
    end)

    luassert.truthy(#scheduled_callbacks == 1, "single-step branch should schedule exactly one move")
    local expected = 3.0 / runtime_constants.robot_speed
    luassert.truthy(math.abs(scheduled_callbacks[1].delay - expected) < 1e-6, "non-positive duration should fall back to 3.0 / robot_speed step timing")
  end)

  it("test_anim_unit_overlay_clear_obstacles_divides_duration_by_path_length_for_single_step", function()
    local overlay = require("src.ui.render.anim.unit_overlay")
    local state = support.build_min_state({
      mutate = function(target)
        target.board_scene.tiles[2] = {
          get_position = function()
            return math.Vector3(10.0, 0.0, 0.0)
          end,
        }
      end,
    })
    local scheduled_callbacks = {}
    local function _mock_create(_, pos)
      return _new_robot_handle(pos, { moves = {} })
    end
    _with_patches({
      { target = host_runtime, key = "create_unit_with_scale", value = _mock_create },
      { target = host_runtime, key = "acquire_unit", value = _mock_create },
      {
        target = ui_host_runtime,
        key = "schedule",
        value = function(delay, callback)
          scheduled_callbacks[#scheduled_callbacks + 1] = { delay = delay, callback = callback }
        end,
      },
      { target = host_runtime, key = "destroy_unit", value = function() end },
      { target = host_runtime, key = "release_unit", value = function() end },
      { target = host_runtime, key = "prewarm_unit", value = function() end },
    }, function()
      overlay.play_clear_obstacles(state, {
        branches = { { { tile_index = 2, has_obstacle = false } } },
        player_id = 1,
        duration = 0.4,
      }, 0.4, { clear_overlay = function() end })
    end)

    luassert.truthy(#scheduled_callbacks == 1, "single-step branch should schedule exactly one move")
    luassert.truthy(math.abs(scheduled_callbacks[1].delay - 0.4) < 1e-6, "positive duration should divide by the single-step path length (0.4 / 1)")
  end)

  it("test_anim_unit_overlay_clear_obstacles_spawns_with_robot_rotation_and_scale", function()
    -- #339:不走池化,prewarm 已删——rotation/scale 改由 spawn 直接传给 create_unit_with_scale。
    local overlay = require("src.ui.render.anim.unit_overlay")
    local state = support.build_min_state({
      mutate = function(target)
        target.board_scene.tiles[2] = {
          get_position = function()
            return math.Vector3(10.0, 0.0, 0.0)
          end,
        }
      end,
    })
    local create_calls = {}
    local scheduled_callbacks = {}
    _with_patches({
      {
        target = host_runtime,
        key = "create_unit_with_scale",
        value = function(robot_id, pos, rotation, scale)
          create_calls[#create_calls + 1] = {
            robot_id = robot_id,
            pos = pos,
            rotation = rotation,
            scale = scale,
          }
          return _new_robot_handle(pos, { moves = {} })
        end,
      },
      {
        target = ui_host_runtime,
        key = "schedule",
        value = function(delay, callback)
          scheduled_callbacks[#scheduled_callbacks + 1] = { delay = delay, callback = callback }
        end,
      },
      { target = host_runtime, key = "destroy_unit", value = function() end },
    }, function()
      overlay.play_clear_obstacles(state, {
        branches = { { { tile_index = 2, has_obstacle = false } } },
        player_id = 1,
        duration = 0.4,
      }, 0.4, { clear_overlay = function() end })
    end)

    luassert.truthy(#create_calls == 1, "single-branch clear should spawn the robot exactly once")
    luassert.truthy(create_calls[1].rotation ~= nil, "spawn should pass the robot rotation")
    luassert.truthy(create_calls[1].scale ~= nil, "spawn should pass the robot scale")
    luassert.truthy(create_calls[1].scale.x == 0.06 and create_calls[1].scale.y == 0.94
      and create_calls[1].scale.z == 0.06, "spawn should pass the robot_scale constant (0.06, 0.94, 0.06)")
  end)

  it("test_anim_unit_overlay_clear_obstacles_marks_shared_tile_obstacle_from_later_branch", function()
    local overlay = require("src.ui.render.anim.unit_overlay")
    local state = support.build_min_state({
      mutate = function(target)
        target.board_scene.tiles[2] = {
          get_position = function()
            return math.Vector3(10.0, 0.0, 0.0)
          end,
        }
        target.board_scene.tiles[3] = {
          get_position = function()
            return math.Vector3(20.0, 0.0, 0.0)
          end,
        }
        target.board_scene.tiles[4] = {
          get_position = function()
            return math.Vector3(20.0, 10.0, 0.0)
          end,
        }
      end,
    })
    local cleared_calls = {}
    local scheduled_callbacks = {}
    local function _mock_create(_, pos)
      return _new_robot_handle(pos, { moves = {} })
    end
    _with_patches({
      { target = host_runtime, key = "create_unit_with_scale", value = _mock_create },
      { target = host_runtime, key = "acquire_unit", value = _mock_create },
      {
        target = ui_host_runtime,
        key = "schedule",
        value = function(delay, callback)
          scheduled_callbacks[#scheduled_callbacks + 1] = { delay = delay, callback = callback }
        end,
      },
      { target = host_runtime, key = "destroy_unit", value = function() end },
      { target = host_runtime, key = "release_unit", value = function() end },
      { target = host_runtime, key = "prewarm_unit", value = function() end },
    }, function()
      overlay.play_clear_obstacles(state, {
        branches = {
          {
            { tile_index = 2, has_obstacle = false },
            { tile_index = 3, has_obstacle = false },
          },
          {
            { tile_index = 2, has_obstacle = true },
            { tile_index = 4, has_obstacle = false },
          },
        },
        player_id = 1,
        duration = 0.6,
      }, 0.6, {
        clear_overlay = function(_, kind, tile_index)
          cleared_calls[#cleared_calls + 1] = kind .. ":" .. tostring(tile_index)
        end,
      })
      _drain_scheduled(scheduled_callbacks)
    end)

    local saw_roadblock_2 = false
    for _, entry in ipairs(cleared_calls) do
      if entry == "roadblock:2" then
        saw_roadblock_2 = true
      end
    end
    luassert.truthy(saw_roadblock_2, "a shared tile flagged as an obstacle in a later branch should still be cleared on arrival")
  end)

  it("test_zero_timing_config_is_preserved_when_the_anim_module_loads", function()
    local fake_registry = {
      register = function() end,
      resolve = function(kind)
        if kind == "roll" then
          return nil
        end
        return nil
      end,
    }

    _reload_with("src.ui.render.anim", {
      ["src.config.gameplay.timing"] = {
        action_anim_default_seconds = 1.0,
        demolish_effect_start_delay_seconds = 0,
        dice_spin_seconds = 1.0,
        dice_face_hold_seconds = 1.0,
      },
      ["src.ui.render.anim.registry"] = fake_registry,
    }, function(reloaded_action_anim)
      local duration = reloaded_action_anim.play(support.build_min_state(), {
        kind = "missile",
      }, {
        runtime_bundle = {
          runtime = {},
          ui_events = { show = {}, hide = {}, send_to_all = function() end },
          host_runtime = {
            enqueue_tip = function() end,
            schedule = function() error("zero start delay should not schedule") end,
          },
        },
      })

      _assert_eq(duration, 1.2, "zero demolish start delay should not fall back to 0.2")
    end)
  end)

  it("test_zero_roll_timing_is_preserved_in_the_registered_roll_handler", function()
    local registered = {}
    local fake_registry = {
      register = function(kind, handler)
        registered[kind] = handler
      end,
      resolve = function(kind)
        return registered[kind]
      end,
    }
    local captured_spin = nil
    local captured_hold = nil

    _reload_with("src.ui.render.anim", {
      ["src.config.gameplay.timing"] = {
        action_anim_default_seconds = 1.0,
        demolish_effect_start_delay_seconds = 0.2,
        dice_spin_seconds = 0,
        dice_face_hold_seconds = 0,
      },
      ["src.ui.render.anim.registry"] = fake_registry,
    }, function(reloaded_action_anim)
      _with_patches({
        { target = require("src.ui.render.anim.handlers"), key = "play_roll_dice_screen", value = function(_, _, spin, hold)
          captured_spin = spin
          captured_hold = hold
        end },
      }, function()
        local duration = reloaded_action_anim.play(support.build_min_state(), {
          kind = "roll",
        }, {
          runtime_bundle = {
            runtime = {},
            ui_events = { show = {}, hide = {}, send_to_all = function() end },
            host_runtime = {},
          },
        })

        _assert_eq(duration, 0, "zero roll timings should make roll handler return zero duration")
      end)
    end)

    _assert_eq(captured_spin, 0, "zero dice spin should not fall back to 1.0")
    _assert_eq(captured_hold, 0, "zero dice hold should not fall back to 1.0")
  end)

  it("test_default_bundle_and_an_unknown_kind_still_resolve_a_duration", function()
    local state = support.build_min_state()
    local duration = action_anim.play(state, {
      kind = "unknown_kind",
      duration = -1,
    })

    _assert_eq(duration, 1.0, "invalid duration should fall back to default action duration")
  end)

  it("test_unit_overlay_clear_overlay_delegates_to_runtime_with_board_scene_deps", function()
    local state = support.build_min_state()
    local calls = {}

    _with_patches({
      { target = overlay_runtime, key = "clear_overlay", value = function(board_scene, kind, tile_index, deps)
        calls[#calls + 1] = {
          board_scene = board_scene,
          kind = kind,
          tile_index = tile_index,
          deps = deps,
        }
      end },
    }, function()
      unit_overlay.clear_overlay(state, "mine", 1)
    end)

    _assert_eq(#calls, 1, "clear_overlay should call runtime once")
    _assert_eq(calls[1].board_scene, state.board_scene, "clear_overlay should pass board scene")
    _assert_eq(calls[1].kind, "mine", "clear_overlay should pass kind")
    _assert_eq(calls[1].tile_index, 1, "clear_overlay should pass tile index")
  end)

  it("test_overlay_destroy_falls_back_to_host_destroy_methods", function()
    local state = support.build_min_state()
    local destroy_unit_calls = 0
    local destroy_children_calls = 0

    _with_patches({
      { target = ui_host_runtime, key = "create_unit_with_scale", value = function()
        return { id = "robot" }
      end },
      { target = ui_host_runtime, key = "destroy_unit", value = function()
        destroy_unit_calls = destroy_unit_calls + 1
      end },
      { target = ui_host_runtime, key = "destroy_unit_with_children", value = function()
        destroy_children_calls = destroy_children_calls + 1
      end },
    }, function()
      unit_overlay.play_clear_obstacles(state, {
        player_id = 1,
        branches = {},
      }, 0.1, {
        clear_overlay = function() end,
      })
    end)

    _assert_eq(destroy_unit_calls, 1, "destroy_unit should be the first fallback")
    _assert_eq(destroy_children_calls, 0, "destroy_unit_with_children should not run after destroy_unit")

    _with_patches({
      { target = ui_host_runtime, key = "create_unit_with_scale", value = function()
        return { id = "robot" }
      end },
      { target = ui_host_runtime, key = "destroy_unit", value = nil },
      { target = ui_host_runtime, key = "destroy_unit_with_children", value = function(_, include_children)
        destroy_children_calls = destroy_children_calls + 1
        _assert_eq(include_children, true, "children fallback should request recursive destroy")
      end },
    }, function()
      unit_overlay.play_clear_obstacles(state, {
        player_id = 1,
        branches = {},
      }, 0.1, {
        clear_overlay = function() end,
      })
    end)

    _assert_eq(destroy_children_calls, 1, "destroy_unit_with_children should run when other fallbacks are missing")
  end)

  it("test_overlay_compute_resolves_tile_building_and_zero_vector_positions", function()
    local state = {
      board_scene = {
        tiles = {
          [1] = { get_position = function() return math.Vector3(1.0, 2.0, 3.0) end },
          [2] = {},
          [3] = nil,
        },
        buildings = {
          [2] = { get_position = function() return math.Vector3(4.0, 5.0, 6.0) end },
        },
      },
    }

    local tile_pos = overlay_compute.resolve_tile_pos(state, 1)
    _assert_eq(tile_pos.x, 1.0, "tile position should be read from tiles")

    local building_pos = overlay_compute.resolve_tile_pos(state, 2)
    _assert_eq(building_pos.x, 4.0, "building position should be used as fallback")

    local zero_pos = overlay_compute.resolve_tile_pos(state, 3)
    _assert_eq(zero_pos.x, 0.0, "missing tile/building should fall back to zero vector")
  end)

  it("test_overlay_compute_reads_position_from_indexed_components", function()
    -- L13 兜底取 index 分量 + L61(1->0):无 x/y/z 字段时按 [1]/[2]/[3] 取分量。
    local state = {
      board_scene = {
        ground = { get_position = function() return { [1] = 0.0, [2] = 1.5, [3] = 0.0 } end },
        tiles = {
          [1] = {
            get_position = function()
              return { [1] = 5.0, [2] = 6.0, [3] = 7.0 }
            end,
          },
        },
      },
    }
    local pos = overlay_compute.overlay_pos_for_tile(state, "mine", 1)
    _assert_eq(pos.x, 5.0, "index 1 component should backfill x")
    _assert_near(pos.y, 2.159, "index 2 component should backfill the ground y")
    _assert_eq(pos.z, 7.0, "index 3 component should backfill z")
  end)

  it("test_overlay_compute_defaults_missing_components_to_zero", function()
    -- L61(0->1)/L62/L63:缺分量必须兜底 0,不能变 1。
    local state = {
      board_scene = {
        ground = { get_position = function() return math.Vector3(0.0, 1.0, 0.0) end },
        tiles = {
          [1] = {
            get_position = function()
              return {}
            end,
          },
        },
      },
    }
    local pos = overlay_compute.overlay_pos_for_tile(state, "roadblock", 1)
    _assert_eq(pos.x, 0.0, "missing x must default to zero")
    _assert_near(pos.y, 0.659, "height must still come from the ground when the tile has no components")
    _assert_eq(pos.z, 0.0, "missing z must default to zero")
  end)

  it("test_overlay_compute_resolves_player_position_from_game", function()
    -- L109 resolve_tile_pos(state, player.position) 换 nil:玩家 overlay 必须落在其格子。
    local state = {
      board_scene = {
        ground = { get_position = function() return math.Vector3(0.0, 1.0, 0.0) end },
        tiles = {
          [5] = {
            get_position = function()
              return math.Vector3(20.0, 30.0, 40.0)
            end,
          },
        },
      },
      game = {
        find_player_by_id = function(_, _id)
          return { position = 5 }
        end,
      },
    }
    local pos = overlay_compute.overlay_pos_for_player(state, "robot", 7)
    _assert_eq(pos.x, 20.0, "player overlay x must come from the player tile")
    _assert_near(pos.y, 1.659, "player overlay y must come from the ground, not the tile anchor")
    _assert_eq(pos.z, 40.0, "player overlay z must come from the player tile")
  end)

  it("test_overlay_pos_fails_loudly_without_ground_or_with_unknown_kind", function()
    local state = { board_scene = { tiles = { [1] = _make_host_unit(1.0, 2.0, 3.0) } } }
    local ok, err = pcall(overlay_compute.overlay_pos_for_tile, state, "mine", 1)
    _assert_eq(ok, false, "missing ground must not silently fall back to the tile anchor")
    luassert.truthy(tostring(err):find("missing board_scene.ground", 1, true), "assert message should name the ground")

    state.board_scene.ground = _make_host_unit(0.0, 0.0, 0.0)
    ok, err = pcall(overlay_compute.overlay_pos_for_tile, state, "bogus", 1)
    _assert_eq(ok, false, "unknown overlay kind must assert")
    luassert.truthy(tostring(err):find("unknown overlay kind: bogus", 1, true), "assert message should name the kind")
  end)

  it("test_resolve_tile_pos_asserts_on_missing_state_or_index", function()
    local ok, err = pcall(function() overlay_compute.resolve_tile_pos(nil, 1) end)
    _assert_eq(ok, false, "missing state should assert")
    luassert.truthy(tostring(err):find("missing state", 1, true), "assert message should mention state")

    ok, err = pcall(function() overlay_compute.resolve_tile_pos({}, nil) end)
    _assert_eq(ok, false, "missing tile_index should assert")
    luassert.truthy(tostring(err):find("missing tile_index", 1, true), "assert message should mention tile_index")
  end)

  it("test_spawns_one_robot_per_additional_branch_child_plus_the_root", function()
    -- #339:不走池化,prewarm 已删——改为直接断言 spawn 数:根机器人 + 每个额外分支子节点一个。
    -- 两条分支指向不同 tile,分支树有两个子节点:根机器人复用走第一个,第二个子节点另 spawn 一个。
    local overlay = require("src.ui.render.anim.unit_overlay")
    local state = support.build_min_state({
      mutate = function(target)
        target.board_scene.tiles[2] = {
          get_position = function()
            return math.Vector3(10.0, 0.0, 0.0)
          end,
        }
        target.board_scene.tiles[3] = {
          get_position = function()
            return math.Vector3(20.0, 0.0, 0.0)
          end,
        }
      end,
    })
    local create_count = 0

    _with_patches({
      { target = host_runtime, key = "create_unit_with_scale", value = function(_, pos)
        create_count = create_count + 1
        return _new_robot_handle(pos, { moves = {} })
      end },
      { target = host_runtime, key = "destroy_unit", value = function() end },
      { target = ui_host_runtime, key = "schedule", value = function() end },
    }, function()
      overlay.play_clear_obstacles(state, {
        branches = {
          { { tile_index = 2, has_obstacle = false } },
          { { tile_index = 3, has_obstacle = false } },
        },
        player_id = 1,
      }, 0.4, {
        clear_overlay = function() end,
      })
    end)

    _assert_eq(create_count, 2, "two distinct branch children need the root plus one extra robot")
  end)

  it("test_divides_the_duration_by_the_longest_branch_not_the_branch_count", function()
    -- kills -#branches 种子的删负号变异:3 条单格分支的步长必须是
    -- duration/1,变异体算成 duration/3。
    local overlay = require("src.ui.render.anim.unit_overlay")
    local state = support.build_min_state({
      mutate = function(target)
        target.board_scene.tiles[2] = {
          get_position = function()
            return math.Vector3(10.0, 0.0, 0.0)
          end,
        }
      end,
    })
    local scheduled = {}

    _with_patches({
      { target = host_runtime, key = "acquire_unit", value = function(_, pos)
        return _new_robot_handle(pos, { moves = {} })
      end },
      { target = host_runtime, key = "destroy_unit", value = function() end },
      { target = host_runtime, key = "release_unit", value = function() end },
      { target = host_runtime, key = "prewarm_unit", value = function() end },
      { target = ui_host_runtime, key = "schedule", value = function(delay, callback)
        scheduled[#scheduled + 1] = { delay = delay, callback = callback }
      end },
    }, function()
      overlay.play_clear_obstacles(state, {
        branches = {
          { { tile_index = 2, has_obstacle = false } },
          { { tile_index = 2, has_obstacle = false } },
          { { tile_index = 2, has_obstacle = false } },
        },
        player_id = 1,
      }, 0.9, {
        clear_overlay = function() end,
      })
    end)

    -- 三分支同格在分支树里合并成一个子节点,只排一步。
    _assert_eq(#scheduled, 1, "shared single-step branches should schedule one step")
    _assert_eq(scheduled[1].delay, 0.9, "step duration must be duration/longest(=1), not duration/#branches")
  end)

  it("test_warns_with_the_exact_payload_when_the_robot_prefab_is_missing", function()
    -- kills logger.warn 的 "[Eggy]" 与 "清障机器人 prefab 缺失，已跳过生成" -> nil。
    local overlay = require("src.ui.render.anim.unit_overlay")
    local prefab = require("Data.Prefab")
    local state = support.build_min_state()
    local warns = {}
    local original_robot = prefab.unit["清障机器人"]
    prefab.unit["清障机器人"] = nil

    _with_patches({
      { target = logger, key = "warn", value = function(...)
        warns[#warns + 1] = { ... }
      end },
    }, function()
      overlay.play_clear_obstacles(state, {
        player_id = 1,
        branches = {},
      }, 0.1, {
        clear_overlay = function() end,
      })
    end)

    prefab.unit["清障机器人"] = original_robot

    _assert_eq(#warns, 1, "missing robot prefab should warn exactly once")
    _assert_eq(warns[1][1], "[Eggy]", "warn should carry the Eggy prefix")
    _assert_eq(warns[1][2], "清障机器人 prefab 缺失，已跳过生成", "warn should carry the skip reason")
    _assert_eq(#warns[1], 2, "warn should have exactly two args")
  end)

  it("test_robot_spawn_uses_presentation_runtime_host_runtime", function()
    -- L159 resolve_presentation_runtime(state) 换 nil:presentation_runtime 挂的
    -- host_runtime 必须拥有机器人生成,不能掉落到全局端口。
    local overlay = require("src.ui.render.anim.unit_overlay")
    local state = support.build_min_state()
    local created = 0
    state.presentation_runtime = {
      host_runtime = {
        create_unit_with_scale = function()
          created = created + 1
          return { id = "robot" }
        end,
        schedule = function() end,
        destroy_unit = function() end,
      },
    }
    overlay.play_clear_obstacles(state, { player_id = 1, branches = {} }, 0.1, {
      clear_overlay = function() end,
    })
    -- lint-allow: call-count 注入的 host_runtime.create_unit_with_scale(GameAPI 封装)出站次数=引擎创建的机器人单位数
    luassert.truthy(created >= 1, "presentation runtime host_runtime must own the robot spawn")
  end)


end)
