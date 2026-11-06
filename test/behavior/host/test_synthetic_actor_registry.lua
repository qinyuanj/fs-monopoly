---@diagnostic disable: need-check-nil, different-requires, undefined-field

require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local function _require_truthy(value, message)
  luassert.truthy(value, message)
  return value
end
local _with_patches = support.with_patches
local runtime_constants = require("src.config.gameplay.runtime_constants")

describe("TestSyntheticActorRegistry", function()

local function _test_spawns_from_first_path_tile()
  local registry_module = require("src.host.synthetic_actor_registry")
  local created = {}
  local registry = registry_module.new({
    LuaAPI = {
      query_unit = function(name)
        return {
          get_position = function()
            created.query_name = name
            return { x = 1, y = 2, z = 3 }
          end,
        }
      end,
    },
    GameAPI = {
      create_creature_fixed_scale = function(unit_key, pos, rot)
        created[#created + 1] = { unit_key = unit_key, pos = pos, rot = rot }
        return {
          start_ai = function() end,
        }
      end,
    },
  })

  registry.register_specs({
    { player_id = -2, unit_key = "npc_2", avatar_image_key = 1002 },
  })
  registry.spawn_pending({
    path = { 7, 8, 9 },
  })

  _assert_eq(created.query_name, "t7", "registry should use the first path tile as spawn anchor")
  _assert_eq(created[1].unit_key, "npc_2", "registry should spawn configured synthetic unit key")
  _assert_eq(created[1].pos.x, 1, "registry should pass queried spawn position to GameAPI")
  _assert_eq(created[1].rot, runtime_constants.q_left, "registry should spawn synthetic actors facing left")
end

local function _test_spawns_at_zero_when_lua_api_cannot_query_start_tile()
  local registry_module = require("src.host.synthetic_actor_registry")
  local created = {}
  local registry = registry_module.new({
    LuaAPI = {},
    GameAPI = {
      create_creature_fixed_scale = function(unit_key, pos)
        created[#created + 1] = { unit_key = unit_key, pos = pos }
        return { start_ai = function() end }
      end,
    },
  })

  registry.register_specs({
    { player_id = -6, unit_key = "npc_6", avatar_image_key = 1006 },
  })
  registry.spawn_pending({ path = { 7 } })

  _assert_eq(#created, 1, "missing query_unit should still spawn with a fallback position")
  _assert_eq(created[1].pos.x, 0, "fallback position should be zero")
end

local function _test_spawns_at_zero_when_query_unit_raises()
  local registry_module = require("src.host.synthetic_actor_registry")
  local created = {}
  local registry = registry_module.new({
    LuaAPI = {
      query_unit = function()
        error("query_unit exploded")
      end,
    },
    GameAPI = {
      create_creature_fixed_scale = function(unit_key, pos)
        created[#created + 1] = { unit_key = unit_key, pos = pos }
        return { start_ai = function() end }
      end,
    },
  })

  registry.register_specs({
    { player_id = -7, unit_key = "npc_7", avatar_image_key = 1007 },
  })
  registry.spawn_pending({ path = { 7 } })

  _assert_eq(#created, 1, "throwing query_unit should still spawn with a fallback position")
  _assert_eq(created[1].pos.x, 0, "throwing query_unit fallback position should be zero")
end

local function _test_reset_destroys_spawned_actor_and_clears_registry()
  local registry_module = require("src.host.synthetic_actor_registry")
  local destroyed = {}
  local spawned_unit = {
    id = "synthetic_unit",
    start_ai = function() end,
  }
  local registry = registry_module.new({
    LuaAPI = {
      query_unit = function()
        return {
          get_position = function()
            return { x = 0, y = 0, z = 0 }
          end,
        }
      end,
    },
    GameAPI = {
      create_creature_fixed_scale = function()
        return spawned_unit
      end,
      destroy_unit = function(unit)
        destroyed[#destroyed + 1] = unit
      end,
    },
  })

  registry.register_specs({
    { player_id = -3, unit_key = "npc_3", avatar_image_key = 1003 },
  })
  registry.spawn_pending({
    path = { 1 },
  })
  luassert.truthy(registry.resolve_actor(-3) ~= nil, "spawned synthetic actor should be resolvable before reset")

  registry.reset()

  _assert_eq(#destroyed, 1, "registry reset should destroy spawned synthetic actor")
  _assert_eq(destroyed[1], spawned_unit, "registry reset should destroy the created unit")
  _assert_eq(registry.resolve_actor(-3), nil, "registry reset should clear actor lookup")
end

local function _test_adapter_lose_destroys_unit_and_drops_from_registry()
  local registry_module = require("src.host.synthetic_actor_registry")
  local destroyed = {}
  local spawned_unit = {
    id = "synthetic_unit_lose",
    start_ai = function() end,
  }
  local registry = registry_module.new({
    LuaAPI = {
      query_unit = function()
        return {
          get_position = function()
            return { x = 0, y = 0, z = 0 }
          end,
        }
      end,
    },
    GameAPI = {
      create_creature_fixed_scale = function()
        return spawned_unit
      end,
      destroy_unit = function(unit)
        destroyed[#destroyed + 1] = unit
      end,
    },
  })

  registry.register_specs({
    { player_id = -4, unit_key = "npc_4", avatar_image_key = 1004 },
  })
  registry.spawn_pending({ path = { 1 } })

  local actor = _require_truthy(registry.resolve_actor(-4), "actor must exist before lose")
  local adapter = _require_truthy(actor.adapter, "actor must expose adapter")

  _assert_eq(adapter.lose(), true, "lose should report retirement happened")
  _assert_eq(#destroyed, 1, "lose should destroy the synthetic unit")
  _assert_eq(destroyed[1], spawned_unit, "lose should destroy the spawned unit")
  _assert_eq(registry.resolve_actor(-4), nil, "lose should drop the actor from the registry")

  _assert_eq(adapter.lose(), true, "second lose call reports the retired state as success (idempotent)")
  _assert_eq(#destroyed, 1, "second lose call should not double-destroy the unit")
end

local function _test_adapter_die_retires_actor_like_lose()
  local registry_module = require("src.host.synthetic_actor_registry")
  local destroyed = {}
  local spawned_unit = {
    id = "synthetic_unit_die",
    start_ai = function() end,
  }
  local registry = registry_module.new({
    LuaAPI = {
      query_unit = function()
        return {
          get_position = function()
            return { x = 0, y = 0, z = 0 }
          end,
        }
      end,
    },
    GameAPI = {
      create_creature_fixed_scale = function()
        return spawned_unit
      end,
      destroy_unit = function(unit)
        destroyed[#destroyed + 1] = unit
      end,
    },
  })

  registry.register_specs({
    { player_id = -5, unit_key = "npc_5", avatar_image_key = 1005 },
  })
  registry.spawn_pending({ path = { 1 } })

  local adapter = _require_truthy(registry.resolve_actor(-5).adapter, "adapter required")
  _assert_eq(adapter.die(), true, "die should retire the actor")
  _assert_eq(#destroyed, 1, "die should destroy the unit")
  _assert_eq(adapter.lose(), true, "lose after die reports the retired state as success (idempotent)")
  _assert_eq(adapter.die(), true, "die after die is idempotent and still true")
  _assert_eq(#destroyed, 1, "re-entry must not double-destroy the unit")
end

-- ── _start_actor_ai branches ──────────────────────────────────────

local function _test_spawn_logs_warning_when_start_ai_is_missing()
  local registry_module = require("src.host.synthetic_actor_registry")
  local warned = {}
  local logger = require("src.foundation.log")
  _with_patches({
    { target = logger, key = "warn", value = function(tag, msg, pid, uk)
      warned[#warned + 1] = { tag = tag, msg = msg, pid = pid, uk = uk }
    end },
  }, function()
    local registry = registry_module.new({
      LuaAPI = {
        query_unit = function()
          return { get_position = function() return { x = 0, y = 0, z = 0 } end }
        end,
      },
      GameAPI = {
        create_creature_fixed_scale = function()
          return {}  -- no start_ai
        end,
      },
    })
    registry.register_specs({ { player_id = -8, unit_key = "npc_8" } })
    registry.spawn_pending({ path = { 1 } })
  end)
  _assert_eq(#warned, 1, "missing start_ai should log one warning")
  _assert_eq(warned[1].msg, "synthetic actor missing start_ai", "missing start_ai should use correct message")
end

local function _test_spawn_logs_warning_when_start_ai_raises()
  local registry_module = require("src.host.synthetic_actor_registry")
  local warned = {}
  local logger = require("src.foundation.log")
  _with_patches({
    { target = logger, key = "warn", value = function(tag, msg)
      warned[#warned + 1] = { tag = tag, msg = msg }
    end },
  }, function()
    local registry = registry_module.new({
      LuaAPI = {
        query_unit = function()
          return { get_position = function() return { x = 0, y = 0, z = 0 } end }
        end,
      },
      GameAPI = {
        create_creature_fixed_scale = function()
          return {
            start_ai = function() error("start_ai boom") end,
          }
        end,
      },
    })
    registry.register_specs({ { player_id = -9, unit_key = "npc_9" } })
    registry.spawn_pending({ path = { 1 } })
  end)
  _assert_eq(#warned, 1, "raising start_ai should log one warning")
  _assert_eq(warned[1].msg, "synthetic actor start_ai failed", "raising start_ai should use failure message")
end

-- ── adapter: send_ui_custom_event / game_win_and_show_result_panel ──

local function _test_adapter_send_ui_custom_event_returns_false()
  local registry_module = require("src.host.synthetic_actor_registry")
  local registry = registry_module.new({
    LuaAPI = {
      query_unit = function()
        return { get_position = function() return { x = 0, y = 0, z = 0 } end }
      end,
    },
    GameAPI = {
      create_creature_fixed_scale = function()
        return { start_ai = function() end }
      end,
    },
  })
  registry.register_specs({ { player_id = -10, unit_key = "npc_10", name = "Bot10", avatar_image_key = 1010 } })
  registry.spawn_pending({ path = { 1 } })

  local ak = _require_truthy(registry.resolve_actor(-10), "actor must exist")
  local adapter = _require_truthy(ak.adapter, "adapter must exist")
  _assert_eq(adapter.send_ui_custom_event(), false, "send_ui_custom_event should always return false")
  _assert_eq(adapter.game_win_and_show_result_panel(), false,
    "game_win_and_show_result_panel should always return false")
end

-- ── adapter: id / get_roleid / get_name ───────────────────────────

local function _test_adapter_id_and_name_match_configured_spec()
  local registry_module = require("src.host.synthetic_actor_registry")
  local registry = registry_module.new({
    LuaAPI = {
      query_unit = function()
        return { get_position = function() return { x = 0, y = 0, z = 0 } end }
      end,
    },
    GameAPI = {
      create_creature_fixed_scale = function()
        return { start_ai = function() end }
      end,
    },
  })
  registry.register_specs({ { player_id = -11, unit_key = "npc_11", name = "Alpha", avatar_image_key = 1011 } })
  registry.spawn_pending({ path = { 1 } })

  local ak = _require_truthy(registry.resolve_actor(-11), "actor must exist")
  local adapter = _require_truthy(ak.adapter, "adapter must exist")
  _assert_eq(adapter.id, -11, "adapter id should match player_id")
  _assert_eq(adapter.get_roleid(), -11, "get_roleid should return player_id")
  _assert_eq(adapter.get_name(), "Alpha", "get_name should return configured name")
  _assert_eq(adapter.get_head_icon(), 1011, "get_head_icon should return avatar_image_key")
  _assert_eq(adapter.is_synthetic_actor, true, "is_synthetic_actor should be true")
end

-- ── _normalize_pending_spec: fields present / absent ──────────────

local function _test_spawns_with_default_name_and_missing_avatar_when_spec_fields_absent()
  local registry_module = require("src.host.synthetic_actor_registry")
  local registry = registry_module.new({
    LuaAPI = {
      query_unit = function()
        return { get_position = function() return { x = 0, y = 0, z = 0 } end }
      end,
    },
    GameAPI = {
      create_creature_fixed_scale = function()
        return { start_ai = function() end }
      end,
    },
  })
  registry.register_specs({ { player_id = -12, unit_key = "npc_12" } })
  registry.spawn_pending({ path = { 1 } })

  local ak = _require_truthy(registry.resolve_actor(-12), "actor should spawn with minimal spec")
  _assert_eq(ak.name, "AI-12", "name should default to AI prefix + player_id")
  _assert_eq(ak.adapter.get_name(), "AI-12", "adapter name should match default")
  _assert_eq(ak.avatar_image_key, nil, "missing avatar_image_key should stay nil")
end

-- ── _safe_query_start_pos: nil tile_unit → zero pos ───────────────

local function _test_spawns_at_zero_when_query_unit_returns_nil()
  local registry_module = require("src.host.synthetic_actor_registry")
  local created = {}
  local registry = registry_module.new({
    LuaAPI = {
      query_unit = function()
        return nil
      end,
    },
    GameAPI = {
      create_creature_fixed_scale = function(unit_key, pos)
        created[#created + 1] = { unit_key = unit_key, pos = pos }
        return { start_ai = function() end }
      end,
    },
  })
  registry.register_specs({ { player_id = -13, unit_key = "npc_13" } })
  registry.spawn_pending({ path = { 1 } })
  _assert_eq(#created, 1, "nil query_unit result should still spawn")
  _assert_eq(created[1].pos.x, 0, "nil query_unit should fall back to zero position")
end

-- ── _resolve_start_tile_id: nil map_cfg / missing path ────────────

local function _test_spawns_at_zero_when_map_cfg_is_nil()
  local registry_module = require("src.host.synthetic_actor_registry")
  local created = {}
  local registry = registry_module.new({
    LuaAPI = {
      query_unit = function()
        return { get_position = function() return { x = 5, y = 5, z = 0 } end }
      end,
    },
    GameAPI = {
      create_creature_fixed_scale = function(unit_key, pos)
        created[#created + 1] = pos
        return { start_ai = function() end }
      end,
    },
  })
  registry.register_specs({ { player_id = -14, unit_key = "npc_14" } })
  registry.spawn_pending(nil)
  _assert_eq(#created, 1, "nil map_cfg should still spawn")
  _assert_eq(created[1].x, 0, "nil map_cfg should fall back to zero position")
end

-- ── _resolve_start_tile_id: map_cfg without path ─────────────────

local function _test_spawns_at_zero_when_map_cfg_has_no_path()
  local registry_module = require("src.host.synthetic_actor_registry")
  local created = {}
  local registry = registry_module.new({
    LuaAPI = {
      query_unit = function()
        return { get_position = function() return { x = 5, y = 5, z = 0 } end }
      end,
    },
    GameAPI = {
      create_creature_fixed_scale = function(unit_key, pos)
        created[#created + 1] = pos
        return { start_ai = function() end }
      end,
    },
  })
  registry.register_specs({ { player_id = -15, unit_key = "npc_15" } })
  registry.spawn_pending({})
  _assert_eq(#created, 1, "map_cfg without path should still spawn")
  _assert_eq(created[1].x, 0, "map_cfg without path should fall back to zero position")
end

-- ── _resolve_destroy_unit: nil env / game_api without destroy_unit ─

local function _test_adapter_lose_is_noop_when_destroy_unit_missing()
  local registry_module = require("src.host.synthetic_actor_registry")
  local spawned_unit = { start_ai = function() end }
  local registry = registry_module.new({
    LuaAPI = {
      query_unit = function()
        return { get_position = function() return { x = 0, y = 0, z = 0 } end }
      end,
    },
    GameAPI = {
      create_creature_fixed_scale = function() return spawned_unit end,
      -- no destroy_unit
    },
  })
  registry.register_specs({ { player_id = -16, unit_key = "npc_16" } })
  registry.spawn_pending({ path = { 1 } })

  local adapter = _require_truthy(registry.resolve_actor(-16).adapter, "adapter required")
  _assert_eq(adapter.lose(), true, "lose should still retire even when destroy_unit is missing")
  _assert_eq(registry.resolve_actor(-16), nil, "actor should be removed from registry")
end

-- ── registry.reset: already destroyed actor ───────────────────────

local function _test_reset_skips_already_destroyed_actor()
  local registry_module = require("src.host.synthetic_actor_registry")
  local destroyed = {}
  local spawned_unit = { start_ai = function() end }
  local registry = registry_module.new({
    LuaAPI = {
      query_unit = function()
        return { get_position = function() return { x = 0, y = 0, z = 0 } end }
      end,
    },
    GameAPI = {
      create_creature_fixed_scale = function() return spawned_unit end,
      destroy_unit = function(u) destroyed[#destroyed + 1] = u end,
    },
  })
  registry.register_specs({ { player_id = -17, unit_key = "npc_17" } })
  registry.spawn_pending({ path = { 1 } })

  local adapter = _require_truthy(registry.resolve_actor(-17).adapter, "adapter required")
  _assert_eq(adapter.lose(), true, "first lose should retire")
  _assert_eq(#destroyed, 1, "first lose should destroy once")

  -- reset should skip the already-destroyed actor
  registry.reset()
  _assert_eq(#destroyed, 1, "reset should not double-destroy an already retired actor")
end

-- ── registry.spawn_pending: empty pending specs → no-op ───────────

local function _test_spawn_pending_is_noop_when_no_specs_registered()
  local registry_module = require("src.host.synthetic_actor_registry")
  local spawned = false
  local registry = registry_module.new({
    GameAPI = {
      create_creature_fixed_scale = function()
        spawned = true
        return { start_ai = function() end }
      end,
    },
  })
  -- No register_specs call; pending_specs is empty.
  registry.spawn_pending({ path = { 1 } })
  _assert_eq(spawned, false, "empty pending specs should not spawn anything")
end

-- ── _start_actor_ai: successful call logs nothing ─────────────────

local function _test_spawn_logs_nothing_when_start_ai_succeeds()
  local registry_module = require("src.host.synthetic_actor_registry")
  local warned = {}
  local logger = require("src.foundation.log")
  _with_patches({
    { target = logger, key = "warn", value = function(...) warned[#warned + 1] = { ... } end },
  }, function()
    local registry = registry_module.new({
      LuaAPI = {
        query_unit = function()
          return { get_position = function() return { x = 0, y = 0, z = 0 } end }
        end,
      },
      GameAPI = {
        create_creature_fixed_scale = function()
          return {
            start_ai = function() end,
          }
        end,
      },
    })
    registry.register_specs({ { player_id = -18, unit_key = "npc_18" } })
    registry.spawn_pending({ path = { 1 } })
  end)
  _assert_eq(#warned, 0, "successful start_ai should log no warning")
end

-- ── registry.is_synthetic_player: 退役后仍认得该 player ───────────

local function _test_is_synthetic_player_survives_retirement()
  -- #611:合成 AI 淘汰时 die/lose 触发退役并从注册表删除,resolve_actor 恒 nil。
  -- 终局面板路由要静默跳过它,必须有一个不随退役消失的合成身份判定。
  local registry_module = require("src.host.synthetic_actor_registry")
  local registry = registry_module.new({
    LuaAPI = {
      query_unit = function()
        return { get_position = function() return { x = 0, y = 0, z = 0 } end }
      end,
    },
    GameAPI = {
      create_creature_fixed_scale = function() return { start_ai = function() end } end,
      destroy_unit = function() end,
    },
  })
  registry.register_specs({
    { player_id = -21, unit_key = "npc_21" },
    { player_id = -22, unit_key = "npc_22" },
  })
  registry.spawn_pending({ path = { 1 } })

  _assert_eq(registry.is_synthetic_player(-21), true, "spawned synthetic player should be recognized")
  _assert_eq(registry.is_synthetic_player(1), false, "host player should not be recognized as synthetic")

  local adapter = _require_truthy(registry.resolve_actor(-21).adapter, "adapter required")
  adapter.die()
  _assert_eq(registry.resolve_actor(-21), nil, "retired actor should be dropped from the registry")
  _assert_eq(registry.is_synthetic_player(-21), true, "retired synthetic player must still be recognized (#611)")
  _assert_eq(registry.is_synthetic_player(-22), true, "surviving synthetic player should be recognized")
end

local function _test_is_synthetic_player_is_cleared_by_reset()
  -- 新一局重登记前 reset 清空:上一局的合成 player_id 不得泄漏给下一局。
  local registry_module = require("src.host.synthetic_actor_registry")
  local registry = registry_module.new({
    LuaAPI = {},
    GameAPI = {
      create_creature_fixed_scale = function() return { start_ai = function() end } end,
      destroy_unit = function() end,
    },
  })
  registry.register_specs({ { player_id = -23, unit_key = "npc_23" } })
  registry.spawn_pending({ path = { 1 } })
  _assert_eq(registry.is_synthetic_player(-23), true, "synthetic player should be recognized before reset")

  registry.reset()
  _assert_eq(registry.is_synthetic_player(-23), false, "reset should clear synthetic player identities")
end

-- ── 宿主边界缺失/失败时的可见行为 ──────────────────────────────────

local function _test_spawn_pending_reports_missing_spawn_api_when_game_api_is_absent()
  local registry_module = require("src.host.synthetic_actor_registry")
  local registry = registry_module.new({ LuaAPI = {} })
  registry.register_specs({ { player_id = -24, unit_key = "npc_24" } })
  local ok, err = pcall(registry.spawn_pending, { path = { 1 } })
  _assert_eq(ok, false, "spawning without GameAPI should fail loudly")
  luassert.truthy(string.find(tostring(err), "missing GameAPI.create_creature_fixed_scale", 1, true),
    "absent GameAPI should report the missing spawn API, got: " .. tostring(err))
end

local function _test_spawn_pending_reports_failed_spawn_when_host_create_raises()
  local registry_module = require("src.host.synthetic_actor_registry")
  local registry = registry_module.new({
    LuaAPI = {},
    GameAPI = {
      create_creature_fixed_scale = function()
        error("create boom")
      end,
    },
  })
  registry.register_specs({ { player_id = -25, unit_key = "npc_25" } })
  local ok, err = pcall(registry.spawn_pending, { path = { 1 } })
  _assert_eq(ok, false, "a throwing host create should fail the spawn")
  luassert.truthy(string.find(tostring(err), "failed to spawn synthetic actor: -25", 1, true),
    "throwing host create should report the failed player, got: " .. tostring(err))
  _assert_eq(registry.resolve_actor(-25), nil, "a failed spawn must not register an actor")
end

local function _test_reset_tolerates_game_api_removed_after_spawn()
  local registry_module = require("src.host.synthetic_actor_registry")
  local env = {
    LuaAPI = {},
    GameAPI = {
      create_creature_fixed_scale = function() return { start_ai = function() end } end,
    },
  }
  local registry = registry_module.new(env)
  registry.register_specs({ { player_id = -26, unit_key = "npc_26" } })
  registry.spawn_pending({ path = { 1 } })
  env.GameAPI = nil

  local ok, err = pcall(registry.reset)
  _assert_eq(ok, true, "reset must not raise once the host GameAPI is gone: " .. tostring(err))
  _assert_eq(registry.resolve_actor(-26), nil, "reset should still clear the actor lookup")
end

local function _test_adapter_kept_across_reset_does_not_destroy_again()
  local registry_module = require("src.host.synthetic_actor_registry")
  local destroyed = {}
  local registry = registry_module.new({
    LuaAPI = {},
    GameAPI = {
      create_creature_fixed_scale = function() return { start_ai = function() end } end,
      destroy_unit = function(unit) destroyed[#destroyed + 1] = unit end,
    },
  })
  registry.register_specs({ { player_id = -27, unit_key = "npc_27" } })
  registry.spawn_pending({ path = { 1 } })
  local adapter = _require_truthy(registry.resolve_actor(-27).adapter, "adapter required")

  registry.reset()
  _assert_eq(#destroyed, 1, "reset should destroy the live actor once")
  _assert_eq(adapter.lose(), true, "lose on an actor already retired by reset reports success")
  _assert_eq(#destroyed, 1, "an adapter held across reset must not destroy the unit again")
end


it("test_spawns_from_first_path_tile", _test_spawns_from_first_path_tile)
it("test_spawns_at_zero_when_lua_api_cannot_query_start_tile", _test_spawns_at_zero_when_lua_api_cannot_query_start_tile)
it("test_spawns_at_zero_when_query_unit_raises", _test_spawns_at_zero_when_query_unit_raises)
it("test_reset_destroys_spawned_actor_and_clears_registry", _test_reset_destroys_spawned_actor_and_clears_registry)
it("test_adapter_lose_destroys_unit_and_drops_from_registry", _test_adapter_lose_destroys_unit_and_drops_from_registry)
it("test_adapter_die_retires_actor_like_lose", _test_adapter_die_retires_actor_like_lose)
it("test_spawn_logs_warning_when_start_ai_is_missing", _test_spawn_logs_warning_when_start_ai_is_missing)
it("test_spawn_logs_warning_when_start_ai_raises", _test_spawn_logs_warning_when_start_ai_raises)
it("test_adapter_send_ui_custom_event_returns_false", _test_adapter_send_ui_custom_event_returns_false)
it("test_adapter_id_and_name_match_configured_spec", _test_adapter_id_and_name_match_configured_spec)
it("test_spawns_with_default_name_and_missing_avatar_when_spec_fields_absent", _test_spawns_with_default_name_and_missing_avatar_when_spec_fields_absent)
it("test_spawns_at_zero_when_query_unit_returns_nil", _test_spawns_at_zero_when_query_unit_returns_nil)
it("test_spawns_at_zero_when_map_cfg_is_nil", _test_spawns_at_zero_when_map_cfg_is_nil)
it("test_spawns_at_zero_when_map_cfg_has_no_path", _test_spawns_at_zero_when_map_cfg_has_no_path)
it("test_adapter_lose_is_noop_when_destroy_unit_missing", _test_adapter_lose_is_noop_when_destroy_unit_missing)
it("test_reset_skips_already_destroyed_actor", _test_reset_skips_already_destroyed_actor)
it("test_spawn_pending_is_noop_when_no_specs_registered", _test_spawn_pending_is_noop_when_no_specs_registered)
it("test_spawn_logs_nothing_when_start_ai_succeeds", _test_spawn_logs_nothing_when_start_ai_succeeds)
it("test_is_synthetic_player_survives_retirement", _test_is_synthetic_player_survives_retirement)
it("test_is_synthetic_player_is_cleared_by_reset", _test_is_synthetic_player_is_cleared_by_reset)
it("test_spawn_pending_reports_missing_spawn_api_when_game_api_is_absent", _test_spawn_pending_reports_missing_spawn_api_when_game_api_is_absent)
it("test_spawn_pending_reports_failed_spawn_when_host_create_raises", _test_spawn_pending_reports_failed_spawn_when_host_create_raises)
it("test_reset_tolerates_game_api_removed_after_spawn", _test_reset_tolerates_game_api_removed_after_spawn)
it("test_adapter_kept_across_reset_does_not_destroy_again", _test_adapter_kept_across_reset_does_not_destroy_again)
end)
