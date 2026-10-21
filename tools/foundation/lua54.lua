--- Shared, version-checked interpreter selection for every test backend.
--- WSL Ubuntu 单平台(ADR 0073):入口显式写 lua5.4,候选表同样以 lua5.4 打头,
--- 不再写死 `lua`(本机 `lua` 是 5.1,兄弟仓依赖它)。
local fs = require("foundation.fs")
local proc = require("foundation.proc")
local M = {}
local cached, resolved
local function available(value)
  if value:find("/") then return fs.path_exists(value) end
  return proc.command_exists(value)
end
local function is_lua54(value)
  if not available(value) then return false end
  local result = proc.run_command({ value, "-v" })
  return result.ok == true and tostring(result.output or ""):find("Lua 5%.4") ~= nil
end
function M.detect_lua54()
  if resolved then return cached end
  resolved = true
  local override = os.getenv("LUA54_BIN")
  if override and override ~= "" then
    if is_lua54(override) then cached = override end
    return cached
  end
  for _, candidate in ipairs({ "lua5.4", "lua54" }) do
    if is_lua54(candidate) then cached = candidate; return cached end
  end
end
-- 只返回一个值:assert 成功时会把第二个参数(诊断文本)一并吐出,而调用方
-- 常以 `{ lua54_bin(), ... }` 拼 argv,多出的值会被当成第一个参数。
function M.lua54_bin()
  local selected = M.detect_lua54()
  assert(selected ~= nil, "Lua 5.4 interpreter required (lua5.4); check LUA54_BIN")
  return selected
end
return M
