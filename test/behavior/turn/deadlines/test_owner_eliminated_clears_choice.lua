-- 淘汰清窗守卫:被淘汰玩家的待决选择不该挂着干等倒计时(CONTEXT「待决选择」:
-- 残留待决选择是缺陷,不是合法状态)。eliminate 清了背包/神明/淘汰位,唯独不碰
-- pending_choice,窗口原本要挂满 15s 超时 force_skip 才消失。守卫落在 choice
-- 超时 tick 的公共入口:owner 已淘汰 → 立即 force_skip(reason=owner_eliminated),
-- 不走自动代答——被淘汰者不该被代答。
-- luacheck: std +busted
require("test.bootstrap").install_package_paths()
local luassert = assert
local function _assert_same(actual, expected, message)
  luassert.is.same(expected, actual, message)
end
local support = require("test.support.shared_support")
local tick_choice_timeout = require("test.support.choice_timeout")
local ChoiceTimeout = require("src.turn.waits.choice_timeout")
local bankruptcy = require("src.rules.elimination.bankruptcy")
local logger = require("src.foundation.log")
local config_reset = require("test.support.config_reset")

local function _open_owned_choice(g, owner)
  return support.open_choice(g, {
    kind = "item_phase_passive",
    owner_role_id = owner.id,
    options = { { id = "opt_a", label = "选项A" } },
    meta = { phase = "post_action", player_id = owner.id },
  })
end

local function _step_once(g, state, dispatched)
  local lifecycle = tick_choice_timeout.new({
    on_pending_choice = function() end,
    is_choice_active = function() return true end,
    build_action = function() return nil end,
    dispatch_action_with_close_choice = function(_, _, action)
      dispatched[#dispatched + 1] = action
    end,
  })
  lifecycle.step(g, state, 0.1)
end

describe("TestOwnerEliminatedClearsChoice", function()

before_each(function()
  config_reset.reset_all()
end)

it("test_force_skips_the_pending_choice_as_soon_as_its_owner_is_eliminated", function()
  local g = support.new_game({ players = { "P1", "P2", "P3" } })
  local owner = g.players[1]
  _open_owned_choice(g, owner)
  bankruptcy.eliminate(g, owner, { reason = "测试破产" })
  luassert.is_not_nil(g.turn.pending_choice, "eliminate itself does not clear the window (that is the tick guard's job)")

  local dispatched = {}
  local warns = {}
  local orig_warn = logger.warn
  logger.warn = function(...)
    warns[#warns + 1] = table.concat({ ... }, " ")
    return orig_warn(...)
  end
  local ok, err = pcall(_step_once, g, {}, dispatched)
  logger.warn = orig_warn
  luassert.truthy(ok, err)

  luassert.is_nil(g.turn.pending_choice, "eliminated owner's choice must be cleared on the next tick, not after the 15s countdown")
  _assert_same(#dispatched, 0, "an eliminated owner must be skipped, never auto-answered")
  local skip_logged = false
  for _, line in ipairs(warns) do
    if line:find("owner_eliminated", 1, true) then
      skip_logged = true
    end
  end
  luassert.is_true(skip_logged, "the skip must be attributed to owner_eliminated for diagnosis")
end)

it("test_leaves_a_living_owners_choice_untouched", function()
  local g = support.new_game({ players = { "P1", "P2", "P3" } })
  local owner = g.players[1]
  local pending = _open_owned_choice(g, owner)

  local dispatched = {}
  _step_once(g, {}, dispatched)

  _assert_same(g.turn.pending_choice, pending, "a living owner keeps the window and the countdown")
  _assert_same(#dispatched, 0)
end)

it("test_guards_the_production_default_choice_tick_as_well", function()
  local g = support.new_game({ players = { "P1", "P2", "P3" } })
  local owner = g.players[1]
  _open_owned_choice(g, owner)
  bankruptcy.eliminate(g, owner, { reason = "测试破产" })

  local state = require("test.support.gameplay_fixtures").build_loop_state()
  ChoiceTimeout.step_default(g, state, 0.1)

  luassert.is_nil(g.turn.pending_choice, "the default production tick must clear an eliminated owner's window")
end)


end)
