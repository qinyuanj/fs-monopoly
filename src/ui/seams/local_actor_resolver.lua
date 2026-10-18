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

