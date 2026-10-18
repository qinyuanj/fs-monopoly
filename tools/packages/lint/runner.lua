local _self = debug.getinfo(1, "S").source or "@tools/packages/lint/runner.lua"
local _sb = dofile(_self:gsub("\\", "/"):gsub("^@", ""):match("^(.*)/[^/]+$")
  .. "/../../foundation/script_bootstrap.lua")
local env = _sb.install("tools/packages/lint", _self)

local fs_lib = require("foundation.fs")
local path_lib = require("foundation.path")
local proc_lib = require("foundation.proc")
local text_lib = require("foundation.text")

local M = {}
local REPO_ROOT = env.repo_root
local CONFIG_PATH = path_lib.join_path(REPO_ROOT, "tools/packages/lint/.luacheckrc")
local DEFAULT_TARGETS = { "src", "test", "tools" }

local function _text(zh, en)
  return text_lib.bilingual(zh, en)
end

local function _help_text(command_name)
  local name = tostring(command_name or "tools/packages/lint/runner.lua")
  return table.concat({
    "用法:",
    "  lua " .. name .. " [path ...]",
    "  lua " .. name .. " --help",
    "",
    "Usage:",
    "  lua " .. name .. " [path ...]",
    "  lua " .. name .. " --help",
    "",
    "默认检查 src、test、tools。",
    "Default targets are src, test, and tools.",
    "luacheck 从受控 Lua 环境（机器 LuaRocks 5.4 tree）装载；只核对不安装，口径不满足退 1 并打印安装命令。",
    "luacheck loads from the controlled Lua environment (machine LuaRocks 5.4 tree); verified only, never installed.",
  }, "\n") .. "\n"
end

local function _parse_args(args)
  local options = {
    help = false,
    targets = {},
  }

  for _, token in ipairs(args or {}) do
    if token == "--help" or token == "-h" then
      options.help = true
    else
      options.targets[#options.targets + 1] = path_lib.normalize_path(token)
    end
  end

  if #options.targets == 0 then
    for _, target in ipairs(DEFAULT_TARGETS) do
      options.targets[#options.targets + 1] = target
    end
  end

  return options
end

local function _validate_targets(targets)
  for _, target in ipairs(targets or {}) do
    local resolved = path_lib.resolve_path(REPO_ROOT, target)
    if not fs_lib.path_exists(resolved) then
      return nil, _text(
        "路径不存在: " .. tostring(target),
        "Path does not exist: " .. tostring(target)
      )
    end
  end
  return true
end

local function _failure(message)
  return { code = 1, stdout = "", stderr = tostring(message) .. "\n" }
end

-- 跑一次 lint,不写终端:返回 { code, stdout, stderr },由 run 统一写出。
-- options.targets 已归一;options.preflight / options.run_command 是
-- 注入缝(默认取 foundation.lua_env / foundation.proc),测试不必替换模块字段。
function M.execute(options)
  options = options or {}
  if not fs_lib.path_exists(CONFIG_PATH) then
    return _failure(_text(
      "缺少 luacheck 配置: " .. CONFIG_PATH,
      "Missing luacheck config: " .. CONFIG_PATH
    ))
  end

  local ok, err = _validate_targets(options.targets)
  if not ok then
    return _failure(err)
  end

  -- 受控 Lua 环境预检(#150):只核对机器 LuaRocks tree,不安装、不写入;
  -- 不满足是真实失败(退 1),诊断里带可直接执行的安装命令。
  local preflight = options.preflight or require("foundation.lua_env").preflight
  local verified, preflight_err, info = preflight()
  if not verified then
    return _failure(preflight_err)
  end
  local roots = {}
  for _, root in ipairs(info.roots) do
    -- 单引号 + 正斜杠:与整条 -e 的原生 argv 定界不冲突。
    roots[#roots + 1] = "'" .. path_lib.normalize_path(root) .. "'"
  end
  local command = {
    require("foundation.lua54").lua54_bin(),
    "-e", "local e=dofile('tools/foundation/lua_env.lua'); "
      .. "e.require_controlled('luacheck.main',{" .. table.concat(roots, ",") .. "})()",
    "--", "luacheck",
    "--config", "tools/packages/lint/.luacheckrc",
    "-j", "1",
  }
  for _, target in ipairs(options.targets) do
    command[#command + 1] = target
  end

  local run_command = options.run_command or proc_lib.run_command
  local result = run_command(command, { cwd = REPO_ROOT })
  local stdout = result.output or ""
  if stdout ~= "" and stdout:sub(-1) ~= "\n" then
    stdout = stdout .. "\n"
  end
  return { code = result.ok and 0 or (result.code or 1), stdout = stdout, stderr = "" }
end

function M.run(args)
  local options = _parse_args(args or arg or {})
  if options.help then
    io.stdout:write(_help_text((arg and arg[0]) or "tools/packages/lint/runner.lua"))
    return 0
  end

  local result = M.execute(options)
  io.stdout:write(result.stdout)
  io.stderr:write(result.stderr)
  return result.code
end

function M.main()
  local code = M.run(arg or {})
  os.exit(code)
end

if ... == "packages.lint.runner" then
  return M
end

M.main()