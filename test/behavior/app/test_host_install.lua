require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local with_patches = support.with_patches

local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end

describe("TestHostInstall", function()

  after_each(function()
  require("src.ui.screens.skin_panel").reset_for_tests()
  require("src.host.context").set_current(nil)
  -- 本 spec 反复把运行时端口拆到未配置态验证安装路径;拆完必须把共享测试基线装回去,
  -- 否则同进程后续 suite 会撞上「missing market paid gateway」之类的空端口。全量
  -- behavior 车道靠 suite 顺序掩盖了它,mutate 车道的窄 suite 子集会当场翻车。
  support.restore_runtime_services()
  end)

local function _test_host_ports_lists_five_capability_slots_in_fixed_order()
  -- 清单单一真源（#250/#251）：5 个 port 槽的有序表逐位钉死。
  -- 清 package.loaded 重放 chunk:清单只在加载时执行,得在 case 内重放才能让变异
  -- 车道 suite-file map 归因到本 suite(原条目用后装回,不泄漏)。
  local name = "src.ui.seams.host_ports"
  local saved = package.loaded[name]
  package.loaded[name] = nil
  local refired = require(name)
  package.loaded[name] = saved

  _assert_eq(5, #refired, "host_ports holds exactly five slots")
  _assert_eq(require("src.ui.seams.host_events"), refired[1], "slot 1 is host_events")
  _assert_eq(require("src.ui.seams.host_roles"), refired[2], "slot 2 is host_roles")
  _assert_eq(require("src.ui.seams.host_units"), refired[3], "slot 3 is host_units")
  _assert_eq(require("src.ui.seams.host_sfx"), refired[4], "slot 4 is host_sfx")
  _assert_eq(require("src.ui.seams.host_scene_ui"), refired[5], "slot 5 is host_scene_ui")
end

local function _test_rejects_removed_runtime_options()
  local host_install = require("src.app.host_install")

  local context_ok, context_err = pcall(host_install.install, {
    context_policy = {},
    skip_context_install = true,
  })
  _assert_eq(context_ok, false, "context_policy should be rejected")
  luassert.truthy(tostring(context_err):find("context_policy option removed", 1, true) ~= nil,
    "context_policy error should identify removed option")

  local fallback_ok, fallback_err = pcall(host_install.install, {
    enable_legacy_helper_fallback = true,
    skip_context_install = true,
  })
  _assert_eq(fallback_ok, false, "legacy helper fallback should be rejected")
  luassert.truthy(tostring(fallback_err):find("enable_legacy_helper_fallback option removed", 1, true) ~= nil,
    "legacy fallback error should identify removed option")
end

local function _test_skip_context_install_wires_purchase_skins_to_paid_port()
  local host_install = require("src.app.host_install")
  local paid_purchase_port = require("src.rules.ports.paid_purchase")
  local skin_panel = require("src.ui.screens.skin_panel")
  local skin_equip = require("src.rules.cosmetics")
  local player = { id = 9 }
  local state = {
    ui = {},
    game = {
      find_player_by_id = function(_, role_id)
        if tostring(role_id) == "9" then
          return player
        end
        return nil
      end,
    },
  }
  local captured = nil

  with_patches({
    {
      target = paid_purchase_port,
      key = "start",
      value = function(game, start_player, entry)
        captured = { game = game, player = start_player, entry = entry }
        return true
      end,
    },
    {
      target = skin_equip,
      key = "equip",
      value = function()
        return true
      end,
    },
  }, function()
    host_install.install({ skip_context_install = true })
    skin_panel.open(state, 9)
    skin_panel.handle_action(state, { type = "equip", slot_index = 1 }, 9)
  end)

  _assert_eq(captured and captured.game, state.game, "purchase should use state game")
  _assert_eq(captured and captured.player, player, "purchase should resolve player")
  _assert_eq(captured and captured.entry.kind, "skin", "purchase should create skin entry")
end

local function _test_install_subscribes_reward_day_events_and_grants_the_resolved_player()
  local host_install = require("src.app.host_install")
  local local_actor_resolver = require("src.ui.render.support.local_actor_resolver")
  local captured = {}
  local resolver_states = {}
  local game_api = {
    get_all_valid_roles = function() return {} end,
    random_int = function(min) return min end,
  }
  local lua_api = {
    call_delay_time = function(_, fn) fn() end,
    global_register_custom_event = function(name, handler)
      captured[name] = handler
    end,
    global_register_trigger_event = function() end,
    global_unregister_trigger_event = function() end,
    unit_register_custom_event = function() end,
    unit_register_trigger_event = function() end,
    global_send_custom_event = function() end,
  }
  local client_player = { id = 1, cash = 0 }
  local payload_player = { id = 5, cash = 0 }
  local players = { [1] = client_player, [5] = payload_player }
  local game = {
    find_player_by_id = function(_, role_id) return players[role_id] end,
    add_player_cash = function(_, player, amount) player.cash = (player.cash or 0) + amount end,
  }
  local app_state = { ui = {} }

  with_patches({
    { key = "GameAPI", value = game_api },
    { key = "LuaAPI", value = lua_api },
    { key = "SetTimeOut", value = nil },
    { key = "RegisterCustomEvent", value = nil },
    { key = "RegisterTriggerEvent", value = nil },
    { key = "UnitCustomEvent", value = nil },
    { key = "UnitTriggerEvent", value = nil },
    { key = "TriggerCustomEvent", value = nil },
    { key = "all_roles", value = nil },
    { key = "ALLROLES", value = nil },
    { key = "camera_helper", value = nil },
    {
      target = local_actor_resolver,
      key = "resolve_from_event",
      -- payload.role wins; absent → fall back to the client role (id 1).
      value = function(state, data)
        resolver_states[#resolver_states + 1] = state
        if data and data.role ~= nil then return data.role end
        return 1
      end,
    },
  }, function()
    host_install.install({
      install_globals = true,
      get_current_game = function() return game end,
      get_app_state = function() return app_state end,
    })

    _assert_eq(type(captured.RewardDay4), "function", "RewardDay4 must be subscribed via the host port")
    _assert_eq(captured.RewardDay8, nil, "unconfigured day RewardDay8 must not be subscribed")

    captured.RewardDay4(nil, nil, { role = 5 })
    captured.RewardDay1(nil, nil, {})
  end, { skip_runtime_context_refresh = true })

  _assert_eq(payload_player.cash, 4000, "RewardDay4 must credit the payload-resolved player the day-4 reward")
  _assert_eq(client_player.cash, 500, "RewardDay1 with no payload role must fall back to the client player")
  _assert_eq(resolver_states[1], app_state, "host_install must pass the live app state to the resolver")
end

local function _test_reward_day_events_refresh_player_ui_from_dirty_immediately()
  local host_install = require("src.app.host_install")
  local local_actor_resolver = require("src.ui.render.support.local_actor_resolver")
  local captured = {}
  local refresh_calls = {}
  local lua_api = {
    call_delay_time = function(_, fn) fn() end,
    global_register_custom_event = function(name, handler)
      captured[name] = handler
    end,
    global_register_trigger_event = function() end,
    global_unregister_trigger_event = function() end,
    unit_register_custom_event = function() end,
    unit_register_trigger_event = function() end,
    global_send_custom_event = function() end,
  }
  local player = { id = 5, cash = 0 }
  local game = {
    dirty = { any = false, players = false },
    find_player_by_id = function(_, role_id)
      if role_id == 5 then return player end
      return nil
    end,
    add_player_cash = function(self, target, amount)
      target.cash = (target.cash or 0) + amount
      self.dirty.any = true
      self.dirty.players = true
    end,
    consume_dirty = function(self)
      local snapshot = {
        any = self.dirty.any,
        players = self.dirty.players,
      }
      self.dirty.any = false
      self.dirty.players = false
      return snapshot
    end,
  }
  local app_state = {
    ui = {},
    gameplay_loop_ports = {
      ui_sync = {
        refresh_from_dirty = function(refresh_game, refresh_state, dirty)
          refresh_calls[#refresh_calls + 1] = {
            game = refresh_game,
            state = refresh_state,
            dirty = dirty,
          }
          return true
        end,
      },
    },
  }

  with_patches({
    { key = "GameAPI", value = { get_all_valid_roles = function() return {} end, random_int = function(min) return min end } },
    { key = "LuaAPI", value = lua_api },
    { key = "SetTimeOut", value = nil },
    { key = "RegisterCustomEvent", value = nil },
    { key = "RegisterTriggerEvent", value = nil },
    { key = "UnitCustomEvent", value = nil },
    { key = "UnitTriggerEvent", value = nil },
    { key = "TriggerCustomEvent", value = nil },
    { key = "all_roles", value = nil },
    { key = "ALLROLES", value = nil },
    { key = "camera_helper", value = nil },
    {
      target = local_actor_resolver,
      key = "resolve_from_event",
      value = function(_, data)
        return data and data.role or nil
      end,
    },
  }, function()
    host_install.install({
      install_globals = true,
      get_current_game = function() return game end,
      get_app_state = function() return app_state end,
    })

    captured.RewardDay4(nil, nil, { role = 5 })
  end, { skip_runtime_context_refresh = true })

  _assert_eq(player.cash, 4000, "RewardDay4 must still grant the configured coins")
  _assert_eq(#refresh_calls, 1, "RewardDay4 must refresh the UI in the same host event")
  _assert_eq(refresh_calls[1].game, game, "refresh should use the live game")
  _assert_eq(refresh_calls[1].state, app_state, "refresh should use the live app state")
  _assert_eq(refresh_calls[1].dirty.players, true, "coin grant must refresh player rows")
  _assert_eq(game.dirty.any, false, "immediate refresh should consume the dirty bucket")
end

local function _test_reward_day_grant_survives_missing_ui_sync_ports()
  local host_install = require("src.app.host_install")
  local local_actor_resolver = require("src.ui.render.support.local_actor_resolver")
  local captured = {}
  local lua_api = {
    call_delay_time = function(_, fn) fn() end,
    global_register_custom_event = function(name, handler)
      captured[name] = handler
    end,
    global_register_trigger_event = function() end,
    global_unregister_trigger_event = function() end,
    unit_register_custom_event = function() end,
    unit_register_trigger_event = function() end,
    global_send_custom_event = function() end,
  }
  local player = { id = 5, cash = 0 }
  local game = {
    find_player_by_id = function(_, role_id)
      if role_id == 5 then return player end
      return nil
    end,
    add_player_cash = function(_, target, amount)
      target.cash = (target.cash or 0) + amount
    end,
    consume_dirty = function()
      return { any = false, players = false }
    end,
  }
  local app_state = { ui = {} }

  with_patches({
    { key = "GameAPI", value = { get_all_valid_roles = function() return {} end, random_int = function(min) return min end } },
    { key = "LuaAPI", value = lua_api },
    { key = "SetTimeOut", value = nil },
    { key = "RegisterCustomEvent", value = nil },
    { key = "RegisterTriggerEvent", value = nil },
    { key = "UnitCustomEvent", value = nil },
    { key = "UnitTriggerEvent", value = nil },
    { key = "TriggerCustomEvent", value = nil },
    { key = "all_roles", value = nil },
    { key = "ALLROLES", value = nil },
    { key = "camera_helper", value = nil },
    {
      target = local_actor_resolver,
      key = "resolve_from_event",
      value = function(_, data)
        return data and data.role or nil
      end,
    },
  }, function()
    host_install.install({
      install_globals = true,
      get_current_game = function() return game end,
      get_app_state = function() return app_state end,
    })

    captured.RewardDay4(nil, nil, { role = 5 })
  end, { skip_runtime_context_refresh = true })

  _assert_eq(player.cash, 4000, "RewardDay4 must still grant coins without ui_sync ports")
end

local function _test_skips_reward_day_wiring_when_either_lazy_accessor_is_missing()
  local host_install = require("src.app.host_install")
  local captured = {}
  local lua_api = {
    call_delay_time = function(_, fn) fn() end,
    global_register_custom_event = function(name, handler)
      captured[name] = handler
    end,
    global_register_trigger_event = function() end,
    global_unregister_trigger_event = function() end,
    unit_register_custom_event = function() end,
    unit_register_trigger_event = function() end,
    global_send_custom_event = function() end,
  }
  with_patches({
    { key = "GameAPI", value = { get_all_valid_roles = function() return {} end, random_int = function(min) return min end } },
    { key = "LuaAPI", value = lua_api },
    { key = "SetTimeOut", value = nil },
    { key = "RegisterCustomEvent", value = nil },
    { key = "RegisterTriggerEvent", value = nil },
    { key = "UnitCustomEvent", value = nil },
    { key = "UnitTriggerEvent", value = nil },
    { key = "TriggerCustomEvent", value = nil },
    { key = "all_roles", value = nil },
    { key = "ALLROLES", value = nil },
    { key = "camera_helper", value = nil },
  }, function()
    -- get_current_game is a function but get_app_state is absent: the wiring
    -- guard requires BOTH accessors, so sign-in rewards must NOT be subscribed.
    host_install.install({
      install_globals = true,
      get_current_game = function() return nil end,
    })
    _assert_eq(captured.RewardDay1, nil, "reward-day wiring must be skipped when get_app_state is missing")
  end, { skip_runtime_context_refresh = true })
end

local function _test_install_wires_runtime_context_aliases_and_default_ports()
  local host_install = require("src.app.host_install")
  local runtime_context = require("src.host.context")
  local runtime_ports = require("src.foundation.ports.runtime_ports")
  local role = { get_roleid = function() return 42 end }
  local game_api = {
    get_all_valid_roles = function()
      return { role }
    end,
    random_int = function(min)
      return min
    end,
  }
  local lua_api = {
    call_delay_time = function(_, fn) fn() end,
    global_register_custom_event = function() end,
    global_register_trigger_event = function() end,
    global_unregister_trigger_event = function() end,
    unit_register_custom_event = function() end,
    unit_register_trigger_event = function() end,
    global_send_custom_event = function() end,
  }

  with_patches({
    { key = "GameAPI", value = game_api },
    { key = "LuaAPI", value = lua_api },
    { key = "SetTimeOut", value = nil },
    { key = "RegisterCustomEvent", value = nil },
    { key = "RegisterTriggerEvent", value = nil },
    { key = "UnitCustomEvent", value = nil },
    { key = "UnitTriggerEvent", value = nil },
    { key = "TriggerCustomEvent", value = nil },
    { key = "all_roles", value = nil },
    { key = "ALLROLES", value = nil },
    { key = "camera_helper", value = nil },
  }, function()
    host_install.install({ install_globals = true })

    _assert_eq(runtime_context.current().env.GameAPI, game_api, "runtime context should keep GameAPI")
    _assert_eq(GameAPI, game_api, "global alias should expose GameAPI")
    _assert_eq(LuaAPI, lua_api, "global alias should expose LuaAPI")
    _assert_eq(SetTimeOut, lua_api.call_delay_time, "global alias should expose delay helper")
    _assert_eq(all_roles[1], role, "runtime helpers should publish all roles when requested")
    _assert_eq(runtime_ports.resolve_role(42), role, "default runtime ports should resolve roles")
  end, { skip_runtime_context_refresh = true })
end

local function _test_skip_context_install_wires_skin_panel_to_skin_equip()
  local host_install = require("src.app.host_install")
  local skin_panel = require("src.ui.screens.skin_panel")
  local skin_equip = require("src.rules.cosmetics")
  local runtime_refs = require("src.config.content.runtime_refs")
  local captured = nil

  with_patches({
    {
      target = skin_equip,
      key = "equip",
      value = function(role_id, creature_key)
        captured = { role_id = role_id, creature_key = creature_key }
        return true
      end,
    },
  }, function()
    host_install.install({ skip_context_install = true })
    local state = { ui = {} }
    skin_panel.open(state, 9)
    skin_panel.handle_action(state, { type = "buy", slot_index = 3 }, 9)
    skin_panel.handle_action(state, { type = "equip", slot_index = 3 }, 9)
  end)

  _assert_eq(captured and captured.role_id, 9, "skin equip should receive role id")
  _assert_eq(captured and captured.creature_key,
    runtime_refs.skins[tostring(require("src.app.cosmetics.transaction").catalog[3].product_id)],
    "skin equip should receive the numeric resource id resolved from refs.skins")
end

local function _test_skip_context_install_wires_skin_panel_to_skin_unequip()
  local host_install = require("src.app.host_install")
  local skin_panel = require("src.ui.screens.skin_panel")
  local skin_equip = require("src.rules.cosmetics")
  local runtime_refs = require("src.config.content.runtime_refs")
  local captured = nil

  with_patches({
    {
      target = skin_equip,
      key = "equip",
      value = function()
        return true
      end,
    },
    {
      target = skin_equip,
      key = "unequip",
      value = function(role_id, default_creature_key)
        captured = { role_id = role_id, default_creature_key = default_creature_key }
        return true
      end,
    },
  }, function()
    host_install.install({ skip_context_install = true })
    local state = { ui = {} }
    skin_panel.open(state, 9)
    skin_panel.handle_action(state, { type = "buy", slot_index = 3 }, 9)
    skin_panel.handle_action(state, { type = "equip", slot_index = 3 }, 9)
    skin_panel.handle_action(state, { type = "unequip", slot_index = 3 }, 9)
  end)

  _assert_eq(captured and captured.role_id, 9, "skin unequip should receive role id")
  _assert_eq(captured and captured.default_creature_key,
    runtime_refs.default_creature,
    "skin unequip should receive the default creature fallback from refs.default_creature")
end

local function _test_reward_day_without_consume_dirty_is_a_safe_noop()
  -- #293:_refresh_sign_in_reward_ui 的守卫(or→and 变异会带 nil game 走下去崩、
  -- false→true 变异会谎报成功)未测——用缺 consume_dirty 的 game 钉住守卫。
  local host_install = require("src.app.host_install")
  local captured = {}
  local lua_api = {
    call_delay_time = function(_, fn) fn() end,
    global_register_custom_event = function(name, handler)
      captured[name] = handler
    end,
    global_register_trigger_event = function() end,
    global_unregister_trigger_event = function() end,
    unit_register_custom_event = function() end,
    unit_register_trigger_event = function() end,
    global_send_custom_event = function() end,
  }
  local player = { id = 5, cash = 0 }
  local game = {
    find_player_by_id = function(_, role_id)
      if role_id == 5 then return player end
      return nil
    end,
    add_player_cash = function(self, target, amount)
      target.cash = (target.cash or 0) + amount
    end,
    -- 没有 consume_dirty:刷新守卫应直接短路,不发刷新也不崩。
  }
  local app_state = { ui = {} }

  with_patches({
    { key = "GameAPI", value = { get_all_valid_roles = function() return {} end, random_int = function(min) return min end } },
    { key = "LuaAPI", value = lua_api },
    { key = "SetTimeOut", value = nil },
    { key = "RegisterCustomEvent", value = nil },
    { key = "RegisterTriggerEvent", value = nil },
    { key = "UnitCustomEvent", value = nil },
    { key = "UnitTriggerEvent", value = nil },
    { key = "TriggerCustomEvent", value = nil },
    { key = "all_roles", value = nil },
    { key = "ALLROLES", value = nil },
    { key = "camera_helper", value = nil },
    {
      target = require("src.ui.render.support.local_actor_resolver"),
      key = "resolve_from_event",
      value = function(_, data)
        return data and data.role or nil
      end,
    },
  }, function()
    host_install.install({
      install_globals = true,
      get_current_game = function() return game end,
      get_app_state = function() return app_state end,
    })
    -- 守卫路径:game 无 consume_dirty → 刷新短路,但奖励仍照发。
    captured.RewardDay4(nil, nil, { role = 5 })
  end, { skip_runtime_context_refresh = true })

  _assert_eq(player.cash, 4000, "RewardDay4 must still grant without a refreshable game")
end

local function _capture_sign_in_deps()
  -- patch sign_in.install 捕获 wiring deps,绕过事件注册直取 after_grant,
  -- 以便断言其返回值(宿主事件路径丢弃返回值,false→true 变异只能靠直调区分)。
  -- get_app_state 配 ui_sync 端口:state 无 ui_sync 时守卫 or→and 变异体会走
  -- 同样的 false 路径逃逸,必须让变异体能越过守卫触及 game:consume_dirty()。
  local sign_in = require("src.app.host_integrations.sign_in")
  local captured_deps = nil
  with_patches({
    {
      target = sign_in,
      key = "install",
      value = function(deps)
        captured_deps = deps
      end,
    },
  }, function()
    require("src.app.host_install").install({
      skip_context_install = true,
      get_current_game = function() return nil end,
      get_app_state = function()
        return {
          ui = {},
          gameplay_loop_ports = {
            ui_sync = {
              refresh_from_dirty = function()
                error("guard must short-circuit before refresh")
              end,
            },
          },
        }
      end,
    })
  end)
  return captured_deps
end

local function _test_after_grant_guard_returns_false_and_never_crashes()
  -- #293: _refresh_sign_in_reward_ui 的守卫 or→and 变异会带着 nil game / 缺
  -- consume_dirty 的 game 走下去崩(位点 A/B),return false→true 变异会谎报成功;
  -- 现有用例 state 无 ui_sync 端口,变异体照样走 false 路径,杀不掉——这里给
  -- state 配上 ui_sync 端口,直调 after_grant 断言返回值并验证不崩。
  local deps = _capture_sign_in_deps()
  local refresh_calls = {}
  local app_state = {
    ui = {},
    gameplay_loop_ports = {
      ui_sync = {
        refresh_from_dirty = function()
          refresh_calls[#refresh_calls + 1] = true
          return true
        end,
      },
    },
  }
  deps.after_grant(nil, app_state)
  _assert_eq(#refresh_calls, 0, "nil game must short-circuit before any refresh")
  _assert_eq(deps.after_grant(nil, app_state), false, "nil game must report no refresh")
  -- game 非 nil 但缺 consume_dirty:守卫必须短路,不得调用 game:consume_dirty()。
  local bare_game = {}
  _assert_eq(deps.after_grant(bare_game, app_state), false, "missing consume_dirty must report no refresh")
  _assert_eq(#refresh_calls, 0, "missing consume_dirty must not reach the ui_sync refresh")
end

local function _test_after_grant_returns_false_when_ui_sync_missing()
  -- #293: ui_sync == nil 分支的 return false→true 变异(谎报刷新成功)只能靠
  -- 直调 after_grant 断言返回值区分;宿主事件路径丢弃返回值杀不掉。
  local sign_in = require("src.app.host_integrations.sign_in")
  local deps = nil
  with_patches({
    {
      target = sign_in,
      key = "install",
      value = function(captured)
        deps = captured
      end,
    },
  }, function()
    require("src.app.host_install").install({
      skip_context_install = true,
      get_current_game = function() return nil end,
      get_app_state = function()
        return { ui = {}, gameplay_loop_ports = { ui_sync = nil } }
      end,
    })
  end)
  local game = {
    consume_dirty = function()
      return { any = false, players = false }
    end,
  }
  _assert_eq(deps.after_grant(game, { ui = {}, gameplay_loop_ports = { ui_sync = nil } }),
    false, "missing ui_sync must report no refresh")
end

local function _test_install_configures_achievement_progress_with_built_port()
  -- #293: L126 configure(nil) 变异(丢掉 achievement_runtime.build_port())——
  -- 钉住 configure 收到的参数必须是 build_port() 的产物,不是 nil。
  local achievement_progress_port = require("src.rules.ports.achievement_progress")
  local captured = "unset"
  with_patches({
    {
      target = achievement_progress_port,
      key = "configure",
      value = function(port)
        captured = port
      end,
    },
  }, function()
    require("src.app.host_install").install({ skip_context_install = true })
  end)
  luassert.truthy(captured ~= nil, "achievement_progress must be configured with a built port")
  luassert.truthy(type(captured) == "table", "achievement_progress port must be a table, got " .. type(captured))
end


it("test_host_ports_lists_five_capability_slots_in_fixed_order", _test_host_ports_lists_five_capability_slots_in_fixed_order)
it("test_rejects_removed_runtime_options", _test_rejects_removed_runtime_options)
it("test_skip_context_install_wires_purchase_skins_to_paid_port", _test_skip_context_install_wires_purchase_skins_to_paid_port)
it("test_install_subscribes_reward_day_events_and_grants_the_resolved_player", _test_install_subscribes_reward_day_events_and_grants_the_resolved_player)
it("test_reward_day_events_refresh_player_ui_from_dirty_immediately", _test_reward_day_events_refresh_player_ui_from_dirty_immediately)
it("test_reward_day_grant_survives_missing_ui_sync_ports", _test_reward_day_grant_survives_missing_ui_sync_ports)
it("test_skips_reward_day_wiring_when_either_lazy_accessor_is_missing", _test_skips_reward_day_wiring_when_either_lazy_accessor_is_missing)
it("test_install_wires_runtime_context_aliases_and_default_ports", _test_install_wires_runtime_context_aliases_and_default_ports)
it("test_skip_context_install_wires_skin_panel_to_skin_equip", _test_skip_context_install_wires_skin_panel_to_skin_equip)
it("test_skip_context_install_wires_skin_panel_to_skin_unequip", _test_skip_context_install_wires_skin_panel_to_skin_unequip)
it("test_reward_day_without_consume_dirty_is_a_safe_noop", _test_reward_day_without_consume_dirty_is_a_safe_noop)
it("test_after_grant_guard_returns_false_and_never_crashes", _test_after_grant_guard_returns_false_and_never_crashes)
it("test_after_grant_returns_false_when_ui_sync_missing", _test_after_grant_returns_false_when_ui_sync_missing)
it("test_install_configures_achievement_progress_with_built_port", _test_install_configures_achievement_progress_with_built_port)
end)
