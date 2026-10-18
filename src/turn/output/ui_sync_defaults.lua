local M = {}

-- turn 层不认识 UI 状态里的门控键名：门控语义一律经 ui_sync 端口的
-- resolve_ui_gate（gate 值对象，见 src/ui/ports/ui_sync/gate.lua）获取。
--
-- 显式契约（gameplay_loop_ports.resolve(nil) 或 ui_sync 组部分覆盖时生效）：
-- * 默认 resolve_ui_gate 不读 state.ui，恒返回全关的惰性 gate；
-- * 默认 set_input_blocked 惰性：不落写 UI 输入锁标志，恒返回 false；
-- * 需要真实门控（读或写）的调用方必须在 ui_sync 组注入
--   resolve_ui_gate / set_input_blocked（生产链路由 presentation 端口提供，
--   见 src/ui/ports/ui_sync.lua）。
-- 防静默降级：override 组提供了任一门控查询/落写键却缺 resolve_ui_gate 时，
-- fill_ui_sync_defaults 直接报错（见 _assert_gate_overrides_consistent）。
local _inert_gate = {
  input_blocked = false,
  choice_active = false,
  market_active = false,
  popup_active = false,
  popup_seq = nil,
  popup_auto_close_seconds = nil,
  popup_owner_index = nil,
}

local function _resolve_inert_gate()
  return _inert_gate
end

local function _lazy_step(load_module, step_method)
  return function(game, state, dt)
    local mod = load_module()
    mod[step_method](game, state, dt)
  end
end

-- #602 外壳退役:选择/弹层超时步进分别直读 choice_timeout 与 modal_timeout
-- 两个本源模块,不再经过外壳 loader。
function M.build_base_ui_sync_ports(load_choice_timeout, load_tick_ui_sync, load_modal_timeout)
  return {
    apply_input_lock = function() end,
    step_choice_timeout = _lazy_step(load_choice_timeout, "step_default"),
    step_modal_timeout = _lazy_step(load_modal_timeout, "step_default"),
    update_countdown = function(game, state)
      local tick_ui_sync = load_tick_ui_sync()
      tick_ui_sync.update_countdown(game, state)
    end,
    resolve_ui_gate = _resolve_inert_gate,
    build_model = function() return {} end,
    refresh_from_dirty = function() return false end,
    follow_camera = function() return false end,
    sync_camera_position = function() return false end,
    get_ui_state = function() return nil end,
    is_input_blocked = function() return false end,
    is_popup_active = function() return false end,
    is_choice_active = function() return false end,
    get_popup_owner_index = function() return nil end,
    set_input_blocked = function() return false end,
    probe_choice_ui_missing = function() end,
  }
end

local function _default_get_ui_state(state)
  return state and state.ui or nil
end

local function _default_gate_flag(field)
  return function(ui_sync_ports)
    return function(state)
      return ui_sync_ports.resolve_ui_gate(state)[field] == true
    end
  end
end

local function _default_gate_value(field)
  return function(ui_sync_ports)
    return function(state)
      return ui_sync_ports.resolve_ui_gate(state)[field]
    end
  end
end

local function _default_set_input_blocked()
  return function()
    return false
  end
end

-- fill 生成的默认实现集合（弱键）：loop 会把已解析端口组写回
-- state.gameplay_loop_ports 并在下个 tick 重新 resolve，这些派生默认
-- 不算「调用方 override」，防静默降级校验不得对其误报。
local _derived_defaults = setmetatable({}, { __mode = "k" })

local function _fill_default(ui_sync_ports, base_ui_sync_ports, key, resolver)
  if ui_sync_ports[key] == nil or ui_sync_ports[key] == base_ui_sync_ports[key] then
    local fn = resolver(ui_sync_ports)
    _derived_defaults[fn] = true
    ui_sync_ports[key] = fn
  end
end

local function _build_ui_sync_specs()
  return {
    { key = "get_ui_state", resolver = function() return _default_get_ui_state end },
    { key = "resolve_ui_gate", resolver = function() return _resolve_inert_gate end },
    { key = "is_input_blocked", resolver = _default_gate_flag("input_blocked") },
    { key = "is_popup_active", resolver = _default_gate_flag("popup_active") },
    { key = "is_choice_active", resolver = _default_gate_flag("choice_active") },
    { key = "get_popup_owner_index", resolver = _default_gate_value("popup_owner_index") },
    { key = "set_input_blocked", resolver = _default_set_input_blocked },
  }
end

local function _apply_ui_sync_defaults(ui_sync_ports, base_ui_sync_ports, specs)
  for _, spec in ipairs(specs) do
    _fill_default(ui_sync_ports, base_ui_sync_ports, spec.key, spec.resolver)
  end
end

-- 依赖 gate 语义的查询/落写键：override 提供了其中任意一个却缺 resolve_ui_gate
-- 时，resolve_ui_gate 会静默回退惰性 gate，与真实查询产生不一致信号，故直接报错。
local _gate_dependent_keys = {
  "is_input_blocked",
  "is_popup_active",
  "is_choice_active",
  "get_popup_owner_index",
  "set_input_blocked",
}

local function _is_overridden(ui_sync_ports, base_ui_sync_ports, key)
  local fn = ui_sync_ports[key]
  return fn ~= nil and fn ~= base_ui_sync_ports[key] and not _derived_defaults[fn]
end

local function _assert_gate_overrides_consistent(ui_sync_ports, base_ui_sync_ports)
  if _is_overridden(ui_sync_ports, base_ui_sync_ports, "resolve_ui_gate") then
    return
  end
  for _, key in ipairs(_gate_dependent_keys) do
    if _is_overridden(ui_sync_ports, base_ui_sync_ports, key) then
      error("ui_sync override provides " .. key
        .. " but lacks resolve_ui_gate; default resolve_ui_gate is inert (never reads state.ui)"
        .. " -- provide resolve_ui_gate to keep gate signals consistent")
    end
  end
end

local _ui_sync_specs = _build_ui_sync_specs()

function M.fill_ui_sync_defaults(ui_sync_ports, base_ui_sync_ports)
  _assert_gate_overrides_consistent(ui_sync_ports, base_ui_sync_ports)
  _apply_ui_sync_defaults(ui_sync_ports, base_ui_sync_ports, _ui_sync_specs)
end

return M

