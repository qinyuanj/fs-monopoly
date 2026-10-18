local logger = require("src.foundation.log")

local Scope = {}
Scope.__index = Scope

local function _run_cleanup(cleanup)
  return pcall(cleanup)
end

function Scope.new()
  return setmetatable({
    _cleanups = {},
    _state = "active",
  }, Scope)
end

function Scope:defer(cleanup)
  assert(type(cleanup) == "function", "cleanup must be function")
  if self._state == "destroyed" then
    local ok, err = _run_cleanup(cleanup)
    if not ok then
      error(err, 2)
    end
    return cleanup
  end
  assert(self._state == "active", "cannot defer cleanup during destroying scope")
  self._cleanups[#self._cleanups + 1] = cleanup
  return cleanup
end

-- 倒序清空 cleanups 数组,聚合首个错误(CRAP 门禁 #452:循环与错误聚合
-- 从 destroy 提出来,各自复杂度落在小函数上)。后续错误只记日志。
local function _drain_cleanups(cleanups)
  local has_error = false
  local first_error = nil
  for index = #cleanups, 1, -1 do
    local cleanup = cleanups[index]
    cleanups[index] = nil
    local ok, err = _run_cleanup(cleanup)
    if not ok then
      if not has_error then
        has_error = true
        first_error = err
      else
        logger.warn("scope cleanup failed:", tostring(err))
      end
    end
  end
  return has_error, first_error
end

function Scope:destroy()
  if self._state ~= "active" then
    return
  end

  self._state = "destroying"
  local has_error, first_error = _drain_cleanups(self._cleanups)
  self._state = "destroyed"

  if has_error then
    error(first_error, 2)
  end
end

return Scope

