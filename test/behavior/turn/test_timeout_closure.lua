-- 选择与弹层超时的配置回退、边界和默认收屏行为。
-- tick_timeout_spec covers the resolve_choice happy paths and the modal-timer
-- state machine, leaving the config-fallback / type-guard / boundary survivors
-- alive. This spec drives the exported surface directly, patching timing and
-- constants config to reach the branches the architect flagged
-- (L22 _positive_numeric, L35 scoped-timeout fallback, L43 _resolve_modal_ports,
-- L81 _resolve_modal_timeout) plus the modal asserts and elapsed boundaries.
--
local check = require("luassert")
local support = require("test.support.shared_support")
local fixtures = require("test.support.gameplay_fixtures")
local config_reset = require("test.support.config_reset")
local ChoiceTimeout = require("src.turn.waits.choice_timeout")
local modal_timeout = require("src.turn.waits.modal_timeout")
local timing = require("src.config.gameplay.timing")
local constants = require("src.config.content.constants")
local runtime_state = require("src.state.runtime")
local choice_auto_policy = require("src.turn.policies.choice_auto")
local turn_dispatch = require("src.turn.actions.action_dispatcher")

local _assert_eq = support.assert_eq
local _with_patches = support.with_patches

local function _resolve_choice(game, state, choice)
  return ChoiceTimeout.resolve_choice_timeout_seconds(game, state, choice)
end

local function _step_modal_timeout(modal)
  local game = support.new_game()
  local state = fixtures.build_loop_state()
  local ports = fixtures.build_test_ports()
  ports.modal = modal
  state.gameplay_loop_ports = ports
  state._resolved_gameplay_loop_ports = ports
  state.ui.popup_active = true
  state.ui.popup_seq = 7
  state.ui.popup_payload = { auto_close_seconds = 5.0 }
  modal_timeout.step_default(game, state, 999.0)
end

-- Output-port stub: records the synced timer payloads.
local function _output_state(start_elapsed, current_ref)
  local elapsed = start_elapsed
  local syncs = {}
  local ports = {
    get_modal_elapsed = function() return elapsed end,
    get_modal_ref = function() return current_ref end,
    sync_modal_timer = function(_, payload)
      syncs[#syncs + 1] = payload
      if payload.elapsed_seconds ~= nil then elapsed = payload.elapsed_seconds end
    end,
  }
  return { gameplay_loop_ports = { output = ports } }, syncs
end

local function _active_opts(extra)
  local opts = {
    is_active = function() return true end,
    get_ref = function() return "ref" end,
    on_timeout = function() end,
  }
  for k, v in pairs(extra or {}) do opts[k] = v end
  return opts
end

-- Fake gameplay_loop_ports: build_test_ports supplies output (via the real
-- output_state_adapter fallback) and a ui_sync table; we graft the choice
-- callbacks onto ui_sync so the default-choice closures can delegate.
local function _choice_state(ui_sync_extra)
  local game = support.new_game()
  local state = fixtures.build_loop_state()
  local ports = fixtures.build_test_ports()
  for key, value in pairs(ui_sync_extra or {}) do ports.ui_sync[key] = value end
  state._resolved_gameplay_loop_ports = ports
  state.gameplay_loop_ports = ports
  game.turn.pending_choice = { id = 1, kind = "test", route_key = "r" }
  return game, state, ports
end

describe("TestTimeoutClosure", function()

before_each(function()
  config_reset.reset_all()
end)

it("test_a nil constants base resolves to a 0 timeout and short-circuits before firing", function()
  -- kills _resolve_modal_timeout's `or 0` -> `or 1` (L81) and step's `<= 0` ->
  -- `< 0` (L134): with no base the timeout is 0, so the <=0 branch syncs the
  -- empty payload and returns without ever firing on_timeout, even at huge dt.
  local fired = false
  _with_patches({
    { target = constants, key = "action_timeout_seconds", value = nil },
  }, function()
    local state, syncs = _output_state(100.0, "ref")
    modal_timeout.step(state, 100.0,
      _active_opts({ on_timeout = function() fired = true end }))
    _assert_eq(fired, false, "a 0 timeout (or 0, not or 1) takes the <=0 branch before firing")
    _assert_eq(next(syncs[#syncs]), nil, "the <=0 branch syncs the empty timer payload")
  end)
end)

it("test_a scoped timeout of exactly 1 is positive (the > 0 boundary, not > 1)", function()
  -- kills _positive_numeric's `> 0` -> `> 1` mutant: a value of 1 must count
  -- as positive and win over the constants base.
  _with_patches({
    { target = timing, key = "scope_timeouts", value = { choice = 1.0 } },
    { target = constants, key = "action_timeout_seconds", value = 99.0 },
  }, function()
    _assert_eq(_resolve_choice(nil, nil, nil), 1.0,
      "choice=1 is positive and is chosen over the constants base 99")
  end)
end)

it("test_a_non_numeric_override_is_ignored_and_the_base_is_kept", function()
  local fired = false
  _with_patches({
    { target = constants, key = "action_timeout_seconds", value = 4.0 },
  }, function()
    local state = _output_state(3.0, "ref")
    modal_timeout.step(state, 2.0, _active_opts({
      get_timeout_seconds = function() return "later" end,
      on_timeout = function() fired = true end,
    }))
    _assert_eq(fired, true, "a non-numeric override leaves the base 4 in force, so 5 >= 4 fires")
  end)
end)

it("test_a_numeric_override_replaces_the_constants_base", function()
  local fired = false
  _with_patches({
    { target = constants, key = "action_timeout_seconds", value = 4.0 },
  }, function()
    local state = _output_state(3.0, "ref")
    modal_timeout.step(state, 2.0, _active_opts({
      get_timeout_seconds = function() return 100.0 end,
      on_timeout = function() fired = true end,
    }))
    _assert_eq(fired, false, "5 < the 100 override must not fire")
  end)
end)

it("test_asserts_when_an_active_modal_opts_table_is_missing_is_active", function()
  _with_patches({
    { target = constants, key = "action_timeout_seconds", value = 10.0 },
  }, function()
    local state = _output_state(0.0, "ref")
    local ok = pcall(function()
      modal_timeout.step(state, 1.0, { get_ref = function() return "ref" end, on_timeout = function() end })
    end)
    _assert_eq(ok, false, "a positive timeout with missing opts.is_active asserts")
  end)
end)

it("test_asserts_when_the_modal_ref_cannot_be_resolved", function()
  _with_patches({
    { target = constants, key = "action_timeout_seconds", value = 10.0 },
  }, function()
    local state = _output_state(0.0, "ref")
    local ok, err = pcall(function()
      modal_timeout.step(state, 1.0, _active_opts({ get_ref = function() return nil end }))
    end)
    _assert_eq(ok, false, "a nil modal ref asserts 'missing modal ref'")
    -- #293: L127 assert 消息变异(消息串翻 nil)必须被钉住。
    check.is_truthy(tostring(err):find("missing modal ref", 1, true) ~= nil,
      "the nil modal ref error must identify 'missing modal ref'")
  end)
end)

it("test_closes the popup when only close_popup is present (the or-guard)", function()
  local closed = false
  _step_modal_timeout({ close_popup = function() closed = true end })
  _assert_eq(closed, true,
    "close_popup alone resolves the modal ports (close_choice_modal OR close_popup)")
end)

it("test_delegates the ui-sync choice callbacks when the ports expose them", function()
  local calls = { pending = 0, active = 0, resolve = 0 }
  local game, state = _choice_state({
    on_pending_choice = function() calls.pending = calls.pending + 1 end,
    is_choice_active = function() calls.active = calls.active + 1; return true end,
    resolve_choice_ui_state = function() calls.resolve = calls.resolve + 1; return { should_warn = false } end,
  })
  ChoiceTimeout.step_default(game, state, 0.01)
  check.is_truthy(calls.pending >= 1, "a fresh pending choice routes through ui_sync.on_pending_choice")
  check.is_truthy(calls.active >= 1, "the active check delegates to ui_sync.is_choice_active")
  check.is_truthy(calls.resolve >= 1, "the ui-gate resolve delegates to ui_sync.resolve_choice_ui_state")
end)

it("test_dispatches the auto action through the close-choice path when modal ports exist", function()
  local dispatched
  local game, state = _choice_state({ is_choice_active = function() return true end })
  _with_patches({
    { target = timing, key = "auto_decision_delay_seconds", value = 0 }, -- force the timeout path
    { target = choice_auto_policy, key = "decide", value = function() return { type = "auto_skip", actor_role_id = 1 } end },
    { target = turn_dispatch, key = "dispatch_action", value = function(_, _, action, opts)
        dispatched = { action = action, opts = opts }
        return true
      end },
  }, function()
    ChoiceTimeout.step_default(game, state, 999.0) -- huge dt clears the min-visible gate and the timeout
  end)
  check.is_not_nil(dispatched, "the decided auto action is dispatched on timeout")
  _assert_eq(dispatched.action.type, "auto_skip", "the policy's action is forwarded verbatim")
  check.is_not_nil(dispatched.opts, "modal ports present -> a close-choice opts table is supplied")
end)

it("test_dispatches with no close-choice opts when modal ports are absent", function()
  local dispatched
  local game, state, ports = _choice_state({ is_choice_active = function() return true end })
  ports.modal = nil -- no modal ports to resolve
  _with_patches({
    { target = timing, key = "auto_decision_delay_seconds", value = 0 },
    { target = choice_auto_policy, key = "decide", value = function() return { type = "auto_skip", actor_role_id = 1 } end },
    { target = turn_dispatch, key = "dispatch_action", value = function(_, _, action, opts)
        dispatched = { action = action, opts = opts }
        return true
      end },
  }, function()
    ChoiceTimeout.step_default(game, state, 999.0)
  end)
  check.is_not_nil(dispatched, "the action still dispatches without modal ports")
  _assert_eq(dispatched.opts, nil, "absent modal ports -> dispatch carries no close-choice opts")
end)

-- modal.on_timeout exercises _resolve_modal_ports (L43 or-guard) -----------

it("test_does_nothing_when_neither_modal_close_function_is_present", function()
  local ok = pcall(function()
    _step_modal_timeout({})
  end)
  check.is_truthy(ok, "modal ports without either close function resolve to nil and no-op")
end)

it("test_does_nothing_when_the_modal_ports_are_not_a_table", function()
  local ok = pcall(function()
    _step_modal_timeout("not-a-table")
  end)
  check.is_truthy(ok, "a non-table modal port resolves to nil and is a no-op")
end)

it("test_does_nothing_when_the_modal_ports_expose_only_close_choice_modal", function()
  -- 超时收屏只消费 close_popup，单独提供 close_choice_modal 不应报错。
  local ok = pcall(function() _step_modal_timeout({ close_choice_modal = function() end }) end)
  check.is_truthy(ok, "on_timeout must not crash when close_popup is absent")
end)

it("test_does_nothing_while_no_popup_is_active", function()
  local closed = false
  local game = support.new_game()
  local state = fixtures.build_loop_state()
  local ports = fixtures.build_test_ports()
  ports.modal.close_popup = function() closed = true end
  state._resolved_gameplay_loop_ports = ports
  state.gameplay_loop_ports = ports
  state.ui.popup_active = false

  modal_timeout.step_default(game, state, 999.0)

  _assert_eq(closed, false, "an inactive popup gate never fires the auto-close")
end)

it("test_falls_back_to_0_when_neither_a_scoped_timeout_nor_a_constants_base_exist", function()
  _with_patches({
    { target = timing, key = "scope_timeouts", value = false },
    { target = constants, key = "action_timeout_seconds", value = nil },
  }, function()
    _assert_eq(_resolve_choice(nil, nil, nil), 0,
      "with no scope table and no constants base the timeout is 0")
  end)
end)

it("test_falls_back_to_the_constants_base_when_scope_timeouts_is_not_a_table", function()
  _with_patches({
    { target = timing, key = "scope_timeouts", value = false },
    { target = constants, key = "action_timeout_seconds", value = 99.0 },
  }, function()
    _assert_eq(_resolve_choice(nil, nil, nil), 99.0,
      "a missing scope_timeouts table falls back to the constants base")
  end)
end)

it("test_fires exactly when elapsed reaches the timeout (the >= boundary)", function()
  local fired = false
  _with_patches({
    { target = constants, key = "action_timeout_seconds", value = 10.0 },
  }, function()
    local state = _output_state(8.0, "ref")
    modal_timeout.step(state, 2.0,
      _active_opts({ on_timeout = function() fired = true end }))
    _assert_eq(fired, true, "8 + 2 == 10 must fire (elapsed >= timeout)")
  end)
end)

it("test_fires_the_modal_popup_auto_close_once_the_gate_timeout_elapses", function()
  local closed = false
  local game = support.new_game()
  local state = fixtures.build_loop_state()
  local ports = fixtures.build_test_ports()
  ports.modal.close_popup = function() closed = true end
  state._resolved_gameplay_loop_ports = ports
  state.gameplay_loop_ports = ports
  -- An active popup with a finite auto-close window drives is_active / get_ref
  -- / get_timeout_seconds in the default modal opts.
  state.ui.popup_active = true
  state.ui.popup_seq = 7
  state.ui.popup_payload = { auto_close_seconds = 5.0 }

  modal_timeout.step_default(game, state, 999.0)

  _assert_eq(closed, true, "an active popup past its auto-close window closes the popup")
end)

it("test_modal_close_cache_rebinds_when_modal_ports_switch_between_games", function()
  local closed = { a = 0, b = 0 }
  local function _dispatch_modal(modal)
    local dispatched
    local game, state, ports = _choice_state({ is_choice_active = function() return true end })
    ports.modal = modal
    _with_patches({
      { target = timing, key = "auto_decision_delay_seconds", value = 0 }, -- force the timeout path
      { target = choice_auto_policy, key = "decide", value = function() return { type = "auto_skip", actor_role_id = 1 } end },
      { target = turn_dispatch, key = "dispatch_action", value = function(_, _, action, opts)
          dispatched = { action = action, opts = opts }
          return true
        end },
    }, function()
      ChoiceTimeout.step_default(game, state, 999.0)
    end)
    return dispatched and dispatched.opts or nil
  end

  local modal_a = { close_choice_modal = function() closed.a = closed.a + 1 end }
  local modal_b = { close_choice_modal = function() closed.b = closed.b + 1 end }

  local opts_a = _dispatch_modal(modal_a)
  check.is_not_nil(opts_a, "the first game's timeout dispatch reaches the close-choice path")
  opts_a.on_close_choice({})
  check.is_truthy(closed.a == 1 and closed.b == 0, "game A's timeout close reaches A's modal")

  local opts_b = _dispatch_modal(modal_b)
  check.is_not_nil(opts_b, "the second game's timeout dispatch still wires the close-choice path")
  opts_b.on_close_choice({})
  check.is_truthy(closed.a == 1 and closed.b == 1,
    "game B must rebind the cached closure to B's modal, never close A's")

  local opts_a2 = _dispatch_modal(modal_a)
  check.is_not_nil(opts_a2, "returning to A's port reference still dispatches through the close-choice path")
  opts_a2.on_close_choice({})
  check.is_truthy(closed.a == 2 and closed.b == 1,
    "returning to A's port reference rebinds the cache to A again")
end)

it("test_pulls the pending choice from runtime_state when game/choice are absent", function()
  -- third arm of the _resolve_pending_choice or-chain (state fallback).
  _with_patches({
    { target = timing, key = "scope_timeouts", value = { choice = 15.0, market_buy = 60.0 } },
    { target = runtime_state, key = "get_pending_choice", value = function() return { kind = "market_buy" } end },
  }, function()
    _assert_eq(_resolve_choice(nil, { any = true }, nil), 60.0,
      "a runtime pending market_buy choice resolves the market_buy scope")
  end)
end)

it("test_resolves_modal_ports_through_close_choice_modal_alone_and_wires_on_close_choice", function()
  -- kills _resolve_modal_ports' close_choice_modal arm (L43 type/==/literal x3):
  -- modal ports exposing ONLY close_choice_modal (no close_popup) must still
  -- resolve via the or-guard's first arm, so dispatch carries opts. Invoking
  -- on_close_choice must reach close_choice_modal, killing the `~=` cache guard
  -- (L53) that decides whether the closure is (re)built for this ref.
  local dispatched, closed
  local game, state, ports = _choice_state({ is_choice_active = function() return true end })
  ports.modal = { close_choice_modal = function() closed = true end }
  _with_patches({
    { target = timing, key = "auto_decision_delay_seconds", value = 0 },
    { target = choice_auto_policy, key = "decide", value = function() return { type = "auto_skip", actor_role_id = 1 } end },
    { target = turn_dispatch, key = "dispatch_action", value = function(_, _, action, opts)
        dispatched = { action = action, opts = opts }
        return true
      end },
  }, function()
    ChoiceTimeout.step_default(game, state, 999.0)
  end)
  check.is_not_nil(dispatched, "the auto action dispatches")
  check.is_not_nil(dispatched.opts,
    "modal ports with only close_choice_modal still resolve (the or-guard's first arm)")
  check.is_truthy(type(dispatched.opts.on_close_choice) == "function",
    "a fresh modal ref wires the on_close_choice closure (the ~= cache guard)")
  dispatched.opts.on_close_choice({})
  _assert_eq(closed, true, "invoking on_close_choice routes to modal close_choice_modal")
end)

it("test_the choice min-visible defaults to 0 when the delay is unset", function()
  -- delay 未配置 → min_visible=0:未达超时前不得派出任何动作。
  local dispatched = {}
  local game, state = _choice_state({ is_choice_active = function() return true end })
  _with_patches({
    { target = timing, key = "auto_decision_delay_seconds", value = nil },
    { target = timing, key = "scope_timeouts", value = { choice = 99.0 } },
    { target = turn_dispatch, key = "dispatch_action", value = function(_, _, action)
        dispatched[#dispatched + 1] = action
        return true
      end },
  }, function()
    ChoiceTimeout.step_default(game, state, 0.5)
  end)
  _assert_eq(#dispatched, 0, "an unset auto-decision delay yields no min-visible dispatch")
end)

it("test_the choice min-visible reads the configured auto-decision delay", function()
  -- #602:策略导出退役后,经公开 step_default 驱动默认装配——delay=0.7 时
  -- elapsed 跨过 0.7 必须派出 tick_min_visible 动作。
  local dispatched = {}
  local game, state = _choice_state({ is_choice_active = function() return true end })
  _with_patches({
    { target = timing, key = "auto_decision_delay_seconds", value = 0.7 },
    { target = timing, key = "scope_timeouts", value = { choice = 99.0 } },
    { target = turn_dispatch, key = "dispatch_action", value = function(_, _, action)
        dispatched[#dispatched + 1] = action
        return true
      end },
    { target = choice_auto_policy, key = "decide", value = function()
        return { type = "choice_select", choice_id = 1, option_id = 1, actor_role_id = 1 }
      end },
  }, function()
    ChoiceTimeout.step_default(game, state, 0.8)
  end)
  check.is_truthy(#dispatched >= 1, "crossing the configured delay must dispatch a min-visible action")
end)

it("test_treats_a_negative_scoped_timeout_as_unset", function()
  _with_patches({
    { target = timing, key = "scope_timeouts", value = { choice = 15.0, neg_kind = -5.0 } },
  }, function()
    _assert_eq(_resolve_choice(nil, nil, { kind = "neg_kind" }), 15.0,
      "a negative scoped timeout falls back to the choice scope")
  end)
end)

it("test_treats_a_nil_dt_as_a_zero_increment", function()
  _with_patches({
    { target = constants, key = "action_timeout_seconds", value = 10.0 },
  }, function()
    local state, syncs = _output_state(2.0, "ref")
    modal_timeout.step(state, nil, _active_opts())
    local last = syncs[#syncs]
    _assert_eq(last.elapsed_seconds, 2.0, "a nil dt adds 0 to the elapsed time")
  end)
end)

it("test_treats_a_non_numeric_scoped_timeout_as_unset", function()
  _with_patches({
    { target = timing, key = "scope_timeouts", value = { choice = 15.0, bad_kind = "soon" } },
  }, function()
    _assert_eq(_resolve_choice(nil, nil, { kind = "bad_kind" }), 15.0,
      "a non-numeric scoped timeout falls back to the choice scope")
  end)
end)

-- #603 modal 引用缓存钉:dispatch 时挂的 on_close_choice 必须绑定当局 modal
-- 端口。模块级缓存按端口引用比较重绑，两局端口引用交替不得串局。
it("test_treats_a_zero_scoped_timeout_as_unset_and_falls_back_to_the_choice_scope", function()
  -- _positive_numeric's `> 0` boundary: a kind whose scope value is 0 must
  -- fall through to scope_timeouts.choice rather than returning 0.
  _with_patches({
    { target = timing, key = "scope_timeouts", value = { choice = 15.0, zero_kind = 0 } },
  }, function()
    _assert_eq(_resolve_choice(nil, nil, { kind = "zero_kind" }), 15.0,
      "a 0 scoped timeout is not positive and yields the choice scope")
  end)
end)

it("test_uses scope_timeouts.choice when the kind-specific scope is absent", function()
  -- kills the second or-arm (`or _positive_numeric(scope_timeouts.choice)` ->
  -- nil): an unmatched kind must still fall back to the choice scope, not the
  -- constants base. constants is set to a distinct value so the arms diverge.
  _with_patches({
    { target = timing, key = "scope_timeouts", value = { choice = 15.0 } },
    { target = constants, key = "action_timeout_seconds", value = 99.0 },
  }, function()
    _assert_eq(_resolve_choice(nil, nil, { kind = "no_such_kind" }), 15.0,
      "a missing kind scope resolves scope_timeouts.choice, not the constants base")
  end)
end)

it("test_uses_the_constants_base_when_opts_carries_no_timeout_override", function()
  local fired = false
  _with_patches({
    { target = constants, key = "action_timeout_seconds", value = 4.0 },
  }, function()
    local state = _output_state(3.0, "ref")
    modal_timeout.step(state, 2.0,
      _active_opts({ on_timeout = function() fired = true end }))
    _assert_eq(fired, true, "3 + 2 >= the constants base 4 fires the timeout")
  end)
end)

it("test_zeroes_the_elapsed_time_in_the_reset_synced_when_the_timeout_fires", function()
  -- kills _handle_modal_timeout's `elapsed_seconds = 0` -> `= 1`: the fire-path
  -- reset payload (the last sync) must carry elapsed 0.
  _with_patches({
    { target = constants, key = "action_timeout_seconds", value = 4.0 },
  }, function()
    local state, syncs = _output_state(3.0, "ref")
    modal_timeout.step(state, 2.0, _active_opts())
    _assert_eq(syncs[#syncs].elapsed_seconds, 0,
      "the timeout-fire reset zeroes elapsed_seconds")
  end)
end)


end)
