-- leaderboard_settlement 装配接线:gm.finished 事件触发当前对局的 settle;
-- 惰性访问器缺位时跳过接线(context-only 测试装配路径)。
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local host_runtime = require("src.host.init")
local monopoly_event = require("src.foundation.events")
local leaderboard = require("src.app.host_integrations.leaderboard")
local settlement = require("src.app.host_integrations.leaderboard_settlement")
local logger = require("src.foundation.log")

local function _install_archives()
  local store = {}
  runtime_ports.configure({
    archives_enabled = function()
      return true
    end,
    get_archive_int = function(role_id, archive_key)
      return store[tostring(role_id) .. "|" .. tostring(archive_key)] or 0
    end,
    set_archive_int = function(role_id, archive_key, value)
      store[tostring(role_id) .. "|" .. tostring(archive_key)] = value
    end,
  })
  return store
end

describe("TestLeaderboardSettlement", function()
  after_each(function()
    runtime_ports.reset_for_tests()
    support.restore_runtime_services()
  end)

local function _test_skips_wiring_without_lazy_game_accessor()
  local register_calls = 0
  support.with_patches({
    {
      target = host_runtime,
      key = "register_custom_event",
      value = function()
        register_calls = register_calls + 1
        return true
      end,
    },
  }, function()
    luassert.truthy(settlement.install({}) == false, "install without get_current_game must skip wiring")
    luassert.truthy(settlement.install(nil) == false, "install without opts must skip wiring")
  end)
  -- lint-allow: call-count host_runtime.register_custom_event 封装 LuaAPI.global_register_custom_event,零调用=未向引擎注册事件
  luassert.truthy(register_calls == 0, "skipped install must not touch the host event port")
end

local function _test_settles_current_game_on_game_finished_event()
  local handler = nil
  local game = {
    players = { { id = 1, name = "P1", properties = {}, cash = 30000 } },
    winners = { { id = 1 } },
    player_cash = function(_, player)
      return player.cash or 0
    end,
    board = { get_tile_by_id = function() return nil end },
  }
  support.with_patches({
    {
      target = host_runtime,
      key = "register_custom_event",
      value = function(event_name, fn)
        luassert.truthy(event_name == monopoly_event.game.finished,
          "settlement must subscribe the game.finished event; got " .. tostring(event_name))
        handler = fn
        return true
      end,
    },
  }, function()
    luassert.truthy(settlement.install({ get_current_game = function() return game end }) == true,
      "install must report wiring success")
  end)
  -- with_patches 收尾会把 runtime ports 刷回共享基线,内存档案必须在接线之后再装。
  local store = _install_archives()

  luassert.truthy(type(handler) == "function", "install must register a handler")
  handler("gm.finished", nil, {})

  luassert.truthy(store["1|" .. tostring(leaderboard.win_count_archive_key)] == 1,
    "winner must gain one win on game finished")
  luassert.truthy(store["1|" .. tostring(leaderboard.total_assets_archive_key)] == 30000,
    "present player must accumulate remaining assets on game finished")
  luassert.truthy(game.leaderboard_settled == true, "settle must mark the game settled")
end

local function _test_handler_tolerates_missing_game()
  local handler = nil
  support.with_patches({
    {
      target = host_runtime,
      key = "register_custom_event",
      value = function(_, fn)
        handler = fn
        return true
      end,
    },
  }, function()
    settlement.install({ get_current_game = function() return nil end })
  end)

  handler("gm.finished", nil, {})
end

-- with_patches 会刷新 runtime ports 基线,watch_game 用例以
-- skip_runtime_context_refresh 保住自配的 resolve_role,teardown 负责装回基线。
local function _configure_roles(role_by_id)
  runtime_ports.configure({
    resolve_role = function(role_id)
      return role_by_id[role_id] or nil
    end,
  })
end

local function _test_watch_game_registers_quit_listener_per_human_player()
  local role1, role3 = { tag = "role1" }, { tag = "role3" }
  _configure_roles({ [1] = role1, [3] = role3 })
  local ai_player = { id = 2, name = "AI", is_ai = true }
  local human1 = { id = 1, name = "P1" }
  local human3 = { id = 3, name = "P3" }
  local registrations = {}
  local warns = {}
  support.with_patches({
    {
      target = host_runtime,
      key = "register_trigger_event",
      value = function(event_desc, fn)
        registrations[#registrations + 1] = { desc = event_desc, handler = fn }
        return true, "trigger-handle"
      end,
    },
    {
      target = logger,
      key = "warn",
      value = function(...)
        warns[#warns + 1] = { ... }
      end,
    },
  }, function()
    luassert.truthy(settlement.watch_game({ players = { human1, ai_player, human3 } }) == true,
      "watch_game must report wiring success")
  end, { skip_runtime_context_refresh = true })

  luassert.truthy(#registrations == 2, "must watch exactly the two human players; got " .. #registrations)
  luassert.truthy(registrations[1].desc[1] == "ET_SPEC_ROLE_EXIT_GAME",
    "quit watch must use the host role-exit trigger event")
  luassert.truthy(registrations[1].desc[2] == role1, "quit watch must pass the resolved role")
  luassert.truthy(registrations[2].desc[2] == role3, "quit watch must pass the resolved role")

  registrations[2].handler("ET_SPEC_ROLE_EXIT_GAME", nil, {})
  luassert.truthy(human3.quit_reason == "disconnect", "exiting player must be marked quit")
  luassert.truthy(human1.quit_reason == nil, "staying player must not be marked")

  registrations[2].handler("ET_SPEC_ROLE_EXIT_GAME", nil, {})
  luassert.truthy(human3.quit_reason == "disconnect", "repeated exit events must keep the first mark")
  luassert.truthy(#warns == 0, "healthy registration must not leave skip warns")
end

local function _test_exit_callback_skips_other_players_exit()
  _configure_roles({ [1] = { tag = "role1" } })
  local player1 = { id = 1, name = "P1" }
  local registrations = {}
  support.with_patches({
    {
      target = host_runtime,
      key = "register_trigger_event",
      value = function(event_desc, fn)
        registrations[#registrations + 1] = { desc = event_desc, handler = fn }
        return true, "trigger-handle"
      end,
    },
  }, function()
    settlement.watch_game({ players = { player1 } })
  end, { skip_runtime_context_refresh = true })

  -- 触发语义未取证(#585):宿主若不按注册 role 过滤,任一玩家退出会触发
  -- 全部回调;payload role 指向他人时不得标记本玩家,指向本人时标记。
  registrations[1].handler("ET_SPEC_ROLE_EXIT_GAME", nil, { role = { get_roleid = function() return 2 end } })
  luassert.truthy(player1.quit_reason == nil,
    "another player's exit (roleid path) must not mark this player")
  registrations[1].handler("ET_SPEC_ROLE_EXIT_GAME", nil, { role = { id = 2 } })
  luassert.truthy(player1.quit_reason == nil,
    "another player's exit (id path) must not mark this player")
  registrations[1].handler("ET_SPEC_ROLE_EXIT_GAME", nil, { role = 2 })
  luassert.truthy(player1.quit_reason == nil,
    "another player's exit (raw id path) must not mark this player")
  registrations[1].handler("ET_SPEC_ROLE_EXIT_GAME", nil, { role = { id = "1" } })
  luassert.truthy(player1.quit_reason == "disconnect",
    "own exit with string role id must mark this player")
end

local function _test_watch_game_skips_and_logs_when_role_unresolved()
  _configure_roles({})
  local warns = {}
  local register_calls = 0
  support.with_patches({
    {
      target = host_runtime,
      key = "register_trigger_event",
      value = function()
        register_calls = register_calls + 1
        return true
      end,
    },
    {
      target = logger,
      key = "warn",
      value = function(...)
        warns[#warns + 1] = { ... }
      end,
    },
  }, function()
    settlement.watch_game({ players = { { id = 7, name = "P7" } } })
  end, { skip_runtime_context_refresh = true })

  -- lint-allow: call-count host_runtime.register_trigger_event 封装 LuaAPI.global_register_trigger_event,零调用=未向引擎注册退出监听
  luassert.truthy(register_calls == 0, "unresolved role must not register a quit listener")
  luassert.truthy(#warns == 1, "unresolved role must leave a warn trace (ADR 0046)")
end

local function _test_watch_game_warns_when_host_rejects_registration()
  _configure_roles({ [1] = { tag = "role1" } })
  local warns = {}
  support.with_patches({
    {
      target = host_runtime,
      key = "register_trigger_event",
      value = function()
        -- 真机取证(#585):宿主拒绝时 SDK 包装层吞错,首返回值仍为 true,句柄为 nil。
        return true, nil
      end,
    },
    {
      target = logger,
      key = "warn",
      value = function(...)
        warns[#warns + 1] = { ... }
      end,
    },
  }, function()
    settlement.watch_game({ players = { { id = 1, name = "P1" } } })
  end, { skip_runtime_context_refresh = true })

  luassert.truthy(#warns == 1, "rejected registration must leave a warn trace (ADR 0046)")
end

-- 未知 proxy 形态(既非 table 也非字符串/数字)读不出 id:保守按本玩家退出标记。
local function _test_exit_callback_marks_quit_when_role_id_is_unreadable()
  _configure_roles({ [1] = { tag = "role1" } })
  local player1 = { id = 1, name = "P1" }
  local registrations = {}
  support.with_patches({
    {
      target = host_runtime,
      key = "register_trigger_event",
      value = function(event_desc, fn)
        registrations[#registrations + 1] = { desc = event_desc, handler = fn }
        return true, "trigger-handle"
      end,
    },
  }, function()
    settlement.watch_game({ players = { player1 } })
  end, { skip_runtime_context_refresh = true })

  registrations[1].handler("ET_SPEC_ROLE_EXIT_GAME", nil, { role = true })
  luassert.truthy(player1.quit_reason == "disconnect",
    "unreadable role payload must fall back to marking this player quit")
end

-- 端口不可用(首返回值为 false)与宿主拒绝是两条独立跳过路径,都必须留痕。
local function _test_watch_game_warns_when_trigger_port_is_unavailable()
  _configure_roles({ [1] = { tag = "role1" } })
  local warns = {}
  support.with_patches({
    {
      target = host_runtime,
      key = "register_trigger_event",
      value = function()
        return false, nil
      end,
    },
    {
      target = logger,
      key = "warn",
      value = function(...)
        warns[#warns + 1] = { ... }
      end,
    },
  }, function()
    settlement.watch_game({ players = { { id = 1, name = "P1" } } })
  end, { skip_runtime_context_refresh = true })

  luassert.truthy(#warns == 1, "unavailable trigger port must leave a warn trace (ADR 0046)")
end

-- get_roleid 读不出(返回 nil 或抛错)时回落 .id 比对,不得把 nil 或错误消息当 id。
local function _test_exit_callback_falls_back_to_role_id_field_when_get_roleid_fails()
  _configure_roles({ [1] = { tag = "role1" } })
  local player1 = { id = 1, name = "P1" }
  local registrations = {}
  support.with_patches({
    {
      target = host_runtime,
      key = "register_trigger_event",
      value = function(event_desc, fn)
        registrations[#registrations + 1] = { desc = event_desc, handler = fn }
        return true, "trigger-handle"
      end,
    },
  }, function()
    settlement.watch_game({ players = { player1 } })
  end, { skip_runtime_context_refresh = true })

  registrations[1].handler("ET_SPEC_ROLE_EXIT_GAME", nil,
    { role = { get_roleid = function() return nil end, id = 2 } })
  luassert.is_nil(player1.quit_reason, "nil get_roleid must fall back to .id and see another player's exit")
  registrations[1].handler("ET_SPEC_ROLE_EXIT_GAME", nil,
    { role = { get_roleid = function() error("proxy gone") end, id = 1 } })
  luassert.is.equal("disconnect", player1.quit_reason, "raising get_roleid must fall back to .id and mark own exit")
end

local function _test_watch_game_rejects_missing_game_or_players()
  luassert.truthy(settlement.watch_game(nil) == false, "watch_game must reject nil game")
  luassert.truthy(settlement.watch_game({}) == false, "watch_game must reject a game without players")
end

it("test_skips_wiring_without_lazy_game_accessor", _test_skips_wiring_without_lazy_game_accessor)
it("test_settles_current_game_on_game_finished_event", _test_settles_current_game_on_game_finished_event)
it("test_handler_tolerates_missing_game", _test_handler_tolerates_missing_game)
it("test_watch_game_registers_quit_listener_per_human_player", _test_watch_game_registers_quit_listener_per_human_player)
it("test_exit_callback_skips_other_players_exit", _test_exit_callback_skips_other_players_exit)
it("test_watch_game_skips_and_logs_when_role_unresolved", _test_watch_game_skips_and_logs_when_role_unresolved)
it("test_watch_game_warns_when_host_rejects_registration", _test_watch_game_warns_when_host_rejects_registration)
it("test_exit_callback_marks_quit_when_role_id_is_unreadable", _test_exit_callback_marks_quit_when_role_id_is_unreadable)
it("test_watch_game_warns_when_trigger_port_is_unavailable", _test_watch_game_warns_when_trigger_port_is_unavailable)
it("test_exit_callback_falls_back_to_role_id_field_when_get_roleid_fails",
  _test_exit_callback_falls_back_to_role_id_field_when_get_roleid_fails)
it("test_watch_game_rejects_missing_game_or_players", _test_watch_game_rejects_missing_game_or_players)
end)
