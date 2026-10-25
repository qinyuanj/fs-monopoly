require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- Regression for the market_select view-command port path.
--
-- Field symptom (deploy log, 2026-07-11): every black-market item tap logged
--   [warn] view_command port missing, intent dropped: market_select
-- and the selection never registered. Mechanism: the assembled
-- view_command port resolved nil at dispatch time, so
-- view_command_dispatcher dropped the intent.
--
-- The existing two_tap_flatten_e2e Scenario D leans on the bind_ui_runtime
-- helper, which always injects fully assembled presentation ports — so it
-- cannot catch view_command being dropped from the assembled ports, nor does it
-- assert the "port missing" warn stays silent. These specs pin both directly.
local P = require("test.support.shared_support")
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local _with_patches = P.with_patches
local _bind_ui_runtime = P.bind_ui_runtime

local presentation_ports = require("src.ui.ports")
local view_command_dispatcher = require("src.ui.input.view_command")
local intent_dispatcher = require("src.ui.input.intent_dispatcher")
local market_renderer = require("src.ui.screens.market")
local logger = require("src.foundation.log")

local function _capture_warns()
  local warns = {}
  return warns, { target = logger, key = "warn", value = function(...)
    local parts = {}
    for _, v in ipairs({ ... }) do
      parts[#parts + 1] = tostring(v)
    end
    warns[#warns + 1] = table.concat(parts, " ")
  end }
end

local function _has_port_missing_warn(warns)
  for _, line in ipairs(warns) do
    if string.find(line, "view_command port missing", 1, true) then
      return true
    end
  end
  return false
end
describe("TestMarketSelectPortDispatch", function()
it("test_assembled_view_command_port_keeps_a_market_select_handler", function()
  local view_command_port = presentation_ports.build_view_command(presentation_ports.build())
  _assert_eq(type(view_command_port.dispatch), "function",
    "assembled view_command port must expose a dispatch function")

  local selected = nil
  _with_patches({
    { target = market_renderer, key = "select_market_option",
      value = function(_, option_id) selected = option_id end },
  }, function()
    local handled = view_command_port.dispatch({}, { type = "market_select", option_id = 2001 })
    _assert_eq(handled, true, "view_command port must report market_select as handled")
  end)

  _assert_eq(selected, 2001,
    "market_select must route through the assembled port to select_market_option")
end)

it("test_market_select_through_intent_dispatcher_reaches_the_port_without_a_missing_port_warn", function()
  local selected = nil
  local warns, warn_patch = _capture_warns()

  local state = {
    ui_model = {
      choice = {
        id = 88,
        kind = "market_buy",
        route_key = "market",
        owner_role_id = 7,
        options = { { id = 2001, label = "路障卡" } },
      },
      market = {
        choice_id = 88,
        options = { { id = 2001, label = "路障卡" } },
      },
    },
    ui = { input_blocked = false },
    game = {},
  }
  -- bind_ui_runtime injects real presentation ports and state.view_command_port.
  _bind_ui_runtime(state)

  _with_patches({
    { key = "UIManager", value = { client_role = nil } },
    warn_patch,
    { target = market_renderer, key = "select_market_option",
      value = function(_, option_id) selected = option_id end },
  }, function()
    intent_dispatcher.dispatch(state, state.game, {
      type = "market_select",
      option_id = 2001,
      actor_role_id = 7,
    }, {})
  end)

  _assert_eq(selected, 2001,
    "market_select dispatched through intent_dispatcher must reach the port handler")
  _assert_eq(_has_port_missing_warn(warns), false,
    "a properly wired view_command port must not drop market_select as 'port missing'")
end)

it("test_view_command_assembled_at_game_start_survives_the_tick_time_turn_ports_resolve", function()
  -- Field symptom round 2 (deploy log, 2026-07-12): the first tick funnels
  -- state.gameplay_loop_ports through gameplay_loop_ports.resolve
  -- (src/turn/loop/init.lua) and writes the resolved table back. When
  -- view_command lived inside that bundle, a resolve that kept only declared
  -- turn groups made every later market_select tap hit 'port missing'.
  -- #209: view_command is held by the ui-owned state.view_command_port
  -- written at game start, so the turn ports resolve can no longer drop it.
  local gameplay_start = require("src.app.gameplay_start")
  local gameplay_loop = require("src.turn.loop")
  local loop_ports = require("src.turn.loop.ports")
  local frame_timer = require("src.host.frame_timer")
  local warns, warn_patch = _capture_warns()
  local selected = nil
  local state = {}
  local fake_game = { turn = { turn_count = 1, phase = "moving" } }

  _with_patches({
    { target = gameplay_loop, key = "new_game", value = function() return fake_game end },
    { target = gameplay_loop, key = "set_game", value = function() end },
    { target = frame_timer, key = "repeat_every", value = function() return { id = "tick" } end },
  }, function()
    gameplay_start.start(state, { nil })
  end)
  loop_ports.resolve_for_state(state)
  loop_ports.resolve_for_state(state)

  _with_patches({
    warn_patch,
    { target = market_renderer, key = "select_market_option",
      value = function(_, option_id) selected = option_id end },
  }, function()
    local handled = view_command_dispatcher.dispatch(state,
      { type = "market_select", option_id = 2001 })
    _assert_eq(handled, true,
      "market_select must stay handled after the tick-time ports resolve")
  end)

  _assert_eq(selected, 2001,
    "the game-start view_command port must keep routing market_select to select_market_option")
  _assert_eq(_has_port_missing_warn(warns), false,
    "the tick-time turn ports resolve must not unwire view_command")
end)

it("test_view_command_dispatcher_warns_and_drops_market_select_when_the_port_is_unwired", function()
  -- Pins the diagnostic contract that surfaced the field bug: an absent
  -- view_command port yields the exact 'port missing' warn and a false return.
  local warns, warn_patch = _capture_warns()
  local dropped

  _with_patches({ warn_patch }, function()
    dropped = view_command_dispatcher.dispatch(
      {},
      { type = "market_select", option_id = 2001 }
    )
  end)

  _assert_eq(dropped, false, "missing view_command port must make dispatch return false")
  _assert_eq(_has_port_missing_warn(warns), true,
    "missing view_command port must emit the 'view_command port missing' diagnostic")
end)

it("test_game_action_intent_without_game_warns_and_drops", function()
  local warns, warn_patch = _capture_warns()
  local state = { ui = { input_blocked = false } }
  _bind_ui_runtime(state)

  _with_patches({
    { key = "UIManager", value = { client_role = nil } },
    warn_patch,
  }, function()
    intent_dispatcher.dispatch(state, nil, {
      type = "choice_select",
      option_id = 1,
      actor_role_id = 7,
    }, {})
  end)

  luassert.truthy(#warns == 1
      and string.find(warns[1], "ui intent without game", 1, true) ~= nil,
    "a game-action intent without a game should warn and drop: " .. tostring(warns[1]))
end)


end)
