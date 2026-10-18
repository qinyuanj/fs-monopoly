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

--[[ mutate4lua-manifest
version=4
projectHash=06b51c8b5805ffa6
scope.0.id=chunk:src/ui/seams/screen_openers.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=69
scope.0.semanticHash=3b51051cf9bb0759
scope.1.id=function:_assert_impl_shape
scope.1.kind=function
scope.1.startLine=17
scope.1.endLine=23
scope.1.semanticHash=ae5888e74a6f394e
scope.2.id=function:_resolve_impl
scope.2.kind=function
scope.2.startLine=25
scope.2.endLine=30
scope.2.semanticHash=710cb48908ddcc1c
scope.3.id=function:screen_openers.configure
scope.3.kind=function
scope.3.startLine=32
scope.3.endLine=34
scope.3.semanticHash=4afb02f78251fcb2
scope.4.id=function:screen_openers.reset_for_tests
scope.4.kind=function
scope.4.startLine=36
scope.4.endLine=38
scope.4.semanticHash=f308d8708726be18
scope.5.id=function:screen_openers.is_configured
scope.5.kind=function
scope.5.startLine=40
scope.5.endLine=42
scope.5.semanticHash=70efc1221c5d6d62
scope.6.id=function:screen_openers.open_secondary_confirm
scope.6.kind=function
scope.6.startLine=44
scope.6.endLine=46
scope.6.semanticHash=d590c542c8c308c5
scope.7.id=function:screen_openers.open_pre_confirm
scope.7.kind=function
scope.7.startLine=48
scope.7.endLine=50
scope.7.semanticHash=aad746b6887fa005
scope.8.id=function:screen_openers.open_item_phase_pre_confirm
scope.8.kind=function
scope.8.startLine=52
scope.8.endLine=54
scope.8.semanticHash=aba9250a8c6b104f
scope.9.id=function:screen_openers.refresh_secondary_confirm_copy
scope.9.kind=function
scope.9.startLine=56
scope.9.endLine=58
scope.9.semanticHash=aba9250a8c6b104f
scope.10.id=function:screen_openers.open_market
scope.10.kind=function
scope.10.startLine=60
scope.10.endLine=62
scope.10.semanticHash=360776c78d632b1f
scope.11.id=function:screen_openers.close_market
scope.11.kind=function
scope.11.startLine=64
scope.11.endLine=66
scope.11.semanticHash=f1ce1850b7232305
]]
