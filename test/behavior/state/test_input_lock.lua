require("test.bootstrap").install_package_paths()
-- busted injects the extensible assertion object into each file environment.
-- luacheck: ignore 143
local luassert = assert
-- #211(#206 C):锁输入回合相位集合与谓词的唯一真源,turn 与 ui 共同向内依赖。

local input_lock = require("src.state.input_lock")

local phases = require("test.support.input_lock_phases")
local LOCKED_PHASES = phases.locked
local UNLOCKED_PHASES = phases.unlocked

describe("TestInputLock", function()

  it("test_locked_phases_block_input", function()
    for _, phase in ipairs(LOCKED_PHASES) do
      luassert.is_true(input_lock.is_phase_input_blocked(phase), phase .. " should lock input")
    end
  end)

  it("test_other_phases_allow_input", function()
    for _, phase in ipairs(UNLOCKED_PHASES) do
      luassert.is_false(input_lock.is_phase_input_blocked(phase), phase .. " should not lock input")
    end
    luassert.is_false(input_lock.is_phase_input_blocked(nil), "nil phase should not lock input")
  end)

  it("test_game_predicate_reads_current_turn_phase", function()
    for _, phase in ipairs(LOCKED_PHASES) do
      luassert.is_true(input_lock.is_game_input_blocked({ turn = { phase = phase } }),
        phase .. " game should lock input")
    end
    for _, phase in ipairs(UNLOCKED_PHASES) do
      luassert.is_false(input_lock.is_game_input_blocked({ turn = { phase = phase } }),
        phase .. " game should not lock input")
    end
  end)

  it("test_game_predicate_treats_missing_game_or_turn_as_unlocked", function()
    luassert.is_false(input_lock.is_game_input_blocked(nil), "nil game should not lock input")
    luassert.is_false(input_lock.is_game_input_blocked({}), "game without turn should not lock input")
    luassert.is_false(input_lock.is_game_input_blocked({ turn = {} }), "turn without phase should not lock input")
  end)
end)
