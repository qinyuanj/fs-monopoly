local check = require("luassert")
local ChoiceTimeout = require("src.turn.waits.choice_timeout")
local modal_timeout = require("src.turn.waits.modal_timeout")
local timing = require("src.config.gameplay.timing")

local _config_reset = require("test.support.config_reset")

local function _assert_eq(a, b, msg)
  check.equal(a, b, tostring(msg) .. ": expected " .. tostring(b) .. " got " .. tostring(a))
end

describe("TestTickTimeout", function()

before_each(function()
  _config_reset.reset_all()
end)

it("test_resolve_choice_timeout choice from game.turn", function()
  local choice = { kind = "market_buy" }
  local game = { turn = { pending_choice = choice } }
  local timeout = ChoiceTimeout.resolve_choice_timeout_seconds(game, nil, nil)
  local expected = timing.scope_timeouts.market_buy
  _assert_eq(timeout, expected, "choice from game.turn should use scope_timeouts.market_buy")
end)

it("test_resolve_choice_timeout_market_buy_doubles", function()
  local choice = { kind = "market_buy" }
  local timeout = ChoiceTimeout.resolve_choice_timeout_seconds(nil, nil, choice)
  local expected = timing.scope_timeouts.market_buy
  _assert_eq(timeout, expected, "market_buy should use scope_timeouts.market_buy")
end)

it("test_resolve_choice_timeout_no_choice_returns_base", function()
  local timeout = ChoiceTimeout.resolve_choice_timeout_seconds(nil, nil, nil)
  local expected = timing.scope_timeouts.choice
  _assert_eq(timeout, expected, "no choice should return scope_timeouts.choice")
end)

it("test_resolve_choice_timeout_non_market_buy_returns_base", function()
  local choice = { kind = "item_phase_passive" }
  local timeout = ChoiceTimeout.resolve_choice_timeout_seconds(nil, nil, choice)
  local expected = timing.scope_timeouts.choice
  _assert_eq(timeout, expected, "non-market_buy choice should use scope_timeouts.choice")
end)

it("test_step_modal_timeout_active_updates_elapsed", function()
  local last_sync = nil
  local elapsed = 0
  local output_ports = {
    get_modal_elapsed = function() return elapsed end,
    get_modal_ref = function() return "ref1" end,
    sync_modal_timer = function(_, payload) last_sync = payload; if payload.elapsed_seconds then elapsed = payload.elapsed_seconds end end,
  }
  local state = { gameplay_loop_ports = { output = output_ports } }
  modal_timeout.step(state, 0.5, {
    get_timeout_seconds = function() return 10 end,
    is_active = function() return true end,
    get_ref = function() return "ref1" end,
    on_timeout = function() error("should not timeout") end,
  })
  check.is_not_nil(last_sync, "sync_modal_timer should be called")
  _assert_eq(last_sync.elapsed_seconds, 0.5, "elapsed should be updated")
end)

it("test_step_modal_timeout_asserts_opts_presence_with_guard_messages", function()
  -- kills _assert_modal_opts' four message -> nil mutants. The default
  -- timeout (constants.action_timeout_seconds = 15) is positive, so the
  -- assert runs before is_active is consulted.
  local output_ports = {
    get_modal_elapsed = function() return 0 end,
    get_modal_ref = function() return nil end,
    sync_modal_timer = function() end,
  }
  local state = { gameplay_loop_ports = { output = output_ports } }
  check.has_error(function()
    modal_timeout.step(state, 0.1, nil)
  end, "missing opts")
  check.has_error(function()
    modal_timeout.step(state, 0.1, {})
  end, "missing opts.is_active")
  check.has_error(function()
    modal_timeout.step(state, 0.1, { is_active = function() return true end })
  end, "missing opts.on_timeout")
  check.has_error(function()
    modal_timeout.step(state, 0.1, {
      is_active = function() return true end,
      on_timeout = function() end,
    })
  end, "missing opts.get_ref")
end)

it("test_step_modal_timeout_fires_on_timeout", function()
  local timed_out = false
  local elapsed_val = 9.0
  local output_ports = {
    get_modal_elapsed = function() return elapsed_val end,
    get_modal_ref = function() return "ref1" end,
    sync_modal_timer = function(_, payload) if payload.elapsed_seconds then elapsed_val = payload.elapsed_seconds end end,
  }
  local state = { gameplay_loop_ports = { output = output_ports } }
  modal_timeout.step(state, 2.0, {
    get_timeout_seconds = function() return 10 end,
    is_active = function() return true end,
    get_ref = function() return "ref1" end,
    on_timeout = function() timed_out = true end,
  })
  _assert_eq(timed_out, true, "on_timeout should fire when elapsed >= timeout")
end)

it("test_step_modal_timeout_inactive_clears_timer", function()
  local synced = nil
  local output_ports = {
    get_modal_elapsed = function() return 0 end,
    get_modal_ref = function() return nil end,
    sync_modal_timer = function(_, payload) synced = payload end,
  }
  local state = { gameplay_loop_ports = { output = output_ports } }
  modal_timeout.step(state, 0.1, {
    get_timeout_seconds = function() return 5 end,
    is_active = function() return false end,
    get_ref = function() return "ref1" end,
    on_timeout = function() end,
  })
  check.is_not_nil(synced, "sync_modal_timer should be called when inactive")
end)

it("test_step_modal_timeout_new_ref_resets_timer", function()
  local syncs = {}
  local output_ports = {
    get_modal_elapsed = function() return 5 end,
    get_modal_ref = function() return "old_ref" end,
    sync_modal_timer = function(_, payload) syncs[#syncs + 1] = payload end,
  }
  local state = { gameplay_loop_ports = { output = output_ports } }
  modal_timeout.step(state, 0.1, {
    get_timeout_seconds = function() return 10 end,
    is_active = function() return true end,
    get_ref = function() return "new_ref" end,
    on_timeout = function() end,
  })
  -- First sync should reset elapsed to 0 (new ref), then update
  check.is_truthy(#syncs >= 1, "should have sync calls")
  _assert_eq(syncs[1].ref, "new_ref", "first sync should be with new ref")
  _assert_eq(syncs[1].elapsed_seconds, 0, "new ref should reset elapsed to 0")
end)

it("test_step_modal_timeout_zero_timeout_clears_timer", function()
  local synced = nil
  local output_ports = {
    get_modal_elapsed = function() return 0 end,
    get_modal_ref = function() return nil end,
    sync_modal_timer = function(_, payload) synced = payload end,
  }
  local state = { gameplay_loop_ports = { output = output_ports } }
  modal_timeout.step(state, 0.1, {
    get_timeout_seconds = function() return 0 end,
    is_active = function() return true end,
    get_ref = function() return "ref1" end,
    on_timeout = function() end,
  })
  check.is_not_nil(synced, "sync_modal_timer should be called")
end)

end)
