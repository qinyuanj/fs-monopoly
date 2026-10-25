-- #204 / #205 皮肤归属的换模型:经 equip / unequip 接口驱动,在 runtime_ports 的
-- set_role_model / reset_role_model 端口边界观察调用;宿主签名与调用形态由
-- src/host/role_model 锁定(test/behavior/host/test_role_model.lua)。复位优先
-- reset_role_model,端口报失败时退回默认造型。资源 id 取自 runtime_refs。
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

-- 装上端口替身、授予奶龙后穿上,返回接口的 equipped(模型是否换成)与替身句柄。
local function _equip_with(opts)
  local host = host_double.install(opts)
  local state = host_double.state()
  skin_ownership.grant(state, 11, NAILONG)
  return skin_ownership.equip(state, 11, NAILONG).equipped, host
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

local function _unequip_with(opts)
  local host = host_double.install(opts)
  local state = host_double.state()
  skin_ownership.unequip(state, 11)
  return state, host
end

describe("TestSkinOwnershipModel", function()
  after_each(function()
    support.restore_runtime_services()
  end)

  it("test_equip_sends_the_skin_asset_through_the_set_role_model_port_once", function()
    local equipped, host = _equip_with()

    _assert_eq(equipped, true, "model change should succeed")
    luassert.same({ { op = "set_model", role_id = 11, args = { NAILONG_ASSET } } }, host.model_calls,
      "one set_role_model(role_id, asset_id) call")
  end)

  it("test_failed_set_role_model_reports_no_model_change_with_warn", function()
    local equipped
    local warns = _with_warns(function()
      equipped = _equip_with({ set_model_ok = false })
    end)

    _assert_eq(equipped, false, "port failure fails the model change")
    local joined = table.concat(warns, "\n")
    luassert.truthy(joined:find("set_role_model failed for player 11", 1, true), joined)
  end)

  it("test_skin_without_a_model_resource_warns_and_never_reaches_the_port", function()
    local host
    local warns = _with_warns(function()
      _with_refs({ skins = {}, default_creature = DEFAULT_CREATURE }, function()
        local equipped
        equipped, host = _equip_with()
        _assert_eq(equipped, false, "no resource, no model change")
      end)
    end)
    luassert.same({}, host.model_calls, "model port must not be called")
    luassert.truthy(#warns >= 1, "missing resource should warn")
  end)

  it("test_unequip_resets_through_the_reset_role_model_port_only", function()
    local _, host = _unequip_with()

    luassert.same({ { op = "reset_model", role_id = 11, args = {} } }, host.model_calls,
      "reset succeeded, default creature not applied")
  end)

  it("test_unequip_falls_back_to_the_default_creature_when_reset_fails", function()
    local host
    local warns = _with_warns(function()
      host = select(2, _unequip_with({ reset_model_ok = false }))
    end)

    luassert.same({ op = "set_model", role_id = 11, args = { DEFAULT_CREATURE } }, host.model_calls[2],
      "default creature applied after the failed reset")
    local joined = table.concat(warns, "\n")
    luassert.truthy(joined:find("reset_role_model failed for player 11", 1, true), joined)
  end)

  it("test_unequip_forwards_the_configured_default_creature_unchanged", function()
    local host
    _with_warns(function()
      _with_refs({ skins = {}, default_creature = "default_77" }, function()
        host = select(2, _unequip_with({ reset_model_ok = false }))
      end)
    end)
    _assert_eq(host.model_calls[2].args[1], "default_77", "configured default creature forwarded")
  end)

  it("test_unequip_warns_when_no_reset_and_no_default_creature_or_the_fallback_fails", function()
    local no_default = _with_warns(function()
      _with_refs({ skins = {} }, function()
        _unequip_with({ reset_model_ok = false })
      end)
    end)
    luassert.truthy(table.concat(no_default, "\n"):find("missing default creature_key", 1, true),
      table.concat(no_default, "\n"))

    local failed = _with_warns(function()
      _unequip_with({ reset_model_ok = false, set_model_ok = false })
    end)
    luassert.truthy(table.concat(failed, "\n"):find("default creature fallback failed for player 11", 1, true),
      table.concat(failed, "\n"))
  end)

  it("test_unequip_still_clears_the_selection_when_the_model_cannot_be_reset", function()
    local state
    _with_warns(function()
      state = _unequip_with({ reset_model_ok = false, set_model_ok = false })
    end)
    _assert_eq(skin_ownership.equipped(state, 11), nil, "selection cleared")
  end)
end)
