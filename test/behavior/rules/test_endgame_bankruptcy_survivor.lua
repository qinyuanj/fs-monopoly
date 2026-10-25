-- bankruptcy.lua 变异 survivor 补测（#168）：钉住显式 popup port、
-- 破产弹窗载荷穿透、清算触发边界与 occupant 反向清除。全部经公开入口
-- （eliminate / resolve_bankruptcy_text）驱动,协作方用 with_patches 桩。
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local bankruptcy = require("src.rules.elimination.bankruptcy")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local bankruptcy_feedback_port = require("src.rules.ports.bankruptcy_feedback")
local event_feed = require("src.rules.ports.event_feed")
local life_loss = require("src.rules.elimination.life_loss")
local inventory_class = require("src.player.actions.inventory")
local monopoly_event = require("src.foundation.events")
local event_kinds = require("src.config.gameplay.event_kinds")

local logger = require("src.foundation.log")

local _assert_eq = support.assert_eq
local _with_patches = support.with_patches

local function _make_player(opts)
  opts = opts or {}
  return {
    id = opts.id or 7,
    name = opts.name or "破产者",
    properties = opts.properties or {},
    eliminated = opts.eliminated or nil,
    inventory = opts.inventory or inventory_class:new({ max_slots = 2 }),
  }
end

-- 合成 game：只带 eliminate 消费的方法面。tiles = { [tile_id] = tile }。
local function _make_game(opts)
  opts = opts or {}
  local calls = { reset_tiles = {}, property_sets = {}, eliminated = {}, deity_cleared = {} }
  local game = {
    occupants = opts.occupants or {},
    popup_port = opts.popup_port,
    board = {
      get_tile_by_id = function(_, tile_id)
        return (opts.tiles or {})[tile_id]
      end,
    },
    reset_tile = function(_, tile)
      calls.reset_tiles[#calls.reset_tiles + 1] = tile
    end,
    set_player_property = function(_, player, tile_id, owned)
      calls.property_sets[#calls.property_sets + 1] = { player = player, tile_id = tile_id, owned = owned }
    end,
    set_player_eliminated = function(_, player, flag)
      calls.eliminated[#calls.eliminated + 1] = { player = player, flag = flag }
    end,
    clear_player_deity = function(_, player)
      calls.deity_cleared[#calls.deity_cleared + 1] = player
    end,
  }
  return game, calls
end

-- 通用桩：隔离全局协作方,捕获 event_feed 与清算反馈。
local function _run_eliminate(game, player, opts, extra_patches)
  local events = {}
  local feedback = {}
  local patches = {
    { target = event_feed, key = "publish", value = function(_, event)
      events[#events + 1] = event
    end },
    { target = bankruptcy_feedback_port, key = "on_tiles_cleared", value = function(_, p, ids)
      feedback[#feedback + 1] = { player = p, tile_ids = ids }
    end },
    { target = runtime_ports, key = "resolve_role", value = function() return nil end },
    { target = runtime_ports, key = "mark_role_lose", value = function() end },
    { target = life_loss, key = "try_call_life_die", value = function() end },
  }
  for _, patch in ipairs(extra_patches or {}) do
    patches[#patches + 1] = patch
  end
  _with_patches(patches, function()
    bankruptcy.eliminate(game, player, opts)
  end)
  return events, feedback
end

describe("TestEndgameBankruptcySurvivor", function()
it("test_淘汰清空道具槽：槽位数不变、每槽置空", function()
  local game = _make_game({})
  local inv = inventory_class:new({ max_slots = 3 })
  inv:add({ id = "a" })
  inv:add({ id = "b" })
  local player = _make_player({ inventory = inv })
  _run_eliminate(game, player)
  local items = player.inventory.items
  _assert_eq(#items, 3, "slot count follows max_slots")
  _assert_eq(items[1], false, "slot 1 cleared")
  _assert_eq(items[2], false, "slot 2 cleared")
  _assert_eq(items[3], false, "slot 3 cleared")
  _assert_eq(player.inventory._suspend_on_change, false, "change notifications resume after clearing")
end)

it("test_popup_port 直连分支：破产弹窗载荷逐字段穿透", function()
  local pushed = {}
  local port = { push_popup = function(_, payload) pushed[#pushed + 1] = payload end }
  local game = _make_game({ popup_port = port })
  local player = _make_player({ id = 11, name = "阿破" })
  _run_eliminate(game, player, { reason = "被税收压垮" })
  _assert_eq(#pushed, 1, "one bankruptcy popup should be pushed")
  _assert_eq(pushed[1].kind, "bankruptcy", "popup kind")
  _assert_eq(pushed[1].player_id, 11, "popup player_id")
  _assert_eq(pushed[1].player_name, "阿破", "popup player_name")
  _assert_eq(pushed[1].text, "被税收压垮", "popup text should use opts.reason")
end)

it("test_popup port 完全缺位或缺 push_popup 方法时均静默", function()
  local game_none = _make_game({})
  _run_eliminate(game_none, _make_player())
  local game_no_push = _make_game({ popup_port = {} })
  _run_eliminate(game_no_push, _make_player())
end)

it("test_无持有地块时不发清算事件、不调清算反馈", function()
  local game = _make_game({})
  local events, feedback = _run_eliminate(game, _make_player({ properties = {} }))
  for _, event in ipairs(events) do
    luassert.truthy(event.kind ~= event_kinds.bankruptcy_liquidation,
      "no liquidation event without owned tiles")
  end
  _assert_eq(#feedback, 0, "feedback port must not fire without owned tiles")
end)

it("test_恰有一块地时清算触发：事件/重置/反馈一次不多不少", function()
  local tile = { id = "t1", name = "一号地" }
  local game, calls = _make_game({ tiles = { t1 = tile } })
  local player = _make_player({ properties = { t1 = true, t2 = false } })
  local events, feedback = _run_eliminate(game, player)
  local liquidation_events = {}
  for _, event in ipairs(events) do
    if event.kind == event_kinds.bankruptcy_liquidation then
      liquidation_events[#liquidation_events + 1] = event
    end
  end
  _assert_eq(#liquidation_events, 1, "exactly one liquidation event")
  luassert.truthy(liquidation_events[1].text:find("一号地", 1, true) ~= nil, "liquidation text should name the tile")
  _assert_eq(#calls.reset_tiles, 1, "exactly the owned tile is reset")
  _assert_eq(calls.reset_tiles[1], tile, "reset should target the owned tile")
  _assert_eq(#calls.property_sets, 1, "one ownership clear")
  _assert_eq(calls.property_sets[1].owned, false, "ownership must be cleared to false")
  _assert_eq(#feedback, 1, "feedback port fires once")
  _assert_eq(#feedback[1].tile_ids, 1, "feedback carries the owned tile id")
  _assert_eq(feedback[1].tile_ids[1], "t1", "feedback tile id")
end)

it("test_多块地清算时事件文本用顿号连接", function()
  -- #293:table.concat(names, "、") 的 separator 变异(→ nil)未测。
  local tile_a = { id = "ta", name = "甲地" }
  local tile_b = { id = "tb", name = "乙地" }
  local game, _ = _make_game({ tiles = { ta = tile_a, tb = tile_b } })
  local player = _make_player({ properties = { ta = true, tb = true } })
  local events = _run_eliminate(game, player)
  local joined = ""
  for _, event in ipairs(events) do
    if event.kind == event_kinds.bankruptcy_liquidation then
      joined = event.text
    end
  end
  luassert.truthy(joined:find("、", 1, true) ~= nil
    and joined:find("甲地", 1, true) ~= nil and joined:find("乙地", 1, true) ~= nil,
    "liquidation text should join tile names with 、; got " .. tostring(joined))
end)

it("test_occupant 清除：连续重复命中全清,他人原序保留", function()
  -- 反向遍历边界:相邻重复(7,7)必须都被移除——正向遍历或 -1 偏移变异会漏删。
  local game = _make_game({
    occupants = {
      tile_a = { 7, 7, 3, 7 },
      tile_b = { 1, 2 },
    },
  })
  _run_eliminate(game, _make_player({ id = 7 }))
  _assert_eq(#game.occupants.tile_a, 1, "all copies of the player id must be removed")
  _assert_eq(game.occupants.tile_a[1], 3, "other occupants survive")
  _assert_eq(#game.occupants.tile_b, 2, "untouched lists keep their members")
  _assert_eq(game.occupants.tile_b[1], 1, "untouched order preserved (first)")
  _assert_eq(game.occupants.tile_b[2], 2, "untouched order preserved (second)")
end)

it("test_已出局玩家重复 eliminate 是无操作", function()
  local game, calls = _make_game({})
  local events = _run_eliminate(game, _make_player({ eliminated = true }))
  _assert_eq(#events, 0, "no events for an already-eliminated player")
  _assert_eq(#calls.eliminated, 0, "elimination flag must not be re-set")
end)

it("test_resolve_bankruptcy_text：reason 非空用 reason,空串/缺省回默认文案", function()
  local player = _make_player({ name = "小明" })
  _assert_eq(bankruptcy.resolve_bankruptcy_text(player, { reason = "欠租" }), "欠租",
    "non-empty reason wins")
  _assert_eq(bankruptcy.resolve_bankruptcy_text(player, { reason = "" }), "小明 破产出局",
    "empty reason falls back to the default text")
  _assert_eq(bankruptcy.resolve_bankruptcy_text(player, nil), "小明 破产出局",
    "missing opts falls back to the default text")
end)

it("test_持有的 tile id 不在棋盘时跳过并告警,不炸清算", function()
  -- properties 里挂一个棋盘上不存在的 stale id:清算必须跳过它、
  -- 走 logger.warn 告警路径,其余真实地契照常清算。
  local warned = {}
  local tile = { id = "t1", name = "存在的地" }
  local game, calls = _make_game({ tiles = { t1 = tile } })
  local player = _make_player({ properties = { t1 = true, ghost_tile = true } })
  _run_eliminate(game, player, {}, {
    { target = logger, key = "warn", value = function(...)
      warned[#warned + 1] = table.concat({ ... }, " ")
    end },
  })
  _assert_eq(#warned, 1, "missing tile should be warned exactly once")
  luassert.truthy(warned[1]:find("ghost_tile", 1, true), "warn should name the stale tile id, got " .. tostring(warned[1]))
  _assert_eq(#calls.reset_tiles, 1, "only the real tile gets reset")
  _assert_eq(calls.reset_tiles[1], tile, "the real tile is the one reset")
end)

it("test_eliminate_emits_feedback_event_with_bankruptcy_text_as_reason", function()
  local emitted = {}
  _run_eliminate(_make_game({}), _make_player({ name = "张三" }), { reason = "欠租出局" }, {
    { target = monopoly_event, key = "emit", value = function(kind, payload)
      emitted[#emitted + 1] = { kind = kind, payload = payload }
    end },
  })
  _assert_eq(#emitted, 1, "one bankruptcy feedback event should be emitted")
  _assert_eq(emitted[1].payload.reason, "欠租出局", "event reason should use the bankruptcy text")
  _assert_eq(emitted[1].payload.player_id, 7, "event player_id should match")
end)

it("test_clear_occupant_lists_stops_at_index_1_even_when_0_holds_the_player_id", function()
  -- kills the reverse loop's lower-bound `1` -> `0`: a list with a seeded
  -- [0] entry makes the extra iteration observable — the mutant walks to
  -- i=0, matches the seeded id, and table.remove(list, 0) raises
  -- "position out of bounds".
  local list = { 5, 7 }
  list[0] = 5
  local game = { occupants = { tile_a = list } }
  bankruptcy._M_test._clear_occupant_lists(game, { id = 5 })
  support.assert_eq(#list, 1, "the matching array entry should be removed")
  support.assert_eq(list[1], 7, "the non-matching entry should stay")
  support.assert_eq(list[0], 5, "the seeded [0] probe must be left untouched")
end)


end)
