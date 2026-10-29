-- packages/probe/script.lua —— 试玩态探针的纯演算:标记生成、long bracket 选级、
-- 包装 game_execute 代码、解析 status 与 log grep 输出。不起进程、不落盘。
local M = {}

M.MARKER_PREFIX = "DEBUG-PROBE-"

-- 标记 = 前缀 + 时间戳 + 随机十六进制;只含 [A-Za-z0-9-],在 .NET 正则里按字面匹配。
function M.make_marker(now, random_hex)
  return M.MARKER_PREFIX .. tostring(now) .. "-" .. tostring(random_hex)
end

-- 选最小的等级 n(>= 2,与 [==[ ]==] 惯例一致),使闭合串 "]" .. "="*n .. "]"
-- 不出现在载荷里。载荷以换行收尾(见 wrap),末尾的 "]" / "]=" 不会与闭合串拼接误闭合。
function M.bracket_level(payload)
  local level = 2
  local text = tostring(payload or "")
  while text:find("]" .. string.rep("=", level) .. "]", 1, true) ~= nil do
    level = level + 1
  end
  return level
end

-- 注入的 probe 前导。标记在游戏内拼接('DEBUG-PROBE-' .. '<后缀>'),
-- 这样编辑器若把 exec 源码回显进日志,源码行不会被 log grep <标记> 误命中。
function M.prelude(marker)
  local suffix = tostring(marker):sub(#M.MARKER_PREFIX + 1)
  return "local function probe(...) print('" .. M.MARKER_PREFIX .. "' .. '" .. suffix .. "', ...) end"
end

-- 交给 editor-cli exec 的完整代码:EditorAPI.game_execute([==[ <前导> <脚本> ]==])。
-- 开括号后紧跟换行(Lua 会吞掉这一个换行),脚本行号 = 原行号 + 1。
function M.wrap(source, marker)
  local payload = M.prelude(marker) .. "\n" .. tostring(source or "") .. "\n"
  local eq = string.rep("=", M.bracket_level(payload))
  return "EditorAPI.game_execute([" .. eq .. "[\n" .. payload .. "]" .. eq .. "])\n"
end

-- status 输出里 in_game_runtime 一行是否为 True;缺这一行按否处理。
function M.in_game_runtime(status_output)
  for line in (tostring(status_output or "") .. "\n"):gmatch("(.-)\r?\n") do
    local value = line:match("^%s*in_game_runtime%s+(%S+)")
    if value ~= nil then
      return value == "True"
    end
  end
  return false
end

-- log grep 文本输出:命中行形如 "> 8: [20:08:38.529] [info/client] ...",上下文行
-- 不带 "> ",末行 "matches=N ..."。只取命中行并去掉 "> <行号>: " 前缀。
function M.parse_hits(grep_output)
  local hits = {}
  for line in (tostring(grep_output or "") .. "\n"):gmatch("(.-)\r?\n") do
    if line:sub(1, 2) == "> " then
      hits[#hits + 1] = (line:gsub("^> %d+: ", "", 1))
    end
  end
  return hits
end

return M
