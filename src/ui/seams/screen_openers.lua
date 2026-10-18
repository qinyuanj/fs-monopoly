-- 开屏接缝(#332 拆 ui.coord ↔ ui.screens 投影环):coord 的开屏/收屏动作
-- (secondary_confirm / market)经此纯契约 port,不反向 require screens 模块;
-- 实现由装配侧 configure 注入(host_install / 测试基线)。
-- 签名与被转发实现同形,本模块不叠加任何屏结论。
local screen_openers = {}
local configured_impl = nil

local _REQUIRED_METHODS = {
  "open_secondary_confirm",
  "open_pre_confirm",
  "open_item_phase_pre_confirm",
  "refresh_secondary_confirm_copy",
  "open_market",
  "close_market",
}

local function _assert_impl_shape(impl)
  assert(type(impl) == "table", "invalid screen_openers implementation")
  for _, name in ipairs(_REQUIRED_METHODS) do
    assert(type(impl[name]) == "function", "screen_openers implementation missing " .. name)
  end
  return impl
end

local function _resolve_impl()
  if configured_impl == nil then
    return nil
  end
  return configured_impl
end

function screen_openers.configure(impl)
  configured_impl = _assert_impl_shape(impl)
end

function screen_openers.reset_for_tests()
  configured_impl = nil
end

function screen_openers.is_configured()
  return configured_impl ~= nil
end

function screen_openers.open_secondary_confirm(state, choice, choice_id)
  return assert(_resolve_impl(), "missing screen_openers implementation").open_secondary_confirm(state, choice, choice_id)
end

function screen_openers.open_pre_confirm(state, choice, option_id, title, body)
  return assert(_resolve_impl(), "missing screen_openers implementation").open_pre_confirm(state, choice, option_id, title, body)
end

function screen_openers.open_item_phase_pre_confirm(state, choice)
  return assert(_resolve_impl(), "missing screen_openers implementation").open_item_phase_pre_confirm(state, choice)
end

function screen_openers.refresh_secondary_confirm_copy(state, option_id)
  return assert(_resolve_impl(), "missing screen_openers implementation").refresh_secondary_confirm_copy(state, option_id)
end

function screen_openers.open_market(state, choice, choice_id, market)
  return assert(_resolve_impl(), "missing screen_openers implementation").open_market(state, choice, choice_id, market)
end

function screen_openers.close_market(state)
  return assert(_resolve_impl(), "missing screen_openers implementation").close_market(state)
end

return screen_openers

