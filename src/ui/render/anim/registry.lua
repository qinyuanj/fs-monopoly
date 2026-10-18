local registry = {}

local handlers = {}

function registry.register(kind, handler)
  assert(kind ~= nil and kind ~= "", "missing kind")
  assert(type(handler) == "function", "missing handler")
  handlers[kind] = handler
end

function registry.resolve(kind)
  return handlers[kind]
end

return registry

