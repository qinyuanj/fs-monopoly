-- lua_env.lua —— 受控 Lua 环境(GLOSSARY「受控 Lua 环境」,spec #146 / #150)。
--
-- 本仓测试与质量工具唯一允许的 Lua 装载来源:版本落在下方口径内的机器 LuaRocks 包树。
-- 本模块只核对、不写入:preflight 只调 `luarocks config` / `luarocks list`,
-- 不满足即返回失败文本并附可直接执行的安装命令,绝不自动安装。
--
-- 本文件会被子进程 `dofile`(lint 的 luacheck 装载),故顶层不 require 任何项目模块;
-- 需要 foundation 的函数在调用时才惰性 require。

local lua_env = {}

-- 版本口径:min 含、below 不含(下一大版本)。install 是失败时打印的钉定安装版本。
lua_env.REQUIREMENTS = {
  { name = "busted", min = "2.3.0", below = "3", install = "2.3.0-1" },
  { name = "luassert", min = "1.9.0", below = "2", install = "1.9.0-1" },
  { name = "luacov", min = "0.17.0", below = "1", install = "0.17.0-1" },
  { name = "luacov-reporter-lcov", min = "0.2", below = "1", install = "0.2-0" },
  { name = "luacheck", min = "1.2.0", below = "2", install = "1.2.0-1" },
}

local LUA_VERSION = "5.4"

local function _normalize(path)
  return (tostring(path or ""):gsub("\\", "/"):gsub("/+$", ""))
end

-- "2.3.0-1" → {2,3,0};去掉 rock 修订号。认不出的片段按 0。
local function _parse_version(text)
  local base = tostring(text or ""):match("^([^%-]+)") or ""
  local parts = {}
  for number in base:gmatch("[^%.]+") do
    parts[#parts + 1] = tonumber(number:match("^%d+")) or 0
  end
  return parts
end

local function _compare(a, b)
  for index = 1, math.max(#a, #b) do
    local left, right = a[index] or 0, b[index] or 0
    if left ~= right then
      return left < right and -1 or 1
    end
  end
  return 0
end

function lua_env.version_in_range(version, requirement)
  local parsed = _parse_version(version)
  return _compare(parsed, _parse_version(requirement.min)) >= 0
    and _compare(parsed, _parse_version(requirement.below)) < 0
end

local function _range_text(requirement)
  return ">=" .. requirement.min .. ",<" .. requirement.below
end

-- 面向人的命令用裸 luarocks(PATH 上的那个),不泄露探测到的绝对路径。
local function _install_command(requirement)
  return "luarocks --lua-version " .. LUA_VERSION .. " install "
    .. requirement.name .. " " .. requirement.install
end

local function _luarocks_exe(opts)
  if opts.luarocks_exe ~= nil then
    return opts.luarocks_exe
  end
  local override = os.getenv("MONOPOLY_LUAROCKS_EXE")
  if override ~= nil and override ~= "" then
    return override
  end
  return "luarocks"
end

-- 默认子进程执行面刻意不 require foundation.proc:本模块会在 stock busted 的钉死
-- 环境里被 dofile,那时只有仓根与受控 tree 在 package.path 上,tools/ 还不可见。
-- io.popen 的 close 在失败时返回 nil, "exit", code,足够区分成功/失败。
local function _quote(arg)
  local text = tostring(arg)
  if text:match("^[%w%-%._/\\:]+$") ~= nil then
    return text
  end
  return '"' .. text .. '"'
end

local function _default_run(command)
  local parts = {}
  for _, arg in ipairs(command) do parts[#parts + 1] = _quote(arg) end
  local handle = io.popen(table.concat(parts, " ") .. " 2>&1")
  if handle == nil then
    return { ok = false, output = "io.popen failed" }
  end
  local output = handle:read("*a") or ""
  local ok, _, code = handle:close()
  return { ok = ok == true, code = code, output = output }
end

local function _run_command(opts)
  return opts.run_command or _default_run
end

-- `luarocks config rocks_trees` 打印一个 Lua 表字面量:元素是 {name=,root=} 或裸路径串。
local function _parse_roots(output)
  local chunk = load("return " .. tostring(output or ""), "=rocks_trees", "t", {})
  local ok, trees = false, nil
  if chunk ~= nil then
    ok, trees = pcall(chunk)
  end
  if not ok or type(trees) ~= "table" then
    return nil
  end
  local roots = {}
  for _, tree in ipairs(trees) do
    local root = type(tree) == "table" and tree.root or tree
    if type(root) == "string" and root ~= "" then
      roots[#roots + 1] = root
    end
  end
  if #roots == 0 then
    return nil
  end
  return roots
end

-- 该包在机器 tree 中已装的全部版本;按名称精确过滤(luarocks list 是子串匹配)。
local function _installed_versions(run, exe, name)
  local result = run({ exe, "--lua-version", LUA_VERSION, "list", name, "--porcelain" })
  local versions = {}
  if result.ok ~= true then
    return versions
  end
  for line in tostring(result.output or ""):gmatch("[^\r\n]+") do
    local pkg, version = line:match("^([^\t]+)\t([^\t]+)\tinstalled")
    if pkg == name then
      versions[#versions + 1] = version
    end
  end
  return versions
end

-- 解析受控 Lua 环境的 tree 根:`luarocks config rocks_trees`。
-- 只读、不列包;需要版本核对时用 preflight。失败返回 nil, 诊断文本。
function lua_env.roots(opts)
  opts = opts or {}
  local run = _run_command(opts)
  local exe = _luarocks_exe(opts)
  local config = run({ exe, "--lua-version", LUA_VERSION, "config", "rocks_trees" })
  if config.ok ~= true then
    return nil, "受控 Lua 环境不可核对: `luarocks config rocks_trees` 失败: " .. tostring(config.output)
  end
  local roots = _parse_roots(config.output)
  if roots == nil then
    return nil, "受控 Lua 环境不可核对: luarocks config 未给出 rocks_trees: " .. tostring(config.output)
  end
  return roots
end

-- 预检受控 Lua 环境。返回 true, nil, { roots = {...}, versions = {name = version} };
-- 失败返回 nil, 诊断文本(含逐项安装命令)。run_command / luarocks_exe 为注入缝。
function lua_env.preflight(opts)
  opts = opts or {}
  local run = _run_command(opts)
  local exe = _luarocks_exe(opts)

  local roots, roots_err = lua_env.roots({ run_command = run, luarocks_exe = exe })
  if roots == nil then
    return nil, roots_err
  end

  local problems, versions = {}, {}
  for _, requirement in ipairs(lua_env.REQUIREMENTS) do
    local found = _installed_versions(run, exe, requirement.name)
    local chosen
    for _, version in ipairs(found) do
      if lua_env.version_in_range(version, requirement) then
        chosen = version
      end
    end
    if chosen ~= nil then
      versions[requirement.name] = chosen
    elseif #found == 0 then
      problems[#problems + 1] = {
        text = requirement.name .. " 未安装(要求 " .. _range_text(requirement) .. ")",
        command = _install_command(requirement),
      }
    else
      problems[#problems + 1] = {
        text = requirement.name .. " " .. table.concat(found, ", ")
          .. " 不在口径内(要求 " .. _range_text(requirement) .. ")",
        command = _install_command(requirement),
      }
    end
  end

  if #problems > 0 then
    local lines = { "受控 Lua 环境不满足本仓口径(只核对、不自动安装):" }
    for _, problem in ipairs(problems) do
      lines[#lines + 1] = "  - " .. problem.text
    end
    lines[#lines + 1] = "请手动执行:"
    for _, problem in ipairs(problems) do
      lines[#lines + 1] = "  " .. problem.command
    end
    return nil, table.concat(lines, "\n")
  end
  return true, nil, { roots = roots, versions = versions }
end

-- file 是否位于任一 root 之内(按路径段比较,root-evil 不算在 root 内;Windows 不分大小写)。
function lua_env.is_inside(file, roots)
  local target = _normalize(file):lower()
  for _, root in ipairs(roots or {}) do
    local base = _normalize(root):lower()
    if target:sub(1, #base + 1) == base .. "/" then
      return true
    end
  end
  return false
end

local function _readable(path)
  local handle = io.open(path, "rb")
  if handle == nil then
    return false
  end
  handle:close()
  return true
end

-- 按 search_path 的搜索顺序定位模块首个命中文件,并要求它位于受控 Lua 环境之内。
-- exists 为注入缝(默认可读性探测)。成功返回文件路径;否则 nil, 诊断文本。
function lua_env.locate(module, roots, search_path, exists)
  exists = exists or _readable
  local relative = tostring(module):gsub("%.", "/")
  local tried = {}
  for template in tostring(search_path):gmatch("[^;]+") do
    local candidate = _normalize((template:gsub("%?", relative)))
    if exists(candidate) then
      if lua_env.is_inside(candidate, roots) then
        return candidate
      end
      return nil, "模块 " .. module .. " 从受控 Lua 环境以外解析: " .. candidate
    end
    tried[#tried + 1] = candidate
  end
  return nil, "模块 " .. module .. " 在受控 Lua 环境中找不到(已找: " .. table.concat(tried, ", ") .. ")"
end

-- 把 roots 的 share/lib 路径前置到 package.path / package.cpath(进程内)。
function lua_env.install_paths(roots)
  for index = #roots, 1, -1 do
    local root = _normalize(roots[index])
    package.path = root .. "/share/lua/" .. LUA_VERSION .. "/?.lua;" .. root
      .. "/share/lua/" .. LUA_VERSION .. "/?/init.lua;" .. package.path
    package.cpath = root .. "/lib/lua/" .. LUA_VERSION .. "/?.dll;" .. root
      .. "/lib/lua/" .. LUA_VERSION .. "/?.so;" .. package.cpath
  end
end

-- 子进程入口:装好受控路径、校验 module 出自受控 Lua 环境,再 require 返回。
function lua_env.require_controlled(module, roots)
  lua_env.install_paths(roots)
  local file, err = lua_env.locate(module, roots, package.path)
  if file == nil then
    error(err, 0)
  end
  return require(module)
end

return lua_env
