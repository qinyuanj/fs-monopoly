-- luacheck: std +busted
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local _new_game = support.new_game
local camera_policy = require("src.turn.policies.camera")

describe("TestCameraPolicy", function()
it("test_resolve_follow_player_id_current", function()
  local game = _new_game()
  local result = camera_policy._resolve_follow_player_id(game)
  local p1 = game.players[1]
  luassert.truthy(result == p1.id, "should return current player id when not eliminated")
end)
it("test_resolve_follow_player_id_next_non_eliminated", function()
  local game = _new_game()
  game.players[1].eliminated = true
  local result = camera_policy._resolve_follow_player_id(game)
  local p2 = game.players[2]
  luassert.truthy(result == p2.id, "should return next non-eliminated player")
end)
it("test_resolve_follow_player_id_no_index", function()
  local game = _new_game()
  game.turn.current_player_index = nil
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == nil, "should return nil when no current player index")
end)
it("test_resolve_follow_player_id_no_players", function()
  local game = _new_game()
  game.players = {}
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == nil, "should return nil when no players")
end)
it("test_resolve_follow_player_id_multiple_eliminated", function()
  local game = _new_game()
  game.players[1].eliminated = true
  game.players[2].eliminated = true
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == nil, "should return nil when all players eliminated")
end)
it("test_resolve_follow_player_id_nil_id", function()
  local game = _new_game()
  game.players[1].id = nil
  game.players[2].id = 2
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == 2, "should skip player with nil id")
end)
it("test_resolve_follow_player_id_nil_turn", function()
  local game = _new_game()
  game.turn = nil
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == nil, "should return nil when turn is nil")
end)
it("test_resolve_follow_player_id_nil_players", function()
  local game = _new_game()
  game.players = nil
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == nil, "should return nil when players is nil")
end)
it("test_resolve_follow_player_id_empty_players", function()
  local game = _new_game()
  game.players = {}
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == nil, "should return nil with empty players")
end)
it("test_resolve_follow_player_id_current_not_eliminated", function()
  local game = _new_game()
  game.players[1].eliminated = true
  game.turn.current_player_index = 2
  game.players[2].eliminated = false
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == game.players[2].id, "should return current player when not eliminated")
end)
it("test_resolve_follow_player_id_wrap_around", function()
  local game = _new_game()
  game.turn.current_player_index = 2
  game.players[2].eliminated = true
  game.players[1].eliminated = false
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == game.players[1].id, "should wrap around to find non-eliminated player")
end)
it("test_resolve_follow_player_id_skip_nil_id", function()
  local game = _new_game()
  game.players[1].id = nil
  game.players[1].eliminated = false
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == game.players[2].id, "should skip player with nil id even if not eliminated")
end)
it("test_resolve_follow_player_id_index_zero", function()
  local game = _new_game()
  game.turn.current_player_index = 0
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == game.players[1].id, "index 0 should scan forward to the first player")
end)
it("test_resolve_follow_player_id_negative_index", function()
  local game = _new_game()
  game.turn.current_player_index = -1
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == game.players[#game.players].id, "index -1 should wrap to the last player")
end)
it("test_resolve_follow_player_id_all_eliminated", function()
  local game = _new_game()
  for _, p in ipairs(game.players) do
    p.eliminated = true
  end
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == nil, "should return nil when all players eliminated")
end)
it("test_resolve_follow_player_next_non_eliminated", function()
  local game = _new_game()
  game.players[1].eliminated = true
  game.players[2].eliminated = false
  game.turn.current_player_index = 1

  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == 2, "should return next non-eliminated player")
end)
it("test_resolve_follow_player_wrap_around", function()
  local game = _new_game()
  for i, p in ipairs(game.players) do
    p.eliminated = (i ~= 1)
  end
  game.turn.current_player_index = 4

  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == 1, "should handle wrap-around")
end)
it("test_resolve_follow_player_current_valid", function()
  local game = _new_game()
  game.turn.current_player_index = 2
  game.players[2].eliminated = false

  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == 2, "should return current player when valid")
end)

it("test_sync_follow_refreshed_without_state_changes_target", function()
  local game = _new_game()
  local followed_id = nil
  local ports = {
    ui_sync = {
      follow_camera = function(state, player_id)
        luassert.truthy(state == nil, "state should be optional when ui was refreshed")
        followed_id = player_id
        return true
      end,
    },
  }

  camera_policy.sync_follow(game, nil, ports, true)

  luassert.truthy(followed_id == game.players[1].id, "ui_refreshed should allow target change without runtime state")
end)

it("test_sync_follow_unchanged_target_syncs_camera_position", function()
  local game = _new_game()
  local state = {}
  local follow_calls = 0
  local synced_state = nil
  local ports = {
    ui_sync = {
      follow_camera = function() follow_calls = follow_calls + 1 return true end,
      sync_camera_position = function(s) synced_state = s end,
    },
  }

  camera_policy.sync_follow(game, state, ports, true)
  camera_policy.sync_follow(game, state, ports, true)

  -- lint-allow: call-count ui_sync 是注入端口,follow_camera 下发次数即对宿主的出站命令
  luassert.truthy(follow_calls == 1, "跟随目标未变时不应重复下发 follow_camera")
  luassert.truthy(synced_state == state, "跟随目标未变时应改为同步相机位置")
end)

it("test_sync_follow_unchanged_target_without_sync_camera_position", function()
  local game = _new_game()
  local state = {}
  local follow_calls = 0
  local ports = {
    ui_sync = {
      follow_camera = function() follow_calls = follow_calls + 1 return true end,
    },
  }

  camera_policy.sync_follow(game, state, ports, true)
  camera_policy.sync_follow(game, state, ports, true)

  -- lint-allow: call-count ui_sync 是注入端口,follow_camera 下发次数即对宿主的出站命令
  luassert.truthy(follow_calls == 1, "宿主未提供 sync_camera_position 时目标未变仍不应重复跟随")
end)

it("test_sync_follow_without_ui_sync_ports_returns_early", function()
  local game = _new_game()
  camera_policy.sync_follow(game, {}, {}, true)
  camera_policy.sync_follow(game, {}, nil, true)
  luassert.truthy(true, "sync_follow should tolerate missing ui_sync ports")
end)

it("test_sync_follow_without_refresh_keeps_existing_target", function()
  local game = _new_game()
  local follow_calls = 0
  local ports = {
    ui_sync = {
      follow_camera = function()
        follow_calls = follow_calls + 1
        return true
      end,
    },
  }

  camera_policy.sync_follow(game, nil, ports, false)

  -- lint-allow: call-count ui_sync 是注入端口,follow_camera 下发次数即对宿主的出站命令
  luassert.truthy(follow_calls == 0,
    "未刷新且无运行时状态时不应切换跟随目标")
end)

it("test_reset_follow_clears_runtime_last_follow_target", function()
  -- L126 `state and ensure_turn_runtime(state) or nil` 三连变异(and->or /
  -- 调用换 nil / or->and)都会让 runtime 上的 last_follow_player_id 清不掉。
  local runtime_state = require("src.state.runtime")
  local state = {}
  local runtime = runtime_state.ensure_turn_runtime(state)
  runtime.last_follow_player_id = "p1"

  camera_policy.reset_follow(state)

  local after = runtime_state.ensure_turn_runtime(state)
  luassert.truthy(after.last_follow_player_id == nil,
    "reset_follow must clear the runtime last_follow_player_id")
end)

it("test_resolve_follow_player_single_player_game", function()
  -- L25 `count <= 0` 的 0->1:单人局(1 人)不能误判为空局返回 nil。
  local game = _new_game()
  game.players = { game.players[1] }
  game.turn.current_player_index = 1
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == game.players[1].id,
    "single-player game must still resolve its own id")
end)

it("test_scan_starts_at_player_after_current", function()
  -- L34 `start_index - 1` 的 - -> +:扫描必须从 current 的下一位开始,
  -- 不能跳到(current+2)位把后面活人优先于 immediate next 选中。
  local game = _new_game({ players = { "P1", "P2", "P3", "P4" }, ai = {} })
  game.players[1].eliminated = true -- 当前位淘汰,进入扫描
  game.players[3].eliminated = true
  -- players[2] 与 players[4] 都存活:原序应取 immediate next(2),偏移+1 会先看 4
  game.turn.current_player_index = 1
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == game.players[2].id,
    "scan must prefer the immediate next player")
end)

it("test_scan_with_zero_index_starts_from_first_player", function()
  -- L33 `for offset = 1, count` 的 1->0:current index=0 时扫描必须从玩家 1 开始,
  -- 不能从最后一个玩家(offset 0 命中 players[count])开始抢先返回。
  local game = _new_game({ players = { "P1", "P2", "P3", "P4" }, ai = {} })
  game.players[2].eliminated = true
  game.players[3].eliminated = true
  -- players[1] 与 players[4] 存活:原序从 1 开始返回 1,1->0 会先看 4 返回 4
  game.turn.current_player_index = 0
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == game.players[1].id,
    "zero index must scan from player 1")
end)

it("test_scan_with_negative_index_wraps_from_end", function()
  -- L34 `+ 1` 的 1->0:negative index 下取模回绕仍须从(原序)尾端开始扫描。
  local game = _new_game({ players = { "P1", "P2", "P3", "P4" }, ai = {} })
  game.players[1].eliminated = true
  -- players[2]/players[3]/players[4] 存活:原序(-1)从 4 开始返回 4,+0 偏移会从 3 开始返回 3
  game.turn.current_player_index = -1
  local result = camera_policy._resolve_follow_player_id(game)
  luassert.truthy(result == game.players[4].id,
    "negative index must wrap to scan from the last player")
end)
it("test_sync_follow_skips_while_target_pan_active", function()
  -- 效果平移(pan)存活期内,即使 last_follow 被 dirty.turn 心跳清掉也不得
  -- 重放 follow,否则镜头被拽离效果地块(效果结算偶发 jitter)。
  local game = _new_game()
  local state = { turn_runtime = { target_pan_active = true } }
  local follow_calls = 0
  local ports = {
    ui_sync = {
      follow_camera = function() follow_calls = follow_calls + 1 return true end,
      sync_camera_position = function() end,
    },
  }

  camera_policy.sync_follow(game, state, ports, true)

  -- lint-allow: call-count ui_sync 是注入端口,follow_camera 下发次数即对宿主的出站命令
  luassert.truthy(follow_calls == 0, "pan 存活期内不得重放 follow_camera")
end)

it("test_sync_follow_resumes_after_target_pan_release", function()
  local game = _new_game()
  local state = { turn_runtime = { target_pan_active = true } }
  local followed_id = nil
  local ports = {
    ui_sync = {
      follow_camera = function(_, player_id) followed_id = player_id return true end,
    },
  }

  camera_policy.sync_follow(game, state, ports, true)
  state.turn_runtime.target_pan_active = nil
  camera_policy.sync_follow(game, state, ports, true)

  luassert.truthy(followed_id == game.players[1].id, "release 清标志后应恢复跟随")
end)
end)
