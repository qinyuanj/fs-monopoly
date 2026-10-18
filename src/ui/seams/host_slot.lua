-- 宿主能力 port 的槽工厂：ui 侧只声明「函数名 + 未装配默认值」，实现表由 app
-- 装配时由 app/host_install.lua 经 configure 注入（#250）。未装配时各函数退回默认值，
-- 语义对齐 src/host 在无 runtime context 时的降级返回。
local host_slot = {}

function host_slot.new(spec)
  local slot = {}
  local impl = nil
  local names = {}

  function slot.configure(new_impl)
    impl = new_impl
  end

  function slot.reset_for_tests()
    impl = nil
  end

  function slot.is_configured()
    return impl ~= nil
  end

  for _, entry in ipairs(spec) do
    local name = entry.name
    local default = entry.default
    names[#names + 1] = name
    slot[name] = function(...)
      local fn = impl and impl[name] or nil
      if type(fn) ~= "function" then
        return default
      end
      return fn(...)
    end
  end

  -- 声明名单单一真源：聚合面（host_runtime）据此派生逐名转发，不再手写清单。
  -- 返回副本，消费方改动不回污染槽内部状态。
  function slot.declared_names()
    local copy = {}
    for i = 1, #names do
      copy[i] = names[i]
    end
    return copy
  end

  return slot
end

return host_slot

