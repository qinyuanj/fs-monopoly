-- #204 皮肤归属的换模型(自 rules/cosmetics 迁入):经 equip / unequip 接口驱动,
-- 观察角色控制单位替身上的 set_model_by_creature_key / reset_model 调用约定。
-- 宿主 set_model 调用约定不定(带不带 self、几个参数),模块按序试探;复位优先
-- reset_model,宿主没有或复位失败时退回默认造型。资源 id 取自 runtime_refs。
require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local host_double = require("test.support.skin_ownership_host")
local logger = require("src.foundation.log")
local runtime_assets = require("src.config.runtime_assets")
local skin_ownership = require("src.rules.skin_ownership")

local NAILONG = 5005
local NAILONG_ASSET = 1073909878
local DEFAULT_CREATURE = 1

local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end

local function _patch(patches, fn)
  support.with_patches(patches, fn, { skip_runtime_context_refresh = true })
end

local function _with_warns(fn)
  local warns = {}
  _patch({
    {
      target = logger,
      key = "warn",
      value = function(...)
        warns[#warns + 1] = table.concat({ ... }, " ")
      end,
    },
  }, fn)
  return warns
end

-- 装上替身单位、授予奶龙后穿上,返回接口的 equipped(模型是否换成)。
local function _equip_with(unit, opts)
  local host_opts = opts or {}
  host_opts.unit = unit
  host_double.install(host_opts)
  local state = host_double.state()
  skin_ownership.grant(state, 11, NAILONG)
  return skin_ownership.equip(state, 11, NAILONG).equipped
end

-- 以给定资源表替换运行资产 refs(只含皮肤模型与默认造型)。
local function _with_refs(refs, fn)
  runtime_assets.configure_for_tests({ refs = refs })
  local ok, err = pcall(fn)
  runtime_assets.reset_for_tests()
  if not ok then
    error(err, 0)
  end
end

local function _unequip_with(unit)
  host_double.install({ unit = unit })
  local state = host_double.state()
  skin_ownership.unequip(state, 11)
  return state
end

describe("TestSkinOwnershipModel", function()
  after_each(function()
    support.restore_runtime_services()
  end)

  it("test_first_setter_attempt_passes_the_asset_id_and_full_boolean_flags", function()
    local captured = {}
    local unit = {
      set_model_by_creature_key = function(...)
        captured[#captured + 1] = { ... }
        return true
      end,
    }

    _assert_eq(_equip_with(unit), true, "model change should succeed")
    luassert.same({ { NAILONG_ASSET, true, true, true } }, captured, "first attempt is (asset_id, true, true, true)")
  end)

  it("test_setter_is_retried_with_self_and_short_signatures_in_order", function()
    local shapes = {
      { accepts = function(args, unit) return args[1] == unit and #args == 5 end, attempts = 2 },
      { accepts = function(args) return #args == 1 end, attempts = 3 },
      { accepts = function(args, unit) return args[1] == unit and #args == 2 end, attempts = 4 },
    }
    for _, shape in ipairs(shapes) do
      local unit
      local attempts = {}
      unit = {
        set_model_by_creature_key = function(...)
          local args = table.pack(...)
          args.n = nil
          attempts[#attempts + 1] = args
          if not shape.accepts(args, unit) then
            error("unsupported setter signature")
          end
          return true
        end,
      }

      _assert_eq(_equip_with(unit), true, "a later signature should still change the model")
      -- lint-allow: call-count 宿主 setter 的试探顺序就是调用约定契约
      _assert_eq(#attempts, shape.attempts, "signatures are tried in order")
      local last = attempts[#attempts]
      luassert.truthy(last[1] == NAILONG_ASSET or last[2] == NAILONG_ASSET, "accepted call carries the asset id")
    end
  end)

  it("test_missing_role_or_setter_reports_no_model_change_with_warn", function()
    local warns = _with_warns(function()
      _assert_eq(_equip_with(nil, { missing_role = true }), false, "missing role fails the model change")
      _assert_eq(_equip_with({}), false, "missing setter fails the model change")
    end)
    luassert.truthy(#warns >= 2, "each failure should warn")
  end)

  it("test_get_ctrl_unit_failure_warns_with_role_id", function()
    host_double.install()
    local runtime_ports = require("src.foundation.ports.runtime_ports")
    local state = host_double.state()
    skin_ownership.grant(state, 11, NAILONG)
    local result
    local warns = _with_warns(function()
      _patch({
        {
          target = runtime_ports,
          key = "resolve_role",
          value = function()
            return { get_ctrl_unit = function() error("ctrl boom") end }
          end,
        },
      }, function()
        result = skin_ownership.equip(state, 11, NAILONG)
      end)
    end)
    _assert_eq(result.equipped, false, "failed ctrl unit reports no model change")
    local joined = table.concat(warns, "\n")
    luassert.truthy(joined:find("get_ctrl_unit failed", 1, true) and joined:find("11", 1, true), joined)
  end)

  it("test_skin_without_a_model_resource_warns_and_never_reaches_the_host", function()
    local model_calls = {}
    local warns = _with_warns(function()
      _with_refs({ skins = {}, default_creature = DEFAULT_CREATURE }, function()
        _assert_eq(_equip_with(host_double.recording_unit(model_calls)), false, "no resource, no model change")
      end)
    end)
    luassert.same({}, model_calls, "host setter must not be called")
    luassert.truthy(#warns >= 1, "missing resource should warn")
  end)

  it("test_unequip_prefers_reset_model_and_retries_it_with_self", function()
    local unit
    local resets = {}
    unit = {
      reset_model = function(self)
        resets[#resets + 1] = { self = self }
        if self ~= unit then
          error("reset requires host self")
        end
        return true
      end,
      set_model_by_creature_key = function()
        error("default creature must not be applied when reset works")
      end,
    }

    _unequip_with(unit)

    -- lint-allow: call-count 先直调再带 self 是宿主 reset_model 的调用约定契约
    _assert_eq(#resets, 2, "direct reset tried before the self form")
    _assert_eq(resets[2].self, unit, "fallback passes the unit as self")
  end)

  it("test_unequip_falls_back_to_the_default_creature_when_reset_is_missing_or_fails", function()
    for _, reset_model in ipairs({ false, function() error("reset failed") end }) do
      local applied = {}
      local unit = {
        reset_model = reset_model or nil,
        set_model_by_creature_key = function(...)
          applied[#applied + 1] = { ... }
          return true
        end,
      }
      _with_warns(function()
        _unequip_with(unit)
      end)
      _assert_eq(applied[1][1], DEFAULT_CREATURE, "default creature applied")
    end
  end)

  it("test_unequip_forwards_the_configured_default_creature_unchanged", function()
    local applied = {}
    local unit = {
      set_model_by_creature_key = function(...)
        applied[#applied + 1] = { ... }
        return true
      end,
    }
    _with_refs({ skins = {}, default_creature = "default_77" }, function()
      _unequip_with(unit)
    end)
    _assert_eq(applied[1][1], "default_77", "configured default creature forwarded")
  end)

  it("test_unequip_warns_when_no_reset_and_no_default_creature_or_the_fallback_fails", function()
    local no_default = _with_warns(function()
      _with_refs({ skins = {} }, function()
        _unequip_with({})
      end)
    end)
    luassert.truthy(#no_default >= 1, "missing fallback should warn")

    local failed = _with_warns(function()
      _unequip_with({ set_model_by_creature_key = function() error("setter failed") end })
    end)
    luassert.truthy(table.concat(failed, "\n"):find("default creature fallback failed for player 11", 1, true),
      table.concat(failed, "\n"))
  end)

  it("test_unequip_still_clears_the_selection_when_the_model_cannot_be_reset", function()
    local state
    _with_warns(function()
      state = _unequip_with({})
    end)
    _assert_eq(skin_ownership.equipped(state, 11), nil, "selection cleared")
  end)
end)
