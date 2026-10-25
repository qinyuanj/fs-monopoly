-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
-- luacheck: ignore 211

local support = require("test.support.shared_support")
local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local role_control_lock_policy = require("src.ui.input.role_control_lock")
local bankruptcy = require("src.rules.elimination.bankruptcy")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local default_ports = require("src.host.default_ports")

local function _with_buff_enums(buff_id, fn)
  local original = _G.Enums
  _G.Enums = { BuffState = { BUFF_FORBID_CONTROL = buff_id } }
  local ok, err = pcall(fn)
  _G.Enums = original
  if not ok then
    error(err)
  end
end

local function _single_role_runtime(unit, role_id)
  return {
    for_each_role_or_global = function(fn)
      fn({ get_ctrl_unit = function() return unit end })
    end,
    resolve_role_id = function() return role_id end,
  }
end

-- 宿主边界替身：销毁后仍保留非 nil 句柄，Buff API 只记录错误并返回 nil。
local function _host_unit(initial_count)
  local unit = { count = initial_count or 0, dead = false, destroyed = false, invalid_buff_calls = {} }
  local function usable(op)
    if unit.destroyed then
      unit.invalid_buff_calls[#unit.invalid_buff_calls + 1] = op
      return false
    end
    return true
  end
  unit.get_state_count = function()
    if usable("get_state_count") then return unit.count end
    return nil
  end
  unit.add_state = function()
    if usable("add_state") then unit.count = unit.count + 1 end
  end
  unit.remove_state = function()
    if usable("remove_state") then unit.count = unit.count - 1 end
  end
  unit.die = function() unit.dead = true end
  unit.is_die_status = function() return unit.dead end
  return unit
end

local function _with_bankruptcy_roles(fn)
  local game = support.new_game({ players = { "P1", "P2" } })
  local lost, live, spectator = _host_unit(), _host_unit(), _host_unit(1)
  local current = lost
  local lost_role = { id = game.players[1].id, get_ctrl_unit = function() return current end }
  local roles = {
    lost_role,
    { id = game.players[2].id, get_ctrl_unit = function() return live end },
    { id = "spectator", get_ctrl_unit = function() return spectator end },
  }
  local api = { destroy_unit = function(unit) unit.destroyed = true end }
  local context = { roles = roles, env = { GameAPI = api } }
  local runtime = {
    for_each_role_or_global = function(callback)
      for _, role in ipairs(roles) do callback(role) end
    end,
    resolve_role_id = function(role) return tostring(role.id) end,
  }
  local state = { game = game }
  local function eliminate()
    bankruptcy.eliminate(game, game.players[1])
    luassert.is_true(game.players[1].eliminated)
    luassert.is_true(lost.destroyed, "the real host death adapter must destroy the unit")
    luassert.are.equal(lost, lost_role.get_ctrl_unit(), "the host role retains its dead handle")
  end
  local ok, err = pcall(function()
    support.with_patches({ { key = "GameAPI", value = api } }, function()
      runtime_ports.configure(default_ports.build({ current = function() return context end }))
      _with_buff_enums(70, function()
        fn(state, { runtime = runtime }, eliminate, lost, live, spectator, roles,
          function(unit) current = unit end)
      end)
    end)
  end)
  support.restore_runtime_services()
  if not ok then error(err, 0) end
end

describe("TestRoleControlLock", function()

it("bankruptcy leaves a retained dead role untouched while live roles keep lock ownership", function()
  _with_bankruptcy_roles(function(state, deps, eliminate, lost, live, spectator)
    eliminate()
    role_control_lock_policy.sync(state, true, deps)
    role_control_lock_policy.sync(state, true, deps)
    luassert.are.same({}, lost.invalid_buff_calls)
    luassert.are.equal(1, live.count)
    luassert.are.equal(1, spectator.count)
    role_control_lock_policy.sync(state, false, deps)
    luassert.are.equal(0, live.count, "release our live lock")
    luassert.are.equal(1, spectator.count, "preserve the spectator's externally owned lock")
  end)
end)

for _, cleanup in ipairs({ "retained", "disable", "unseen", "swap", "exempt" }) do
  it("bankruptcy discards an owned dead lock safely during " .. cleanup, function()
    _with_bankruptcy_roles(function(state, deps, eliminate, lost, live, spectator, roles, swap)
      role_control_lock_policy.sync(state, true, deps)
      luassert.are.equal(1, lost.count, "acquire ownership through public sync before bankruptcy")
      eliminate()
      local replacement = _host_unit()
      if cleanup == "unseen" then table.remove(roles, 1) end
      if cleanup == "swap" then swap(replacement) end
      if cleanup == "exempt" then
        state.role_control_lock_exempt_by_role = { [state.game.players[1].id] = true }
      end
      role_control_lock_policy.sync(state, cleanup ~= "disable", deps)
      luassert.are.same({}, lost.invalid_buff_calls, "never query or remove buffs on the destroyed unit")
      luassert.are.equal(0, replacement.count, "an eliminated role cannot acquire a replacement lock")
      role_control_lock_policy.sync(state, false, deps)
      luassert.are.same({}, lost.invalid_buff_calls, "later disable must not revisit a cached dead lock")
      luassert.are.equal(0, live.count)
      luassert.are.equal(1, spectator.count)
    end)
  end)
end

it("test__sync_falls_back_to_tostring_role_id_when_resolve_fails", function()
  -- kills L149 `resolve_role_id(role) or tostring(role)` -> `or nil`:
  -- resolve_role_id 失败时锁键退化 nil,角色根本不被锁(role_id==nil 提前 return)。
  local buff_calls = {}
  local unit = {
    get_state_count = function()
      return 0
    end,
    add_state = function(_, buff_id)
      buff_calls[#buff_calls + 1] = { op = "add", buff = buff_id }
    end,
    remove_state = function()
      buff_calls[#buff_calls + 1] = { op = "remove" }
    end,
  }
  local role = { get_ctrl_unit = function()
    return unit
  end }
  local deps = {
    runtime = {
      for_each_role_or_global = function(fn)
        fn(role)
      end,
      resolve_role_id = function()
        return nil
      end,
    },
  }
  local state = {}
  _with_buff_enums("BUFF_FORBID_CONTROL", function()
    role_control_lock_policy.sync(state, true, deps)
  end)
  _assert_eq(#buff_calls, 1, "the fallback tostring id must still lock the role (kills `or tostring(role)` -> `or nil`)")
  _assert_eq(buff_calls[1].op, "add", "the fallback path acquires the control buff")
end)

-- presentation_ui.role_control_lock
it("test__sync_marks_buff_api_incomplete_when_add_state_missing", function()
  -- Pins L21 `_can_apply` chain `... and unit.add_state ...`: an `or` mutant treats a unit that
  -- has get_state_count but no add_state as usable and skips the warning.
  local unit = {
    get_state_count = function() return 1 end,
    remove_state = function() end,
  }
  local state = { role_control_lock = { by_role = {} } }

  _with_buff_enums(70, function()
    role_control_lock_policy.sync(state, true, { runtime = _single_role_runtime(unit, "p1") })
  end)

  luassert.truthy(
    state.debug_runtime
      and state.debug_runtime.log_once
      and state.debug_runtime.log_once["role_control_lock:missing_buff_api_p1"] == true,
    "a unit missing add_state must be treated as buff-api-incomplete and warned"
  )
end)

it("test__sync_marks_buff_api_incomplete_when_remove_state_missing", function()
  -- Pins L22 `_can_apply` chain `... and unit.remove_state`: an `or` mutant treats a unit that
  -- lacks remove_state as usable and skips the warning.
  local unit = {
    get_state_count = function() return 1 end,
    add_state = function() end,
  }
  local state = { role_control_lock = { by_role = {} } }

  _with_buff_enums(71, function()
    role_control_lock_policy.sync(state, true, { runtime = _single_role_runtime(unit, "p1") })
  end)

  luassert.truthy(
    state.debug_runtime
      and state.debug_runtime.log_once
      and state.debug_runtime.log_once["role_control_lock:missing_buff_api_p1"] == true,
    "a unit missing remove_state must be treated as buff-api-incomplete and warned"
  )
end)

it("test__release_tolerates_nil_state_count_without_error", function()
  -- Pins L30 `if count and count > 0`: an `or` mutant evaluates `nil > 0` and raises.
  local stale = {
    get_state_count = function() return nil end,
    remove_state = function() end,
  }
  local state = { role_control_lock = { by_role = { p1 = { owned = true, unit = stale } } } }

  local ok = pcall(function()
    _with_buff_enums(72, function()
      role_control_lock_policy.sync(state, false, {
        runtime = { for_each_role_or_global = function() end },
      })
    end)
  end)

  luassert.truthy(ok, "release must guard with `count and count > 0` and tolerate a nil state count")
end)

it("test__release_skips_removal_when_state_count_is_zero", function()
  -- Pins L30 `count > 0`: a `>=` mutant removes the buff even when the count is already 0.
  local removed = 0
  local stale = {
    get_state_count = function() return 0 end,
    remove_state = function() removed = removed + 1 end,
  }
  local state = { role_control_lock = { by_role = { p1 = { owned = true, unit = stale } } } }

  _with_buff_enums(73, function()
    role_control_lock_policy.sync(state, false, {
      runtime = { for_each_role_or_global = function() end },
    })
  end)

  _assert_eq(removed, 0, "a state count of 0 must not trigger remove_state (strict > 0)")
end)

it("test__sync_keeps_lock_when_controlling_unit_unchanged", function()
  -- Pins L41 first `and` (`entry.unit and entry.unit ~= unit ...`): an `or` mutant releases the
  -- buff even when the controlling unit is the same one already tracked.
  local removed = 0
  local unit = {
    get_state_count = function() return 1 end,
    add_state = function() end,
    remove_state = function() removed = removed + 1 end,
  }
  local state = { role_control_lock = { by_role = { p1 = { owned = true, unit = unit } } } }

  _with_buff_enums(74, function()
    role_control_lock_policy.sync(state, true, { runtime = _single_role_runtime(unit, "p1") })
  end)

  _assert_eq(removed, 0, "re-syncing the same controlling unit must not release its buff")
end)

it("test__sync_leaves_unowned_previous_unit_untouched_on_swap", function()
  -- Pins L41 second `and` (`... ~= unit and entry.owned`): an `or` mutant releases a previous
  -- unit's buff on swap even though we never owned it.
  local removed = 0
  local old_unit = {
    get_state_count = function() return 1 end,
    add_state = function() end,
    remove_state = function() removed = removed + 1 end,
  }
  local new_unit = {
    get_state_count = function() return 0 end,
    add_state = function() end,
    remove_state = function() end,
  }
  local state = { role_control_lock = { by_role = { p1 = { owned = false, unit = old_unit } } } }

  _with_buff_enums(75, function()
    role_control_lock_policy.sync(state, true, { runtime = _single_role_runtime(new_unit, "p1") })
  end)

  _assert_eq(removed, 0,
    "a previously unowned unit must not be released when the controlling unit changes")
end)

it("test__sync_preserves_unowned_flag_when_buff_already_present", function()
  -- Pins L55 `entry.owned = entry.owned == true`: a `== false` mutant flips an unowned entry to
  -- owned when the buff is already applied.
  local unit = {
    get_state_count = function() return 1 end,
    add_state = function() end,
    remove_state = function() end,
  }
  local state = { role_control_lock = { by_role = { p1 = { owned = false, unit = unit } } } }

  _with_buff_enums(76, function()
    role_control_lock_policy.sync(state, true, { runtime = _single_role_runtime(unit, "p1") })
  end)

  _assert_eq(state.role_control_lock.by_role.p1.owned, false,
    "a buff we did not add must stay unowned (entry.owned == true)")
end)

it("test__sync_does_not_lock_exempt_role_with_capable_unit", function()
  -- Pins L113 exempt read (`read(...) == true`), L114 `exempt or not unit`, and L143
  -- `state.role_control_lock_exempt_by_role or {}`: each mutant would lock an exempt role that
  -- has a fully-capable control unit.
  local added = 0
  local unit = {
    get_state_count = function() return 0 end,
    add_state = function() added = added + 1 end,
    remove_state = function() end,
  }
  local state = {
    role_control_lock = { by_role = {} },
    role_control_lock_exempt_by_role = { p1 = true },
  }

  _with_buff_enums(77, function()
    role_control_lock_policy.sync(state, true, { runtime = _single_role_runtime(unit, "p1") })
  end)

  _assert_eq(added, 0, "an exempt role with a capable ctrl unit must not receive the control-lock buff")
  _assert_eq(state.role_control_lock.by_role.p1, nil, "an exempt role must not create a lock entry")
end)


end)
