local check = require("luassert")
local roll = require("src.turn.phases.roll")
local dice_multiplier = require("src.turn.phases.dice_multiplier")
local status_ops = require("src.player.actions.status")

describe("TestRollDice", function()

local module_names = { "src.rules.movement", "src.turn.phases.move_followup", "src.turn.phases.move" }
local original_modules
before_each(function()
  original_modules = {}
  for _, name in ipairs(module_names) do original_modules[name] = package.loaded[name] end
end)
after_each(function()
  for _, name in ipairs(module_names) do package.loaded[name] = original_modules[name] end
end)

local function _test_apply_roll_total_uses_pending_multiplier()
  local game = { player_pending_dice_multiplier = status_ops.player_pending_dice_multiplier }
  local boosted = { id = 1, status = { pending_dice_multiplier = 4 } }
  check.is_truthy(dice_multiplier.apply_roll_total(game, 3, boosted) == 12,
    "apply_roll_total should multiply raw total by the pending multiplier")
  local plain = { id = 2, status = {} }
  check.is_truthy(dice_multiplier.apply_roll_total(game, 5, plain) == 5,
    "apply_roll_total should pass through raw total without a multiplier")
end

it("test_apply_dice_multiplier_applies_and_resets", function()
  local player = { id = 1, name = "P1", position = 1, status = { pending_dice_multiplier = 4 } }
  local game = {
    board = { get_tile = function() return { type = "normal" } end },
    turn = { move_anim_seq = 0, last_turn = {} },
    dirty = {},
    players = { player },
    anim_gate_port = { wait_move_anim = false },
    player_pending_dice_multiplier = status_ops.player_pending_dice_multiplier,
    consume_pending_dice_multiplier = status_ops.consume_pending_dice_multiplier,
  }
  local turn_mgr = { game = game }
  local original_movement = package.loaded["src.rules.movement"]
  local original_move_followup = package.loaded["src.turn.phases.move_followup"]
  package.loaded["src.rules.movement"] = {
    move = function(_, _, total)
      check.is_truthy(total == 12, "total should be multiplied: expected 12, got " .. tostring(total))
      return { visited = {}, steps = {} }
    end
  }
  package.loaded["src.turn.phases.move_followup"] = {
    run = function() return "test_result" end
  }
  package.loaded["src.turn.phases.move"] = nil
  local move_module = require("src.turn.phases.move")
  local result = move_module(turn_mgr, {
    player = player,
    total = 3,
    raw_total = 3,
  })
  check.is_truthy(game:player_pending_dice_multiplier(player) == 1, "should reset multiplier to 1")
  package.loaded["src.rules.movement"] = original_movement
  package.loaded["src.turn.phases.move_followup"] = original_move_followup
  package.loaded["src.turn.phases.move"] = nil
  check.is_truthy(result == "test_result", "should complete move phase")
end)

it("test_apply_dice_multiplier_nil_raw_total", function()
  local player = { id = 1, position = 1, status = { pending_dice_multiplier = 3 } }
  local turn_mgr = {
    game = {
      board = { get_tile = function() return { type = "normal" } end },
      turn = { move_anim_seq = 0 },
      dirty = {},
      players = { player },
      anim_gate_port = { wait_move_anim = false },
      player_pending_dice_multiplier = status_ops.player_pending_dice_multiplier,
      consume_pending_dice_multiplier = status_ops.consume_pending_dice_multiplier,
    },
  }
  local original_movement = package.loaded["src.rules.movement"]
  local original_move_followup = package.loaded["src.turn.phases.move_followup"]
  package.loaded["src.rules.movement"] = {
    move = function(game, p, total)
      check.is_truthy(total == 6, "total should not be multiplied when raw_total is nil")
      return { visited = {}, steps = {} }
    end
  }
  package.loaded["src.turn.phases.move_followup"] = {
    run = function() return "test_result" end
  }
  package.loaded["src.turn.phases.move"] = nil
  local move_module = require("src.turn.phases.move")
  local result = move_module(turn_mgr, {
    player = player,
    total = 6,
    raw_total = nil,
  })
  package.loaded["src.rules.movement"] = original_movement
  package.loaded["src.turn.phases.move_followup"] = original_move_followup
  package.loaded["src.turn.phases.move"] = nil
  check.is_truthy(result == "test_result", "should skip multiplier when raw_total is nil")
end)

it("test_apply_move_total_applies_multiplier_updates_last_turn_and_publishes", function()
  local game = {
    last_turn = { total = 0 },
    dirty = {},
    player_pending_dice_multiplier = status_ops.player_pending_dice_multiplier,
    consume_pending_dice_multiplier = status_ops.consume_pending_dice_multiplier,
  }
  local player = { id = 1, name = "P1", position = 1, status = { pending_dice_multiplier = 4 } }

  local total = dice_multiplier.apply_move_total(game, player, 3, 3)

  check.is_truthy(total == 12, "multiplied total should be applied")
  check.is_truthy(game.last_turn.total == 12, "last_turn should record the multiplied total")
end)

it("test_apply_roll_total_uses_pending_multiplier", function()
  _test_apply_roll_total_uses_pending_multiplier()
end)

it("test_play_roll_dice_rejects_invalid_face_zero", function()
  -- anim.total = 0：无效值，_resolve_face_value 返回 nil，回退到默认 face 1
  -- 变异 >=0 会使 face=0 通过检查，导致 face 0 而非 face 1（Lua 中 0 是 truthy）
  local dice_anim = require("src.ui.render.anim.dice")

  local face_nodes = {}
  for i = 1, 6 do
    face_nodes[i] = { visible = false }
  end

  local node_map = {
    canvas = { visible = false },
    spin = { visible = false },
    f1 = face_nodes[1], f2 = face_nodes[2], f3 = face_nodes[3],
    f4 = face_nodes[4], f5 = face_nodes[5], f6 = face_nodes[6],
  }

  local runtime = {
    query_node = function(name) return node_map[name] end,
    for_each_role_or_global = function(fn) fn() end,
  }

  local schedule_calls = {}
  local opts = {
    runtime = runtime,
    dice_screen_nodes = {
      canvas = "canvas", spin = "spin",
      faces = { "f1", "f2", "f3", "f4", "f5", "f6" },
    },
    ui_events = {
      show = {}, hide = {},
      send_to_all = function() end,
    },
    schedule = function(delay, fn)
      table.insert(schedule_calls, delay)
      if #schedule_calls == 1 then
        fn()
      end
    end,
  }

  dice_anim.play_roll_dice_screen({ total = 0 }, 0, 0, opts)
  -- total=0 被 >=1 拒绝，_resolve_face_value 返回 nil
  -- _resolve_roll_display_face 走 or 1 默认，最终 face=1
  -- 变异 >=0 会使 0 通过检查，_resolve_face_value 返回 0（0 是 truthy）
  -- _resolve_roll_display_face: 0 or 1 = 0（Lua 中 0 是 truthy，or 短路返回 0）
  -- _show_roll_result 设 face=0 → _set_face_nodes_visibility 中 face==index 全为 false
  -- 原代码 face 1 可见，变异存活则所有 face 不可见
  check.is_truthy(face_nodes[1].visible == true,
    "face 1 should be visible as default when total=0 is rejected (kill replace 1 with 0)")
end)

it("test_play_roll_dice_resolves_face_from_anim_data", function()
  -- 测试 face 解析逻辑：total 边界值(6)、正常值(3)、rolls 优先、回退到 total
  -- 覆盖 _resolve_face_value 和 _resolve_roll_face 的各条分支
  local dice_anim = require("src.ui.render.anim.dice")

  local face_nodes = {}
  for i = 1, 6 do
    face_nodes[i] = { visible = false }
  end

  local node_map = {
    canvas = { visible = false },
    spin = { visible = false },
    f1 = face_nodes[1], f2 = face_nodes[2], f3 = face_nodes[3],
    f4 = face_nodes[4], f5 = face_nodes[5], f6 = face_nodes[6],
  }

  local runtime = {
    query_node = function(name) return node_map[name] end,
    for_each_role_or_global = function(fn) fn() end,
  }

  local schedule_calls = {}
  local function make_opts()
    schedule_calls = {}
    for _, n in pairs(node_map) do n.visible = false end
    return {
      runtime = runtime,
      dice_screen_nodes = {
        canvas = "canvas", spin = "spin",
        faces = { "f1", "f2", "f3", "f4", "f5", "f6" },
      },
      ui_events = {
        show = {}, hide = {},
        send_to_all = function() end,
      },
      schedule = function(delay, fn)
        table.insert(schedule_calls, delay)
        if #schedule_calls == 1 then
          fn() -- 只执行 step，跳过 cleanup 以便检查中间状态
        end
      end,
    }
  end

  -- anim.total = 6：边界值，验证 <=6 判定（杀死 replace <= with <）
  dice_anim.play_roll_dice_screen({ total = 6 }, 0, 0, make_opts())
  check.is_truthy(face_nodes[6].visible, "face 6 should be visible for total=6")
  check.is_truthy(not face_nodes[5].visible, "face 5 should not be visible for total=6")

  -- anim.total = 3：验证 _resolve_face_value 正常解析（杀死 to_integer→nil）
  dice_anim.play_roll_dice_screen({ total = 3 }, 0, 0, make_opts())
  check.is_truthy(face_nodes[3].visible, "face 3 should be visible for total=3")
  check.is_truthy(not face_nodes[1].visible, "face 1 should not be visible for total=3")

  -- anim.total = 5 无 rolls：验证回退到 anim.total 路径（杀死 _resolve_face_value(anim.total)→nil）
  dice_anim.play_roll_dice_screen({ total = 5 }, 0, 0, make_opts())
  check.is_truthy(face_nodes[5].visible, "face 5 should be visible for total=5 (fallback path)")

  -- anim.rolls = {3}：验证优先使用 rolls[1]（杀死 _resolve_roll_face(anim)→nil）
  dice_anim.play_roll_dice_screen({ rolls = { 3 } }, 0, 0, make_opts())
  check.is_truthy(face_nodes[3].visible, "face 3 should be visible when rolls={3}")
end)

it("test_play_roll_dice_timing_defaults_to_zero", function()
  -- 测试 duration/hold_seconds nil 时默认值为 0（杀死 replace 0 with 1）
  local dice_anim = require("src.ui.render.anim.dice")

  local node_map = {
    canvas = { visible = false },
    spin = { visible = false },
  }
  for i = 1, 6 do
    node_map["f" .. i] = { visible = false }
  end

  local runtime = {
    query_node = function(name) return node_map[name] end,
    for_each_role_or_global = function(fn) fn() end,
  }

  local schedule_calls = {}
  local function make_opts()
    schedule_calls = {}
    return {
      runtime = runtime,
      dice_screen_nodes = {
        canvas = "canvas", spin = "spin",
        faces = { "f1", "f2", "f3", "f4", "f5", "f6" },
      },
      ui_events = {
        show = {}, hide = {},
        send_to_all = function() end,
      },
      schedule = function(delay, fn)
        table.insert(schedule_calls, delay)
        if #schedule_calls == 1 then
          fn() -- 执行 step 以触发副作用验证
        end
      end,
    }
  end

  -- duration=nil → 默认值 0（杀第一个 replace 0 with 1）
  dice_anim.play_roll_dice_screen(nil, nil, 0, make_opts())
  check.is_truthy(#schedule_calls >= 1, "should have at least one schedule call")
  check.is_truthy(schedule_calls[1] == 0,
    "step delay should default to 0 when duration is nil, got " .. tostring(schedule_calls[1]))

  -- hold_seconds=nil → cleanup_delay 仍为 0（杀第二个 replace 0 with 1）
  dice_anim.play_roll_dice_screen(nil, 0, nil, make_opts())
  check.is_truthy(#schedule_calls >= 2, "should have at least two schedule calls when cleanup present")
  -- cleanup_delay = duration + hold_seconds，hold_seconds=nil 默认 0，cleanup delay 应为 0
  -- _schedule_teardown 调用 run_step(cleanup_delay or 0, ...) 再 scheduler(delay or 0, ...)
  -- 第二帧 schedule 的 delay 就是 cleanup 调度的 delay
  check.is_truthy(schedule_calls[2] == 0,
    "cleanup delay should default to 0 when hold_seconds is nil, got " .. tostring(schedule_calls[2]))
end)

it("test_roll_dice_more_overrides", function()
  local results, total = roll._roll_dice(2, { 1, 2, 3, 4 }, { next_int = function() return 6 end })
  check.is_truthy(#results == 2, "should return only 2 results")
  check.is_truthy(results[1] == 1 and results[2] == 2, "should use first 2 override values")
  check.is_truthy(total == 3, "total should be sum of first 2 values")
end)


it("test_roll_dice_screen_tolerates_a_nil_anim", function()
  local dice_anim = require("src.ui.render.anim.dice")
  local runtime = {
    query_node = function()
      return { visible = false }
    end,
    for_each_role_or_global = function(fn)
      fn()
    end,
  }
  local opts = {
    runtime = runtime,
    dice_screen_nodes = {
      canvas = "canvas_node",
      spin = "spin_node",
      faces = { "face_1", "face_2", "face_3", "face_4", "face_5", "face_6" },
    },
    ui_events = {
      show = {},
      hide = {},
      send_to_all = function() end,
    },
    schedule = function() end,
  }

  dice_anim.play_roll_dice_screen(nil, 0, 0, opts)

  check.is_truthy(true, "roll dice screen should tolerate a nil anim")
end)

it("test_roll_dice_single_die_rng", function()
  local results, total = roll._roll_dice(1, nil, { next_int = function(_, min, max) return min end })
  check.is_truthy(#results == 1, "should return 1 result")
  check.is_truthy(results[1] == 1, "should use min value from rng")
  check.is_truthy(total == 1, "total should be min value")
end)

it("test_roll_dice_zero_count", function()
  local results, total = roll._roll_dice(0, nil, { next_int = function() return 3 end })
  check.is_truthy(#results == 0, "should return empty results for zero dice")
  check.is_truthy(total == 0, "total should be 0 for zero dice")
end)

end)
