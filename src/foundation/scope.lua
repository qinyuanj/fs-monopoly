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

--[[ mutate4lua-manifest
version=4
projectHash=813a348515fc87b9
scope.0.id=chunk:src/foundation/scope.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=76
scope.0.semanticHash=b49e2c4c039987fe
scope.1.id=function:_run_cleanup
scope.1.kind=function
scope.1.startLine=6
scope.1.endLine=8
scope.1.semanticHash=f1ce1850b7232305
scope.2.id=function:Scope.new
scope.2.kind=function
scope.2.startLine=10
scope.2.endLine=15
scope.2.semanticHash=b9caa5215cc4c906
scope.3.id=function:Scope:defer
scope.3.kind=function
scope.3.startLine=17
scope.3.endLine=29
scope.3.semanticHash=b3969483e1987ef8
scope.4.id=function:Scope:fork
scope.4.kind=function
scope.4.startLine=31
scope.4.endLine=38
scope.4.semanticHash=d4c13312beb411dc
scope.5.id=function:<anonymous>
scope.5.kind=function
scope.5.startLine=34
scope.5.endLine=36
scope.5.semanticHash=2f9b911b0d7951de
scope.6.id=function:_drain_cleanups
scope.6.kind=function
scope.6.startLine=42
scope.6.endLine=59
scope.6.semanticHash=3c4b988a3256b0de
scope.7.id=function:Scope:destroy
scope.7.kind=function
scope.7.startLine=61
scope.7.endLine=73
scope.7.semanticHash=3085ddfcea19a7e0
]]
