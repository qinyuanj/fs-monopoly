require("test.bootstrap").install_package_paths()
-- busted injects the extensible assertion object into each file environment.
-- luacheck: ignore 143
local luassert = assert
local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end
local board_state = require("src.state.board_state")
local log_capture = require("test.support.log_capture")

-- board_state mixin methods route every tile mutation through _sync_board_visual;
-- these exercise that port resolution (attached / missing / throwing)
-- via the public set_tile_owner entry.
local function _land_tile(id, owner_id)
  return { type = "land", id = id, owner_id = owner_id }
end

describe("TestBoardState", function()

  it("test_pushes_the_changed_tile_through_an_attached_feedback_port", function()
    local synced = nil
    local self_state = {
      dirty = {},
      board_visual_feedback_port = {
        sync_many = function(_, payload)
          synced = payload
          return true
        end,
      },
    }

    board_state.set_tile_owner(self_state, _land_tile(5, 2), 7)

    _assert_eq(self_state.dirty.board_tiles, true, "owner change should mark the board dirty")
    luassert.truthy(synced ~= nil, "an attached feedback port should receive the sync payload")
    _assert_eq(synced.tile_ids[1], 5, "sync payload should target the changed tile id")
  end)

  it("test_still_completes_the_owner_change_with_no_port_and_survives_a_throwing_port", function()
    local no_port = { dirty = {} }
    board_state.set_tile_owner(no_port, _land_tile(1), 3)
    _assert_eq(no_port.dirty.board_tiles, true,
      "owner change should mark dirty even without a feedback port")

    local throwing = {
      dirty = {},
      board_visual_feedback_port = {
        sync_many = function()
          error("sync boom")
        end,
      },
    }
    local tile = _land_tile(2)
    local ok = pcall(board_state.set_tile_owner, throwing, tile, 4)
    _assert_eq(ok, true, "a throwing feedback port must not break the owner update")
    _assert_eq(tile.owner_id, 4, "the owner should still be applied despite the port error")
  end)

  -- #551:失败路径可观测性契约——pcall 吞错 / port 未接线 warn 留痕且去重;
  -- no-op port(handled==false)是 headless 合法日常,保持静默。
  local function _count_board_state_warns(captured)
    local count = 0
    for _, line in ipairs(captured.lines) do
      if line:find("[board_state]", 1, true) ~= nil then
        count = count + 1
      end
    end
    return count
  end

  local function _assert_warn_contains(captured, needle, label)
    local joined = table.concat(captured.lines, "\n")
    luassert.truthy(joined:find("[board_state]", 1, true) ~= nil
      and joined:find(needle, 1, true) ~= nil, label .. "; got " .. joined)
  end

  local function _throwing_game()
    return {
      dirty = {},
      board_visual_feedback_port = {
        sync_many = function()
          error("sync boom")
        end,
      },
    }
  end

  it("test_warns_with_the_swallowed_error_when_the_port_throws", function()
    local returned = "untouched"
    local ok, _, captured = log_capture.capture(function()
      returned = board_state.set_tile_owner(_throwing_game(), _land_tile(3), 5)
    end)
    luassert.truthy(ok == true, "a throwing port must not break the owner update")
    _assert_eq(returned, nil, "public tile mutators keep returning nil on sync failure")
    _assert_warn_contains(captured, "sync boom",
      "warn should carry the category tag and the swallowed error message")
  end)

  it("test_warns_when_no_feedback_port_is_wired", function()
    local returned = "untouched"
    local ok, _, captured = log_capture.capture(function()
      returned = board_state.set_tile_owner({ dirty = {} }, _land_tile(1), 3)
    end)
    luassert.truthy(ok == true, "missing port must not break the owner update")
    _assert_eq(returned, nil, "public tile mutators keep returning nil with no port wired")
    _assert_warn_contains(captured, "not wired",
      "warn should report the unwired feedback port")
  end)

  it("test_warns_once_per_failure_category_per_game_instance", function()
    local game = _throwing_game()
    local ok, _, captured = log_capture.capture(function()
      board_state.set_tile_owner(game, _land_tile(3), 5)
      board_state.set_tile_level(game, { type = "land", id = 4, owner_id = 5 }, 2)
    end)
    luassert.truthy(ok == true, "repeated sync failures must not break tile updates")
    _assert_eq(_count_board_state_warns(captured), 1,
      "the same failure category should warn only once per game instance")
  end)

  it("test_stays_silent_when_the_port_reports_nothing_handled", function()
    local noop = {
      dirty = {},
      board_visual_feedback_port = {
        sync_many = function()
          return false
        end,
      },
    }
    local returned = "untouched"
    local ok, _, captured = log_capture.capture(function()
      returned = board_state.set_tile_owner(noop, _land_tile(6), 8)
    end)
    luassert.truthy(ok == true, "an unhandled sync must not break the owner update")
    _assert_eq(returned, nil, "public tile mutators keep returning nil when nothing is handled")
    _assert_eq(_count_board_state_warns(captured), 0,
      "a no-op port (headless default) is legitimate and must stay silent")
  end)



end)
