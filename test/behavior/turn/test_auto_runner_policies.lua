-- luacheck: std +busted
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local fixtures = require("test.support.gameplay_fixtures")
local _new_game = support.new_game
local _build_loop_state = fixtures.build_loop_state
local runtime_state = require("src.state.runtime")
local gameplay_loop = require("src.turn.loop")
local choice_auto_policy = require("src.turn.policies.choice_auto")
local control = require("src.player.control")

-- Additional tests for choice_auto_policy.decide to reach 100% coverage
describe("TestAutoRunnerPolicies", function()

it("test_log_missing_auto_choice_action_logs_once", function()
  local state = _build_loop_state()
  runtime_state.ensure_debug_runtime(state)
  local ctx = {
    pending_choice = { id = 123, kind = "test_choice" },
    current_player_computer_controlled = true,
  }
  gameplay_loop._log_missing_auto_choice_action(state, ctx)
  gameplay_loop._log_missing_auto_choice_action(state, ctx)
  luassert.truthy(state.debug_runtime.log_once["auto_runner_choice_no_action_123"] == true, "should mark log_once key")
end)
it("test_log_missing_auto_choice_action_skips_when_waiting", function()
  local state = _build_loop_state()
  runtime_state.ensure_debug_runtime(state)
  state.auto_runner.waiting_for_interval = true
  local ctx = {
    pending_choice = { id = 123, kind = "test_choice" },
    current_player_computer_controlled = true,
  }
  gameplay_loop._log_missing_auto_choice_action(state, ctx)
  luassert.truthy(state.debug_runtime.log_once["auto_runner_choice_no_action_123"] == nil, "should not log when waiting for interval")
end)
it("test_log_missing_auto_choice_action_skips_when_not_auto", function()
  local state = _build_loop_state()
  runtime_state.ensure_debug_runtime(state)
  local ctx = {
    pending_choice = { id = 123, kind = "test_choice" },
    current_player_computer_controlled = false,
  }
  gameplay_loop._log_missing_auto_choice_action(state, ctx)
  luassert.truthy(state.debug_runtime.log_once["auto_runner_choice_no_action_123"] == nil, "should not log when not auto")
end)
it("test_choice_auto_policy_wait_choice_not_auto", function()
  local game = _new_game()
  local choice = { id = 1, options = { { id = "opt1" }, { id = "opt2" } } }
  local ctx = { mode = "wait_choice", elapsed_seconds = 0 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result == nil, "should return nil when not auto actor and min_visible not reached")
end)
it("test_choice_auto_policy_preconsumed_item", function()
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  local choice = { id = 1, options = { { id = "opt1" } }, meta = { item_preconsumed = true } }
  local ctx = { mode = "wait_choice", elapsed_seconds = 0, min_visible_seconds = 0 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result ~= nil, "should return action for preconsumed item")
  luassert.truthy(result.type == "choice_select", "should return choice_select action")
  luassert.truthy(result.option_id == "opt1", "should select first option")
end)
it("test_choice_auto_policy_timeout_cancel", function()
  local game = _new_game()
  local choice = { id = 1, options = { { id = "opt1" } }, allow_cancel = true }
  local ctx = { mode = "tick_timeout" }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result ~= nil, "should return action for timeout mode")
  luassert.truthy(result.type == "choice_cancel", "should return choice_cancel when allow_cancel is true")
end)
it("test_choice_auto_policy_min_visible_not_reached", function()
  local game = _new_game()
  local choice = { id = 1, options = { { id = "opt1" }, { id = "opt2" } } }
  -- Test with mode = "wait_choice", not auto, min_visible > 0, elapsed = 0
  local ctx = { mode = "wait_choice", elapsed_seconds = 0, min_visible_seconds = 1 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result == nil, "should return nil when min_visible not reached")
end)
it("test_choice_auto_policy_preconsumed_no_options", function()
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  -- Test with preconsumed item but no options
  local choice = { id = 1, options = {}, meta = { item_preconsumed = true } }
  local ctx = { mode = "wait_choice", elapsed_seconds = 0, min_visible_seconds = 0 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result == nil, "should return nil for preconsumed item with no options")
end)
it("test_choice_auto_policy_tick_min_visible_auto", function()
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  -- Test tick_min_visible mode with auto actor
  local choice = { id = 1, options = { { id = "opt1" } } }
  local ctx = { mode = "tick_min_visible", elapsed_seconds = 1, min_visible_seconds = 0 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result ~= nil, "should return action for tick_min_visible with auto actor")
  luassert.truthy(result.type == "choice_select", "should return choice_select")
end)
it("test_choice_auto_policy_tick_min_visible_not_ready", function()
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  -- Test tick_min_visible mode with elapsed < min_visible
  local choice = { id = 1, options = { { id = "opt1" } } }
  local ctx = { mode = "tick_min_visible", elapsed_seconds = 1, min_visible_seconds = 5 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result == nil, "should return nil when elapsed < min_visible")
end)
it("test_choice_auto_policy_timeout_no_cancel", function()
  local game = _new_game()
  -- Test tick_timeout mode with allow_cancel = false
  local choice = { id = 1, options = { { id = "opt1" } }, allow_cancel = false }
  local ctx = { mode = "tick_timeout" }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result ~= nil, "should return action for timeout without cancel")
  luassert.truthy(result.type == "choice_select", "should fallback to choice_select")
end)
it("test_choice_auto_policy_unknown_mode_fallback", function()
  local game = _new_game()
  -- Test default mode (unknown mode)
  local choice = { id = 1, options = { { id = "opt1" } } }
  local ctx = { mode = "unknown_mode", allow_first_option_fallback = true }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result ~= nil, "should return action for unknown mode with fallback")
  luassert.truthy(result.type == "choice_select", "should return choice_select")
end)
it("test_choice_auto_policy_unknown_mode_no_fallback", function()
  local game = _new_game()
  -- Test default mode without fallback
  local choice = { id = 1, options = { { id = "opt1" } } }
  local ctx = { mode = "unknown_mode", allow_first_option_fallback = false }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result == nil, "should return nil without fallback")
end)
it("test_choice_auto_policy_nil_choice", function()
  local game = _new_game()
  -- Test with nil choice
  local result = choice_auto_policy.decide(game, {}, nil, {})
  luassert.truthy(result == nil, "should return nil for nil choice")
end)
it("test_choice_auto_policy_no_choice_id", function()
  local game = _new_game()
  -- Test with choice but no id
  local choice = { options = { { id = "opt1" } } }
  local result = choice_auto_policy.decide(game, {}, choice, {})
  luassert.truthy(result == nil, "should return nil for choice without id")
end)
it("test_choice_auto_policy_pending_action", function()
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  -- Test with pending_action in context
  local choice = { id = 1, options = { { id = "opt1" } } }
  local pending = { type = "custom_action" }
  local ctx = { mode = "wait_choice", pending_action = pending }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result == pending, "should return pending_action when provided")
end)
it("test_choice_auto_policy_fallback_first_option", function()
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  -- Test auto_play_port returning nil, fallback to first option
  local choice = { id = 1, options = { { id = "opt2" } }, meta = {} }
  local ctx = { mode = "tick_timeout", allow_first_option_fallback = true }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result ~= nil, "should fallback to first option")
  luassert.truthy(result.option_id == "opt2", "should select the actual first option")
end)
it("test_choice_auto_policy_string_option_ids", function()
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  -- Test with option id as string directly (not table)
  local choice = { id = 1, options = { "opt_a", "opt_b" }, meta = { item_preconsumed = true } }
  local ctx = { mode = "wait_choice", elapsed_seconds = 0, min_visible_seconds = 0 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result ~= nil, "should handle string option ids")
  luassert.truthy(result.option_id == "opt_a", "should select first string option")
end)
it("test_choice_auto_policy_resolve_owner_nil_game", function()
  -- Test _resolve_choice_owner returns nil when no game
  local choice = { id = 1, owner_role_id = 1 }
  local result = choice_auto_policy.resolve_choice_owner(nil, choice)
  luassert.truthy(result == nil, "should return nil when no game")
end)
it("test_choice_auto_policy_resolve_owner_from_choice", function()
  local game = _new_game()
  local p1 = game.players[1]
  -- Test _resolve_choice_owner returns player from choice owner_role_id
  local choice = { id = 1, owner_role_id = p1.id }
  local result = choice_auto_policy.resolve_choice_owner(game, choice)
  luassert.truthy(result == p1, "should return player from choice owner_role_id")
end)
it("test_choice_auto_policy_resolve_owner_fallback", function()
  local game = _new_game()
  local p1 = game.players[1]
  -- Test _resolve_choice_owner falls back to current_player
  local choice = { id = 1 }
  local result = choice_auto_policy.resolve_choice_owner(game, choice)
  luassert.truthy(result == p1, "should fallback to current player")
end)
it("test_choice_auto_policy_resolve_owner_no_current", function()
  local game = _new_game()
  game.current_player = function() return nil end
  local choice = { id = 1 }
  local result = choice_auto_policy.resolve_choice_owner(game, choice)
  luassert.truthy(result == nil, "should return nil when no current player")
end)
it("test_choice_auto_policy_min_visible_zero", function()
  local game = _new_game()
  -- Test with min_visible=0 (edge case)
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  local choice = { id = 1, options = { { id = "opt1" } }, meta = { item_preconsumed = true } }
  local ctx = { mode = "wait_choice", elapsed_seconds = 0, min_visible_seconds = 0 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result ~= nil, "should work with min_visible=0")
end)
it("test_choice_auto_policy_non_auto_min_visible_zero", function()
  local game = _new_game()
  -- Test non-auto actor with min_visible <= 0
  local choice = { id = 1, options = { { id = "opt1" } } }
  local ctx = { mode = "wait_choice", elapsed_seconds = 0, min_visible_seconds = 0 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  -- Non-auto actor should still return nil because is_auto_actor is false
  luassert.truthy(result == nil, "non-auto actor should return nil even with min_visible=0")
end)
it("test_choice_auto_policy_preconsumed_string_option", function()
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  -- Test preconsumed item with first option having no id field
  local choice = { id = 1, options = { "direct_string_option" }, meta = { item_preconsumed = true } }
  local ctx = { mode = "wait_choice", elapsed_seconds = 0, min_visible_seconds = 0 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result ~= nil, "should handle string options in preconsumed mode")
  luassert.truthy(result.option_id == "direct_string_option", "should use string as option_id")
end)
it("test_choice_auto_policy_nil_options", function()
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  -- Test choice with nil options
  local choice = { id = 1, options = nil, meta = { item_preconsumed = true } }
  local ctx = { mode = "wait_choice", elapsed_seconds = 0, min_visible_seconds = 0 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result == nil, "should return nil when options is nil")
end)
it("test_choice_auto_policy_empty_options", function()
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  -- Test choice with empty options table
  local choice = { id = 1, options = {}, meta = { item_preconsumed = true } }
  local ctx = { mode = "wait_choice", elapsed_seconds = 0, min_visible_seconds = 0 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result == nil, "should return nil when options is empty")
end)
it("test_choice_auto_policy_negative_elapsed", function()
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  -- Test negative elapsed seconds normalization
  local choice = { id = 1, options = { { id = "opt1" } }, meta = { item_preconsumed = true } }
  local ctx = { mode = "wait_choice", elapsed_seconds = -5, min_visible_seconds = 0 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result ~= nil, "should handle negative elapsed seconds")
end)
it("test_choice_auto_policy_negative_min_visible", function()
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  -- Test negative min_visible seconds normalization
  local choice = { id = 1, options = { { id = "opt1" } }, meta = { item_preconsumed = true } }
  local ctx = { mode = "wait_choice", elapsed_seconds = 0, min_visible_seconds = -1 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result ~= nil, "should handle negative min_visible seconds")
end)

it("test_choice_auto_policy_tick_min_visible_at_boundary", function()
  -- #293:L70 `min_visible <= 0 or elapsed >= min_visible` 的 or->and 与
  -- >=->> 变异在 elapsed == min_visible 达标边界会把自动选择误判成未达标。
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  local choice = { id = 1, options = { { id = "opt1" } } }
  local ctx = { mode = "tick_min_visible", elapsed_seconds = 5, min_visible_seconds = 5 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result ~= nil, "elapsed == min_visible must count as ready")
  luassert.truthy(result.type == "choice_select", "ready auto actor should select first option")
end)

it("test_choice_auto_policy_wait_choice_ready_auto_actor_without_fallback", function()
  -- #293:L105 `_dispatch_auto_actor_mode(..., false, ...)` 的 false->true 变异
  -- 会让 wait_choice 分支在 auto_action 缺失时也做首选项兜底,与 ctx 的
  -- allow_first_option_fallback 缺省(不兜底)行为冲突。
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  local choice = { id = 1, options = { { id = "opt1" } } }
  local ctx = { mode = "wait_choice", elapsed_seconds = 0, min_visible_seconds = 0 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result == nil,
    "wait_choice without explicit fallback must not auto-pick the first option")
end)

it("test_choice_auto_policy_timeout_no_options_force_skips", function()
  -- #293:L100 `type = "choice_force_skip"`(→ nil 变异)在无选项兜底的
  -- tick_timeout 下会产出无 type 的动作,强制跳过路径未测。
  local game = _new_game()
  local choice = { id = 1, options = {} }
  local ctx = { mode = "tick_timeout" }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result ~= nil, "timeout with no options must still dispatch")
  luassert.truthy(result.type == "choice_force_skip",
    "timeout with no fallback options must force-skip; got " .. tostring(result.type))
end)

it("test_choice_auto_policy_negative_elapsed_near_min_visible_stays_unready", function()
  -- #293:L61 `_normalize_visible_seconds` 的 `return 0`(0->1 变异)会把负
  -- elapsed 归一化成 1,使 min_visible=1 的窗口提前达标。
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  local choice = { id = 1, options = { { id = "opt1" } } }
  local ctx = { mode = "tick_min_visible", elapsed_seconds = -1, min_visible_seconds = 1 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result == nil,
    "negative elapsed must normalize to 0 and stay below min_visible=1")
end)

it("test_choice_auto_policy_min_visible_one_stays_unready_at_zero_elapsed", function()
  -- #293:L70 `min_visible <= 0` 的 0->1 变异会把 min_visible=1 的窗口
  -- 判成恒达标,elapsed=0 时提前自动选择。
  local game = _new_game()
  local p1 = game.players[1]
  control.toggle_manual_delegation(p1)
  local choice = { id = 1, options = { { id = "opt1" } } }
  local ctx = { mode = "tick_min_visible", elapsed_seconds = 0, min_visible_seconds = 1 }
  local result = choice_auto_policy.decide(game, {}, choice, ctx)
  luassert.truthy(result == nil,
    "elapsed=0 with min_visible=1 must stay unready")
end)

it("test_new_game_enables_auto_runner_and_builds_item_index", function()
  local enabled_value = "unset"
  local timer_reset = false
  local fake_game = {
    logger = { info = function() end },
    players = { {}, {} },
  }
  local state = {
    game_factory = function() return fake_game end,
    auto_runner = {
      set_enabled = function(_, enabled) enabled_value = enabled end,
      reset_timer = function() timer_reset = true end,
    },
  }
  local game = gameplay_loop.new_game(state)
  luassert.truthy(game == fake_game, "new_game should return the factory-built game")
  luassert.truthy(enabled_value == true, "new_game should enable the auto runner")
  luassert.truthy(timer_reset, "new_game should reset the auto runner timer")
  luassert.truthy(type(state.ui_runtime) == "table", "new_game should build the ui runtime")
  luassert.truthy(state.ui_runtime.item_name_by_id ~= nil, "new_game should populate the item name index")
end)
it("test_new_game_without_set_enabled_still_resets_timer", function()
  local timer_reset = false
  local fake_game = {
    logger = { info = function() end },
    players = {},
  }
  local state = {
    game_factory = function() return fake_game end,
    auto_runner = {
      reset_timer = function() timer_reset = true end,
    },
  }
  local game = gameplay_loop.new_game(state)
  luassert.truthy(game == fake_game, "new_game should return game when set_enabled is absent")
  luassert.truthy(timer_reset, "new_game should still reset timer without set_enabled")
end)
end)
