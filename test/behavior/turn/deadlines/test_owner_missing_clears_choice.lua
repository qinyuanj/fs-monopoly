-- owner 悬空清窗守卫:choice 显式 owner_role_id 在 players 里查无此人时
-- (断线重连/读档重建后 owner 悬空,见 #455 待真机核实的重建场景),
-- owner.resolve_role_id 的「兜底当前回合玩家」会造出 actor≠owner 的代答动作,
-- 被 validator_actor_choice 拦截,窗口永不消失、blocked warn 每 15s 超时刷屏
-- (真机 2026-08-12:断线重连后马灯规律广播
-- "choice action blocked by actor check: choice_cancel actor_role_id=1 owner_role_id=2")。
-- 守卫落在 choice 超时 tick 的公共入口:owner 悬空 → 立即 force_skip
-- (reason=owner_dangling),与 owner_eliminated 同口径,不带兜底 actor 去派发。
-- luacheck: std +busted
require("test.bootstrap").install_package_paths()
local luassert = assert
local function _assert_same(actual, expected, message)
  luassert.is.same(expected, actual, message)
end
local support = require("test.support.shared_support")
local tick_choice_timeout = require("test.support.choice_timeout")
local ChoiceTimeout = require("src.turn.waits.choice_timeout")
local logger = require("src.foundation.log")
local config_reset = require("test.support.config_reset")

local DANGLING_OWNER_ROLE_ID = 99

local function _open_orphaned_choice(g)
  return support.open_choice(g, {
    kind = "item_phase_passive",
    owner_role_id = DANGLING_OWNER_ROLE_ID,
    options = { { id = "opt_a", label = "选项A" } },
    meta = { phase = "post_action", player_id = DANGLING_OWNER_ROLE_ID },
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

local function _any_line_contains(lines, needle)
  for _, line in ipairs(lines or {}) do
    if line:find(needle, 1, true) then
      return true
    end
  end
  return false
end

-- 同时抓两层:logger.warn 调用文本 + ui_sink(马灯广播通道,ADR 0030)条目。
local function _with_captured_channels(fn)
  local warns = {}
  local marquee = {}
  local orig_warn = logger.warn
  logger.warn = function(...)
    warns[#warns + 1] = table.concat({ ... }, " ")
    return orig_warn(...)
  end
  logger.set_ui_sink(function(entry)
    if entry and entry.level == "warn" then
      marquee[#marquee + 1] = tostring(entry.text)
    end
  end)
  local ok, err = pcall(fn)
  logger.warn = orig_warn
  logger.set_ui_sink(nil)
  luassert.truthy(ok, err)
  return warns, marquee
end

local function _spy_advance_turn(g)
  local calls = 0
  local orig = g.advance_turn
  g.advance_turn = function(self, ...)
    calls = calls + 1
    if orig then
      return orig(self, ...)
    end
  end
  return function() return calls end
end

describe("TestOwnerMissingClearsChoice", function()

before_each(function()
  config_reset.reset_all()
end)

it("test_force_skips_the_pending_choice_when_owner_is_dangling", function()
  local g = support.new_game({ players = { "P1", "P2", "P3" } })
  _open_orphaned_choice(g)
  luassert.is_not_nil(g.turn.pending_choice, "precondition: orphaned choice is pending")
  local advance_calls = _spy_advance_turn(g)

  local dispatched = {}
  local warns, marquee = _with_captured_channels(function()
    _step_once(g, {}, dispatched)
    -- 再 tick 一轮:清窗后不得再有新一轮 blocked warn(刷屏循环必须死亡)。
    _step_once(g, {}, dispatched)
  end)

  luassert.is_nil(g.turn.pending_choice, "orphaned choice must be cleared on the next tick")
  _assert_same(#dispatched, 0, "a dangling owner must be force-skipped, never auto-answered")
  _assert_same(advance_calls(), 1,
    "force_skip advances the turn exactly once to unblock the current player")
  luassert.is_true(_any_line_contains(warns, "owner_dangling"),
    "the skip must be attributed to owner_dangling for diagnosis")
  luassert.is_false(_any_line_contains(warns, "choice action blocked by actor check"),
    "no actor-mismatch blocked warn may escape to the marquee channel")
  luassert.is_true(_any_line_contains(marquee, "choice_force_skipped") and _any_line_contains(marquee, "owner_dangling"),
    "the single force_skip diagnostic must reach the marquee (ui_sink) channel")
  luassert.is_false(_any_line_contains(marquee, "choice action blocked by actor check"),
    "the marquee must never carry the blocked warn")
end)

it("test_leaves_a_resolvable_owners_choice_untouched", function()
  local g = support.new_game({ players = { "P1", "P2", "P3" } })
  local owner = g.players[2]
  local pending = support.open_choice(g, {
    kind = "item_phase_passive",
    owner_role_id = owner.id,
    options = { { id = "opt_a", label = "选项A" } },
    meta = { phase = "post_action", player_id = owner.id },
  })

  local dispatched = {}
  _step_once(g, {}, dispatched)

  _assert_same(g.turn.pending_choice, pending, "a resolvable owner keeps the window and the countdown")
  _assert_same(#dispatched, 0)
end)

it("test_guards_the_production_default_choice_tick_as_well", function()
  local g = support.new_game({ players = { "P1", "P2", "P3" } })
  _open_orphaned_choice(g)

  local state = require("test.support.gameplay_fixtures").build_loop_state()
  ChoiceTimeout.step_default(g, state, 0.1)

  luassert.is_nil(g.turn.pending_choice, "the default production tick must clear an orphaned window")
end)


end)
