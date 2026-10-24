-- Unit-level branch coverage for src.app.gameplay_start M.prime_first_turn
-- and the M.start early-return / tick handle / port-assignment paths.
-- Survivors from #293 batch 2.

require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local _with_patches = support.with_patches

local gameplay_start = require("src.app.gameplay_start")
local gameplay_loop = require("src.turn.loop")
local presentation_ports = require("src.ui.ports")
local frame_timer = require("src.host.frame_timer")

describe("TestGameplayStart", function()

-- ── M.prime_first_turn ────────────────────────────────────────────

local function _test_prime_first_turn_returns_false_when_turn_is_nil()
  local game = {}
  local result = gameplay_start.prime_first_turn(game)
  _assert_eq(result, false, "prime_first_turn should return false when game.turn is nil")
end

local function _test_prime_first_turn_returns_false_when_turn_count_not_zero()
  local game = {
    advance_turn = function() end,
    turn = { turn_count = 3, phase = "start", pending_choice = nil },
  }
  local result = gameplay_start.prime_first_turn(game)
  _assert_eq(result, false, "prime_first_turn should return false when turn_count is not 0")
end

local function _test_prime_first_turn_returns_false_when_phase_not_start()
  local game = {
    advance_turn = function() end,
    turn = { turn_count = 0, phase = "moving", pending_choice = nil },
  }
  local result = gameplay_start.prime_first_turn(game)
  _assert_eq(result, false, "prime_first_turn should return false when phase is not start")
end

local function _test_prime_first_turn_returns_false_when_pending_choice_exists()
  local game = {
    advance_turn = function() end,
    turn = { turn_count = 0, phase = "start", pending_choice = { kind = "dice" } },
  }
  local result = gameplay_start.prime_first_turn(game)
  _assert_eq(result, false, "prime_first_turn should return false when pending_choice is not nil")
end

local function _test_prime_first_turn_advances_and_returns_true_for_fresh_turn()
  local advanced = false
  local game_ref = {}
  game_ref[1] = {
    advance_turn = function()
      advanced = true
    end,
    turn = { turn_count = 0, phase = "start", pending_choice = nil },
  }
  local result = gameplay_start.prime_first_turn(game_ref[1])
  _assert_eq(result, true, "prime_first_turn should return true when turn is fresh")
  _assert_eq(advanced, true, "prime_first_turn should advance turn when fresh")
end

-- ── M.start early-return & tick handle ───────────────────────────

local function _test_start_returns_existing_game_when_already_created()
  local existing_game = { id = "started_game" }
  local current_game_ref = { existing_game }
  local state = { tick_handle = {} }

  local result = gameplay_start.start(state, current_game_ref)
  _assert_eq(result, existing_game, "start should return existing game when current_game_ref[1] is set")
end

local function _test_start_stores_tick_handle()
  local capture = { repeat_every_calls = 0 }
  local tick_handle = { id = "tick" }
  local fake_game = {
    turn = { turn_count = 1, phase = "moving", pending_choice = nil },
  }
  _with_patches({
    { target = gameplay_loop, key = "new_game", value = function() return fake_game end },
    { target = gameplay_loop, key = "set_game", value = function() end },
    { target = presentation_ports, key = "build", value = function() return {} end },
    {
      target = frame_timer,
      key = "repeat_every",
      value = function()
        capture.repeat_every_calls = capture.repeat_every_calls + 1
        return tick_handle
      end,
    },
  }, function()
    local state = {}
    local current_game_ref = { nil }
    gameplay_start.start(state, current_game_ref)
    _assert_eq(state.tick_handle, tick_handle, "start should retain the tick cancellation handle")
    _assert_eq(state.tick_started, nil, "retired tick_started flag should remain absent")
  end)

  _assert_eq(capture.repeat_every_calls, 1, "tick loop should be registered exactly once on first start")
end

local function _test_start_stop_start_replaces_tick_without_duplicate_callback()
  local capture = { callbacks = {}, stopped_handles = {} }
  local fake_game = {
    turn = { turn_count = 1, phase = "moving", pending_choice = nil },
  }
  _with_patches({
    { target = gameplay_loop, key = "new_game", value = function() return fake_game end },
    { target = gameplay_loop, key = "set_game", value = function() end },
    { target = presentation_ports, key = "build", value = function() return {} end },
    {
      target = frame_timer,
      key = "repeat_every",
      value = function(_, callback)
        local handle = { id = #capture.callbacks + 1 }
        capture.callbacks[#capture.callbacks + 1] = callback
        return handle
      end,
    },
    {
      target = frame_timer,
      key = "stop",
      value = function(handle)
        capture.stopped_handles[#capture.stopped_handles + 1] = handle
      end,
    },
  }, function()
    local state = {}
    local current_game_ref = { nil }

    gameplay_start.start(state, current_game_ref)
    local first_handle = state.tick_handle
    gameplay_start.stop(state)
    gameplay_start.stop(state)
    gameplay_start.start(state, current_game_ref)

    _assert_eq(#capture.callbacks, 2, "restart should register exactly one replacement tick callback")
    _assert_eq(#capture.stopped_handles, 1, "stop should cancel an active tick only once")
    _assert_eq(capture.stopped_handles[1], first_handle, "stop should cancel the first tick handle")
    luassert.truthy(state.tick_handle ~= first_handle, "restart should retain the replacement handle")
  end)
end

-- ── M.start port assignment ───────────────────────────────────────

local function _test_start_assigns_turn_action_port_with_dispatch_and_block()
  local fake_game = {
    turn = { turn_count = 1, phase = "moving", pending_choice = nil },
  }
  _with_patches({
    { target = gameplay_loop, key = "new_game", value = function() return fake_game end },
    { target = gameplay_loop, key = "set_game", value = function() end },
    { target = presentation_ports, key = "build", value = function() return {} end },
  }, function()
    local state = { tick_handle = {} }
    local current_game_ref = { nil }
    gameplay_start.start(state, current_game_ref)

    luassert.truthy(type(state.turn_action_port) == "table", "turn_action_port should be a table")
    luassert.truthy(type(state.turn_action_port.dispatch_action) == "function",
      "dispatch_action should be a function")
    luassert.truthy(type(state.turn_action_port.should_block_action) == "function",
      "should_block_action should be a function")
  end)
end

local function _test_start_assigns_presentation_runtime()
  local fake_game = {
    turn = { turn_count = 1, phase = "moving", pending_choice = nil },
  }
  _with_patches({
    { target = gameplay_loop, key = "new_game", value = function() return fake_game end },
    { target = gameplay_loop, key = "set_game", value = function() end },
    { target = presentation_ports, key = "build", value = function() return {} end },
  }, function()
    local state = { tick_handle = {} }
    local current_game_ref = { nil }
    gameplay_start.start(state, current_game_ref)

    luassert.truthy(type(state.presentation_runtime) == "table", "presentation_runtime should be assigned")
  end)
end

-- ── Tick callback reads current_game_ref[1] ───────────────────────

local function _test_tick_callback_reads_current_game_ref_correctly()
  local capture = { tick_cb = nil, tick_values = {} }
  local game_v1 = { id = "v1" }
  local game_v2 = { id = "v2" }
  _with_patches({
    { target = gameplay_loop, key = "new_game", value = function() return game_v1 end },
    { target = gameplay_loop, key = "set_game", value = function() end },
    {
      target = gameplay_loop,
      key = "tick",
      value = function(game, _, _)
        capture.tick_values[#capture.tick_values + 1] = game
      end,
    },
    { target = presentation_ports, key = "build", value = function() return {} end },
    {
      target = frame_timer,
      key = "repeat_every",
      value = function(_, cb)
        capture.tick_cb = cb
      end,
    },
  }, function()
    local state = {}
    local current_game_ref = { nil }
    gameplay_start.start(state, current_game_ref)
    luassert.truthy(type(capture.tick_cb) == "function", "tick callback should be registered")
    -- First tick uses game_v1
    capture.tick_cb()
    _assert_eq(capture.tick_values[1], game_v1, "first tick should use current game from ref[1]")
    -- Change the ref and tick again
    current_game_ref[1] = game_v2
    capture.tick_cb()
    _assert_eq(capture.tick_values[2], game_v2, "second tick should read updated game from ref[1]")
  end)
end


it("test_prime_first_turn_returns_false_when_turn_is_nil", _test_prime_first_turn_returns_false_when_turn_is_nil)
it("test_prime_first_turn_returns_false_when_turn_count_not_zero", _test_prime_first_turn_returns_false_when_turn_count_not_zero)
it("test_prime_first_turn_returns_false_when_phase_not_start", _test_prime_first_turn_returns_false_when_phase_not_start)
it("test_prime_first_turn_returns_false_when_pending_choice_exists", _test_prime_first_turn_returns_false_when_pending_choice_exists)
it("test_prime_first_turn_advances_and_returns_true_for_fresh_turn", _test_prime_first_turn_advances_and_returns_true_for_fresh_turn)
it("test_start_returns_existing_game_when_already_created", _test_start_returns_existing_game_when_already_created)
it("test_start_stores_tick_handle", _test_start_stores_tick_handle)
it("test_start_stop_start_replaces_tick_without_duplicate_callback", _test_start_stop_start_replaces_tick_without_duplicate_callback)
it("test_start_assigns_turn_action_port_with_dispatch_and_block", _test_start_assigns_turn_action_port_with_dispatch_and_block)
it("test_start_assigns_presentation_runtime", _test_start_assigns_presentation_runtime)
it("test_tick_callback_reads_current_game_ref_correctly", _test_tick_callback_reads_current_game_ref_correctly)

-- ── #193 / ADR 0074:开局读皮肤存档恢复穿戴 ─────────────────────

describe("skin restore on start", function()
  local runtime_ports = require("src.foundation.ports.runtime_ports")
  local skin_ownership = require("src.rules.skin_ownership")
  local leaderboard_settlement = require("src.app.host_integrations.leaderboard_settlement")

  after_each(function()
    support.restore_runtime_services()
  end)

  it("test_start_reequips_saved_skin_for_human_players_only", function()
    -- 两名玩家存档都记着穿水豚嘟嘟(5006,归属 key 1053;穿戴 key 1051)。
    local archive = { [1053] = 1, [1051] = 5006 }
    local archive_reads = {}
    local model_roles = {}
    runtime_ports.configure({
      archives_enabled = function() return true end,
      get_archive_int = function(role_id, key)
        archive_reads[tostring(role_id)] = true
        return archive[key] or 0
      end,
      set_archive_int = function(_, key, value)
        archive[key] = value
        return true
      end,
      resolve_role = function(role_id)
        return {
          get_ctrl_unit = function()
            return {
              set_model_by_creature_key = function()
                model_roles[tostring(role_id)] = true
                return true
              end,
            }
          end,
        }
      end,
    })
    local fake_game = {
      players = { { id = 1 }, { id = 2, is_ai = true } },
      turn = { turn_count = 1, phase = "moving", pending_choice = nil },
    }
    local state = { ui = {} }
    _with_patches({
      { target = gameplay_loop, key = "new_game", value = function() return fake_game end },
      { target = gameplay_loop, key = "set_game", value = function() end },
      { target = presentation_ports, key = "build", value = function() return {} end },
      { target = frame_timer, key = "repeat_every", value = function() return {} end },
      { target = leaderboard_settlement, key = "watch_game", value = function() return true end },
    }, function()
      gameplay_start.start(state, { nil })
    end, { skip_runtime_context_refresh = true })

    _assert_eq(skin_ownership.equipped(state, 1), 5006, "human player's saved skin should be put back on at start")
    _assert_eq(model_roles["1"], true, "the human player's model should be changed")
    _assert_eq(archive_reads["2"], nil, "AI players have no archive and should not be read")
    _assert_eq(skin_ownership.equipped(state, 2), nil, "AI players should be skipped")
    _assert_eq(state.ui.skin_panel, nil, "restoring should not touch the skin shop")
  end)
end)
end)
