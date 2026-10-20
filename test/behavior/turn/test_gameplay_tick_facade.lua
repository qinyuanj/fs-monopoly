local check = require("luassert")
local support = require("test.support.shared_support")
local fixtures = require("test.support.gameplay_fixtures")
local gameplay_loop = require("src.turn.loop.init")
local runtime_state = require("src.state.runtime")

describe("TestGameplayTickFacade", function()

local function _new_subject()
  local game = support.new_game({ players = { "P1", "P2" }, ai = {} })
  local state = fixtures.build_loop_state()
  state.auto_runner.next_action = function() return nil end
  state._resolved_gameplay_loop_ports = nil
  return game, state
end

it("test_auto_runner_receives_tick_context_from_the_public_tick", function()
  local game, state = _new_subject()
  local captured
  support.with_patches({
    {
      target = gameplay_loop,
      key = "step_auto_runner",
      value = function(received_game, received_state, dt, context)
        captured = { game = received_game, state = received_state, dt = dt, context = context }
      end,
    },
  }, function()
    gameplay_loop.tick(game, state, 0.25)
  end)

  check.equal(captured.game, game)
  check.equal(captured.state, state)
  check.same(captured.dt, 0.25)
  check.equal(captured.context.game, game)
  check.equal(captured.context.state, state)
  check.same(captured.context.current_player_id, game:current_player().id)
end)

it("test_blocked_refreshed_ui_reapplies_input_lock", function()
  local game, state = _new_subject()
  local lock_applications = 0
  local ui_sync = state.gameplay_loop_ports.ui_sync
  ui_sync.get_ui_state = function() return {} end
  ui_sync.set_input_blocked = function() return false end
  ui_sync.is_input_blocked = function() return true end
  ui_sync.refresh_from_dirty = function() return true end
  ui_sync.apply_input_lock = function()
    lock_applications = lock_applications + 1
  end

  gameplay_loop.tick(game, state, 0)

  -- lint-allow: call-count ui_sync/gameplay_loop_ports 是注入端口,同步次数即 tick 的对外输出
  check.same(lock_applications, 1)
end)

it("test_missing_ui_probe_samples_after_the_dirty_refresh", function()
  -- #523 时序 pin：缺屏探针必须在 refresh_from_dirty 之后采样——同帧
  -- 「先探后开」的误报（阻塞期创建、放行帧首开的窗口）不得回归。
  local game, state = _new_subject()
  local order = {}
  state.gameplay_loop_ports.ui_sync.refresh_from_dirty = function()
    order[#order + 1] = "refresh"
    return false
  end
  state.gameplay_loop_ports.ui_sync.probe_choice_ui_missing = function()
    order[#order + 1] = "probe"
  end

  gameplay_loop.tick(game, state, 0)

  local refresh_at, probe_at
  for index, tag in ipairs(order) do
    if tag == "refresh" then refresh_at = index end
    if tag == "probe" then probe_at = index end
  end
  check.is_not_nil(refresh_at, "the dirty refresh runs in the tick")
  check.is_not_nil(probe_at, "the missing-ui probe runs in the tick")
  check.is_true(probe_at > refresh_at, "the probe samples after the dirty refresh")
end)

it("test_pending_choice_opened_in_the_same_frame_does_not_warn", function()
  -- #523 复现路径回归 pin（验收第 1 条）：窗口在 dirty 刷新内首开
  --（refresh 落 choice_active/screen_key 模拟 open_choice_modal 的门控
  -- 副作用），同帧探针必须看到 open=true 不告警；探针若被移回刷新之前
  --（先探后开），本 pin 立即转红。
  local game, state = _new_subject()
  local ui_sync_ports = require("src.ui.ports.ui_sync")
  local runtime_ports = require("src.foundation.ports.runtime_ports")
  local logger = require("src.foundation.log")
  local choice = {
    id = 51,
    kind = "landing_optional_effect",
    route_key = "secondary_confirm",
    owner_role_id = game.players[1].id,
    options = { { id = "buy_land", label = "购买地块" } },
  }
  game.turn.phase = "wait_choice"
  game.turn.pending_choice = choice
  runtime_state.set_pending_choice(state, choice, { choice_id = choice.id, elapsed_seconds = 0 })
  local ui_sync = state.gameplay_loop_ports.ui_sync
  ui_sync.probe_choice_ui_missing = ui_sync_ports.build({
    get_ui_state = function() return state.ui end,
  }).probe_choice_ui_missing
  ui_sync.refresh_from_dirty = function()
    state.ui.choice_active = true
    state.ui.active_choice_screen_key = "secondary_confirm"
    return true
  end
  local warned = {}
  support.with_patches({
    { target = runtime_ports, key = "resolve_roles", value = function()
      return { { get_roleid = function() return game.players[1].id end } }
    end },
    { target = logger, key = "warn", value = function(...)
      warned[#warned + 1] = table.concat({ ... }, " ")
    end },
  }, function()
    gameplay_loop.tick(game, state, 0)
  end)
  check.same(#warned, 0, "a choice opened in the same frame's refresh never warns")
end)

it("test_both_control_observations_keep_same_frame_ui_current", function()
  local control = require("src.player.control")
  local snapshot = require("src.turn.output.player_control_snapshot")
  local model_sync = require("src.ui.ports.ui_sync")._model
  local game, state = _new_subject()
  local player = game.players[1]
  local old = snapshot.install(game)
  control.toggle_manual_delegation(player)
  local before_action, after_action, model
  state.auto_runner.next_action = function()
    before_action = game.player_control_snapshots
    control.toggle_manual_delegation(player)
    return nil
  end
  state.gameplay_loop_ports.ui_sync.refresh_from_dirty = function()
    after_action = game.player_control_snapshots
    model = model_sync.build_model(state, game)
    return false
  end

  gameplay_loop.tick(game, state, 0)

  check.not_equal(old, before_action, "frame start observes changes before auto actions")
  check.is_true(before_action[1].is_delegated)
  check.not_equal(before_action, after_action, "post-action observation sees same-frame changes")
  check.is_false(after_action[1].is_delegated)
  check.is_false(model.delegated_by_player[1])
  check.equal(after_action, game.player_control_snapshots, "UI build reuses the post-action version")
  check.is_false(old[1].is_delegated)
  state.auto_runner.next_action = function() return nil end
  gameplay_loop.tick(game, state, 0)
  check.equal(after_action, game.player_control_snapshots, "stable tick and UI keep the version")
end)

it("test_set_game_installs_independent_control_snapshots", function()
  local control = require("src.player.control")
  local snapshot = require("src.turn.output.player_control_snapshot")
  local first_game, state = _new_subject()
  gameplay_loop.set_game(state, first_game)
  local first = first_game.player_control_snapshots
  check.is_false(snapshot.find(first_game, 1).is_delegated)
  check.equal(first, snapshot.install(first_game))

  local second_game = support.new_game({ players = { "P1", "P2" }, ai = {} })
  control.toggle_manual_delegation(second_game.players[1])
  gameplay_loop.set_game(state, second_game)
  check.not_equal(first, second_game.player_control_snapshots)
  check.is_true(snapshot.find(second_game, 1).is_delegated)
  check.equal(first, snapshot.install(first_game))
  check.is_false(first[1].is_delegated)
end)

it("test_release_pulse_marks_turn_dirty_and_syncs_status_during_visual_hold", function()
  local game, state = _new_subject()
  local refreshed_dirty
  local status_syncs = 0
  runtime_state.set_landing_visual_hold_active(state, true)
  runtime_state.mark_landing_visual_release_pulse(state)
  state.gameplay_loop_ports.ui_sync.refresh_from_dirty = function(_, _, dirty)
    refreshed_dirty = dirty
    return false
  end
  state.gameplay_loop_ports.anim.sync_status_3d = function()
    status_syncs = status_syncs + 1
  end

  gameplay_loop.tick(game, state, 0)

  check.is_true(refreshed_dirty.any)
  check.is_true(refreshed_dirty.turn)
  -- lint-allow: call-count ui_sync/gameplay_loop_ports 是注入端口,同步次数即 tick 的对外输出
  check.same(status_syncs, 1)
end)

it("test_visual_hold_skips_status_sync_but_keeps_event_log_flowing", function()
  local game, state = _new_subject()
  local status_syncs = 0
  local event_log_syncs = 0
  runtime_state.set_landing_visual_hold_active(state, true)
  state.gameplay_loop_ports.anim.sync_status_3d = function()
    status_syncs = status_syncs + 1
  end
  state.gameplay_loop_ports.debug.sync_event_log = function()
    event_log_syncs = event_log_syncs + 1
  end

  gameplay_loop.tick(game, state, 0)

  -- lint-allow: call-count ui_sync/gameplay_loop_ports 是注入端口,同步次数即 tick 的对外输出
  check.same(status_syncs, 0)
  -- lint-allow: call-count ui_sync/gameplay_loop_ports 是注入端口,同步次数即 tick 的对外输出
  check.same(event_log_syncs, 1)
end)

end)
