-- luacheck: ignore 211
local luassert = assert
local support = require("test.support.shared_support")
local shared_support = require("test.support.shared_support")

local bankruptcy_feedback_port = require("src.rules.ports.bankruptcy_feedback")
local turn_action_port = require("src.ui.input.turn_action")
local gameplay_loop_ports = require("src.turn.loop.ports")
local gameplay_loop_runtime = require("src.turn.loop.runtime")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local turn_roll = require("src.turn.phases.roll")
local turn_move = require("src.turn.phases.move")

describe("TestUsecaseBoundary", function()
  after_each(function()
    support.restore_runtime_services()
  end)

  it("test_turn_action_port_resolve_defaults", function()
  local resolved = turn_action_port.resolve({}, nil)
  local res = resolved.dispatch_action({}, {}, { type = "noop" }, {})
  luassert.is.equal("rejected", res.status, "default dispatch_action should reject")
  luassert.is.equal(false, resolved.should_block_action({}, { type = "noop" }),
    "default should_block_action should be false")
  end)

  it("test_turn_action_port_override_precedence", function()
  local calls = 0
  local state = {
    turn_action_port = {
      dispatch_action = function()
        calls = calls + 1
        return { status = "state" }
      end,
      should_block_action = function()
        return false
      end,
    },
  }
  local resolved = turn_action_port.resolve(state, {
    turn_action_port = {
      dispatch_action = function()
        calls = calls + 1
        return { status = "override" }
      end,
      should_block_action = function()
        return true
      end,
    },
  })
  local res = resolved.dispatch_action({}, {}, { type = "noop" }, {})
  luassert.is.equal("override", res.status, "override port should take precedence over state port")
  -- lint-allow: call-count 端口覆写契约:覆写实现被调用恰一次(或不被调用)
  luassert.is.equal(1, calls, "dispatch should call override implementation once")
  luassert.is.equal(true, resolved.should_block_action({}, { type = "noop" }),
    "override should_block_action should take precedence")
  end)

  it("test_turn_action_port_normalize_auto_intent_contract", function()
  local state = {}
  local intent = { type = "ui_button", id = "auto", actor_role_id = 7 }
  support.with_patches({
    { target = turn_action_port, key = "normalize_auto_intent", value = turn_action_port.normalize_auto_intent },
    { key = "UIManager", value = { client_role = nil } },
  }, function()
    local out = turn_action_port.normalize_auto_intent(state, intent)
    luassert.is.equal("ui_button", out.type, "normalize should preserve type")
    luassert.is.equal("auto", out.id, "normalize should preserve button id")
    luassert.is.equal(7, out.actor_role_id, "normalize should preserve actor role fallback")
  end)
  end)

  it("test_turn_action_port_normalize_auto_intent_rejects_missing_actor", function()
  local state = {}
  local intent = { type = "ui_button", id = "auto" }
  support.with_patches({
    { key = "UIManager", value = { client_role = nil } },
  }, function()
    local out = turn_action_port.normalize_auto_intent(state, intent)
    luassert.is.equal(nil, out, "normalize should reject auto intent without actor context")
  end)
  end)

  it("test_gameplay_loop_clock_contract_split_sources", function()
  runtime_ports.reset_for_tests()
  local default_ports = gameplay_loop_ports.resolve(nil)
  local default_clock = default_ports.clock
  luassert.is.equal(0, default_clock.wall_now_seconds(), "default wall clock should be environment-agnostic zero fallback")
  -- #210：基础 clock 委派 runtime_ports，未装配宿主时钟时 diff 也返回 0（不再算术兜底）。
  luassert.is.equal(0, default_clock.wall_diff_seconds(9, 7), "default wall diff should follow unconfigured runtime port zero")
  luassert.is.equal(0, default_clock.cpu_now_seconds(), "default cpu clock should be environment-agnostic zero fallback")
  luassert.is.equal(0, default_clock.cpu_diff_seconds(9, 7), "default cpu diff should follow unconfigured runtime port zero")

  runtime_ports.configure({
    wall_now_seconds = function() return 42 end,
    wall_diff_seconds = function(a, b) return (a - b) * 10 end,
    cpu_now_seconds = function() return 1.5 end,
    cpu_diff_seconds = function(a, b) return a - b end,
  })
  local injected_ports = gameplay_loop_ports.resolve({
    clock = {
      wall_now_seconds = function()
        return runtime_ports.wall_now_seconds()
      end,
      wall_diff_seconds = function(a, b)
        return runtime_ports.wall_diff_seconds(a, b)
      end,
      cpu_now_seconds = function()
        return runtime_ports.cpu_now_seconds()
      end,
      cpu_diff_seconds = function(a, b)
        return runtime_ports.cpu_diff_seconds(a, b)
      end,
    },
  })
  local clock = injected_ports.clock
  luassert.is.equal(42, clock.wall_now_seconds(), "injected wall clock should be used when provided")
  luassert.is.equal(20, clock.wall_diff_seconds(9, 7), "injected wall diff should preserve injected semantics")
  luassert.is.equal(1.5, clock.cpu_now_seconds(), "injected cpu clock should be used when provided")
  luassert.is.equal(2, clock.cpu_diff_seconds(9, 7), "injected cpu diff should remain arithmetic")
  runtime_ports.reset_for_tests()
  end)

  it("test_choice_contract_copies_explicit_fields_once", function()
  local choice_contract = require("src.config.choice.contract")
  local source = {
    route_key = "target",
    requires_confirm = true,
    pre_confirm_on_select = false,
    owner_role_id = 8,
    confirm_title = "请确认",
    confirm_body = "你选的是：A",
    uses_item_slots = false,
    pre_confirm_before_slot_pick = false,
    active_tab = "item",
    page_index = 2,
    page_count = 3,
    phase = "pre_action",
    queue = { 2, 3 },
    effect_ids = { "buy_land" },
    move_result = { next_state = "wait_choice" },
  }
  local target = {}
  choice_contract.copy_explicit_fields(source, target)
  luassert.is.equal("target", target.route_key, "contract should copy route_key")
  luassert.is.equal(false, target.pre_confirm_on_select, "contract should copy select pre-confirm flag")
  luassert.is.equal(8, target.owner_role_id, "contract should copy owner_role_id")
  luassert.is.equal(3, target.page_count, "contract should copy market paging fields")
  luassert.is.equal(nil, target.phase, "contract should keep phase in meta")
  luassert.is.equal(nil, target.queue, "contract should keep queue in meta")
  luassert.is.equal(nil, target.effect_ids, "contract should keep effect_ids in meta")
  luassert.is.equal(nil, target.move_result, "contract should keep move_result in meta")
  end)

  it("test_gameplay_loop_output_port_defaults_to_ui_runtime_only", function()
  local resolved = gameplay_loop_ports.resolve(nil)
  local state = {}
  local changed = resolved.output.invalidate_ui_model(state)
  luassert.is.equal(true, changed, "default output.invalidate_ui_model should mark ui_runtime dirty")
  luassert.is.equal(nil, state.ui_dirty, "default output.invalidate_ui_model should not mark legacy state.ui_dirty")
  luassert.is.equal(true, state.ui_runtime and state.ui_runtime.ui_dirty,
    "default output.invalidate_ui_model should write ui_runtime")
  local changed_again = resolved.output.invalidate_ui_model(state)
  luassert.is.equal(false, changed_again,
    "default output.invalidate_ui_model should be idempotent when ui_runtime already dirty")
  end)

  it("test_output_state_adapter_exposes_invalidate_ui_model_only", function()
  local output_state_adapter = require("src.turn.output.state_adapter")
  local output = output_state_adapter.build_runtime_output_ports()
  local state = {}
  local changed = output.invalidate_ui_model(state)
  luassert.is.equal(true, changed, "runtime output.invalidate_ui_model should mark ui_runtime dirty")
  luassert.is.equal(true, state.ui_runtime and state.ui_runtime.ui_dirty,
    "invalidate_ui_model should write ui_runtime dirty state")
  end)

  it("test_gameplay_loop_output_port_override_precedence", function()
  local calls = 0
  local resolved = gameplay_loop_ports.resolve({
    output = {
      invalidate_ui_model = function(state)
        calls = calls + 1
        state.override_called = true
        return true
      end,
    },
  })
  local state = {}
  local changed = resolved.output.invalidate_ui_model(state)
  luassert.is.equal(true, changed, "override output.invalidate_ui_model should return override result")
  -- lint-allow: call-count 端口覆写契约:覆写实现被调用恰一次(或不被调用)
  luassert.is.equal(1, calls, "override output.invalidate_ui_model should be called once")
  luassert.is.equal(true, state.override_called, "override output.invalidate_ui_model should receive state")
  luassert.is.equal(nil, state.ui_dirty, "override output.invalidate_ui_model should bypass default ui_dirty bridge")
  end)

  it("test_gameplay_loop_output_port_override_requires_invalidate_ui_model", function()
  local calls = 0
  local resolved = gameplay_loop_ports.resolve({
    output = {
      invalidate_ui_model = function(state)
        calls = calls + 1
        state.override_called = true
        return true
      end,
    },
  })
  local state = {}
  local changed = resolved.output.invalidate_ui_model(state)
  luassert.is.equal(true, changed, "invalidate_ui_model override should satisfy invalidate_ui_model")
  -- lint-allow: call-count 端口覆写契约:覆写实现被调用恰一次(或不被调用)
  luassert.is.equal(1, calls, "invalidate_ui_model override should be called once")
  luassert.is.equal(true, state.override_called, "invalidate_ui_model override should receive state")
  end)

  it("test_sync_input_blocked_does_not_invalidate_ui_model_on_unblock", function()
  local state = {
    ui = {
      input_blocked = true,
    },
  }
  local invalidations = 0
  local ports = {
    ui_sync = {
      get_ui_state = function()
        return state.ui
      end,
      set_input_blocked = function(_, blocked)
        state.ui.input_blocked = blocked
        return true
      end,
    },
    output = {
      invalidate_ui_model = function()
        invalidations = invalidations + 1
        return true
      end,
    },
  }

  local changed = gameplay_loop_runtime.sync_input_blocked(state, "wait_action", ports)

  luassert.is.equal(true, changed, "sync_input_blocked should still report a changed gate state")
  luassert.is.equal(false, state.ui.input_blocked, "sync_input_blocked should release input block outside blocked phases")
  -- lint-allow: call-count 端口覆写契约:覆写实现被调用恰一次(或不被调用)
  luassert.is.equal(0, invalidations, "sync_input_blocked should not invalidate ui_model on unblock")
  end)

  it("test_bankruptcy_feedback_port_defaults_to_no_op_port", function()
  local game = support.new_game({ ai = {} })
  local player = game.players[1]
  local handled = bankruptcy_feedback_port.on_tiles_cleared(game, player, { 1, 2 })
  luassert.is.equal(false, handled, "default bankruptcy feedback port should be a no-op false fallback")
  end)

  it("test_turn_roll_uses_anim_gate_port_without_ui_port", function()
  local game = support.new_game({ ai = {} })
  local player = game:current_player()
  game.ui_port = nil
  game.anim_gate_port = {
    wait_action_anim = true,
    wait_move_anim = false,
  }

  local next_state, next_args = turn_roll._phase_roll({ game = game }, {
    player = player,
    rolls = { 3 },
    raw_total = 3,
    total = 3,
  })

  luassert.is.equal("wait_action_anim", next_state, "turn_roll should use anim_gate_port when deciding action anim wait")
  luassert.is.equal("roll", next_args.next_state, "turn_roll should resume into roll after action anim")
  luassert.is.equal("roll", game.turn.action_anim.kind, "turn_roll should still queue roll animation")
  end)

  it("test_turn_move_uses_anim_gate_port_without_ui_port", function()
  local game = support.new_game({ ai = {} })
  local player = game:current_player()
  game.ui_port = nil
  game.last_turn = {}
  game.anim_gate_port = {
    wait_action_anim = false,
    wait_move_anim = true,
  }

  local next_state, next_args = turn_move({ game = game }, {
    player = player,
    raw_total = 1,
    total = 1,
  })

  luassert.is.equal("wait_move_anim", next_state, "turn_move should use anim_gate_port when deciding move anim wait")
  luassert.is.equal("move_followup", next_args.next_state, "turn_move should resume into move_followup after move anim")
  luassert.is.equal(player.id, game.turn.move_anim.player_id, "turn_move should still queue move animation")
  luassert.is.equal(nil, game.last_turn.move_result, "turn_move should not publish move_result before move anim completes")
  end)

  it("test_chance_uses_injected_rng_without_lua_api_rand", function()
  local game = support.new_game({ ai = {} })
  local player = game:current_player()
  local chance_idx = game.board:find_first_by_type("chance")
  luassert.is_not_nil(chance_idx, "missing chance tile")
  local chance_tile = game.board:get_tile(chance_idx)
  luassert.is_not_nil(chance_tile, "missing chance tile ref")
  game:update_player_position(player, chance_idx)
  game.anim_gate_port = {
    wait_action_anim = true,
    wait_move_anim = false,
  }
  game.rng = {
    next_int = function(_, min, max)
      luassert.is.equal(1, min, "chance should start rng range at 1")
      luassert.is_true(max > 0, "chance should use a positive rng upper bound")
      return 1
    end,
  }

  local prev_lua_api = LuaAPI
  local lua_api = prev_lua_api or {}
  support.with_patches({
    { key = "LuaAPI", value = lua_api },
    { target = lua_api, key = "rand", value = function()
      error("chance should not call LuaAPI.rand when game.rng exists")
    end },
  }, function()
    shared_support.resolve_landing(game, player, chance_tile, {})
  end)

  luassert.is.equal("chance", game.turn.action_anim and game.turn.action_anim.kind,
    "chance should queue chance anim through injected rng")
  luassert.is.equal(3001, game.turn.action_anim.card_id,
    "chance should deterministically pick the first card from injected rng")
  end)
end)
