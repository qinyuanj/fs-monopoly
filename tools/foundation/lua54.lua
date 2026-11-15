--- Shared, version-checked interpreter selection for every test backend.
---
--- 原生 Windows 单平台(ADR 0083):入口统一写 `lua`,候选表按 lua5.4 → lua54 →
--- lua → lua.exe 逐个尝试。名字像不算数:每个候选都跑一次 `-v`,输出含
--- 「Lua 5.4」才采用(本机 PATH 上的 `lua` 也可能是 5.1)。
--- `LUA54_BIN` 可覆写,覆写同样要过版本校验;覆写不通过就返回 nil,
--- 不悄悄回落到候选表——显式覆写失败是环境问题,不该被静默替换。
local fs = require("foundation.fs")
local proc = require("foundation.proc")
local M = {}
local cached, resolved

-- 候选顺序是契约的一部分(ADR 0083 第 7 条),测试按顺序钉住。
local _CANDIDATES = { "lua5.4", "lua54", "lua", "lua.exe" }

function M.candidates()
  local copy = {}
  for index, name in ipairs(_CANDIDATES) do
    copy[index] = name
  end
  return copy
end

-- 版本校验的唯一实现:跑一次 `<候选> -v`,输出含「Lua 5.4」才算数。
-- 命令经统一执行缝(foundation.proc → bash),所以候选是绝对路径还是裸命令名
-- 都走同一条路:裸命令名不存在时子进程自己退 127,这里一并按「不是 5.4」处理,
-- 不再单独做存在性探测(command -v 在原生 Windows 的旧执行面上判不准)。
local function is_lua54(value)
  if (value:find("/") or value:find("\\")) and not fs.path_exists(value) then
    return false
  end
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
  for _, candidate in ipairs(_CANDIDATES) do
    if is_lua54(candidate) then cached = candidate; return cached end
  end
end

-- 只返回一个值:assert 成功时会把第二个参数(诊断文本)一并吐出,而调用方
-- 常以 `{ lua54_bin(), ... }` 拼 argv,多出的值会被当成第一个参数。
function M.lua54_bin()
  local selected = M.detect_lua54()
  assert(selected ~= nil, "Lua 5.4 interpreter required (lua); check LUA54_BIN")
  return selected
end

return M
