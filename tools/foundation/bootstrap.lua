local function _normalize_path(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function _module_dir()
  local source = debug.getinfo(1, "S").source or "@tools/foundation/bootstrap.lua"
  local normalized = _normalize_path(source):gsub("^@", "")
  return normalized:match("^(.*)/[^/]+$") or "tools/foundation"
end

local runtime_paths = dofile(_module_dir() .. "/runtime_paths.lua")

local bootstrap = {}

function bootstrap.resolve(script_path, opts)
  opts = opts or {}
  return runtime_paths.resolve({
    source_path = script_path or opts.source_path or (debug.getinfo(2, "S") and debug.getinfo(2, "S").source) or "",
    cwd = opts.cwd or runtime_paths.current_dir(),
  })
end

-- 只装配仓库自身的模块搜索路径(tools/、test/、根目录)。LuaRocks 模块不在这里
-- 装载:测试与质量工具统一从受控 Lua 环境解析(foundation.lua_env),本仓只核对、
-- 不写入任何 tree,也不在项目内自举安装 rock。
function bootstrap.install(script_path, opts)
  local env = bootstrap.resolve(script_path, opts)
  local helper_path = runtime_paths.join_path(env.tools_dir, "foundation/package_path_helper.lua")
  local helper = dofile(helper_path)
  helper.install_eggy_package_paths({
    repo_root = env.repo_root,
  })
  return env
end

-- 解释器解析与全仓同源:LUA54_BIN 覆写 + 候选表 + `<candidate> -v` 版本验证全在
-- foundation.lua54 一处表达;这里不再自造第二套规则(旧实现读 arg[-1],
-- 而 `-e` 形态下 arg[-1] 恒为 nil,等于沉默退回 PATH 猜测)。调用点均已装好
-- package.path(install / script_bootstrap 在前)。
local function _selected_interpreter()
  return require("foundation.lua54").lua54_bin()
end

-- 裸命令名解析成完整可执行路径(`command -v` 首个命中);已是路径形态原样返回。
-- 只供 tool_discovery_env 导出使用,不改变 detect_lua54 自身的候选语义。
local function _interpreter_path(selected)
  local normalized = runtime_paths.normalize_path(selected)
  if normalized:find("/") ~= nil then
    return normalized
  end
  local shell_lib = require("foundation.shell")
  local found = require("foundation.proc").run_command("command -v " .. shell_lib.shell_quote(selected))
  if found.ok == true then
    local line = tostring(found.output or ""):match("[^\r\n]+")
    if line ~= nil and line ~= "" then
      return runtime_paths.normalize_path(line)
    end
  end
  return selected
end

-- #124:MONOPOLY_LUAROCKS_EXE 由入口进程解析一次后导出(见 tool_discovery_env),
-- 子进程直接复用,跳过 `command -v luarocks` 探测;覆写路径不存在时退回原探测,
-- 报错语义不变。受控 Lua 环境预检(foundation.lua_env)也读这个覆写。
local function _luarocks_exe()
  local fs_lib = require("foundation.fs")
  local override = os.getenv("MONOPOLY_LUAROCKS_EXE")
  if override ~= nil and override ~= "" then
    override = runtime_paths.normalize_path(override)
    if fs_lib.path_exists(override) then
      return override
    end
  end
  local shell_lib = require("foundation.shell")
  local found = require("foundation.proc").run_command("command -v " .. shell_lib.shell_quote("luarocks"))
  local rocks = found.ok and runtime_paths.normalize_path(tostring(found.output):match("[^\r\n]+") or "") or nil
  if rocks == "" then rocks = nil end
  assert(rocks ~= nil, "luarocks executable missing on PATH (install luarocks with Lua 5.4)")
  return rocks
end

-- #124:工具发现结果一次解析、按环境变量导出。入口(verify / spec-lane)在 spawn
-- 子进程前调用,经 proc.run_command 的 options.env 与 parallel_lanes 的 opts.env
-- 传入,整棵子进程树继承:子进程 foundation.lua54 走 LUA54_BIN 路径覆写
-- (path_exists 检查 + 一次 -v 验证),不再逐个 `command -v` 探测;bootstrap 的
-- luarocks 命令直接读 MONOPOLY_LUAROCKS_EXE。解析失败返回 nil,调用方不导出,
-- 子进程退回原有的逐进程探测(行为与旧版一致)。
function bootstrap.tool_discovery_env()
  local selected = _selected_interpreter()
  local exe = _interpreter_path(selected)
  local ok, rocks = pcall(_luarocks_exe)
  if not ok then
    return nil
  end
  return {
    LUA54_BIN = exe,
    MONOPOLY_LUAROCKS_EXE = rocks,
  }
end

return bootstrap
