-- 本地行动者身份解析接缝(#332 拆 ui.input ↔ ui.coord 投影环):input 层
-- (route_item_slots)经此纯契约 port 解析点击者身份,不反向 require coord/
-- render 实现;实现由装配侧 configure 注入(host_install / 测试基线),
-- 未注入时调用当场报错。两个动词与实现模块同形
-- (turn_bound 是 from_event 的别名,语义原样保留);#446 收掉无生产消费者
-- 的 resolve_local。
local resolver = {}
local configured_impl = nil

local function _assert_impl_shape(impl)
  assert(type(impl) == "table", "invalid local_actor_resolver implementation")
  assert(type(impl.resolve_from_event) == "function", "local_actor_resolver implementation missing resolve_from_event")
  assert(type(impl.resolve_turn_bound) == "function", "local_actor_resolver implementation missing resolve_turn_bound")
  return impl
end

function resolver.configure(impl)
  configured_impl = _assert_impl_shape(impl)
end

function resolver.reset_for_tests()
  configured_impl = nil
end

function resolver.is_configured()
  return configured_impl ~= nil
end

function resolver.resolve_from_event(state, data)
  return assert(configured_impl, "missing local_actor_resolver implementation").resolve_from_event(state, data)
end

function resolver.resolve_turn_bound(state, data)
  return assert(configured_impl, "missing local_actor_resolver implementation").resolve_turn_bound(state, data)
end

return resolver

--[[ mutate4lua-manifest
version=4
projectHash=5c7c02ff244dcb61
scope.0.id=chunk:src/ui/seams/local_actor_resolver.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=38
scope.0.semanticHash=74903a63dbcbb31c
scope.1.id=function:_assert_impl_shape
scope.1.kind=function
scope.1.startLine=10
scope.1.endLine=15
scope.1.semanticHash=b483804eea20977b
scope.2.id=function:resolver.configure
scope.2.kind=function
scope.2.startLine=17
scope.2.endLine=19
scope.2.semanticHash=4afb02f78251fcb2
scope.3.id=function:resolver.reset_for_tests
scope.3.kind=function
scope.3.startLine=21
scope.3.endLine=23
scope.3.semanticHash=f308d8708726be18
scope.4.id=function:resolver.is_configured
scope.4.kind=function
scope.4.startLine=25
scope.4.endLine=27
scope.4.semanticHash=70efc1221c5d6d62
scope.5.id=function:resolver.resolve_from_event
scope.5.kind=function
scope.5.startLine=29
scope.5.endLine=31
scope.5.semanticHash=aba9250a8c6b104f
scope.6.id=function:resolver.resolve_turn_bound
scope.6.kind=function
scope.6.startLine=33
scope.6.endLine=35
scope.6.semanticHash=aba9250a8c6b104f
]]
