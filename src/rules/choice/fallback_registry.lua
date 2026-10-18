local M = {}

local _registry = {}

function M.register(kind, fn)
  assert(type(kind) == "string" and kind ~= "", "invalid kind")
  assert(type(fn) == "function", "invalid fallback fn")
  _registry[kind] = fn
end

function M.resolve(kind, game, choice)
  if type(kind) ~= "string" then
    return nil
  end
  local fn = _registry[kind]
  if type(fn) ~= "function" then
    return nil
  end
  local ok, action = pcall(fn, game, choice)
  if not ok then
    return nil
  end
  return action
end

function M.reset()
  _registry = {}
end

return M

