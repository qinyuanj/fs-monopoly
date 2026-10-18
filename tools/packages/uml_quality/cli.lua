-- packages/uml_quality/cli.lua —— uml 子命令(#93):邻接 uml-viewer 质量入口的原生 Windows 调用面。
--
-- 统一接口形态(#300 决议):
--   M.main(args, env) -> 退出码
--   M.usage()         -> 完整 usage 文本
--
-- 质量算法与派发优先级在邻接 uml-viewer;本包钉环境、预检并独立核验变异结果:
--   1. 预检:Lua 模块只从受控 Lua 环境(`luarocks config` 解析的机器 tree)解析
--      (不借仓内工具 tree)、PowerShell 7、uml-viewer 检出、uml-quality.json(用
--      uml-viewer 自己的读取器校验)、crapper/mutator 的 Python 3.11+ venv。任一
--      不过退 1,先删陈旧的 .uml-viewer/quality-result.json,不起工具。
--   2. 派发:在钉死 LUA_PATH/LUA_CPATH/PATH 的 cmd 批处理里跑 uml-command.ps1,
--      crap 退出码原样回传;mutate 独立按目标核验,有效结果/no-sites 退 0,未执行退 1。
-- 预检失败退 1;上游 mutate 的 3(存活突变)只在独立核验通过后归一为 0。
--
-- ir / view(#99 / ADR 0070):
--   ir   从 arch_policy 投影 + docs/architecture.proposals.edn 生成仓根 policy.edn
--        (gitignore),再经 uml-command.ps1 ir 调上游 ir-generator 写 tmp/uml/monopoly.edn。
--   view 在钉死 LUA_PATH/LUA_CPATH 的批处理里调上游启动器,herdr 由上游从 PATH 选
--        (>= 0.9.3 最高版);环境沿启动链下传到 companion,父进程与全局环境不变。
-- env.preflight / env.launch 可注入替身(测试用);缺省走真实预检与 cmd 批处理。
local M = {}

local runtime = require("packages.uml_quality.runtime")
local proposals = require("packages.uml_quality.proposals")
local arch_policy = require("packages.arch_policy")
local proc = require("foundation.proc")
local fs = require("foundation.fs")
local env_lib = require("foundation.env")
local path_lib = require("foundation.path")

local _TOOLS = { check = { "crapper", "mutator" }, crap = { "crapper" }, mutate = { "mutator" }, ir = {}, view = {} }

local _IR_OUT = "tmp/uml/monopoly.edn"

local _PYTHON_PROBE = {
  crapper = "import sys, crapper, crapper.languages.treesitter; "
    .. "print('.'.join(map(str, sys.version_info[:3]))); print(crapper.__file__)",
  mutator = "import sys, mutator; from mutator.crapper_link import ensure_crapper; c = ensure_crapper(); "
    .. "print('.'.join(map(str, sys.version_info[:3]))); print(mutator.__file__); print(c.__file__)",
}

function M.usage()
  return table.concat({
    "用法: lua tools/cli.lua uml <check|crap|mutate|ir|view> [args...]",
    "",
    "check   只做预检:受控 Lua 环境模块来源、PowerShell 7、uml-viewer 检出、",
    "        uml-quality.json、crapper/mutator Python 3.11+ venv。0 = 全过 / 1 = 有缺失。",
    "crap    预检后经 uml-command.ps1 跑 crapper(standardTools,--full-tree)。",
    "        退出码原样回传:0/2 有效结果,其余失败。",
    "mutate  预检后经 uml-command.ps1 跑 mutator;args 原样转发(目标文件或 --changed)。",
    "        独立核验每个目标:本轮 .edn 含变异统计 -> 0,输出变异/杀死/存活数;",
    "        成功扫描证明无站点 -> 0,status=no-sites;缺失/旧产物/无统计 -> 1。",
    "        上游 validResult 仅作诊断;扫描、解析或上游执行失败 -> 1。",
    "ir      arch_policy 投影 + " .. proposals.OVERRIDE_PATH .. " 的 :proposals/:omit",
    "        生成仓根 policy.edn(不入库),再经 uml-command.ps1 ir 写 " .. _IR_OUT .. "。",
    "        覆盖文件缺失/为空视为无推演;非法或含多余键退 1,不写 policy.edn。",
    "        退出码原样回传。不接受额外参数。",
    "view    预检(含 PATH 上 herdr >= 0.9.3)后,在钉死 LUA_PATH/LUA_CPATH 的环境里经",
    "        uml-command.ps1 启动图窗;args 原样转发(如 --restart)。退出码原样回传。",
    "",
    "预检失败退 1;check/crap/mutate 另删除陈旧的 .uml-viewer/quality-result.json。",
    "Python venv 搭建见 tools/specs/uml_quality.prompt。",
    "",
  }, "\n") .. "\n"
end

local function _absolute_root(repo_root)
  return path_lib.resolve_path(env_lib.current_dir(), repo_root or ".")
end

local function _report(state, ok, message)
  io.write((ok and "ok   " or "FAIL ") .. message .. "\n")
  if not ok then state.ok = false end
end

-- crapper 用 shutil.which("lua") 找解释器;钉 lua.exe 所在目录而不是 lua.cmd 垫片目录。
local function _lua_exe(state)
  local ok, lua_bin = pcall(require("foundation.lua54").lua54_bin)
  if not ok then
    _report(state, false, "lua 5.4: " .. tostring(lua_bin))
    return nil
  end
  local result = proc.run_command({ lua_bin, "-e", "io.write(arg[0])" })
  local exe = path_lib.normalize_path(tostring(result.output or ""))
  if result.ok ~= true or not fs.path_exists(exe) then
    _report(state, false, "lua 5.4: cannot resolve native interpreter behind " .. tostring(lua_bin))
    return nil
  end
  _report(state, true, "lua 5.4: " .. exe)
  return exe
end

-- 受控 Lua 环境预检(#150 / #151):只核对机器 LuaRocks tree 与版本口径,
-- 不安装、不写入;失败是真实失败(预检退 1),诊断里带安装命令。
local function _check_lua_env(state)
  local verified, err, info = require("foundation.lua_env").preflight()
  if not verified then
    _report(state, false, "controlled Lua environment: " .. tostring(err):gsub("\n", " "))
    return nil
  end
  for _, root in ipairs(info.roots) do
    _report(state, true, "controlled Lua tree " .. tostring(root))
  end
  return info.roots
end

local function _run_batch(root, env_list, argv, output_path)
  local batch = env_lib.make_temp_path("uml_quality", ".cmd")
  fs.write_file(batch, runtime.batch_text(root, env_list, argv, output_path))
  local ok, kind, code = os.execute('cmd.exe /d /v:off /c ""' .. batch:gsub("/", "\\") .. '""')
  fs.remove_path(batch)
  return require("foundation.shell").exit_status(ok, kind, code)
end

local function _probe_lua_modules(state, root, lua_exe, roots)
  local env_list = runtime.pinned_env(root, roots, path_lib.parent_dir(lua_exe), os.getenv("PATH"))
  local output_path = env_lib.make_temp_path("uml_quality_probe", ".log")
  local argv = { lua_exe, root .. "/tools/packages/uml_quality/probe_lua_modules.lua" }
  for _, name in ipairs(runtime.REQUIRED_LUA_MODULES) do argv[#argv + 1] = name end
  _run_batch(root, env_list, argv, output_path)
  local output = fs.read_raw(output_path) or ""
  fs.remove_path(output_path)
  local ok, verdicts = runtime.probe_verdicts(output, roots)
  for _, verdict in ipairs(verdicts) do _report(state, verdict.ok, "lua module " .. verdict.message) end
  if not ok and #verdicts == 0 then _report(state, false, "lua module probe produced no output: " .. output) end
  return env_list
end

local function _check_pwsh(state)
  local result = proc.run_command({ "pwsh", "-NoProfile", "-Command", "$PSVersionTable.PSVersion.Major" })
  local major = tonumber(tostring(result.output or ""):match("(%d+)"))
  _report(state, result.ok == true and major ~= nil and major >= 7,
    "PowerShell 7 (pwsh): " .. (result.ok == true and ("major " .. tostring(major)) or "not runnable"))
end

local function _check_viewer(state, root, with_config)
  local scripts = root .. "/.uml-viewer/uml-viewer/scripts"
  local present = fs.path_exists(scripts .. "/uml-command.ps1")
  _report(state, present, "uml-viewer checkout: " .. scripts .. "/uml-command.ps1" .. (present and "" or " missing"))
  if not present or not with_config then return present and scripts or nil end
  local result = proc.run_command({ "pwsh", "-NoProfile", "-File",
    root .. "/tools/packages/uml_quality/probe_config.ps1", "-Root", root, "-Scripts", scripts })
  for line in tostring(result.output or ""):gmatch("[^\r\n]+") do
    _report(state, result.ok == true, "uml-quality.json " .. line)
  end
  if result.ok ~= true and tostring(result.output or "") == "" then
    _report(state, false, "uml-quality.json probe failed (exit " .. tostring(result.code) .. ")")
  end
  return scripts
end

local function _check_python(state, root, tool)
  local python = root .. "/.uml-viewer/" .. tool .. "/.venv/Scripts/python.exe"
  if not fs.path_exists(python) then
    _report(state, false, tool .. ": " .. python .. " missing (see tools/specs/uml_quality.prompt)")
    return
  end
  local result = proc.run_command({ python, "-I", "-c", _PYTHON_PROBE[tool] }, { cwd = root })
  if result.ok ~= true then
    _report(state, false, tool .. ": import probe failed: " .. tostring(result.output))
    return
  end
  local verdict = runtime.python_verdict(tool, result.output, root)
  _report(state, verdict.ok, verdict.message)
  if tool == "mutator" then
    local version, _, linked = tostring(result.output):match("([^\r\n]+)[\r\n]+([^\r\n]+)[\r\n]+([^\r\n]+)")
    local link = runtime.python_verdict("crapper", tostring(version) .. "\n" .. tostring(linked), root)
    _report(state, link.ok, "mutator -> " .. link.message)
  end
end

-- 上游按 PATH 序扫 herdr.exe,选 >= 0.9.3 的最高版;这里同样只看 PATH,至少一个达标才放行。
-- 不钉版本、不改 PATH 次序,也不下载或升级。
local function _check_herdr(state, path)
  local seen, rejected, found = {}, {}, false
  for dir in tostring(path or ""):gmatch("[^;]+") do
    local exe = path_lib.normalize_path((dir:gsub('"', ""))) .. "/herdr.exe"
    if not seen[exe:lower()] and fs.path_exists(exe) then
      seen[exe:lower()] = true
      local result = proc.run_command({ exe, "--version" })
      local verdict = runtime.herdr_verdict(result.ok == true and result.output or nil)
      if verdict.ok then
        found = true
        _report(state, true, verdict.message .. ": " .. exe)
      else
        rejected[#rejected + 1] = exe .. " (" .. verdict.message .. ")"
      end
    end
  end
  if not found then
    _report(state, false, "herdr >= " .. table.concat(runtime.HERDR_MIN_VERSION, ".") .. ": none on PATH"
      .. (#rejected > 0 and ("; rejected " .. table.concat(rejected, "; ")) or "")
      .. " (install https://github.com/herdrdev/herdr/releases)")
  end
end

-- uml-command.ps1 ir 先选 examples/*.policy.edn,其次才是仓根 policy.edn;仓根有
-- examples/ 就可能静默顶替生成物(根白名单本就不放行它)。
local function _check_policy_unshadowed(state, root)
  local shadowed = fs.is_dir(root .. "/examples")
  _report(state, not shadowed, "policy.edn " .. (shadowed
    and "may be shadowed: " .. root .. "/examples exists (uml-command.ps1 ir prefers examples/*.policy.edn)"
    or "is the policy uml-command.ps1 ir reads"))
end

local function _preflight(root, op, env)
  local state = { ok = true }
  if op ~= "ir" then
    local lua_exe = _lua_exe(state)
    state.lua_roots = _check_lua_env(state)
    if lua_exe ~= nil and state.lua_roots ~= nil then
      state.env_list = _probe_lua_modules(state, root, lua_exe, state.lua_roots)
    end
  end
  _check_pwsh(state)
  state.scripts = _check_viewer(state, root, op ~= "ir")
  for _, tool in ipairs(_TOOLS[op]) do _check_python(state, root, tool) end
  if op == "ir" then
    state.env_list = {}
    _check_policy_unshadowed(state, root)
  end
  if op == "view" then _check_herdr(state, env.path or os.getenv("PATH")) end
  return state
end

local function _launch(root, env_list, argv)
  local _, code = _run_batch(root, env_list, argv, nil)
  return code
end

local function _echo_result(root)
  local text = fs.read_raw(root .. "/.uml-viewer/quality-result.json")
  if text == nil then
    io.stderr:write("uml: no .uml-viewer/quality-result.json was published\n")
  else
    io.write("uml: quality-result " .. (text:gsub("^\239\187\191", ""):gsub("%s+$", "")) .. "\n")
  end
end

-- 投影 + 覆盖文件在内存里合并;覆盖文件非法时不落盘任何东西。
local function _ir_policy(root)
  local policy, err = arch_policy.load(root .. "/" .. arch_policy.DEFAULT_POLICY_PATH)
  if policy == nil then return nil, err end
  return proposals.merge(arch_policy.project_uml_policy(policy), fs.read_raw(root .. "/" .. proposals.OVERRIDE_PATH), _IR_OUT)
end

local function _mutation_probe(root, state, args)
  local args_file = env_lib.make_temp_path("uml_mutation_args", ".json")
  local targets_file = env_lib.make_temp_path("uml_mutation_targets", ".json")
  local manifest = env_lib.make_temp_path("uml_mutation_manifest", ".json")
  local forward = {}
  for index = 2, #args do forward[#forward + 1] = args[index] end
  fs.write_file(args_file, require("foundation.json_writer").encode(forward))
  local result = proc.run_command({ "pwsh", "-NoProfile", "-File",
    root .. "/tools/packages/uml_quality/mutation_targets.ps1", "-Root", root,
    "-Scripts", state.scripts, "-ArgsFile", args_file, "-OutFile", targets_file })
  fs.remove_path(args_file)
  if result.output and result.output ~= "" then io.write(result.output) end
  if not result.ok then
    fs.remove_path(targets_file)
    io.stderr:write("uml: mutation target selection failed\n")
    return nil
  end
  local argv = { root .. "/.uml-viewer/mutator/.venv/Scripts/python.exe", "-I",
    root .. "/tools/packages/uml_quality/mutation_evidence.py", "prepare", root, targets_file, manifest }
  local prepared = proc.run_command(argv, { cwd = root })
  fs.remove_path(targets_file)
  if not prepared.ok then
    fs.remove_path(manifest)
    io.stderr:write("uml: mutation preparation failed: " .. tostring(prepared.output) .. "\n")
    return nil
  end
  argv[4] = "verify"
  return { argv = argv, manifest = manifest }
end

function M.main(args, env)
  args = args or {}
  env = env or {}
  local op = args[1]
  if op == "--help" or op == "-h" then
    io.write(M.usage())
    return 0
  end
  if _TOOLS[op] == nil or ((op == "check" or op == "ir") and #args > 1) then
    io.stderr:write((op == nil and "缺少子命令" or ("未知参数: " .. tostring(args[#args]))) .. "\n\n" .. M.usage())
    return 2
  end

  local root = _absolute_root(env.repo_root or ".")
  local preflight, launch = env.preflight or _preflight, env.launch or _launch
  local policy_text
  if op == "ir" then
    local err
    policy_text, err = _ir_policy(root)
    if policy_text == nil then
      io.stderr:write("uml: " .. tostring(err) .. "\numl: policy.edn was not written; ir was not started\n")
      return 1
    end
  end

  local state = preflight(root, op, env)
  if not state.ok then
    if op ~= "ir" and op ~= "view" then fs.remove_path(root .. "/.uml-viewer/quality-result.json") end
    io.stderr:write("uml: preflight failed; " .. (op == "check" and "environment is not ready" or (op .. " was not started")) .. "\n")
    return 1
  end
  if op == "check" then return 0 end

  -- view 直接走上游启动器(无子命令名);ir 不接受额外参数,输出路径由本包钉死。
  local argv = { "pwsh", "-NoProfile", "-File", state.scripts .. "/uml-command.ps1", root }
  if op ~= "view" then argv[#argv + 1] = op end
  if op == "ir" then argv[#argv + 1] = _IR_OUT end
  for index = 2, #args do argv[#argv + 1] = args[index] end

  if op == "ir" then
    fs.write_file(root .. "/policy.edn", policy_text)
    fs.ensure_parent_dir(root .. "/" .. _IR_OUT)
    return launch(root, state.env_list, argv)
  end
  if op == "view" then return launch(root, state.env_list, argv) end
  local mutation
  if op == "mutate" then
    mutation = _mutation_probe(root, state, args)
    if mutation == nil then return 1 end
  end
  local code = launch(root, state.env_list, argv)
  _echo_result(root)
  if mutation then
    local result = proc.run_command(mutation.argv, { cwd = root })
    fs.remove_path(mutation.manifest)
    io.write(result.output or "")
    if not result.ok or (code ~= 0 and code ~= 3) then return 1 end
    return 0
  end
  return code
end

return M
