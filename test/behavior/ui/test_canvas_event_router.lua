-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
-- canvas_event_router:
--   Scope 生命周期(#417):重复 bind / destroy / 中途失败回滚
--   变异幸存者补测:
--     L5 require("src.ui.coord.modal") → nil (on_close_choice 路径)
--     action_log_button bind_client_role 分支
local support = require("test.support.shared_support")
local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local _bind_ui_runtime = support.bind_ui_runtime
local _with_patches = support.with_patches
local ui_view = require("src.ui.coord.ui_runtime")
local canvas_event_router = require("src.ui.coord.canvas_event_router")
local base_nodes = require("src.ui.schema.base")
local modal_module = require("src.ui.coord.modal")
local logger = require("src.foundation.log")
local afk_signal = require("src.turn.policies.afk_signal")
-- 文件加载期捕获(与 canvas_event_router 同代引用):套件运行期若有测试重载
-- event_bindings,函数内 require 会拿到新表,补丁打不到路由器持有的旧表(#285 同款顺序耦合)。
local event_bindings = require("src.ui.coord.event_bindings")

local function _new_listenable_node()
  local node = {
    _entries = {},
  }
  function node:listen(_, cb)
    local entry = { cb = cb, alive = true }
    self._entries[#self._entries + 1] = entry
    self._listener_cb = cb
    return {
      destroy = function()
        entry.alive = false
        if self._listener_cb == cb then
          self._listener_cb = nil
        end
      end,
    }
  end
  function node:fire(data)
    local alive = 0
    for _, entry in ipairs(self._entries) do
      if entry.alive then
        alive = alive + 1
        entry.cb(data)
      end
    end
    return alive
  end
  return node
end

-- 与 test_interaction.lua 的 _router_env_patches 同款,但只包含基础 UI 假件。
local function _router_env_patches(node_map, extra)
  local patches = {
    { key = "all_roles", value = nil },
    { key = "GlobalAPI", value = { show_tips = function() end } },
    { key = "UIManager", value = {
      EVENT = { CLICK = "click" },
      query_nodes_by_name = function(name)
        local node = node_map[name] or _new_listenable_node()
        node_map[name] = node
        return { node }
      end,
      client_role = nil,
    } },
  }
  for _, patch in ipairs(extra or {}) do
    patches[#patches + 1] = patch
  end
  return patches
end

local function _make_dispatch_state(fields)
  local captured = {}
  local state = {
    ui = ui_view.build_ui_state(),
    turn_action_port = {
      dispatch_action = function(_, _, action)
        captured[#captured + 1] = action
      end,
      should_block_action = function()
        return false
      end,
    },
  }
  for key, value in pairs(fields or {}) do
    state[key] = value
  end
  return state, captured
end

local function _click_data(role_id)
  return {
    role = {
      get_roleid = function()
        return role_id
      end,
    },
  }
end

describe("TestCanvasEventRouter", function()

after_each(function()
  support.restore_runtime_services()
end)

-- L5 幸存者: require("src.ui.coord.modal") → nil
-- on_close_choice 回调从未被 dispatch 侧触发,modal 的 nil 突变体存活。
-- 这里构造 market_buy 选择并通过 dispatch_action 显式调用 on_close_choice,
-- 验证其会调用 modal.close_choice_modal。
it("test_on_close_choice_calls_close_choice_modal", function()
  local market_nodes = require("src.ui.schema.market")
  local node_map = {
    [market_nodes.confirm] = _new_listenable_node(),
  }
  local closed_choice = false

  _with_patches(_router_env_patches(node_map, {
    { target = modal_module, key = "close_choice_modal", value = function(ctx)
      closed_choice = true
      _assert_eq(ctx ~= nil, true, "close_choice_modal should receive router state ctx")
    end },
  }), function()
    local state = {
      ui = ui_view.build_ui_state(),
      ui_model = {
        current_player_id = "3",
        choice = {
          id = 15,
          kind = "market_buy",
          route_key = "market",
          allow_cancel = true,
          options = { { id = 34, label = "X" } },
        },
        market = {
          choice_id = 15,
          options = { { id = 34, label = "X" } },
        },
      },
      pending_choice_selected_option_id = 34,
      turn_action_port = {
        dispatch_action = function(_, state_arg, action, opts)
          local on_close = opts and opts.on_close_choice
          if on_close then
            on_close(state_arg)
          end
        end,
        should_block_action = function()
          return false
        end,
      },
    }
    _bind_ui_runtime(state)
    canvas_event_router.bind(state, function()
      return {}
    end)
    -- 身份随事件数据携带(#341):匿名点击不再回落缓存注入 actor。
    node_map[market_nodes.confirm]._listener_cb({ role = { get_roleid = function() return 3 end } })
  end)

  _assert_eq(closed_choice, true,
    "on_close_choice dispatch callback should invoke modal.close_choice_modal")
end)

-- L59 幸存者: route_name ~= base_nodes.action_log_button 的 ~= → == 突变体
-- action_log_button 路由的 bind_client_role 必须为 false(原始逻辑),突变体反转后
-- 为 true。截获 register_node_click 的 opts 直接验证(不能观察 client_role 副作用:
-- enable_action_log_toggle_touch 在 bind 时无条件清 client_role)。
it("test_action_log_button_no_client_role_bind", function()
  local node_map = {
    [base_nodes.action_log_button] = _new_listenable_node(),
  }
  local action_log_opts = nil
  local action_log_registered = false

  -- canvas_event_router 内的 ui_event_bindings 与 event_bindings 指向同一 module 表,
  -- 替换表上的 register_node_click 即可截获所有调用。
  local orig_register = event_bindings.register_node_click
  event_bindings.register_node_click = function(cache, route_name, callback, registered, listeners, opts)
    if route_name == base_nodes.action_log_button and not action_log_registered then
      action_log_opts = opts
      action_log_registered = true
    end
  end

  local ok, err = pcall(function()
    _with_patches(_router_env_patches(node_map), function()
      local state = {
        ui = ui_view.build_ui_state(),
      }
      _bind_ui_runtime(state)
      canvas_event_router.bind(state, function()
        return {}
      end)
    end)
  end)

  event_bindings.register_node_click = orig_register

  if not ok then
    error(err)
  end

  _assert_eq(action_log_registered, true,
    "register_node_click should be called for action_log_button route")
  _assert_eq(action_log_opts and action_log_opts.bind_client_role, false,
    "action_log_button should not bind client role (bind_client_role must be false)")
end)

-- #417: 重复 bind 销毁旧 Scope/listener;新 listener 只派发一次 intent。
it("test_rebind_destroys_old_listeners_and_dispatches_once", function()
  local node_map = {}
  local state, captured = _make_dispatch_state()

  _with_patches(_router_env_patches(node_map), function()
    _bind_ui_runtime(state)
    canvas_event_router.bind(state, function()
      return {}
    end)
    local action_node = node_map[base_nodes.action_button]
    _assert_eq(action_node ~= nil, true, "action_button node should be registered")

    canvas_event_router.bind(state, function()
      return {}
    end)

    local alive = action_node:fire(_click_data(3))
    _assert_eq(alive, 1, "rebind should leave exactly one alive listener on the node")
  end)

  _assert_eq(#captured, 1, "new listener should dispatch intent exactly once")
  _assert_eq(captured[1] and captured[1].type, "ui_button", "action_button should dispatch ui_button")
  _assert_eq(captured[1] and captured[1].id, "next", "action_button should dispatch next")
end)

it("test_clears_afk_sequence_for_game_intents_but_not_view_commands", function()
  local node_map = {}
  local state = _make_dispatch_state()
  local calls = {}
  local patches = _router_env_patches(node_map)
  patches[#patches + 1] = {
    target = afk_signal,
    key = "on_real_input",
    value = function(game, state_arg, role_id)
      calls[#calls + 1] = { game = game, state = state_arg, role_id = role_id }
    end,
  }

  _with_patches(patches, function()
    _bind_ui_runtime(state)
    canvas_event_router.bind(state, function()
      return {}
    end)
    node_map[base_nodes.action_button]:fire(_click_data(3))
    node_map[base_nodes.action_log_button]:fire(_click_data(3))
  end)

  _assert_eq(#calls, 1, "only a game intent should clear the AFK sequence")
  _assert_eq(calls[1].state, state, "the router must pass its state to the clear seam")
  _assert_eq(calls[1].role_id, 3, "the attached event actor must identify the seat")
end)

-- router.destroy 幂等，销毁后节点不再派发事件。
it("test_destroy_is_idempotent_and_stops_dispatch", function()
  local node_map = {}
  local state = _make_dispatch_state()

  _with_patches(_router_env_patches(node_map), function()
    _bind_ui_runtime(state)
    canvas_event_router.bind(state, function()
      return {}
    end)

    local action_node = node_map[base_nodes.action_button]
    canvas_event_router.destroy(state)
    _assert_eq(action_node:fire(_click_data(3)), 0,
      "destroyed listeners must not receive events")

    canvas_event_router.destroy(state)
    _assert_eq(action_node:fire(_click_data(3)), 0,
      "repeated destroy must leave listeners inactive")
  end)
end)

-- 路由注册中途失败时回滚已创建 listener，并重抛原始错误。
it("test_mid_registration_failure_rolls_back_and_rethrows", function()
  local node_map = {}
  local state = _make_dispatch_state()
  local orig_register = event_bindings.register_node_click
  local calls = 0
  local forced_error = "forced route register failure"

  event_bindings.register_node_click = function(cache, name, callback, registered, listeners, opts)
    calls = calls + 1
    if calls > 2 then
      error(forced_error)
    end
    return orig_register(cache, name, callback, registered, listeners, opts)
  end

  local ok, err = pcall(function()
    _with_patches(_router_env_patches(node_map), function()
      _bind_ui_runtime(state)
      canvas_event_router.bind(state, function()
        return {}
      end)
    end)
  end)

  event_bindings.register_node_click = orig_register

  _assert_eq(ok, false, "bind must rethrow registration failure")
  _assert_eq(tostring(err):find(forced_error, 1, true) ~= nil, true,
    "bind must rethrow the original registration error")

  -- 前两次注册可能已写入 node_map;回滚后这些 listener 不得再存活。
  -- 条件调用、无条件断言:没有 fire 的节点按 0 处理(vacuous-branch)。
  for _, node in pairs(node_map) do
    local notified = node.fire and node:fire(_click_data(3)) or 0
    _assert_eq(notified, 0,
      "rolled-back listeners must not receive events")
  end
end)

-- #417: 回滚 cleanup 抛错不阻断其他清理,且不覆盖原始注册错误。
it("test_rollback_cleanup_error_does_not_mask_registration_error", function()
  local node_map = {}
  local state = _make_dispatch_state()
  local orig_register = event_bindings.register_node_click
  local calls = 0
  local forced_error = "forced register error for cleanup mask"
  local warnings = {}
  local original_warn = logger.warn

  event_bindings.register_node_click = function(cache, name, callback, registered, listeners, opts)
    calls = calls + 1
    if calls == 1 then
      orig_register(cache, name, callback, registered, listeners, opts)
      local listener = listeners[#listeners]
      local orig_destroy = listener.destroy
      listener.destroy = function(...)
        orig_destroy(...)
        error("cleanup boom")
      end
      return
    end
    error(forced_error)
  end
  logger.warn = function(...)
    warnings[#warnings + 1] = table.concat({ ... }, " ")
  end

  local ok, err = pcall(function()
    _with_patches(_router_env_patches(node_map), function()
      _bind_ui_runtime(state)
      canvas_event_router.bind(state, function()
        return {}
      end)
    end)
  end)

  event_bindings.register_node_click = orig_register
  logger.warn = original_warn

  _assert_eq(ok, false, "bind must still fail on registration error")
  _assert_eq(tostring(err):find(forced_error, 1, true) ~= nil, true,
    "cleanup errors must not replace the original registration error")
  _assert_eq(tostring(err):find("cleanup boom", 1, true) == nil, true,
    "cleanup boom must not surface as the bind error")
  _assert_eq(#warnings >= 1, true, "rollback cleanup failure should be logged")
  local joined = table.concat(warnings, "\n")
  _assert_eq(joined:find("cleanup boom", 1, true) ~= nil, true,
    "logged warnings should mention the cleanup failure")
end)

end)
