-- turn→UI 玩家控制快照契约(#590):每个玩家一份不可变快照,至少包含
local check = require("luassert")
local function _error_contains(expected, fn, ...)
  local args = table.pack(...)
  local ok, raised = pcall(function() return fn(table.unpack(args, 1, args.n)) end)
  check.is_false(ok)
  check.is_truthy(tostring(raised):find(expected, 1, true))
end
-- is_delegated 与 is_computer_controlled,且由玩家控制公开查询派生。
local snapshot = require("src.turn.output.player_control_snapshot")
local control = require("src.player.control")

local function _player(id, is_ai)
  local player = { id = id, name = "P" .. tostring(id), is_ai = is_ai == true }
  control.initialize(player)
  return player
end

describe("TestPlayerControlSnapshot", function()

it("test_builds_a_snapshot_per_player_with_delegation_and_computer_control", function()
  local direct = _player(1, false)
  local manual = _player(2, false)
  local afk = _player(3, false)
  local computer = _player(4, true)
  control.toggle_manual_delegation(manual)
  control.enable_afk_delegation(afk)

  local by_player = snapshot.build({
    players = { direct, manual, afk, computer },
  })

  check.same(by_player[1].is_delegated, false)
  check.same(by_player[1].is_computer_controlled, false)
  check.same(by_player[2].is_delegated, true)
  check.same(by_player[2].is_computer_controlled, true)
  check.same(by_player[3].is_delegated, true)
  check.same(by_player[3].is_computer_controlled, true)
  check.same(by_player[4].is_delegated, false)
  check.same(by_player[4].is_computer_controlled, true)
end)

it("test_each_build_returns_fresh_tables", function()
  local player = _player(1, false)
  local game = { players = { player } }

  local first = snapshot.build(game)
  local second = snapshot.build(game)
  check.not_equal(first, second, "snapshot map must be rebuilt each call")
  check.not_equal(first[1], second[1], "snapshot entries must be rebuilt each call")
end)

it("test_find_resolves_players_by_normalized_role_id", function()
  local player = _player(7, false)
  local game = { players = { player } }
  snapshot.install(game)

  check.same(snapshot.find(game, 7).is_computer_controlled, false)
  check.is_nil(snapshot.find(game, 99))
  check.is_nil(snapshot.find({ players = {} }, 7))
end)

it("test_install_attaches_the_current_snapshot_to_the_game", function()
  local player = _player(1, false)
  local game = { players = { player } }

  local installed = snapshot.install(game)
  check.equal(game.player_control_snapshots, installed, "install must attach the snapshot to game")
  check.same(installed[1].is_delegated, false)
end)

it("test_install_reuses_unchanged_public_control_facts", function()
  local player = _player(1, false)
  local game = { players = { player } }
  local first = snapshot.install(game)
  player.name = "renamed"
  player.cash = 900
  game.turn = { phase = "other" }
  player.id = "01"
  game.players = { player }

  check.equal(first, snapshot.install(game))
  check.equal(first[1], snapshot.find(game, "1"))
  local built = snapshot.build(game)
  check.not_equal(first, built)
  check.not_equal(first[1], built[1])
  check.equal(first, snapshot.install(game), "public build does not alter the installed version")
end)

it("test_invalid_ids_are_skipped_and_duplicate_normalized_ids_keep_the_last_entry", function()
  local invalid_id = setmetatable({}, { __tostring = function() error("invalid id") end })
  local first_player = _player("007", false)
  local last_player = _player(7, true)
  local game = { players = { false, { id = invalid_id }, {}, first_player, last_player } }
  local first = snapshot.install(game)
  check.is_false(first[7].is_delegated)
  check.is_true(first[7].is_computer_controlled)
  check.equal(first, snapshot.install(game))

  control.toggle_manual_delegation(first_player)
  local changed = snapshot.install(game)
  check.not_equal(first, changed, "even a shadowed seat's public facts invalidate the sequence")
  check.is_false(changed[7].is_delegated)
  game.players[4], game.players[5] = last_player, first_player
  local reordered = snapshot.install(game)
  check.not_equal(changed, reordered)
  check.is_true(snapshot.find(game, "07").is_delegated)
  check.is_false(first[7].is_delegated)
end)

it("test_control_changes_create_versions_without_mutating_old_snapshots", function()
  local player = _player(1, false)
  local game = { players = { player } }
  local direct = snapshot.install(game)
  control.toggle_manual_delegation(player)
  local manual = snapshot.install(game)
  check.not_equal(direct, manual)
  check.is_true(manual[1].is_delegated)
  control.initialize(player)
  control.enable_afk_delegation(player)
  check.equal(manual, snapshot.install(game), "manual to AFK keeps the same public boolean facts")
  control.toggle_manual_delegation(player)
  local restored = snapshot.install(game)
  check.not_equal(manual, restored)
  control.enable_afk_delegation(player)
  local afk = snapshot.install(game)
  check.not_equal(restored, afk)
  check.is_true(afk[1].is_delegated)
  control.toggle_manual_delegation(player)
  player.is_ai = true
  local computer = snapshot.install(game)
  check.not_equal(afk, computer)
  check.is_false(computer[1].is_delegated)
  check.is_true(computer[1].is_computer_controlled)
  player.is_ai = false
  check.not_equal(computer, snapshot.install(game))
  check.is_false(snapshot.find(game, 1).is_computer_controlled)
  check.is_false(direct[1].is_delegated)
  check.is_false(direct[1].is_computer_controlled)
  check.is_true(manual[1].is_delegated)
  check.is_true(afk[1].is_delegated)
  _error_contains("immutable", function() manual[1].is_delegated = false end)
  _error_contains("immutable", function() direct[1] = computer[1] end)
end)

it("test_same_id_replacement_reorder_growth_shrink_and_empty_inputs", function()
  local first_player, second_player = _player(1, false), _player(2, true)
  local game = { players = { first_player, second_player } }
  local first = snapshot.install(game)
  game.players[1] = _player("01", false)
  local replaced = snapshot.install(game)
  check.not_equal(first, replaced, "same id with another object creates a version")
  game.players[1], game.players[2] = second_player, game.players[1]
  local reordered = snapshot.install(game)
  check.not_equal(replaced, reordered)
  game.players[3] = _player(3, false)
  local grown = snapshot.install(game)
  check.not_equal(reordered, grown)
  check.is_not_nil(grown[3])
  game.players[3], game.players[2] = nil, nil
  local shrunk = snapshot.install(game)
  check.not_equal(grown, shrunk)
  check.is_nil(shrunk[1])
  check.is_nil(shrunk[3])
  check.equal(shrunk, snapshot.install(game))
  game.players = nil
  local empty = snapshot.install(game)
  check.is_nil(snapshot.find(game, 2))
  check.equal(empty, snapshot.install(game))
  game.players = {}
  check.equal(empty, snapshot.install(game))
  game.players[1] = first_player
  check.not_equal(first, snapshot.install(game), "removed versions are never restored from history")
  check.is_not_nil(first[2])
  check.is_not_nil(grown[3])
  check.not_equal(snapshot.install(nil), snapshot.install(nil))
end)

it("test_normalized_id_changes_and_external_snapshot_replacement_force_new_versions", function()
  local player = _player(1, false)
  local game = { players = { player } }
  local first = snapshot.install(game)
  player.id = 2
  local renamed = snapshot.install(game)
  check.not_equal(first, renamed)
  check.is_nil(snapshot.find(game, 1))
  check.is_not_nil(snapshot.find(game, "02"))
  player.id = nil
  local invalid = snapshot.install(game)
  check.not_equal(renamed, invalid)
  check.is_nil(snapshot.find(game, 2))
  player.id = "seat-A"
  local text_id = snapshot.install(game)
  check.is_not_nil(snapshot.find(game, "seat-A"))
  game.player_control_snapshots = snapshot.build(game)
  local external = game.player_control_snapshots
  local repaired = snapshot.install(game)
  check.not_equal(text_id, repaired)
  check.not_equal(external, repaired)
  check.equal(repaired, snapshot.install(game))
  game.player_control_snapshots = nil
  check.not_equal(repaired, snapshot.install(game))
end)

it("test_interleaved_games_own_separate_current_versions", function()
  local first_player, second_player = _player(1, false), _player(1, true)
  local first_game, second_game = { players = { first_player } }, { players = { second_player } }
  local first, second = snapshot.install(first_game), snapshot.install(second_game)
  check.not_equal(first, second)
  check.equal(first, snapshot.install(first_game))
  check.equal(second, snapshot.install(second_game))
  control.enable_afk_delegation(first_player)
  check.not_equal(first, snapshot.install(first_game))
  check.equal(second, snapshot.install(second_game))
  check.is_false(second[1].is_delegated)
  check.is_true(second[1].is_computer_controlled)
end)

it("test_snapshot_entries_reject_mutation", function()
  local player = _player(1, false)
  local game = { players = { player } }
  local by_player = snapshot.build(game)

  _error_contains("immutable", function()
    by_player[1].is_delegated = true
  end)
  _error_contains("immutable", function()
    by_player[99] = { is_delegated = true, is_computer_controlled = true }
  end)
end)

end)
