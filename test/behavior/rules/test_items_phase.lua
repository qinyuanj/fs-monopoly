require("test.bootstrap").install_package_paths()
-- luacheck: ignore 143 (busted injects the verified luassert object)
local luassert = assert
local phase_module = require("src.rules.items.phase")
local support = require("test.support.shared_support")
local item_ids = require("src.config.gameplay.item_ids")
local strategy = require("src.rules.items.strategy")

local function _assert_eq(a, b, msg)
  luassert.truthy(a == b, tostring(msg) .. ": expected " .. tostring(b) .. " got " .. tostring(a))
end

local function _make_game()
  return {
    turn = {},
    dirty = { turn = false, any = false },
  }
end

local function _with_patches(patches, fn)
  local previous = {}
  for index, patch in ipairs(patches) do
    previous[index] = patch.target[patch.key]
    patch.target[patch.key] = patch.value
  end
  local ok, result = pcall(fn)
  for index = #patches, 1, -1 do
    local patch = patches[index]
    patch.target[patch.key] = previous[index]
  end
  if not ok then
    error(result, 0)
  end
  return result
end

local function _reload_with(module_name, overrides, fn)
  local original_module = package.loaded[module_name]
  local originals = {}
  for key, value in pairs(overrides or {}) do
    originals[key] = package.loaded[key]
    package.loaded[key] = value
  end
  package.loaded[module_name] = nil

  local ok, result = pcall(function()
    return fn(require(module_name))
  end)

  package.loaded[module_name] = original_module
  for key, value in pairs(originals) do
    package.loaded[key] = value
  end
  if not ok then
    error(result)
  end
  return result
end

local function _make_auto_game()
  local game = support.new_game()
  local p = game.players[1]
  game.auto_play_port = {
    is_computer_controlled = function() return true end,
  }
  game.intent_output_port = {
    dispatch = function() end,
    open_choice = function() end,
  }
  return game, p
end

local _config_reset = require("test.support.config_reset")



describe("TestDomainItemsPhaseCoverage", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_is_enabled_pre_action_true", function()
    _assert_eq(phase_module.is_enabled("pre_action"), true, "pre_action should be enabled")
  end)

  it("test_is_enabled_pre_move_true", function()
    _assert_eq(phase_module.is_enabled("pre_move"), true, "pre_move should be enabled")
  end)

  it("test_is_enabled_post_action_true", function()
    _assert_eq(phase_module.is_enabled("post_action"), true, "post_action should be enabled")
  end)

  it("test_is_enabled_unknown_false", function()
    _assert_eq(phase_module.is_enabled("unknown_phase"), false, "unknown phase should not be enabled")
  end)

  it("test_is_enabled_nil_false", function()
    _assert_eq(phase_module.is_enabled(nil), false, "nil phase should not be enabled")
  end)

  it("test_is_repeatable_pre_action_true", function()
    _assert_eq(phase_module.is_repeatable("pre_action"), true, "pre_action should be repeatable")
  end)

  it("test_is_repeatable_pre_move_true", function()
    _assert_eq(phase_module.is_repeatable("pre_move"), true, "pre_move should be repeatable")
  end)

  it("test_is_repeatable_post_action_true", function()
    _assert_eq(phase_module.is_repeatable("post_action"), true, "post_action should be repeatable")
  end)

  it("test_is_repeatable_unknown_false", function()
    _assert_eq(phase_module.is_repeatable("other"), false, "unknown phase should not be repeatable")
  end)

  it("test_finish_marks_phase_done", function()
    local game = _make_game()
    phase_module.finish(game, "pre_action")
    luassert.truthy(game.turn.item_phase, "item_phase should be initialized")
    _assert_eq(game.turn.item_phase.pre_action.done, true, "done should be true")
    _assert_eq(game.dirty.turn, true, "dirty.turn should be set")
    _assert_eq(game.dirty.any, true, "dirty.any should be set")
  end)

  it("test_finish_clears_item_phase_active_when_matches", function()
    local game = _make_game()
    game.turn.item_phase_active = "pre_action"
    phase_module.finish(game, "pre_action")
    _assert_eq(game.turn.item_phase_active, "", "item_phase_active should be cleared when phase matches")
  end)

  it("test_finish_does_not_clear_active_when_different_phase", function()
    local game = _make_game()
    game.turn.item_phase_active = "pre_move"
    phase_module.finish(game, "pre_action")
    _assert_eq(game.turn.item_phase_active, "pre_move", "item_phase_active should not be cleared when phase differs")
  end)

  it("test_build_wait_choice_args_extracts_next_state_from_meta", function()
    local meta = { resume_next_state = "move", resume_next_args = { x = 1 } }
    local result = phase_module.build_wait_choice_args(meta)
    _assert_eq(result.next_state, "move", "should return resume_next_state")
  end)

  it("test_build_wait_choice_args_errors_on_nil_meta", function()
    local ok = pcall(function() phase_module.build_wait_choice_args(nil) end)
    _assert_eq(ok, false, "nil meta should error")
  end)

  it("test_build_wait_choice_args_errors_on_missing_resume_next_state", function()
    local ok = pcall(function() phase_module.build_wait_choice_args({}) end)
    _assert_eq(ok, false, "missing resume_next_state should error")
  end)

  it("test_build_wait_choice_args_extracts_next_args_from_meta", function()
    local meta = { resume_next_state = "move", resume_next_args = { player = 1 } }
    local result = phase_module.build_wait_choice_args(meta)
    luassert.truthy(result.next_args ~= nil and result.next_args.player == 1, "should return resume_next_args with player=1")
  end)

  it("test_build_wait_choice_args_returns_nil_next_args_for_nil_meta_resume_next_args", function()
    local meta = { resume_next_state = "move" }
    local result = phase_module.build_wait_choice_args(meta)
    _assert_eq(result.next_args, nil, "missing resume_next_args should return nil")
  end)

  it("test_build_wait_choice_args_returns_both", function()
    local meta = { resume_next_state = "land", resume_next_args = { y = 2 } }
    local result = phase_module.build_wait_choice_args(meta)
    _assert_eq(result.next_state, "land", "next_state should match resume_next_state")
    _assert_eq(result.next_args.y, 2, "next_args should match resume_next_args")
  end)

  it("test_mark_active_sets_phase_active", function()
    local game = _make_game()
    phase_module.mark_active(game, "pre_move")
    luassert.truthy(game.turn.item_phase, "item_phase should exist")
    _assert_eq(game.turn.item_phase.pre_move.active, true, "active should be true")
    _assert_eq(game.turn.item_phase_active, "pre_move", "item_phase_active should be set")
    _assert_eq(game.dirty.turn, true, "dirty.turn should be set")
  end)

  it("test_decorate_followup_sets_meta_fields", function()
    local spec = {}
    local meta = { phase = "pre_action", resume_next_state = "move", resume_next_args = { a = 1 } }
    phase_module.decorate_followup_choice_spec(spec, meta)
    _assert_eq(spec.meta.phase, "pre_action", "meta.phase should be set")
    _assert_eq(spec.meta.resume_next_state, "move", "meta.resume_next_state should be set")
    _assert_eq(spec.meta.resume_next_args.a, 1, "meta.resume_next_args should be set")
  end)

  it("test_decorate_followup_repeatable_sets_allow_cancel", function()
    local spec = {}
    local meta = { phase = "pre_action", resume_next_state = "move", resume_next_args = nil }
    phase_module.decorate_followup_choice_spec(spec, meta)
    _assert_eq(spec.allow_cancel, true, "repeatable phase should set allow_cancel=true")
    _assert_eq(spec.cancel_label, "返回", "cancel_label should be 返回 when not already set")
  end)

  it("test_decorate_followup_non_repeatable_no_cancel", function()
    local spec = {}
    local meta = { phase = "unknown_non_repeatable", resume_next_state = "x", resume_next_args = nil }
    phase_module.decorate_followup_choice_spec(spec, meta)
    _assert_eq(spec.allow_cancel, nil, "non-repeatable phase should not set allow_cancel")
  end)

  it("test_decorate_followup_preserves_existing_cancel_label", function()
    local spec = { cancel_label = "custom" }
    local meta = { phase = "pre_move", resume_next_state = "x", resume_next_args = nil }
    phase_module.decorate_followup_choice_spec(spec, meta)
    _assert_eq(spec.cancel_label, "custom", "existing cancel_label should be preserved")
  end)

  it("test_decorate_followup_non_table_spec_returns_spec", function()
    local result = phase_module.decorate_followup_choice_spec("not_a_table", {})
    _assert_eq(result, "not_a_table", "non-table spec should be returned unchanged")
  end)

  it("test_decorate_followup_nil_meta_returns_spec", function()
    local spec = { data = true }
    local result = phase_module.decorate_followup_choice_spec(spec, nil)
    _assert_eq(result, spec, "nil meta should return spec unchanged")
  end)

  it("test_finish_nil_phase_clears_active_phase_without_error", function()
    local game = _make_game()
    game.turn.item_phase_active = "pre_action"
    phase_module.finish(game, nil)
    _assert_eq(game.turn.item_phase_active, "", "nil phase should clear active item phase")
  end)

  it("test_finish_empty_phase_clears_active_phase_without_error", function()
    local game = _make_game()
    game.turn.item_phase_active = "pre_action"
    phase_module.finish(game, "")
    _assert_eq(game.turn.item_phase_active, "", "empty phase should clear active item phase")
  end)

  it("test_resolve_completion_nil_phase_returns_resolved_without_finishing", function()
    local game = _make_game()
    game.turn.item_phase_active = "pre_action"
    local result = phase_module.resolve_completion(game, nil, {}, { after_action_anim = { next_state = "x" } })
    _assert_eq(result.status, "resolved", "nil phase should resolve")
    _assert_eq(result.stay, false, "nil phase should not stay")
    _assert_eq(result.after_action_anim.next_state, "x", "after_action_anim should be preserved")
    _assert_eq(game.turn.item_phase_active, "pre_action", "nil phase should not finish active phase")
  end)

  it("test_resolve_completion_non_repeatable_phase_finishes_and_resolves", function()
    local game = _make_game()
    local meta = { phase = "one_shot_phase" }
    local result = phase_module.resolve_completion(game, {}, meta, { after_action_anim = { next_state = "y" } })
    _assert_eq(result.status, "resolved", "non-repeatable phase should resolve")
    _assert_eq(result.stay, false, "non-repeatable phase should not stay")
    _assert_eq(result.after_action_anim.next_state, "y", "after_action_anim should be preserved")
    luassert.truthy(game.turn.item_phase and game.turn.item_phase.one_shot_phase, "non-repeatable phase should be finished")
    _assert_eq(game.turn.item_phase.one_shot_phase.done, true, "finished phase marked done")
  end)

  it("test_resolve_completion_repeatable_phase_with_no_offerable_items_resolves_via_finish", function()
    local game = support.new_game()
    local p = game.players[1]
    game.turn.choice_elapsed_seconds = 0
    local meta = { phase = "pre_action", resume_next_state = "roll", resume_next_args = { player = p } }
    local result = phase_module.resolve_completion(game, p, meta, {})
    _assert_eq(result.status, "resolved", "empty inventory should not reopen; resolves")
    _assert_eq(result.stay, false, "no reopen means no stay")
  end)

  it("test_resolve_completion_reopened_phase_with_pending_action_anim_defers_to_wait_choice", function()
    local game = support.new_game()
    local p = game.players[1]
    p.inventory:add({ id = item_ids.mine })
    game.turn.choice_elapsed_seconds = 3
    game.turn.action_anim = { running = true }
    game.intent_output_port = { open_choice = function() end }
    local meta = { phase = "pre_action", resume_next_state = "roll", resume_next_args = { player = p } }
    local result = phase_module.resolve_completion(game, p, meta, {})
    _assert_eq(result.status, "resolved", "pending action_anim resolves rather than waiting")
    _assert_eq(result.stay, false, "action_anim continuation does not stay")
    luassert.truthy(result.after_action_anim ~= nil, "should carry an after_action_anim continuation")
    _assert_eq(result.after_action_anim.next_state, "wait_choice", "continuation targets wait_choice")
    _assert_eq(result.after_action_anim.next_args.next_state, "roll", "continuation args come from meta")
  end)

  it("test_resolve_completion_reopens_with_fresh_elapsed_after_item_use", function()
    local game = support.new_game()
    local p = game.players[1]
    p.inventory:add({ id = item_ids.mine })
    game.turn.choice_elapsed_seconds = 7
    local captured = {}
    game.intent_output_port = {
      open_choice = function(_, _, opts)
        captured.opts = opts
      end,
    }
    local meta = { phase = "pre_action", resume_next_state = "roll", resume_next_args = { player = p } }
    local result = phase_module.resolve_completion(game, p, meta, {})
    _assert_eq(result.status, "waiting", "reopen should stay waiting")
    _assert_eq(result.stay, true, "reopen should stay")
    _assert_eq(captured.opts and captured.opts.elapsed_seconds, 0,
      "use-completion reopen must reset elapsed: cross-window accumulation locked out remaining cards")
  end)

  it("test_resolve_completion_empty_phase_string_resolves_without_finishing", function()
    local game = _make_game()
    game.turn.item_phase_active = "pre_action"
    local result = phase_module.resolve_completion(game, nil, { phase = "" }, {})
    _assert_eq(result.status, "resolved", "empty phase should resolve")
    _assert_eq(result.stay, false, "empty phase should not stay")
    _assert_eq(game.turn.item_phase_active, "pre_action", "empty phase should not finish active phase")
  end)

  it("test_resolve_completion_ignores_after_action_anim_when_result_is_non_table", function()
    local game = support.new_game()
    local p = game.players[1]
    p.inventory:add({ id = item_ids.mine })
    game.turn.choice_elapsed_seconds = 0
    game.intent_output_port = { open_choice = function() end }
    local meta = { phase = "pre_action", resume_next_state = "roll", resume_next_args = { player = p } }
    local result = phase_module.resolve_completion(game, p, meta, "not_a_table")
    _assert_eq(result.status, "waiting", "non-table result should still reopen")
    _assert_eq(result.stay, true, "non-table result should stay")
  end)

  it("test_reopen_or_finish_finishes_when_no_items_are_offerable", function()
    local game = support.new_game()
    local p = game.players[1]
    local meta = { phase = "pre_action", resume_next_state = "roll", resume_next_args = { player = p } }
    local reopened = phase_module.reopen_or_finish(game, p, meta, {})
    _assert_eq(reopened, false, "no offerable items should not reopen")
    _assert_eq(game.turn.item_phase and game.turn.item_phase.pre_action and game.turn.item_phase.pre_action.done, true, "phase should be finished")
  end)

  it("test_reopen_or_finish_opens_choice_without_elapsed_options", function()
    local game = support.new_game()
    local p = game.players[1]
    p.inventory:add({ id = item_ids.mine })
    local captured = {}
    game.intent_output_port = {
      open_choice = function(_, spec, opts)
        captured.spec = spec
        captured.opts = opts
      end,
    }
    local meta = { phase = "pre_action", resume_next_state = "roll", resume_next_args = { player = p } }
    local reopened = phase_module.reopen_or_finish(game, p, meta, {})
    _assert_eq(reopened, true, "offerable items should reopen")
    _assert_eq(captured.opts, nil, "nil elapsed_seconds should pass nil opts")
    _assert_eq(game.turn.item_phase_active, "pre_action", "phase should be marked active")
  end)

  it("test_run_returns_nil_for_disabled_phase", function()
    local game = support.new_game()
    local p = game.players[1]
    local result = phase_module.run({ game = game }, "not_enabled_phase", { player = p, next_state = "x" })
    _assert_eq(result, nil, "disabled phase should return nil")
  end)

  it("test_run_returns_nil_for_already_finished_phase", function()
    local game = support.new_game()
    local p = game.players[1]
    game.turn.item_phase = { pre_action = { done = true } }
    local result = phase_module.run({ game = game }, "pre_action", { player = p, next_state = "x" })
    _assert_eq(result, nil, "finished phase should return nil")
    _assert_eq(game.turn.item_phase.pre_action, nil, "finished phase should be cleared")
  end)

  it("test_run_human_phase_with_offerable_items_opens_choice", function()
    local game = support.new_game()
    local p = game.players[1]
    p.inventory:add({ id = item_ids.mine })
    local result = phase_module.run({ game = game }, "pre_action", { player = p, next_state = "roll", next_args = {} })
    _assert_eq(result.waiting, true, "human phase should open choice and wait")
    _assert_eq(result.next_state, "roll", "waiting should carry next_state")
    _assert_eq(game.turn.item_phase_active, "pre_action", "phase should be marked active")
  end)

  it("test_run_human_phase_with_no_offerable_items_finishes_and_returns_nil", function()
    local game = support.new_game()
    local p = game.players[1]
    local result = phase_module.run({ game = game }, "pre_action", { player = p, next_state = "roll", next_args = {} })
    _assert_eq(result, nil, "no offerable items should return nil")
    _assert_eq(game.turn.item_phase.pre_action.done, true, "phase should be finished")
  end)

  it("test_run_auto_phase_with_no_pre_finishes_and_returns_nil", function()
    local game, p = _make_auto_game()
    local result
    _with_patches({
      { target = strategy, key = "auto_pre_action", value = function() return nil end },
    }, function()
      result = phase_module.run({ game = game }, "pre_action", { player = p, next_state = "roll", next_args = {} })
    end)
    _assert_eq(result, nil, "no pre should return nil")
    _assert_eq(game.turn.item_phase.pre_action.done, true, "phase should be finished")
  end)

  it("test_run_auto_phase_with_waiting_pre_returns_waiting", function()
    local game, p = _make_auto_game()
    local result
    _with_patches({
      { target = strategy, key = "auto_pre_action", value = function() return { waiting = true } end },
    }, function()
      result = phase_module.run({ game = game }, "pre_action", { player = p, next_state = "roll", next_args = {} })
    end)
    _assert_eq(result.waiting, true, "waiting pre should return waiting")
    _assert_eq(result.next_state, "roll", "waiting should carry next_state")
  end)

  it("test_run_auto_phase_with_after_action_anim_returns_wait_action_anim", function()
    local game, p = _make_auto_game()
    game.turn.action_anim = { running = true }
    local result
    _with_patches({
      { target = strategy, key = "auto_pre_action", value = function()
        return { ok = true, after_action_anim = { next_state = "custom", next_args = { a = 1 } } }
      end },
    }, function()
      result = phase_module.run({ game = game }, "pre_action", { player = p, next_state = "roll", next_args = {} })
    end)
    _assert_eq(result.waiting, true, "after_action_anim should return waiting")
    _assert_eq(result.wait_action_anim, true, "should flag wait_action_anim")
    _assert_eq(result.next_state, "custom", "should use pre's after_action_anim next_state")
  end)

  it("test_run_auto_non_repeatable_phase_with_action_anim_returns_wait_action_anim_and_finishes", function()
    local game, p = _make_auto_game()
    game.turn.action_anim = { running = true }
    local result
    _with_patches({
      { target = strategy, key = "auto_pre_action", value = function() return { ok = true } end },
      { target = phase_module, key = "is_repeatable", value = function() return false end },
    }, function()
      result = phase_module.run({ game = game }, "pre_action", { player = p, next_state = "roll", next_args = {} })
    end)
    _assert_eq(result.waiting, true, "action_anim should return waiting")
    _assert_eq(result.wait_action_anim, true, "should flag wait_action_anim")
    _assert_eq(game.turn.item_phase.pre_action.done, true, "non-repeatable phase should finish")
  end)

  it("test_run_auto_repeatable_phase_with_action_anim_returns_wait_action_anim_after_loop", function()
    local game, p = _make_auto_game()
    game.turn.action_anim = { running = true }
    local calls = 0
    local result
    _with_patches({
      { target = strategy, key = "auto_pre_action", value = function()
        calls = calls + 1
        if calls == 1 then return { ok = true } end
        return nil
      end },
    }, function()
      result = phase_module.run({ game = game }, "pre_action", { player = p, next_state = "roll", next_args = {} })
    end)
    _assert_eq(calls, 2, "repeatable action_anim should loop until pre is nil")
    _assert_eq(result.waiting, true, "action_anim should return waiting")
    _assert_eq(result.wait_action_anim, true, "should flag wait_action_anim")
  end)

  it("test_run_auto_non_repeatable_phase_without_action_anim_finishes_and_returns_nil", function()
    local game, p = _make_auto_game()
    local calls = 0
    local result
    _with_patches({
      { target = strategy, key = "auto_pre_action", value = function()
        calls = calls + 1
        if calls == 1 then return { ok = true } end
        return nil
      end },
      { target = phase_module, key = "is_repeatable", value = function() return false end },
    }, function()
      result = phase_module.run({ game = game }, "pre_action", { player = p, next_state = "roll", next_args = {} })
    end)
    _assert_eq(result, nil, "no action_anim should return nil")
    _assert_eq(game.turn.item_phase.pre_action.done, true, "non-repeatable phase should finish")
  end)

  it("test_run_auto_repeatable_phase_without_action_anim_finishes_and_returns_nil", function()
    local game, p = _make_auto_game()
    local calls = 0
    local result
    _with_patches({
      { target = strategy, key = "auto_pre_action", value = function()
        calls = calls + 1
        if calls == 1 then return { ok = true } end
        return nil
      end },
    }, function()
      result = phase_module.run({ game = game }, "pre_action", { player = p, next_state = "roll", next_args = {} })
    end)
    _assert_eq(calls, 2, "repeatable no action_anim should loop until pre is nil")
    _assert_eq(result, nil, "no action_anim should return nil")
    _assert_eq(game.turn.item_phase.pre_action.done, true, "repeatable phase should finish")
  end)

end)
do
  local function _make_anim_game(anim_state)
    return {
      dirty = { turn = false },
      auto_play_port = { is_computer_controlled = function() return true end },
      turn = {
        item_phase = {},
        item_phase_active = "",
        action_anim = anim_state,
        move_followup_pending = false,
      },
    }
  end

  local function _sequenced_pre(first, second)
    local calls = 0
    return function()
      calls = calls + 1
      if calls == 1 then
        return first
      end
      return second
    end
  end

  local _player = { id = "p1" }
  local _args = { player = _player, next_state = "next", next_args = {} }
  local _move_followup_args = { player = _player, next_state = "move_followup", next_args = {} }

  local function _run_scenario(phase_name, pre_fn, run_args, game)
    local fake_strategy = { auto_pre_action = pre_fn }
    local fake_intent = { dispatch = function(_, pre) return pre end }
    local fake_dirty = { mark = function() end, mark_turn = function() end }
    local fake_chain = {
      resolve_after_action_anim = function(args_in, _)
        return args_in.next_state, args_in.next_args
      end,
    }
    return _reload_with("src.rules.items.phase", {
      ["src.config.gameplay.timing"] = { item_phase_queue = { "pre_action", "post_action", "custom_phase" } },
      ["src.rules.items.strategy"] = fake_strategy,
      ["src.rules.ports.intent_output"] = fake_intent,
      ["src.state.dirty_tracker"] = fake_dirty,
      ["src.foundation.chain_args"] = fake_chain,
    }, function(reloaded_phase)
      return reloaded_phase.run({ game = game }, phase_name, run_args)
    end)
  end


  describe("TestDomainItemsPhaseAutoDispatchAnimationBranches", function()
    it("test_pre_action_after_action_anim_waits_for_the_action_anim", function()
      local game = _make_anim_game({ kind = "test" })
      local res = _run_scenario("pre_action", function()
        return { after_action_anim = {} }
      end, _args, game)
      _assert_eq(res.waiting, true, "after_action_anim should wait")
      _assert_eq(res.wait_action_anim, true, "after_action_anim should set wait flag")
    end)

    it("test_post_action_after_action_anim_waits_and_does_not_finish_the_phase", function()
      local game = _make_anim_game({ kind = "test" })
      local res = _run_scenario("post_action", function()
        return { after_action_anim = {} }
      end, _args, game)
      _assert_eq(res.waiting, true, "post_action after_action_anim should wait")
      _assert_eq(game.turn.item_phase.post_action, nil, "post_action should not be finished yet")
    end)

    it("test_repeatable_phase_with_action_anim_waits_after_the_pre_loop", function()
      local game = _make_anim_game({ kind = "test" })
      local res = _run_scenario("pre_action", _sequenced_pre({}, nil), _args, game)
      _assert_eq(res.waiting, true, "repeatable phase with action_anim should wait after loop")
    end)

    it("test_non_repeatable_custom_phase_with_action_anim_waits_and_finishes", function()
      local game = _make_anim_game({ kind = "test" })
      local res = _run_scenario("custom_phase", _sequenced_pre({}, nil), _args, game)
      _assert_eq(res.waiting, true, "non-repeatable phase with action_anim should wait")
      _assert_eq(game.turn.item_phase.custom_phase.done, true, "non-repeatable phase should be finished")
    end)

    it("test_non_repeatable_custom_phase_without_action_anim_finishes_and_returns_nil", function()
      local game = _make_anim_game(nil)
      local res = _run_scenario("custom_phase", _sequenced_pre({}, nil), _args, game)
      _assert_eq(res, nil, "non-repeatable phase without action_anim should finish and return nil")
      _assert_eq(game.turn.item_phase.custom_phase.done, true, "non-repeatable phase should be finished")
    end)

    it("test_marks_move_followup_pending_when_after_action_anim_resolves_to_move_followup", function()
      local game = _make_anim_game({ kind = "test" })
      local res = _run_scenario("pre_action", function()
        return { after_action_anim = {} }
      end, _move_followup_args, game)
      _assert_eq(res.waiting, true, "move_followup after_action_anim should wait")
      _assert_eq(game.turn.move_followup_pending, true, "move_followup should be marked pending")
    end)
  end)
end
