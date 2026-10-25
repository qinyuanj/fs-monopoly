require("test.bootstrap").install_package_paths()
-- busted injects the extensible assertion object into each file environment.
-- luacheck: ignore 143
local luassert = assert
-- 批3 击杀直测：src/player/actions/location.lua 无既有直测文件，幸存者覆盖
-- find_player_by_id 缓存链 / current_player / 占用表 / relocate 方向 /
-- 医院与山区效果全流程。此处按变异位点逐面 pin 死。

local location_ops = require("src.player.actions.location")
local support = require("test.support.shared_support")
local with_patches = support.with_patches

-- 生产侧 self 是混入了 location_ops 方法的 game 对象（game:player_apply_location_effect）。
local function _base_state(overrides)
  local state = {
    board = {
      get_tile = function(_, index)
        return { id = "tile_" .. tostring(index), type = "land" }
      end,
    },
    players = {
      { id = "p1", name = "甲", position = 3, eliminated = false, status = {} },
      { id = "p2", name = "乙", position = 5, eliminated = false, status = {} },
    },
    turn = { current_player_index = 1 },
    occupants = {},
    player_by_id = nil,
    dirty = {},
    set_player_status = function() end,
    add_player_cash = function() end,
    player_cash = function() return 100 end,
  }
  for key, value in pairs(location_ops) do
    state[key] = value
  end
  for key, value in pairs(overrides or {}) do
    state[key] = value
  end
  return state
end

describe("TestLocationOps", function()

  -- ============ find_player_by_id 缓存链 ============

  it("test_find_player_by_id_resolves_from_players_without_cache", function()
    local state = _base_state()
    local player = location_ops.find_player_by_id(state, "p2")
    luassert.truthy(player == state.players[2], "find should resolve a matching player by id")
    luassert.truthy(player.id == "p2", "the resolved player keeps its id")

    luassert.truthy(location_ops.find_player_by_id(state, "nobody") == nil, "an unmatched id resolves to nil")
  end)

  it("test_find_player_by_id_tolerates_non_table_cache", function()
    -- L130/L136 type 守卫：player_by_id 为非表时不能崩，必须回落到玩家表查找。
    local state = _base_state({ player_by_id = "not-a-table" })
    local player = location_ops.find_player_by_id(state, "p1")
    luassert.truthy(player == state.players[1], "a non-table cache should not block player lookup")
  end)

  it("test_find_player_by_id_prefers_the_exact_player_id_cache_key", function()
    -- L137 首处 or->and：player_id 键命中时必须赢过 normalized 键。
    local cached = { id = "cached_a" }
    local normalized_hit = { id = "cached_b" }
    local state = _base_state({
      players = {},
      player_by_id = { ["12"] = cached, [12] = normalized_hit },
    })
    local player = location_ops.find_player_by_id(state, "12")
    luassert.truthy(player == cached, "the exact player_id cache key should win")
  end)

  it("test_find_player_by_id_prefers_normalized_over_tostring_cache_key", function()
    -- L137 第二处 or->and：normalized 键命中时必须赢过 tostring(normalized) 键。
    local normalized_hit = { id = "cached_n" }
    local text_hit = { id = "cached_t" }
    local state = _base_state({
      players = {},
      player_by_id = { [12] = normalized_hit, ["12"] = text_hit },
    })
    local player = location_ops.find_player_by_id(state, 12)
    luassert.truthy(player == normalized_hit, "the normalized cache key should win")
  end)

  it("test_find_player_by_id_reads_the_tostring_cache_key_as_last_fallback", function()
    -- L137 tostring->nil：tostring(normalized) 键是最后一层缓存兜底，且玩家不在
    -- players 表里时不能被回落查找掩盖。
    local text_hit = { id = "cached_t" }
    local state = _base_state({
      players = {},
      player_by_id = { ["12"] = text_hit },
    })
    local player = location_ops.find_player_by_id(state, 12)
    luassert.truthy(player == text_hit, "the tostring-normalized cache key should resolve")
  end)

  it("test_find_player_by_id_writes_both_cache_keys_on_first_lookup", function()
    -- pin 写盘契约：首查后 player_id 与 normalized 双键都应落盘（normalized 键
    -- 写盘本身被 tostring 回退覆盖，变异不可分——契约仍值得钉）。
    local player = { id = "12", name = "缓存角色" }
    local state = _base_state({
      players = { player },
      player_by_id = {},
    })
    local found = location_ops.find_player_by_id(state, "12")
    luassert.truthy(found == player, "first lookup should find and cache the player")
    luassert.truthy(state.player_by_id["12"] == player, "player_id cache key should be written")
    luassert.truthy(state.player_by_id[12] == player, "normalized cache key should be written")
  end)

  -- ============ current_player ============

  it("test_current_player_reads_the_index_and_reports_missing", function()
    local state = _base_state()
    luassert.truthy(location_ops.current_player(state) == state.players[1], "current_player should return the indexed player")

    local ok, err = pcall(location_ops.current_player, _base_state({ turn = {} }))
    luassert.truthy(ok == false, "missing current_player_index should fail fast")
    luassert.truthy(tostring(err):find("missing current_player_index", 1, true) ~= nil, "missing index error should carry the label")
  end)

  -- ============ update_player_position / 占用表 ============

  it("test_update_player_position_removes_only_the_moved_player_from_the_old_tile", function()
    local state = _base_state()
    local player_a = state.players[1]
    local player_b = state.players[2]
    state.occupants[3] = { player_a.id, player_b.id }
    state.occupants[9] = { player_b.id }

    location_ops.update_player_position(state, player_a, 9)

    luassert.truthy(state.occupants[3][1] == player_b.id and #state.occupants[3] == 1, "the old tile keeps the other occupant")
    luassert.truthy(state.occupants[9][2] == player_a.id, "the new tile gains the moved player")
  end)

  it("test_update_player_position_tolerates_missing_occupants_table", function()
    -- L185 两处 and->or：occupants 缺失时守卫必须放行而不是索引 nil。
    local state = _base_state({ occupants = nil })
    location_ops.update_player_position(state, state.players[1], 9)
    luassert.truthy(state.players[1].position == 9, "position should still update without occupants")
  end)

  -- ============ player_relocate ============

  it("test_player_relocate_defaults_the_move_dir_mode_to_forced_move", function()
    local facing_policy = require("src.rules.board.facing_policy")
    local captured = {}
    with_patches({
      {
        target = facing_policy,
        key = "sync_move_dir_after_position_change",
        value = function(_, _, _, mode)
          captured.mode = mode
        end,
      },
    }, function()
      local state = _base_state()
      local player = state.players[1]
      local idx, tile = location_ops.player_relocate(state, player, { destination_index = 9 })
      luassert.truthy(idx == 9 and tile.id == "tile_9", "relocate should land on the destination")
      luassert.truthy(captured.mode == "forced_move", "relocate without a mode should default to forced_move")
    end)
  end)

  it("test_player_relocate_forwards_an_explicit_move_dir_mode", function()
    local facing_policy = require("src.rules.board.facing_policy")
    local captured = {}
    with_patches({
      {
        target = facing_policy,
        key = "sync_move_dir_after_position_change",
        value = function(_, _, _, mode)
          captured.mode = mode
        end,
      },
    }, function()
      local state = _base_state()
      location_ops.player_relocate(state, state.players[1], { destination_index = 9, move_dir_mode = "reverse" })
      luassert.truthy(captured.mode == "reverse", "an explicit mode should be forwarded")
    end)
  end)

  -- ============ location 效果全流程 ============

  local function _apply_with_capture(state_overrides, effect, cash)
    local capture = {
      statuses = {},
      effects = {},
      publishes = {},
      feedback = nil,
    }
    local achievement_progress = require("src.rules.ports.achievement_progress")
    local event_feed = require("src.rules.ports.event_feed")
    local monopoly_event = require("src.foundation.events")
    local state = _base_state({
      set_player_status = function(_, player, key, value)
        capture.statuses[#capture.statuses + 1] = { player = player, key = key, value = value }
      end,
      player_cash = function() return cash end,
    })
    with_patches({
      { target = achievement_progress, key = "location_effect", value = function(_, player, kind)
        capture.effects[#capture.effects + 1] = kind
      end },
      { target = event_feed, key = "publish", value = function(_, payload)
        capture.publishes[#capture.publishes + 1] = payload
      end },
      {
        target = monopoly_event,
        key = "emit",
        value = function(kind, payload)
          capture.feedback = { kind = kind, payload = payload }
        end,
      },
    }, function()
      location_ops.player_apply_location_effect(state, state.players[1], effect)
    end)
    return capture, state
  end

  it("test_hospital_effect_publishes_fee_stay_and_feedback_with_full_payload", function()
    local capture, state = _apply_with_capture(nil, "hospital", 100)

    luassert.truthy(capture.effects[1] == "hospital", "hospital should report its effect kind")
    luassert.truthy(capture.publishes[1] ~= nil, "medical fee publish should exist")
    luassert.truthy(capture.publishes[1].tip == true, "medical fee publish should tip")
    luassert.truthy(capture.publishes[2].tip == true, "hospital stay publish should tip")
    luassert.truthy(state.players[1].eliminated == false, "a solvent player must not be eliminated")

    local feedback = capture.feedback
    luassert.truthy(feedback ~= nil, "hospital should emit status feedback")
    luassert.truthy(feedback.payload.player_id == "p1", "feedback should carry the player id")
    luassert.truthy(feedback.payload.tile_id == "tile_3", "feedback should carry the tile id")
    luassert.truthy(feedback.payload.tile_index == 3, "feedback should carry the tile index")
    luassert.truthy(feedback.payload.status_type == "hospital", "feedback should carry the hospital status type")
    luassert.truthy(feedback.payload.cue_name == "hospital_shock", "feedback should carry the hospital cue")
  end)

  it("test_hospital_effect_eliminates_when_cash_drops_to_zero_but_not_at_one", function()
    -- #208:断言真实淘汰结果，不再 stub 破产转发端口。
    local fee = require("src.config.content.constants").hospital_fee
    local game = support.new_game({ players = { "P1", "P2", "P3" }, install_ui_port = false })
    local broke, solvent = game.players[1], game.players[2]
    game:set_player_cash(broke, fee)
    game:set_player_cash(solvent, fee + 1)

    game:player_apply_location_effect(broke, "hospital")
    game:player_apply_location_effect(solvent, "hospital")

    luassert.truthy(broke.eliminated == true, "zero cash after the fee should eliminate")
    luassert.truthy(game:player_cash(broke) == 0, "the eliminated patient ends at zero cash")
    luassert.truthy(solvent.eliminated == false, "one cash after the fee must not eliminate")
    luassert.truthy(game:player_cash(solvent) == 1, "the surviving patient keeps one cash")
    luassert.truthy(solvent.status.stay_turns ~= nil and solvent.status.stay_turns > 0,
      "a surviving player should still be held in hospital")
  end)

  it("test_mountain_effect_publishes_stay_and_feedback_with_full_payload", function()
    local capture = _apply_with_capture(nil, "mountain", 100)

    luassert.truthy(capture.effects[1] == "mountain", "mountain should report its effect kind")
    luassert.truthy(capture.publishes[1].tip == true, "mountain stay publish should tip")

    local feedback = capture.feedback
    luassert.truthy(feedback ~= nil, "mountain should emit status feedback")
    luassert.truthy(feedback.payload.cue_name == "mountain_stun", "feedback should carry the mountain cue")
    luassert.truthy(feedback.payload.status_type == "mountain", "feedback should carry the mountain status type")
    luassert.truthy(feedback.payload.player_id == "p1", "feedback should carry the player id")
    luassert.truthy(feedback.payload.tile_id == "tile_3", "feedback should carry the tile id")
  end)

  it("test_unknown_location_effect_rejects_with_the_stable_message", function()
    local ok, err = pcall(location_ops.player_apply_location_effect,
      _base_state(), _base_state().players[1], "bogus_effect")
    luassert.truthy(ok == false, "an unknown location effect should error")
    luassert.truthy(tostring(err):find("unknown location effect: bogus_effect", 1, true) ~= nil, "the unknown-effect error should carry the effect value")
  end)


end)
