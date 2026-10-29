-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
-- #293 批3 pin:src/ui/render/anim/unit_overlay.lua 的幸存者分两类:
-- ① _deps(state) 换 nil(路障/地雷/清除/导弹四条生成链的 deps 实参);
-- ② prefab.unit and prefab.unit["路障"] or nil 的 and->or(unit_id 整表透传)。
-- 其余幸存者为 assert 消息/日志字符串(等价)。桩 overlay_runtime 同表函数
-- 捕获实参,逐链断言 deps 与 id 直取。Data.Prefab 是数据表,setUp 覆写
-- 路障/地雷/导弹键、tearDown 还原,不依赖真数据恰好存在该键。


if not math.Vector3 then
  function math.Vector3(x, y, z)
    return { x = x, y = y, z = z, key = "Vector3" }
  end
end

local overlay = require("src.ui.render.anim.unit_overlay")
local runtime = require("src.ui.render.anim.overlay_runtime")
local prefab = require("Data.Prefab")

local _saved_spawn_overlay = runtime.spawn_overlay
local _saved_clear_overlay = runtime.clear_overlay
local _saved_spawn_transient = runtime.spawn_transient

local _saved_unit_roadblock = prefab.unit and prefab.unit["路障"]
local _saved_unit_mine = prefab.unit and prefab.unit["地雷A"]
local _saved_group_mine = prefab.group and prefab.group["地雷A"]
local _saved_unit_missile = prefab.unit and prefab.unit["导弹"]
local _saved_group_missile = prefab.group and prefab.group["导弹"]

local _captured = nil

local function _assert_eq(a, b, msg)
  luassert.truthy(a == b, tostring(msg) .. ": expected " .. tostring(b) .. " got " .. tostring(a))
end

local function _state()
  return {
    board_scene = { tiles = {}, ground = { get_position = function() return math.Vector3(0.0, 0.0, 0.0) end } },
    presentation_runtime = { marker = "rt" },
  }
end

describe("TestUnitOverlay", function()

  before_each(function()
    _captured = { spawns = {}, clears = {}, transients = {}, clear_calls = {} }
    runtime.spawn_overlay = function(scene, kind, tile_index, group_id, unit_id, pos, scale, deps)
      _captured.spawns[#_captured.spawns + 1] = {
        scene = scene, kind = kind, tile_index = tile_index,
        group_id = group_id, unit_id = unit_id, deps = deps,
      }
    end
    runtime.clear_overlay = function(scene, kind, tile_index, deps)
      _captured.clears[#_captured.clears + 1] = { scene = scene, kind = kind, tile_index = tile_index, deps = deps }
    end
    runtime.spawn_transient = function(group_id, unit_id, pos, duration, deps)
      _captured.transients[#_captured.transients + 1] = {
        group_id = group_id, unit_id = unit_id, pos = pos, duration = duration, deps = deps,
      }
    end
    prefab.unit["路障"] = "roadblock_unit"
    prefab.unit["地雷A"] = "mine_unit"
    prefab.group["地雷A"] = "mine_group"
    prefab.unit["导弹"] = "missile_unit"
    prefab.group["导弹"] = "missile_group"
  end)

  after_each(function()
    runtime.spawn_overlay = _saved_spawn_overlay
    runtime.clear_overlay = _saved_clear_overlay
    runtime.spawn_transient = _saved_spawn_transient
    prefab.unit["路障"] = _saved_unit_roadblock
    prefab.unit["地雷A"] = _saved_unit_mine
    prefab.group["地雷A"] = _saved_group_mine
    prefab.unit["导弹"] = _saved_unit_missile
    prefab.group["导弹"] = _saved_group_missile
  end)

  it("test_play_roadblock_spawns_with_scene_unit_id_and_deps", function()
    -- L24 _deps(state) 换 nil(路障链)与 L31 prefab.unit and ... 的 and->or
    -- (unit_id 整表透传):生成实参必须带 presentation_runtime 与 prefab id。
    local state = _state()
    overlay.play_overlay(state, { kind = "roadblock", tile_index = 3 }, 1.0)
    _assert_eq(#_captured.spawns, 1, "roadblock must spawn once")
    local spawn = _captured.spawns[1]
    _assert_eq(spawn.scene, state.board_scene, "board_scene must be the spawn scene")
    _assert_eq(spawn.kind, "roadblock", "spawn kind")
    _assert_eq(spawn.tile_index, 3, "spawn tile index")
    _assert_eq(spawn.unit_id, "roadblock_unit", "prefab unit id must be passed through")
    _assert_eq(spawn.deps, state.presentation_runtime, "deps must be the presentation runtime")
  end)

  it("test_play_mine_spawns_with_group_unit_and_deps", function()
    -- L36 assert 实参换 nil 与 L37 _deps(state) 换 nil:地雷链的 scene 与
    -- deps 实参必须原样透传。
    local state = _state()
    overlay.play_overlay(state, { kind = "mine", tile_index = 2 }, 1.0)
    _assert_eq(#_captured.spawns, 1, "mine must spawn once")
    local spawn = _captured.spawns[1]
    _assert_eq(spawn.scene, state.board_scene, "board_scene must be the spawn scene")
    _assert_eq(spawn.kind, "mine", "spawn kind")
    _assert_eq(spawn.group_id, "mine_group", "prefab group id must be passed through")
    _assert_eq(spawn.unit_id, "mine_unit", "prefab unit id must be passed through")
    _assert_eq(spawn.deps, state.presentation_runtime, "deps must be the presentation runtime")
  end)

  it("test_clear_overlay_passes_scene_kind_index_and_deps", function()
    -- L44 assert 实参换 nil 与 _deps(state) 换 nil:清除链的 scene/deps 实参
    -- 必须原样透传,kind 与 tile_index 不能错位。
    local state = _state()
    overlay.clear_overlay(state, "roadblock", 5)
    _assert_eq(#_captured.clears, 1, "clear must call runtime once")
    local clear = _captured.clears[1]
    _assert_eq(clear.scene, state.board_scene, "board_scene must be the clear scene")
    _assert_eq(clear.kind, "roadblock", "clear kind")
    _assert_eq(clear.tile_index, 5, "clear tile index")
    _assert_eq(clear.deps, state.presentation_runtime, "deps must be the presentation runtime")
  end)

  it("test_play_missile_spawns_transient_with_ids_and_deps", function()
    -- L63 _deps(state) 换 nil:导弹链的 deps 实参必须原样透传,group/unit id
    -- 直取 prefab。
    local state = _state()
    local clear_calls = 0
    overlay.play_missile(state, { tile_index = 7 }, 1.5, {
      clear_overlay = function(_, _)
        clear_calls = clear_calls + 1
      end,
    })
    _assert_eq(clear_calls, 2, "missile must clear roadblock and mine")
    _assert_eq(#_captured.transients, 1, "missile must spawn a transient")
    local transient = _captured.transients[1]
    _assert_eq(transient.group_id, "missile_group", "prefab group id must be passed through")
    _assert_eq(transient.unit_id, "missile_unit", "prefab unit id must be passed through")
    _assert_eq(transient.duration, 1.5, "duration must be passed through")
    _assert_eq(transient.deps, state.presentation_runtime, "deps must be the presentation runtime")
  end)

  it("test_play_mine_skips_spawn_when_prefab_missing", function()
    -- 基线契约:地雷 prefab 双双缺失时跳过生成(日志路径),不得落任何生成。
    prefab.unit["地雷A"] = nil
    prefab.group["地雷A"] = nil
    overlay.play_overlay(_state(), { kind = "mine", tile_index = 2 }, 1.0)
    _assert_eq(#_captured.spawns, 0, "missing mine prefab must skip spawning")
  end)

  it("test_play_mine_spawns_when_group_only_present", function()
    -- L31 `not group_id and not unit_id` 的 and -> or(变异体在 group 缺 unit
    -- 时误判为全缺而跳过):group 在场、unit 缺失时仍必须生成。
    prefab.unit["地雷A"] = nil
    local state = _state()
    overlay.play_overlay(state, { kind = "mine", tile_index = 2 }, 1.0)
    _assert_eq(#_captured.spawns, 1, "group-only mine must still spawn")
    _assert_eq(_captured.spawns[1].group_id, "mine_group", "group id must be passed through")
    _assert_eq(_captured.spawns[1].unit_id, nil, "missing unit must pass through as nil")
  end)

  it("test_play_unknown_kind_does_not_spawn", function()
    -- play_overlay 只认 roadblock/mine,未知 kind 不落任何生成。
    overlay.play_overlay(_state(), { kind = "teleport", tile_index = 1 }, 1.0)
    _assert_eq(#_captured.spawns, 0, "unknown kind must not spawn")
  end)

end)
