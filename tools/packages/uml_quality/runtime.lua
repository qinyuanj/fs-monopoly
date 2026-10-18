-- packages/uml_quality/runtime.lua —— uml 质量入口的纯演算面(#93)。
--
-- 质量算法与派发全在邻接 uml-viewer(scripts/uml-command.ps1)与 crapper/mutator;
-- 本模块只决定「子进程在什么装载环境里跑」以及「解析结果是否来自受控 Lua 环境」。
-- 不起进程、不落盘;起进程与写终端在 cli.lua。
local M = {}

-- 模块来源判定只有一个实现(ADR 0072):foundation.lua_env.is_inside。
local lua_env = require("foundation.lua_env")

M.MIN_PYTHON = { 3, 11 }

-- crapper/mutator 的 Lua 默认路径(busted.runner + luacov + lcov reporter)要的模块。
M.REQUIRED_LUA_MODULES = { "busted.runner", "luassert", "luacov.runner", "luacov.reporter.lcov" }

local function _normalize(path)
  return (tostring(path or ""):gsub("\\", "/"):gsub("/+$", ""))
end

local function _within(path, prefix)
  local candidate, base = _normalize(path):lower(), _normalize(prefix):lower() .. "/"
  return candidate:sub(1, #base) == base
end

-- 子进程环境,按序写入。LUA_PATH_5_4 优先于 LUA_PATH,两者都钉同一值,避免
-- 继承用户指向全局 %APPDATA%\luarocks tree 的 LUA_PATH;不留 ";;" 默认路径。
-- 装载面 = 仓根 + 受控 Lua 环境的每个 tree(share/lib 5.4)。
function M.pinned_env(repo_root, roots, lua_dir, inherited_path)
  local path_parts = { _normalize(repo_root) .. "/?.lua", _normalize(repo_root) .. "/?/init.lua" }
  local cpath_parts = {}
  for _, root in ipairs(roots or {}) do
    local base = _normalize(root)
    path_parts[#path_parts + 1] = base .. "/share/lua/5.4/?.lua"
    path_parts[#path_parts + 1] = base .. "/share/lua/5.4/?/init.lua"
    cpath_parts[#cpath_parts + 1] = base .. "/lib/lua/5.4/?.dll"
    cpath_parts[#cpath_parts + 1] = base .. "/lib/lua/5.4/?.so"
  end
  local lua_path = table.concat(path_parts, ";")
  local lua_cpath = table.concat(cpath_parts, ";")
  local path = _normalize(lua_dir)
  if inherited_path ~= nil and inherited_path ~= "" then path = path .. ";" .. inherited_path end
  return {
    { "LUA_PATH_5_4", lua_path },
    { "LUA_PATH", lua_path },
    { "LUA_CPATH_5_4", lua_cpath },
    { "LUA_CPATH", lua_cpath },
    { "LUA_INIT", "" },
    { "LUA_INIT_5_4", "" },
    { "PATH", path },
  }
end

-- 上游 companion 在 PATH 上的 herdr 里选 `herdr X.Y.Z` >= 0.9.3(且 protocol 22)的最高版;
-- 这里只判版本,同口径(X.Y.Z 逐段数值比较);protocol 由上游判。
M.HERDR_MIN_VERSION = { 0, 9, 3 }

function M.herdr_verdict(version_output)
  local line = tostring(version_output or ""):match("^%s*(.-)%s*$")
  local minimum = table.concat(M.HERDR_MIN_VERSION, ".")
  local parts = { line:match("^herdr (%d+)%.(%d+)%.(%d+)$") }
  local supported = #parts == 3
  if supported then
    for index = 1, 3 do
      local value, floor = tonumber(parts[index]), M.HERDR_MIN_VERSION[index]
      if value ~= floor then
        supported = value > floor
        break
      end
    end
  end
  if supported then return { ok = true, message = line } end
  return { ok = false, message = "herdr >= " .. minimum .. " required, got " .. (line ~= "" and line or "nothing") }
end

function M.module_verdict(name, resolved, roots)
  if resolved == nil or resolved == "" then
    return { ok = false, message = name .. ": not found in pinned package.path" }
  end
  if not lua_env.is_inside(resolved, roots) then
    return { ok = false, message = name .. ": resolved outside controlled Lua environment: " .. resolved }
  end
  return { ok = true, message = name .. ": " .. _normalize(resolved) }
end

-- crapper/mutator 在 Lua 子进程里 pcall(require, "luarocks.loader");能解析到时
-- loader 会按用户 luarocks 配置接回全局 tree,所以它必须不可见。
function M.loader_verdict(resolved)
  if resolved == nil or resolved == "" then
    return { ok = true, message = "luarocks.loader: not resolvable (global trees stay unreachable)" }
  end
  return { ok = false, message = "luarocks.loader: resolvable at " .. resolved .. "; global trees would leak in" }
end

-- 探针(probe_lua_modules.lua)输出逐行判定;任何一行不过或没有任何判定都算失败,
-- 空输出不能读成「全部通过」。
function M.probe_verdicts(output, roots)
  local verdicts, ok = {}, true
  for line in tostring(output or ""):gmatch("[^\r\n]+") do
    local fields = {}
    for field in (line .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
    local kind, verdict = fields[1], nil
    if kind == "resolve" or kind == "load" then
      verdict = M.module_verdict(fields[2], fields[3], roots)
    elseif kind == "loader" then
      verdict = M.loader_verdict(fields[2])
    elseif kind == "error" then
      verdict = { ok = false, message = tostring(fields[2]) .. ": require failed: " .. tostring(fields[3]) }
    end
    if verdict ~= nil then
      verdicts[#verdicts + 1] = verdict
      ok = ok and verdict.ok
    end
  end
  return ok and #verdicts > 0, verdicts
end

local function _version_ok(version)
  local major, minor = tostring(version):match("^(%d+)%.(%d+)")
  if major == nil then return false end
  major, minor = tonumber(major), tonumber(minor)
  return major > M.MIN_PYTHON[1] or (major == M.MIN_PYTHON[1] and minor >= M.MIN_PYTHON[2])
end

-- output 是探针打印的两行:Python 版本、工具包 __init__.py 路径。
function M.python_verdict(tool, output, repo_root)
  local lines = {}
  for line in tostring(output or ""):gmatch("[^\r\n]+") do lines[#lines + 1] = line end
  local version, file = lines[1], lines[2]
  local required = M.MIN_PYTHON[1] .. "." .. M.MIN_PYTHON[2]
  if not _version_ok(version) then
    return { ok = false, message = tool .. ": Python " .. required .. "+ required, got " .. tostring(version) }
  end
  local source = _normalize(repo_root) .. "/.uml-viewer/" .. tool .. "/src"
  if file == nil or not _within(file, source) then
    return { ok = false, message = tool .. ": imported from " .. tostring(file) .. ", expected under " .. source }
  end
  return { ok = true, message = tool .. ": Python " .. version .. " " .. _normalize(file) }
end

-- cmd 批处理文本:cd 到仓根、写入钉死的环境、跑命令、原样回传退出码。
-- set 值里的 % 加倍,cmd 不再做变量展开;命令行沿用 shell.build_command 口径。
function M.batch_text(repo_root, env_list, argv, output_path)
  local shell = require("foundation.shell")
  local lines = { "@echo off", "chcp 65001 >nul", "cd /d " .. shell.shell_quote((_normalize(repo_root):gsub("/", "\\"))),"if errorlevel 1 exit /b 1" }
  for _, entry in ipairs(env_list) do
    lines[#lines + 1] = 'set "' .. entry[1] .. "=" .. tostring(entry[2]):gsub("%%", "%%%%") .. '"'
  end
  local command = shell.build_command(argv)
  if output_path ~= nil then command = command .. " > " .. shell.shell_quote(output_path) .. " 2>&1" end
  lines[#lines + 1] = command
  lines[#lines + 1] = "exit /b %errorlevel%"
  return table.concat(lines, "\r\n") .. "\r\n"
end

return M
