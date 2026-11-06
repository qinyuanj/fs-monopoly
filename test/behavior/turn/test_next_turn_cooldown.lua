-- ui_button next 行动按钮冷却锁:点击后同一阶段内冷却未满拒绝,冷却恰好满放行,
-- 阶段已推进则不受上一阶段的锁限制。墙钟只在 dispatch ctx 的 clock_ports 边界替身。
require("test.bootstrap").install_package_paths()
-- luacheck: ignore 143
local luassert = assert
local handlers = require("src.turn.actions.action_dispatcher_handlers")
local defaults = require("src.turn.actions.defaults")

local function _env(phase)
  local clock = { now = 100, diff = 0 }
  local env = {
    clock = clock,
    game = { turn = { phase = phase } },
    state = {},
    advanced = {},
    ctx = {
      clock_ports = {
        wall_now_seconds = function()
          return clock.now
        end,
        wall_diff_seconds = function()
          return clock.diff
        end,
      },
    },
  }
  env.step_turn = function(game)
    env.advanced[#env.advanced + 1] = game.turn.phase
  end
  return env
end

local function _click(env)
  return handlers.handle_next_turn(env.step_turn, env.game, env.state, { type = "ui_button", id = "next" }, env.ctx)
end

describe("TestNextTurnCooldown", function()
  it("test_second_click_in_same_phase_within_cooldown_is_rejected", function()
    local env = _env("roll")

    luassert.equal("applied", _click(env).status, "first click should advance")
    env.clock.diff = 0
    luassert.equal("rejected", _click(env).status, "immediate second click in the same phase should be locked")
    luassert.same({ "roll" }, env.advanced, "only the first click should advance the turn")
  end)

  it("test_click_exactly_at_cooldown_is_applied", function()
    local env = _env("roll")

    _click(env)
    env.clock.diff = defaults.next_turn_cooldown
    luassert.equal("applied", _click(env).status, "a click exactly one cooldown later should pass")
    luassert.same({ "roll", "roll" }, env.advanced, "both clicks should advance the turn")
  end)

  it("test_click_after_phase_change_ignores_previous_phase_lock", function()
    local env = _env("roll")

    _click(env)
    env.game.turn.phase = "move"
    env.clock.diff = 0
    luassert.equal("applied", _click(env).status, "a new phase should not inherit the previous phase lock")
    luassert.same({ "roll", "move" }, env.advanced, "the new phase should advance immediately")
  end)
end)
