local logger = require("src.foundation.log")
local tip_queue = require("src.foundation.tips")
local timing = require("src.config.gameplay.timing")
local runtime_install = require("src.app.host_install")
local startup_roster = require("src.app.roster")
local state_factory = require("src.app.state_factory")
local runtime_event_bridge = require("src.app.event_bridge")
local ui_bootstrap = require("src.app.ui_bootstrap")
local gameplay_runtime_bootstrap = require("src.app.gameplay_start")
local gameplay_loop = require("src.turn.loop")
local init_runtime = require("src.app.init_runtime")

local M = {}
local initialized = false
local current_game_ref = { nil }
local state = nil
local _globalapi_missing_warned = false

local function _is_test_mode_enabled()
  if type(logger.is_test_mode) ~= "function" then
    return false
  end
  local ok, enabled = pcall(logger.is_test_mode)
  if not ok then
    return false
  end
  return enabled == true
end

function M.init()
  if initialized then
    return state
  end

  tip_queue.configure_runtime({
    presenter = function(text, duration, tip)
      if init_runtime.try_show_tip_to_role(tip, text, duration) then
        return true
      end
      if not (GlobalAPI and type(GlobalAPI.show_tips) == "function") then
        if not _globalapi_missing_warned then
          _globalapi_missing_warned = true
          logger.warn("[app]", "GlobalAPI.show_tips not available - tips will be dropped until host is ready")
        end
        return false
      end
      _globalapi_missing_warned = false
      return GlobalAPI.show_tips(text, duration)
    end,
    scheduler = function(delay, fn)
      if type(SetTimeOut) == "function" then
        return SetTimeOut(delay, fn)
      end
      if fn then
        fn()
        return true
      end
      return false
    end,
    test_mode = _is_test_mode_enabled(),
    event_tip_fast_backlog_threshold = timing.event_tip_fast_backlog_threshold,
    event_tip_fast_seconds = timing.event_tip_fast_seconds,
  })

  init_runtime.configure_game_time_logger(GameAPI)

  if type(logger.set_ui_sink) == "function" then
    logger.set_ui_sink(init_runtime.build_ui_warn_sink())
  end

  local function _get_current_game()
    return current_game_ref[1]
  end
  -- Sign-in RewardDay events are global host events resolved at fire time, so the
  -- install hands host_install lazy accessors for the (not-yet-built) game and state.
  runtime_install.install({
    get_current_game = _get_current_game,
    get_app_state = function() return state end,
  })
  local auto_runner = startup_roster.build_auto_runner()
  state = state_factory.build_state(_get_current_game, {
    build_game_factory = function(child_state)
      return startup_roster.build_game_factory(child_state)
    end,
    auto_runner = auto_runner,
  })

  logger.set_anim_debug_enabled_provider(init_runtime.build_anim_debug_provider(state))
  state.on_game_replaced = function(new_game)
    current_game_ref[1] = new_game
    gameplay_loop.set_game(state, new_game)
  end

  runtime_event_bridge.install(state, function() return current_game_ref[1] end)
  ui_bootstrap.install(state, current_game_ref, {
    start_runtime = function(ctx_state, game_ref)
      return gameplay_runtime_bootstrap.start(ctx_state, game_ref)
    end,
  })

  initialized = true
  return state
end

return M

