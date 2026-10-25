-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
-- Mutation-pinning specs for src/ui/input/view_command.lua, plus the
-- before-game terminal branch of src/ui/input/intent_dispatcher.lua.
-- The dispatcher is a thin adapter: panel_interrupt gate → state.view_command_port.
-- Per [[feedback_mutation_spec_state_inline]]: state shape kept inline, no
-- shared helpers — nil vs explicit fields are the discrimination contract.

local view_command = require("src.ui.input.view_command")
local intent_dispatcher = require("src.ui.input.intent_dispatcher")
local game_action_dispatcher = require("src.ui.input.game_action")
local panel_interrupt = require("src.ui.state.panel_interrupt")
local logger = require("src.foundation.log")

local function _with_block_entry(stub, body)
  local saved = panel_interrupt.block_entry
  panel_interrupt.block_entry = stub
  local ok, err = pcall(body)
  panel_interrupt.block_entry = saved
  luassert.truthy(ok, err)
end

local function _with_warn_capture(body)
  local warn_calls = {}
  local saved = logger.warn
  logger.warn = function(...) warn_calls[#warn_calls + 1] = { ... } end
  local ok, err = pcall(body, warn_calls)
  logger.warn = saved
  luassert.truthy(ok, err)
  return warn_calls
end

local function _ports_state(dispatch_fn)
  return {
    view_command_port = { dispatch = dispatch_fn },
  }
end

describe("TestViewCommandMutationPin", function()

it("test_returns_true_short_circuit_when_block_entry_blocks_without_touching_ports", function()
  local blocked_calls = {}
  local port_calls = 0
  local state = _ports_state(function() port_calls = port_calls + 1; return true end)
  local result
  _with_block_entry(function(_, panel_id, actor_role_id)
    blocked_calls[#blocked_calls + 1] = { panel_id = panel_id, actor_role_id = actor_role_id }
    return true
  end, function()
    result = view_command.dispatch(state, { type = "open_skin_panel", actor_role_id = 1 })
  end)
  luassert.truthy(result == true, "blocked panel entry must return true short-circuit; got " .. tostring(result))
  -- lint-allow: call-count 变异钉测:注入端口/闸门的调用次数是被钉 mutant 的唯一可见差异
  luassert.truthy(port_calls == 0, "blocked entry must not reach ports dispatch; got " .. port_calls)
  luassert.truthy(blocked_calls[1].panel_id == "skin",
    "expected 'skin' panel id passed to block_entry; got " .. tostring(blocked_calls[1].panel_id))
  luassert.truthy(blocked_calls[1].actor_role_id == 1,
    "expected actor_role_id passed to block_entry; got " .. tostring(blocked_calls[1].actor_role_id))
end)

it("test_proceeds_to_ports_when_block_entry_returns_false", function()
  local port_calls = 0
  local state = _ports_state(function() port_calls = port_calls + 1; return true end)
  local result
  _with_block_entry(function() return false end, function()
    result = view_command.dispatch(state, { type = "open_skin_panel", actor_role_id = 1 })
  end)
  luassert.truthy(result == true, "unblocked entry must delegate to ports; got " .. tostring(result))
  -- lint-allow: call-count 变异钉测:注入端口/闸门的调用次数是被钉 mutant 的唯一可见差异
  luassert.truthy(port_calls == 1, "ports dispatch must run when entry is not blocked; got " .. port_calls)
end)

it("test_treats_truthy_but_not_true_block_entry_result_as_not_blocked('== true' pin)", function()
  local port_calls = 0
  local state = _ports_state(function() port_calls = port_calls + 1; return true end)
  _with_block_entry(function() return 1 end, function()
    view_command.dispatch(state, { type = "open_skin_panel", actor_role_id = 1 })
  end)
  -- lint-allow: call-count 变异钉测:注入端口/闸门的调用次数是被钉 mutant 的唯一可见差异
  luassert.truthy(port_calls == 1, "block_entry returning non-true must not block; got " .. port_calls .. " port call(s)")
end)

it("test_never_consults_block_entry_for_intents_without_a_panel_id", function()
  local block_calls = 0
  local port_calls = 0
  local state = _ports_state(function() port_calls = port_calls + 1; return true end)
  local result
  _with_block_entry(function() block_calls = block_calls + 1; return true end, function()
    result = view_command.dispatch(state, { type = "market_select", option_id = 3 })
  end)
  -- lint-allow: call-count 变异钉测:注入端口/闸门的调用次数是被钉 mutant 的唯一可见差异
  luassert.truthy(block_calls == 0, "market_select has no panel id → gate must be skipped; got " .. block_calls)
  luassert.truthy(result == true, "gate skip must still delegate to ports; got " .. tostring(result))
  -- lint-allow: call-count 变异钉测:注入端口/闸门的调用次数是被钉 mutant 的唯一可见差异
  luassert.truthy(port_calls == 1, "ports dispatch must run for panel-less intents; got " .. port_calls)
end)

local function _seen_panel_id(intent)
  local seen = {}
  _with_block_entry(function(_, panel_id) seen[#seen + 1] = panel_id; return true end, function()
    view_command.dispatch({}, intent)
  end)
  return seen[1]
end

it("test_toggle_action_log_intent_maps_to_'action_log'_panel_id", function()
  local seen = _seen_panel_id({ type = "toggle_action_log", actor_role_id = 1 })
  luassert.truthy(seen == "action_log",
    "toggle_action_log must look up 'action_log' panel id; got " .. tostring(seen))
end)

it("test_open_skin_panel_intent_maps_to_'skin'_panel_id", function()
  local seen = _seen_panel_id({ type = "open_skin_panel", actor_role_id = 1 })
  luassert.truthy(seen == "skin",
    "open_skin_panel must look up 'skin' panel id; got " .. tostring(seen))
end)

it("test_open_gallery_panel_intent_maps_to_'gallery'_panel_id", function()
  local seen = _seen_panel_id({ type = "open_gallery_panel", actor_role_id = 1 })
  luassert.truthy(seen == "gallery",
    "open_gallery_panel must look up 'gallery' panel id; got " .. tostring(seen))
end)

it("test_forwards_state_and_intent_to_ports_view_command_dispatch_and_propagates_true", function()
  local captured = nil
  local state
  state = _ports_state(function(s, i) captured = { state = s, intent = i }; return true end)
  local intent = { type = "marker_intent" }
  local warn_calls = _with_warn_capture(function()
    local result = view_command.dispatch(state, intent)
    luassert.truthy(result == true, "ports dispatch true must propagate; got " .. tostring(result))
  end)
  luassert.truthy(captured.state == state, "state must be forwarded to ports dispatch")
  luassert.truthy(captured.intent == intent, "intent must be forwarded to ports dispatch")
  luassert.truthy(#warn_calls == 0, "healthy port dispatch must not warn; got " .. #warn_calls)
end)

it("test_returns_false_when_ports_dispatch_returns_false", function()
  local result = view_command.dispatch(_ports_state(function() return false end), { type = "x" })
  luassert.truthy(result == false, "ports false must propagate as false; got " .. tostring(result))
end)

it("test_returns_false_when_ports_dispatch_returns_nil('== true' coercion pin)", function()
  local result = view_command.dispatch(_ports_state(function() return nil end), { type = "x" })
  luassert.truthy(result == false, "ports nil must coerce to false; got " .. tostring(result))
end)

it("test_returns_false_when_ports_dispatch_returns_truthy_non_true('== true' coercion pin)", function()
  local result = view_command.dispatch(_ports_state(function() return 1 end), { type = "x" })
  luassert.truthy(result == false, "ports truthy non-true must coerce to false; got " .. tostring(result))
end)

it("test_warns_with_the_intent_type_and_returns_false_when_state_carries_no_ports", function()
  local result
  local warn_calls = _with_warn_capture(function()
    result = view_command.dispatch({}, { type = "popup_confirm" })
  end)
  luassert.truthy(result == false, "missing port must return false; got " .. tostring(result))
  luassert.truthy(#warn_calls == 1, "missing port must warn exactly once; got " .. #warn_calls)
  local found = false
  for _, arg in ipairs(warn_calls[1]) do
    if tostring(arg):find("popup_confirm", 1, true) then found = true end
  end
  luassert.truthy(found, "warn must carry intent.type 'popup_confirm' for diagnostics")
end)

it("test_warns_and_returns_false_when_view_command_sits_only_in_the_turn_ports_bundle", function()
  -- #209：view_command 只从 ui 自有的 state.view_command_port 读取，回合端口包里的同名组不算接线。
  local stray = { view_command = { dispatch = function() return true end } }
  local result
  local warn_calls = _with_warn_capture(function()
    result = view_command.dispatch({ gameplay_loop_ports = stray }, { type = "market_select" })
  end)
  luassert.truthy(result == false, "turn ports view_command must not be dispatched; got " .. tostring(result))
  luassert.truthy(#warn_calls == 1, "expected exactly one warn; got " .. #warn_calls)
end)

it("test_warns_and_returns_false_when_port_dispatch_is_not_a_function", function()
  local state = {
    view_command_port = { dispatch = "not_callable" },
  }
  local result
  local warn_calls = _with_warn_capture(function()
    result = view_command.dispatch(state, { type = "toggle_action_log", actor_role_id = 1 })
  end)
  luassert.truthy(result == false, "malformed port dispatch must return false; got " .. tostring(result))
  luassert.truthy(#warn_calls == 1, "malformed port must warn exactly once; got " .. #warn_calls)
end)

it("test_survives_nil_state_without_crashing_and_returns_false", function()
  local result
  local warn_calls = _with_warn_capture(function()
    result = view_command.dispatch(nil, { type = "market_select" })
  end)
  luassert.truthy(result == false, "nil state must return false; got " .. tostring(result))
  luassert.truthy(#warn_calls == 1, "nil state must warn once; got " .. #warn_calls)
end)

it("test_survives_nil_intent_without_crashing_and_returns_false", function()
  local result
  local warn_calls = _with_warn_capture(function()
    result = view_command.dispatch({}, nil)
  end)
  luassert.truthy(result == false, "nil intent must return false; got " .. tostring(result))
  luassert.truthy(#warn_calls == 1, "nil intent must still warn once; got " .. #warn_calls)
end)

local function _with_game_action_capture(body)
  local game_action_calls = 0
  local saved = game_action_dispatcher.dispatch
  game_action_dispatcher.dispatch = function() game_action_calls = game_action_calls + 1; return true end
  local ok, err = pcall(body)
  game_action_dispatcher.dispatch = saved
  luassert.truthy(ok, err)
  return game_action_calls
end

it("test_consumes_a_before_game_intent_on_missing_port_exactly_one_warn_no_game_path_fallthrough", function()
  local warn_calls
  local game_action_calls = _with_game_action_capture(function()
    warn_calls = _with_warn_capture(function()
      _with_block_entry(function() return false end, function()
        intent_dispatcher.dispatch({}, nil, { type = "open_skin_panel", actor_role_id = 1 })
      end)
    end)
  end)
  luassert.truthy(#warn_calls == 1, "missing port via intent_dispatcher must warn exactly once; got " .. #warn_calls)
  local message = tostring(warn_calls[1][1])
  luassert.truthy(message:find("view_command port missing", 1, true) ~= nil,
    "the single warn must be the port-missing diagnostic, not 'ui intent without game'; got " .. message)
  luassert.truthy(game_action_calls == 0,
    "before-game view command must never fall through to game action; got " .. game_action_calls)
end)

it("test_stays_terminal_even_when_the_port_dispatch_returns_false_no_second_dispatch", function()
  local port_calls = 0
  local state = _ports_state(function() port_calls = port_calls + 1; return false end)
  local game_action_calls = _with_game_action_capture(function()
    _with_block_entry(function() return false end, function()
      intent_dispatcher.dispatch(state, {}, { type = "open_skin_panel", actor_role_id = 1 })
    end)
  end)
  -- lint-allow: call-count 变异钉测:注入端口/闸门的调用次数是被钉 mutant 的唯一可见差异
  luassert.truthy(port_calls == 1, "port dispatch must run exactly once; got " .. port_calls)
  luassert.truthy(game_action_calls == 0,
    "port returning false must not re-enter the game/view fallthrough path; got " .. game_action_calls)
end)

it("test_still_routes_non_before_game_view_commands_through_the_game_first_path", function()
  local port_calls = 0
  local state = _ports_state(function() port_calls = port_calls + 1; return true end)
  local game_action_calls = _with_game_action_capture(function()
    _with_block_entry(function() return false end, function()
      intent_dispatcher.dispatch(state, {}, { type = "market_select", option_id = 1 })
    end)
  end)
  luassert.truthy(game_action_calls == 1, "market_select must hit the game action path first; got " .. game_action_calls)
  -- lint-allow: call-count 变异钉测:注入端口/闸门的调用次数是被钉 mutant 的唯一可见差异
  luassert.truthy(port_calls == 0, "game action consuming the intent must skip the trailing view dispatch; got " .. port_calls)
end)


end)
