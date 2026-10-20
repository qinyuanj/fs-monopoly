---@diagnostic disable: need-check-nil, different-requires, undefined-field

require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local with_patches = support.with_patches

local function _shared_install_patches()
  return {
    { target = _G, key = "RegisterTriggerEvent", value = function(_, cb) cb() end },
    { target = _G, key = "EVENT", value = { GAME_INIT = "GAME_INIT" } },
    { target = package.loaded, key = "src.ui.manager.utils", value = true },
    { target = _G, key = "UIManager", value = { Builder = { new = function() return {} end } } },
    { target = require("src.ui.coord.ui_events"), key = "send_to_all", value = function() end },
    { target = require("src.ui.coord.canvas_event_router"), key = "bind", value = function() end },
    { target = require("src.ui.coord.ui_runtime"), key = "init_ui_assets", value = function() end },
    { target = require("src.ui.coord.ui_runtime"), key = "capture_player_colors", value = function() end },
    { target = require("src.ui.render.board.scene"), key = "init", value = function() end },
    { target = require("src.host.context"), key = "current", value = function() return nil end },
    { target = require("src.foundation.ports.runtime_ports"), key = "resolve_roles", value = function() return {} end },
    { target = require("src.foundation.ports.runtime_ports"), key = "schedule", value = function(_, fn) fn() end },
    { target = require("src.state.ui_role_globals"), key = "install", value = function() return {} end },
    { target = require("src.host.like_collect_subscribe"), key = "setup", value = function() end },
  }
end

local function _with_install_patches(extras, fn)
  local patches = _shared_install_patches()
  for _, extra in ipairs(extras or {}) do
    patches[#patches + 1] = extra
  end
  return with_patches(patches, fn)
end

local function _install_with_runtime(state, opts)
  local ui_bootstrap = require("src.app.ui_bootstrap")
  return ui_bootstrap.install(state, { { board = { map = {} } } }, opts or {
    start_runtime = function() return { board = { map = {} } } end,
  })
end

local function _contains(list, value)
  for _, item in ipairs(list or {}) do
    if item == value then
      return true
    end
  end
  return false
end

describe("TestUiBootstrap", function()

local function _test_bootstrap_nodes_build_required_click_nodes_includes_schema_groups_and_extras()
  local bootstrap_nodes = require("src.app.ui_bootstrap_nodes")
  local base_nodes = require("src.ui.schema.base")
  local player_choice_nodes = require("src.ui.schema.player_choice")
  local remote_choice_nodes = require("src.ui.schema.remote_choice")
  local base_contract = require("src.ui.schema.base_contract")

  local required = bootstrap_nodes.build_required_click_nodes({ extra = { "额外_按钮" } })

  luassert.truthy(_contains(required, base_nodes.action_button), "required nodes should include base action button")
  luassert.truthy(_contains(required, base_nodes.end_button), "required nodes should include optional end button")
  luassert.truthy(_contains(required, base_nodes.cancel_button),
    "required nodes should include the base cancel button (sole followup cancel exit)")
  luassert.truthy(_contains(required, player_choice_nodes.slots[1]), "required nodes should include player choice slots")
  luassert.truthy(_contains(required, remote_choice_nodes.options[1]), "required nodes should include remote choice options")
  luassert.truthy(_contains(required, "遥控骰子_退出灰底"),
    "required nodes should include the remote choice underlay (click-background close, #177)")
  luassert.truthy(_contains(required, base_contract.action_log.toggle_targets[1]),
    "required nodes should include action log toggle targets")
  luassert.truthy(_contains(required, "额外_按钮"), "required nodes should include caller extras")
end

local function _test_bootstrap_nodes_ignores_non_table_extra_nodes()
  local bootstrap_nodes = require("src.app.ui_bootstrap_nodes")
  local required = bootstrap_nodes.build_required_click_nodes({ extra = "not-a-list" })

  luassert.truthy(_contains(required, "not-a-list") == false, "non-table extras should not be appended")
end

local function _test_bootstrap_nodes_fallback_validation_filters_known_and_dedupes_missing_nodes()
  local bootstrap_nodes = require("src.app.ui_bootstrap_nodes")
  local ui_manager_nodes = {
    { "已知按钮" },
    { "" },
    { 123 },
    { [0] = "零号槽不是节点名" },
    "malformed",
  }

  local missing = bootstrap_nodes.validate_required_nodes(ui_manager_nodes, {
    "已知按钮",
    "缺失按钮",
    "缺失按钮",
    "零号槽不是节点名",
    "",
    123,
  })

  luassert.truthy(#missing == 2, "fallback validation should report each missing string node once")
  luassert.truthy(missing[1] == "缺失按钮", "fallback validation should keep the missing node name")
  luassert.truthy(missing[2] == "零号槽不是节点名",
    "fallback validation should only read exported node names from entry slot 1")

  -- #293:assert_required_nodes 的报错用 ", " 连接缺失节点,separator 变异可分。
  luassert.has_error.match(function()
    bootstrap_nodes.assert_required_nodes(ui_manager_nodes, {
      "已知按钮",
    })
  end, "基础_行动按钮, 基础_结束按钮", 1, true)

  local empty_missing = bootstrap_nodes.validate_required_nodes({}, { "" })
  luassert.truthy(#empty_missing == 0, "empty required node names should be ignored")
end

local function _test_bootstrap_nodes_assert_reports_single_missing_node()
  local bootstrap_nodes = require("src.app.ui_bootstrap_nodes")
  local ok, err = pcall(function()
    bootstrap_nodes.assert_required_nodes({
      validate = function()
        return { "唯一缺失按钮" }
      end,
    })
  end)

  luassert.truthy(ok == false, "one missing required node should fail bootstrap validation")
  luassert.truthy(tostring(err):find("唯一缺失按钮", 1, true),
    "bootstrap validation error should include the missing node")
end

local function _test_required_click_nodes_appends_extras()
  local ui_manager_nodes = {
    { "基础屏_行动按钮" },
  }
  local missing = nil

  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = ui_manager_nodes },
  }, function()
    local ok, err = pcall(_install_with_runtime, {})
    missing = err
    luassert.truthy(ok == false, "ui bootstrap should validate missing UI nodes")
  end)

  luassert.truthy(tostring(missing):find("UI 节点缺失", 1, true) ~= nil, "ui bootstrap should report missing required nodes")
end

local function _test_reports_missing_host_child_nodes_before_building_ui_manager()
  local ui_manager_nodes = {
    ["1519736575|2147314485"] = { "基础屏", "ECanvas" },
  }
  local builder_called = false
  local err = nil

  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = ui_manager_nodes },
    { target = _G, key = "GameAPI", value = {
      get_eui_children = function(id)
        if id == "1519736575|2147314485" then
          return { "1519736575|1397686248" }
        end
        return {}
      end,
    } },
    { target = _G, key = "UIManager", value = {
      Builder = {
        new = function()
          builder_called = true
          error("builder should not run when host child nodes are missing")
        end,
      },
    } },
  }, function()
    local ok, install_err = pcall(_install_with_runtime, {})
    err = install_err
    luassert.truthy(ok == false, "ui bootstrap should fail fast for missing host child nodes")
  end)

  local text = tostring(err)
  luassert.truthy(text:find("UI 节点配置缺失", 1, true) ~= nil,
    "ui bootstrap should report missing node configuration")
  luassert.truthy(text:find("基础屏", 1, true) ~= nil,
    "ui bootstrap should include the parent node name")
  luassert.truthy(text:find("1519736575|1397686248", 1, true) ~= nil,
    "ui bootstrap should include the missing host child id")
  luassert.truthy(builder_called == false,
    "ui bootstrap should validate host children before creating UIManager nodes")
end

local function _test_scheduled_callback_switches_canvas_to_base_to_hide_non_base_canvases()
  local canvas_coordinator = require("src.ui.coord.canvas_coordinator")
  local base_nodes = require("src.ui.schema.base")

  local ui_manager_nodes = { validate = function() return {} end }
  local switch_calls = {}

  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = ui_manager_nodes },
    { target = canvas_coordinator, key = "switch", value = function(ui, target)
      switch_calls[#switch_calls + 1] = { ui = ui, target = target }
    end },
  }, function()
    _install_with_runtime({ ui = {} })
  end)

  local switched_to_base = false
  for _, call in ipairs(switch_calls) do
    if call.target == base_nodes.canvas then
      switched_to_base = true
      break
    end
  end
  luassert.truthy(switched_to_base,
    "bootstrap should switch canvas to base to hide non-base canvases at startup")
end

local function _test_install_uses_existing_current_game_ref_without_start_runtime()
  local board_scene = require("src.ui.render.board.scene")
  local map = { path = { 9, 8, 7 } }
  local current_game = { board = { map = map } }
  local captured = {}
  local start_called = false

  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = { validate = function() return {} end } },
    { target = board_scene, key = "init", value = function(state, board_map, game)
      captured.state = state
      captured.map = board_map
      captured.game = game
    end },
  }, function()
    local state = { ui = {} }
    require("src.app.ui_bootstrap").install(state, { current_game }, {
      start_runtime = function()
        start_called = true
        return { board = { map = {} } }
      end,
    })
    luassert.truthy(captured.state == state, "bootstrap should initialize board scene with install state")
  end)

  luassert.truthy(start_called == false, "existing current_game ref should not invoke start_runtime")
  luassert.truthy(captured.game == current_game, "bootstrap should use existing current_game ref")
  luassert.truthy(captured.map == map, "bootstrap should pass current game board map to board scene")
end

local function _test_install_falls_back_to_start_runtime_when_current_game_ref_is_empty()
  local board_scene = require("src.ui.render.board.scene")
  local map = { path = { 1 } }
  local current_game = { board = { map = map } }
  local current_game_ref = { nil }
  local captured = {}
  local start_called = false

  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = { validate = function() return {} end } },
    { target = board_scene, key = "init", value = function(_, board_map, game)
      captured.map = board_map
      captured.game = game
    end },
  }, function()
    require("src.app.ui_bootstrap").install({ ui = {} }, current_game_ref, {
      start_runtime = function(_, ref)
        start_called = true
        ref[1] = current_game
        return current_game
      end,
    })
  end)

  luassert.truthy(start_called == true, "empty current_game ref should invoke start_runtime")
  luassert.truthy(current_game_ref[1] == current_game, "start_runtime should be able to populate the shared game ref")
  luassert.truthy(captured.game == current_game, "bootstrap should use the runtime-created current game")
  luassert.truthy(captured.map == map, "bootstrap should pass runtime-created board map to board scene")
end

local function _test_install_accepts_nil_opts_when_current_game_ref_is_present()
  local ui_manager_nodes = { validate = function() return {} end }
  local ok, err
  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = ui_manager_nodes },
  }, function()
    ok, err = pcall(function()
      require("src.app.ui_bootstrap").install({ ui = {} }, { { board = { map = {} } } }, nil)
    end)
  end)

  luassert.truthy(ok == true, "nil opts should be accepted when current_game already exists: " .. tostring(err))
end

local function _test_spawns_startup_synthetic_actors()
  local ui_bootstrap = require("src.app.ui_bootstrap")
  local capture = {
    registered_specs = nil,
    spawned_map = nil,
  }

  with_patches({
    {
      target = require("src.host.context"),
      key = "current",
      value = function()
        return {
          synthetic_actor_registry = {
            register_specs = function(specs)
              capture.registered_specs = specs
            end,
            spawn_pending = function(map_cfg)
              capture.spawned_map = map_cfg
            end,
          },
        }
      end,
    },
  }, function()
    local game = {
      startup_synthetic_players = {
        { player_id = -2, unit_key = "npc_2" },
      },
      board = { map = { path = { 1, 2, 3 } } },
    }
    ui_bootstrap.spawn_startup_synthetic_actors(game)
  end)

  luassert.truthy(type(capture.registered_specs) == "table" and capture.registered_specs[1].player_id == -2,
    "ui bootstrap should register startup synthetic actor specs")
  luassert.truthy(capture.spawned_map and capture.spawned_map.path[1] == 1,
    "ui bootstrap should spawn pending synthetic actors with board map")
end


-- 批3 击杀 L44：_install_role_globals 必须把解析出的角色列表传给 role_globals，
-- 不能传 nil（0→nil 变异把 resolve_roles() 整体吞掉）。
local function _test_role_globals_install_receives_the_resolved_roles()
  local captured = nil
  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = { validate = function() return {} end } },
    { target = require("src.state.ui_role_globals"), key = "install", value = function(roles)
      captured = roles
    end },
  }, function()
    _install_with_runtime({ ui = {} })
  end)
  luassert.truthy(type(captured) == "table", "role globals install should receive the resolved roles")
end

-- #466:点赞/收藏/订阅事件链路开局接线——GAME_INIT 必须调用
-- like_collect_subscribe.setup 并传入已解析的 current_game,真机无需编辑器侧
-- 开局触发器。
local function _test_game_init_wires_like_collect_subscribe_setup()
  local setup_calls = {}
  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = { validate = function() return {} end } },
    { target = require("src.host.like_collect_subscribe"), key = "setup", value = function(game)
      setup_calls[#setup_calls + 1] = game
    end },
  }, function()
    _install_with_runtime({ ui = {} })
  end)
  luassert.truthy(#setup_calls == 1, "GAME_INIT should call like_collect_subscribe.setup exactly once")
  luassert.truthy(type(setup_calls[1]) == "table" and setup_calls[1].board ~= nil,
    "setup should receive the resolved current game")
end

-- 批3 击杀 L49：空字符串名称的条目（name == ""）标签必须回落为纯节点 id，
-- 不能拼出 "(id)" 括号形式。
local function _test_empty_name_entry_label_keeps_plain_node_id()
  local ui_manager_nodes = {
    ["PARENT"] = { "" },
  }
  local err = nil

  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = ui_manager_nodes },
    { target = _G, key = "GameAPI", value = {
      get_eui_children = function(id)
        if id == "PARENT" then
          return { "MISSING_CHILD" }
        end
        return {}
      end,
    } },
  }, function()
    local ok, install_err = pcall(_install_with_runtime, {})
    err = install_err
    luassert.truthy(ok == false, "empty-name entries should still fail fast for missing children")
  end)

  luassert.truthy(tostring(err):find("PARENT -> MISSING_CHILD", 1, true) ~= nil,
    "empty-name label should stay the plain node id, got: " .. tostring(err))
end

-- 批3 击杀 L58（两处 and→or）与 L76（seen 置位）：已配置子节点不能被误报缺失，
-- 重复缺失子节点必须去重只报一次。
local function _test_configured_and_repeated_children_are_not_reported_missing()
  local ui_manager_nodes = {
    ["PARENT"] = { "父" },
    ["CONFIGURED"] = { "子" },
  }
  local err = nil

  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = ui_manager_nodes },
    { target = _G, key = "GameAPI", value = {
      get_eui_children = function(id)
        if id == "PARENT" then
          return { "CONFIGURED", "MISSING", "MISSING" }
        end
        return {}
      end,
    } },
  }, function()
    local ok, install_err = pcall(_install_with_runtime, {})
    err = install_err
    luassert.truthy(ok == false, "a truly missing child should still fail fast")
  end)

  local text = tostring(err)
  luassert.truthy(text:find("CONFIGURED", 1, true) == nil,
    "configured children must not be reported missing, got: " .. text)
  local _, repeated = text:gsub("MISSING", "")
  luassert.truthy(repeated == 1, "a repeated missing child should be reported exactly once, got: " .. text)
end

-- 批3 击杀 L63 四处：子节点读取失败的错误消息必须带前缀、标签、分隔符与失败值，
-- 四段拼接一处变异即断（nil 拼接直接崩，消息对不上）。
local function _test_children_read_failure_message_carries_label_and_error()
  local ui_manager_nodes = {
    ["PARENT"] = { "父" },
  }
  local err = nil

  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = ui_manager_nodes },
    { target = _G, key = "GameAPI", value = {
      get_eui_children = function()
        error("boom")
      end,
    } },
  }, function()
    local ok, install_err = pcall(_install_with_runtime, {})
    err = install_err
    luassert.truthy(ok == false, "a raising children lookup should fail fast")
  end)

  local text = tostring(err)
  luassert.truthy(text:find("UI 节点子节点读取失败: 父(PARENT): ", 1, true) ~= nil,
    "children-read failure should carry prefix, label and separator, got: " .. text)
  luassert.truthy(text:find("boom", 1, true) ~= nil,
    "children-read failure should carry the lookup error value, got: " .. text)
end

-- 批3 击杀 L106：多个缺失子节点必须用 ", " 连接，分隔符变异可分。
local function _test_missing_children_join_with_comma_separator()
  local ui_manager_nodes = {
    ["PARENT"] = { "父" },
  }
  local err = nil

  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = ui_manager_nodes },
    { target = _G, key = "GameAPI", value = {
      get_eui_children = function(id)
        if id == "PARENT" then
          return { "M1", "M2" }
        end
        return {}
      end,
    } },
  }, function()
    local ok, install_err = pcall(_install_with_runtime, {})
    err = install_err
    luassert.truthy(ok == false, "two missing children should fail fast")
  end)

  luassert.truthy(tostring(err):find("父(PARENT) -> M1, 父(PARENT) -> M2", 1, true) ~= nil,
    "missing children should be joined with a comma separator, got: " .. tostring(err))
end

-- 批3 击杀 L123：canvas_event_router 绑定的 getter 必须读共享 current_game_ref
-- 的 1 号位（1→0 变异会让 getter 恒返 nil）。
local function _test_bind_getter_reads_the_shared_current_game_ref()
  local ui_bootstrap = require("src.app.ui_bootstrap")
  local canvas_event_router = require("src.ui.coord.canvas_event_router")
  local captured_getter = nil
  local game = { board = { map = { path = { 1 } } } }

  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = { validate = function() return {} end } },
    { target = canvas_event_router, key = "bind", value = function(_, getter)
      captured_getter = getter
    end },
  }, function()
    ui_bootstrap.install({ ui = {} }, { game }, {
      start_runtime = function() return { board = { map = {} } } end,
    })
  end)

  luassert.truthy(type(captured_getter) == "function", "bind should receive a game getter")
  luassert.truthy(captured_getter() == game, "bound getter should read the shared current game ref")
end

-- 批3 击杀 L129：_sync_ui_event_roles 必须把解析出的角色列表传给 ui_events，
-- 不能传 nil。
local function _test_sync_ui_event_roles_forwards_the_resolved_roles()
  local ui_events = require("src.ui.coord.ui_events")
  local captured = "unset"

  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = { validate = function() return {} end } },
    { target = ui_events, key = "set_roles", value = function(roles)
      captured = roles
    end },
  }, function()
    _install_with_runtime({ ui = {} })
  end)

  luassert.truthy(type(captured) == "table", "ui event roles should receive the resolved roles")
end

-- 批3 击杀 L135：必需节点校验必须带上市场购买项 extra（item_buttons or {}
-- 变异为 and {} 会把 10 个黑市购买项清空）。
local function _test_required_nodes_include_market_item_buttons()
  local captured_required = nil

  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = {
      validate = function(required)
        captured_required = required
        return {}
      end,
    } },
  }, function()
    _install_with_runtime({ ui = {} })
  end)

  luassert.truthy(type(captured_required) == "table", "required-node validation should run")
  luassert.truthy(_contains(captured_required, "黑市_购买项1"),
    "required nodes should include the market item buttons")
end

-- 批3 击杀 L140/L153：加载屏的显示/隐藏必须使用注册表中的事件名，不能传 nil。
local function _test_loading_screen_show_and_hide_use_the_registered_events()
  local ui_events = require("src.ui.coord.ui_events")
  local sentinel_show = {}
  local sentinel_hide = {}
  local calls = {}

  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = { validate = function() return {} end } },
    { target = ui_events, key = "show", value = { ["加载屏"] = sentinel_show } },
    { target = ui_events, key = "hide", value = { ["加载屏"] = sentinel_hide } },
    { target = ui_events, key = "send_to_all", value = function(event, payload)
      calls[#calls + 1] = { event = event, payload = payload }
    end },
  }, function()
    _install_with_runtime({ ui = {} })
  end)

  luassert.truthy(calls[1] ~= nil and calls[1].event == sentinel_show,
    "startup should broadcast the registered loading-screen show event")
  luassert.truthy(calls[2] ~= nil and calls[2].event == sentinel_hide,
    "the loading transition should broadcast the registered loading-screen hide event")
end

local function _test_missing_child_label_falls_back_to_node_id_for_unnamed_entries()
  local ui_manager_nodes = {
    ["1519736575|2147314485"] = {},
  }
  local err = nil

  _with_install_patches({
    { target = package.loaded, key = "Data.UIManagerNodes", value = ui_manager_nodes },
    { target = _G, key = "GameAPI", value = {
      get_eui_children = function(id)
        if id == "1519736575|2147314485" then
          return { "1519736575|1397686248" }
        end
        return {}
      end,
    } },
  }, function()
    local ok, install_err = pcall(_install_with_runtime, {})
    err = install_err
    luassert.truthy(ok == false,
      "unnamed node entries should still report missing host child nodes")
  end)

  luassert.truthy(tostring(err):find("1519736575|2147314485", 1, true) ~= nil,
    "missing child label should fall back to the parent node id")
end


it("test_bootstrap_nodes_build_required_click_nodes_includes_schema_groups_and_extras", _test_bootstrap_nodes_build_required_click_nodes_includes_schema_groups_and_extras)
it("test_bootstrap_nodes_ignores_non_table_extra_nodes", _test_bootstrap_nodes_ignores_non_table_extra_nodes)
it("test_bootstrap_nodes_fallback_validation_filters_known_and_dedupes_missing_nodes", _test_bootstrap_nodes_fallback_validation_filters_known_and_dedupes_missing_nodes)
it("test_bootstrap_nodes_assert_reports_single_missing_node", _test_bootstrap_nodes_assert_reports_single_missing_node)
it("test_required_click_nodes_appends_extras", _test_required_click_nodes_appends_extras)
it("test_reports_missing_host_child_nodes_before_building_ui_manager", _test_reports_missing_host_child_nodes_before_building_ui_manager)
it("test_scheduled_callback_switches_canvas_to_base_to_hide_non_base_canvases", _test_scheduled_callback_switches_canvas_to_base_to_hide_non_base_canvases)
it("test_install_uses_existing_current_game_ref_without_start_runtime", _test_install_uses_existing_current_game_ref_without_start_runtime)
it("test_install_falls_back_to_start_runtime_when_current_game_ref_is_empty", _test_install_falls_back_to_start_runtime_when_current_game_ref_is_empty)
it("test_install_accepts_nil_opts_when_current_game_ref_is_present", _test_install_accepts_nil_opts_when_current_game_ref_is_present)
it("test_spawns_startup_synthetic_actors", _test_spawns_startup_synthetic_actors)
it("test_role_globals_install_receives_the_resolved_roles", _test_role_globals_install_receives_the_resolved_roles)
it("test_game_init_wires_like_collect_subscribe_setup", _test_game_init_wires_like_collect_subscribe_setup)
it("test_empty_name_entry_label_keeps_plain_node_id", _test_empty_name_entry_label_keeps_plain_node_id)
it("test_configured_and_repeated_children_are_not_reported_missing", _test_configured_and_repeated_children_are_not_reported_missing)
it("test_children_read_failure_message_carries_label_and_error", _test_children_read_failure_message_carries_label_and_error)
it("test_missing_children_join_with_comma_separator", _test_missing_children_join_with_comma_separator)
it("test_bind_getter_reads_the_shared_current_game_ref", _test_bind_getter_reads_the_shared_current_game_ref)
it("test_sync_ui_event_roles_forwards_the_resolved_roles", _test_sync_ui_event_roles_forwards_the_resolved_roles)
it("test_required_nodes_include_market_item_buttons", _test_required_nodes_include_market_item_buttons)
it("test_loading_screen_show_and_hide_use_the_registered_events", _test_loading_screen_show_and_hide_use_the_registered_events)
it("test_missing_child_label_falls_back_to_node_id_for_unnamed_entries", _test_missing_child_label_falls_back_to_node_id_for_unnamed_entries)
end)
