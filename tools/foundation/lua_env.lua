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
-- module 是运行时真正 require 的入口模块,用于核对模块文件确实落在受控 tree 内。
lua_env.REQUIREMENTS = {
  { name = "busted", module = "busted.runner", min = "2.3.0", below = "3", install = "2.3.0-1" },
  { name = "luassert", module = "luassert", min = "1.9.0", below = "2", install = "1.9.0-1" },
  { name = "luacov", module = "luacov.runner", min = "0.17.0", below = "1", install = "0.17.0-1" },
  { name = "luacov-reporter-lcov", module = "luacov.reporter.lcov", min = "0.2", below = "1", install = "0.2-0" },
  { name = "luacheck", module = "luacheck.main", min = "1.2.0", below = "2", install = "1.2.0-1" },
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

-- 该包在各 tree 中已装的全部副本。`luarocks list` 默认只列当前 tree,而模块按
-- rocks_trees 顺序装载,所以必须逐 tree 询问:任一越界副本都可能先被解析到。
local function _installed_copies(run, exe, name, roots)
  local copies = {}
  for _, root in ipairs(roots) do
    local result = run({ exe, "--lua-version", LUA_VERSION, "list", "--tree=" .. root, name, "--porcelain" })
    if result.ok == true then
      for line in tostring(result.output or ""):gmatch("[^\r\n]+") do
        local pkg, version = line:match("^([^\t]+)\t([^\t]+)\tinstalled")
        if pkg == name then
          copies[#copies + 1] = { version = version, root = root }
        end
      end
    end
  end
  return copies
end

-- 按 roots 顺序拼出模块搜索路径(与 install_paths 实际装载顺序一致)。
local function _module_search_path(roots)
  local parts = {}
  for _, root in ipairs(roots) do
    local base = _normalize(root)
    parts[#parts + 1] = base .. "/share/lua/" .. LUA_VERSION .. "/?.lua"
    parts[#parts + 1] = base .. "/share/lua/" .. LUA_VERSION .. "/?/init.lua"
  end
  return table.concat(parts, ";")
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

  local problems, versions, modules = {}, {}, {}
  local search = _module_search_path(roots)
  for _, requirement in ipairs(lua_env.REQUIREMENTS) do
    local copies = _installed_copies(run, exe, requirement.name, roots)
    local described, out_of_range, chosen, verified_roots = {}, 0, nil, {}
    for _, copy in ipairs(copies) do
      described[#described + 1] = copy.version .. " (" .. copy.root .. ")"
      if lua_env.version_in_range(copy.version, requirement) then
        chosen = chosen or copy.version
        verified_roots[#verified_roots + 1] = copy.root
      else
        out_of_range = out_of_range + 1
      end
    end
    if #copies == 0 then
      problems[#problems + 1] = {
        text = requirement.name .. " 未安装(要求 " .. _range_text(requirement) .. ")",
        command = _install_command(requirement),
      }
    elseif out_of_range > 0 then
      problems[#problems + 1] = {
        text = requirement.name .. " " .. table.concat(described, ", ")
          .. " 不在口径内(要求 " .. _range_text(requirement) .. ")",
        command = _install_command(requirement),
      }
    else
      versions[requirement.name] = chosen
      -- 版本清单通过只说明 rock 已装;还要确认运行时真正 require 的模块文件
      -- 能在 roots 顺序下解析到(且 locate 本身会拒绝 tree 以外来源)。
      local file, locate_err = lua_env.locate(requirement.module, roots, search, opts.exists)
      if file == nil then
        problems[#problems + 1] = {
          text = requirement.name .. ": " .. tostring(locate_err),
          command = _install_command(requirement),
        }
      elseif not lua_env.is_inside(file, verified_roots) then
        -- 模块落在某个受控 tree 里、但该 tree 并没有本包在口径内的副本:
        -- 这份文件不是被核对的安装物,不能当成受控来源。
        problems[#problems + 1] = {
          text = requirement.name .. ": 模块 " .. requirement.module
            .. " 从被核对 tree 以外解析: " .. file,
          command = _install_command(requirement),
        }
      else
        modules[requirement.name] = file
      end
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
  return true, nil, { roots = roots, versions = versions, modules = modules }
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

-- 受控装载的搜索模板:只有 roots 的 share/lib 5.4。不留继承来的任何路径。
local function _controlled_search(roots)
  local paths, cpaths = {}, {}
  for _, root in ipairs(roots) do
    local base = _normalize(root)
    paths[#paths + 1] = base .. "/share/lua/" .. LUA_VERSION .. "/?.lua"
    paths[#paths + 1] = base .. "/share/lua/" .. LUA_VERSION .. "/?/init.lua"
    cpaths[#cpaths + 1] = base .. "/lib/lua/" .. LUA_VERSION .. "/?.dll"
    cpaths[#cpaths + 1] = base .. "/lib/lua/" .. LUA_VERSION .. "/?.so"
  end
  return table.concat(paths, ";"), table.concat(cpaths, ";")
end

-- 已装入 package.loaded 的模块不会再经过 searcher,只能按当前(尚未限制的)
-- 装载面反查来源。查不到来源也按 fail closed 处理,不把未知来源当成受控。
local function _guard_preloaded(module, roots)
  if package.loaded[module] == nil then
    return
  end
  local source = package.searchpath(module, package.path)
    or package.searchpath(module, package.cpath)
  if source == nil then
    error("模块 " .. module .. " 已预加载但无法核对来源(受控 Lua 环境要求 fail closed)", 0)
  end
  source = _normalize(source)
  if not lua_env.is_inside(source, roots) then
    error("预加载模块 " .. module .. " 从受控 Lua 环境以外解析: " .. source, 0)
  end
end

-- 置于 package.searchers 首位:所有(含 C)模块都由这里按受限路径解析,
-- 不落回继承路径、preload 或后续 searcher。
local function _install_controlled_searcher(roots)
  local function searcher(name)
    if package.preload[name] ~= nil then
      error("模块 " .. name .. " 来自 package.preload,来源不可核对", 0)
    end
    local source = package.searchpath(name, package.path)
    local native = false
    if source == nil then
      source = package.searchpath(name, package.cpath)
      native = true
    end
    if source == nil then
      error("模块 " .. name .. " 在受控 Lua 环境中找不到", 0)
    end
    source = _normalize(source)
    if not lua_env.is_inside(source, roots) then
      error("模块 " .. name .. " 从受控 Lua 环境以外解析: " .. source, 0)
    end
    local chunk, err
    if native then
      chunk, err = package.loadlib(source, "luaopen_" .. name:gsub("%.", "_"))
    else
      chunk, err = loadfile(source)
    end
    if chunk == nil then
      error(err, 0)
    end
    return chunk, source
  end
  table.insert(package.searchers, 1, searcher)
  return searcher
end

-- 受控装载入口:限制整个 require 链(含传递依赖与 C 模块)只从 roots 解析,
-- 并拒绝来源不可核对的预加载模块。默认保持受限,覆盖调用方的整个运行期
-- (lint 子进程随后还要执行 luacheck);opts.restore_paths 供进程内测试辅助
-- 在 require 结束后恢复原装载面。
function lua_env.require_controlled(module, roots, opts)
  opts = opts or {}
  _guard_preloaded(module, roots)
  if package.loaded[module] == nil and package.preload[module] ~= nil then
    error("模块 " .. module .. " 来自 package.preload,来源不可核对", 0)
  end
  local original_path, original_cpath = package.path, package.cpath
  package.path, package.cpath = _controlled_search(roots)
  local searcher = _install_controlled_searcher(roots)
  local ok, result = pcall(require, module)
  if opts.restore_paths then
    package.path, package.cpath = original_path, original_cpath
    for index, value in ipairs(package.searchers) do
      if value == searcher then
        table.remove(package.searchers, index)
        break
      end
    end
  end
  if not ok then
    error(result, 0)
  end
  return result
end

return lua_env
