local check = require("luassert")
local support = require("test.support.shared_support")
local _new_game = support.new_game
local dispatch_validator = require("src.turn.actions.validator")
local land = require("src.turn.phases.land")
local phase = require("src.rules.items.phase")

local build_wait_choice_args = phase.build_wait_choice_args

-- Helper functions for CRAP coverage tests
local function _crap_assert_eq(a, b, msg)
  check.equal(a, b, tostring(msg) .. ": expected " .. tostring(b) .. " got " .. tostring(a))
end

local function _crap_assert_not_nil(a, msg)
  check.is_not_nil(a, tostring(msg) .. ": expected non-nil got nil")
end

local function _crap_assert_table(a, msg)
  check.is_table(a, tostring(msg) .. ": expected table got " .. type(a))
end

describe("TestPhaseTransitions", function()

it("test_build_wait_choice_args_missing_resume_next_state_asserts", function()
  local meta = {
    resume_next_args = { some = "args" },
  }

  local ok, err = pcall(function()
    build_wait_choice_args(meta)
  end)

  check.is_truthy(not ok, "should have raised an error")
  check.is_truthy(err and string.find(err, "resume_next_state"), "error should mention resume_next_state")
end)

it("test_build_wait_choice_args_next_args_from_resume", function()
  local args_table = { player_id = 2, amount = 5000 }
  local meta = {
    resume_next_state = "payment_state",
    resume_next_args = args_table,
  }
  local result = build_wait_choice_args(meta)

  _crap_assert_eq(result.next_args, args_table, "next_args should be resume_next_args")
  _crap_assert_eq(result.next_args.player_id, 2, "next_args.player_id should be preserved")
  _crap_assert_eq(result.next_args.amount, 5000, "next_args.amount should be preserved")
end)

it("test_build_wait_choice_args_next_args_nil_when_absent", function()
  local meta = {
    resume_next_state = "some_state",
  }
  local result = build_wait_choice_args(meta)

  _crap_assert_eq(result.next_args, nil, "next_args should be nil when resume_next_args is nil")
end)

it("test_build_wait_choice_args_next_args_nil_when_explicit", function()
  local meta = {
    resume_next_state = "some_state",
    resume_next_args = nil,
  }
  local result = build_wait_choice_args(meta)

  _crap_assert_eq(result.next_args, nil, "next_args should be nil when resume_next_args is explicitly nil")
end)

it("test_build_wait_choice_args_next_state_from_meta", function()
  local meta = {
    resume_next_state = "target_state_123",
    resume_next_args = nil,
  }
  local result = build_wait_choice_args(meta)

  _crap_assert_eq(result.next_state, "target_state_123", "next_state should equal resume_next_state")
end)

it("test_build_wait_choice_args_nil_meta_asserts", function()
  local ok, err = pcall(function()
    build_wait_choice_args(nil)
  end)

  check.is_truthy(not ok, "nil meta should raise error")
  check.is_truthy(err and string.find(err, "resume_next_state"), "error should mention resume_next_state")
end)

it("test_build_wait_choice_args_resume_next_args_false", function()
  local meta = {
    resume_next_state = "some_state",
    resume_next_args = false,
  }
  local result = build_wait_choice_args(meta)

  _crap_assert_eq(result.next_args, nil, "next_args should be nil when resume_next_args is false")
end)

it("test_build_wait_choice_args_returns_table_with_keys", function()
  local meta = {
    resume_next_state = "some_state",
    resume_next_args = { arg1 = "value1" },
  }
  local result = build_wait_choice_args(meta)

  _crap_assert_table(result, "result should be table")
  _crap_assert_not_nil(result.next_state, "result.next_state should exist")
  _crap_assert_not_nil(result.next_args, "result.next_args should exist")
end)

it("test_dispatch_validator_validate_choice_actor_match", function()
  local g = _new_game()
  local p1 = g.players[1]
  local choice = { id = 1, owner_role_id = p1.id }
  local action = { type = "choice_select", actor_role_id = p1.id }
  local result = dispatch_validator.validate_choice_actor(g, action, choice)
  check.is_truthy(result == true, "should return true when actor matches owner")
end)

it("test_dispatch_validator_validate_choice_actor_mismatch", function()
  local g = _new_game()
  local p1 = g.players[1]
  local p2 = g.players[2]
  local choice = { id = 1, owner_role_id = p1.id }
  local action = { type = "choice_select", actor_role_id = p2.id }
  local result = dispatch_validator.validate_choice_actor(g, action, choice)
  check.is_truthy(result == false, "should return false when actor does not match owner")
end)

it("test_dispatch_validator_validate_choice_actor_no_actor_id", function()
  local g = _new_game()
  local p1 = g.players[1]
  local choice = { id = 1, owner_role_id = p1.id }
  local action = { type = "choice_select" }
  local result = dispatch_validator.validate_choice_actor(g, action, choice)
  check.is_truthy(result == false, "should return false when action has no actor_role_id")
end)

it("test_dispatch_validator_validate_choice_actor_no_owner", function()
  local g = _new_game()
  local p1 = g.players[1]
  local choice = { id = 1 }
  local action = { type = "choice_select", actor_role_id = p1.id }
  local result = dispatch_validator.validate_choice_actor(g, action, choice)
  check.is_truthy(result == true, "should return true when choice has no owner")
end)

it("test_resolve_wait_state_landing_visual", function()
  -- Test with wait_action_anim=false and no anim but landing visual hold active
  local game = {
    turn = {},
    dirty = {},
  }
local landing_visual_hold = require("src.state.visual_hold")
  landing_visual_hold.hold_state_for_game(game, { duration = 1.0 })
  local next_state = land._resolve_wait_state(game, "post_action", { player = { id = 1 } }, false)
  check.is_truthy(next_state == "wait_landing_visual", "should return wait_landing_visual when landing visual is active")
  landing_visual_hold.release(game)
end)

it("test_resolve_wait_state_move_effect_queue", function()
  -- Test with action_anim_queue containing move_effect
  local game = {
    turn = { action_anim_queue = { { kind = "move_effect" } } },
    dirty = {},
  }
  local next_state, next_args = land._resolve_wait_state(game, "move", { player = { id = 1 } }, false)
  check.is_truthy(next_state == "wait_action_anim", "should return wait_action_anim when queue has move_effect")
  check.is_truthy(next_args.next_state == "wait_choice", "should wrap in wait_choice when wait_action_anim is false")
end)

it("test_resolve_wait_state_no_anim_no_wait", function()
  local game = {
    turn = {},
    dirty = {},
  }
  local next_state, next_args = land._resolve_wait_state(game, "move", { player = { id = 1 } }, false)
  check.is_truthy(next_state == "wait_choice", "should return wait_choice when no action anim and wait_action_anim is false")
  check.is_truthy(next_args.next_state == "move", "should preserve next_state")
end)

it("test_resolve_wait_state_no_anim_wait_action_anim", function()
  local game = {
    turn = {},
    dirty = {},
  }
  local next_state = land._resolve_wait_state(game, "move", { player = { id = 1 } }, true)
  check.is_truthy(next_state == "move", "should return next_state when no action anim and wait_action_anim is true")
end)

it("test_resolve_wait_state_prefers_anim", function()
  local game = {
    turn = { action_anim = { kind = "test" } },
    dirty = {},
  }
local landing_visual_hold = require("src.state.visual_hold")
  landing_visual_hold.hold_state_for_game(game, { duration = 1.0 })
  local next_state, next_args = land._resolve_wait_state(game, "post_action", { player = { id = 1 } }, true)
  check.is_truthy(next_state == "wait_landing_visual", "should route through landing_visual first when both hold and action_anim active")
  check.is_truthy(next_args.next_state == "wait_action_anim", "landing_visual should chain into wait_action_anim")
  landing_visual_hold.release(game)
end)

it("test_resolve_wait_state_wait_move_anim_drains_pending_action_anim_first", function()
  -- wait_move_anim should drain pending action_anim first so chance card popup
  -- gets its dwell window before the stepwise move begins
  local game = {
    turn = {
      action_anim = { kind = "chance", seq = 1, duration = 1.0 },
      move_anim = { kind = "chance_move", seq = 9, player_id = 3 },
    },
    dirty = {},
  }
  local next_state, next_args = land._resolve_wait_state(
    game, "move_followup", { mode = "resolve_landing", player_id = 3 }, false, true
  )
  check.is_truthy(next_state == "wait_action_anim",
    "wait_move_anim with pending action_anim should route through wait_action_anim first")
  check.is_truthy(next_args.next_state == "wait_move_anim",
    "wait_action_anim wrapper should chain into wait_move_anim")
  check.is_truthy(next_args.next_args.next_state == "move_followup",
    "wrapped wait_move_anim args should preserve original move_followup target")
  check.is_truthy(game.turn.move_followup_pending == true,
    "wait_move_anim with move_followup target should set move_followup_pending eagerly")
end)

it("test_resolve_wait_state_wait_move_anim_routes_with_followup_pending", function()
  -- wait_move_anim flag should route directly to wait_move_anim state regardless of action_anim queue
  local game = {
    turn = { move_anim = { kind = "chance_move", seq = 7, player_id = 1 } },
    dirty = {},
  }
  local next_state, next_args = land._resolve_wait_state(
    game, "move_followup", { mode = "resolve_landing", player_id = 1 }, false, true
  )
  check.is_truthy(next_state == "wait_move_anim", "wait_move_anim flag should win over wait_action_anim/has_anim checks")
  check.is_truthy(next_args.next_state == "move_followup", "wait_move_anim should preserve next_state")
  check.is_truthy(game.turn.move_followup_pending == true, "wait_move_anim with move_followup should set move_followup_pending")
end)

it("test_resolve_wait_state_wait_move_anim_skips_followup_flag_for_non_followup", function()
  -- wait_move_anim with non-move_followup next_state should not flip move_followup_pending
  local game = {
    turn = { move_anim = { kind = "chance_move", seq = 8, player_id = 2 } },
    dirty = {},
  }
  land._resolve_wait_state(game, "post_action", { player = { id = 2 } }, false, true)
  check.is_truthy(game.turn.move_followup_pending ~= true,
    "wait_move_anim should not set move_followup_pending when next_state is not move_followup")
end)

it("test_resolve_wait_state_with_action_anim_queue", function()
  local game = {
    turn = { action_anim_queue = { { kind = "move_effect" } } },
    dirty = {},
  }
  local next_state = land._resolve_wait_state(game, "post_action", { player = { id = 1 } }, false)
  check.is_truthy(next_state == "wait_action_anim", "should return wait_action_anim when action anim queue has items")
end)

it("test_resolve_wait_state_with_action_anim_wait_action_anim", function()
  local game = {
    turn = { action_anim = { kind = "test" } },
    dirty = {},
  }
  local next_state, next_args = land._resolve_wait_state(game, "move", { player = { id = 1 } }, true)
  check.is_truthy(next_state == "wait_action_anim", "should return wait_action_anim when action anim exists")
  check.is_truthy(next_args.next_state == "move", "should preserve next_state in args")
end)


end)
