-- packages/dry/cli.lua —— dry 子命令(#148 / 父 spec #146):结构重复检测改由 dryer 承接。
--
-- 统一接口形态(#300 决议):
--   M.main(args, env) -> 退出码(0 有效结果 / 1 真实失败 / 2 用法错误 / 3 不可用)
--   M.usage()         -> 完整 usage 文本
--
-- dryer 检出放邻接目录 .uml-viewer/dryer(按 tools/specs/dryer.prompt 手动 clone 并建
-- venv);本包只核对、不安装,直接调 venv Python(-I -m dryer),绕过上游 `sh` 启动器。
-- 三态互相可辨:
--   * 不可用:检出或 venv 缺失 —— stderr status=unavailable,退 3,不启动工具;
--   * 真实失败:预检其余不过、dryer 非零退出、零候选文件、本次未写出 .metrics/dry.edn;
--   * 有效结果:退 0。重复项只提示,不进判据(软车道口径不变)。
-- env.root / env.proc / env.fs 可注入替身(测试用);缺省走真实仓根与子进程。
local M = {}

local dryer = require("packages.dry.dryer")

function M.usage()
  return table.concat({
    "用法: lua tools/cli.lua dry [dryer 选项] [路径或过滤词 ...]",
    "",
    "结构重复检测(软车道,dryer):抽函数 / 重构前扫候选;选项经 args 直通 dryer",
    "(--threshold / --min-lines / --min-nodes / --edn / --root / -s / --changed ...)。",
    "dryer 检出在邻接 .uml-viewer/dryer(手动 clone + venv,契约见 tools/specs/dryer.prompt),",
    "本命令只核对、不安装,直接用 venv 的 Python 运行。",
    "",
    "有效结果 = dryer 退 0、候选文件数 > 0 且本次新写出 " .. dryer.METRICS .. "(入库);",
    "否则退 1 并点名原因,绝不把空扫描报成「没有重复」。重复项只提示,不致失败。",
    "退出码:0 有效结果 / 1 真实失败 / 2 用法错误 / 3 不可用(检出或 venv 缺失,",
    "stderr 打 status=unavailable tool=dryer step=<checkout|venv>,未启动工具)。",
    "",
  }, "\n") .. "\n"
end

local function _absolute_root(env)
  if env.root ~= nil then return env.root end
  local env_lib = require("foundation.env")
  return require("foundation.path").resolve_path(env_lib.current_dir(), env.repo_root or ".")
end

local function _unavailable(info)
  local boundary = require("foundation.platform_boundary")
  local verdict = boundary.unavailable_verdict("dry", " tool=" .. dryer.TOOL .. " step=" .. info.step, {
    "dryer 的 " .. (info.step == "checkout" and "邻接检出" or "venv") .. "不可用: " .. info.detail,
    "本次未运行任何检查;退出码 " .. boundary.UNAVAILABLE_EXIT_CODE .. " 表示环境不可用,不是检测结论。",
    "处理: 按 tools/specs/dryer.prompt 手动 clone qinyuanj/dryer 到 .uml-viewer/dryer 并建 venv,再重跑。",
  })
  return boundary.emit(verdict)
end

local function _probe_python(root, proc, python)
  local result = proc.run_command({ python, "-I", "-c", dryer.PYTHON_PROBE }, { cwd = root })
  if result.ok ~= true then
    return false, "dryer: 导入探针失败: " .. tostring(result.output)
  end
  local verdict = require("packages.uml_quality.runtime").python_verdict(dryer.TOOL, result.output, root)
  return verdict.ok, verdict.message
end

-- 运行前把旧的 .metrics/dry.edn 挪到备份:此后「文件存在」即「本次新写出」。
-- 失败时放回(软车道失败不应弄丢入库的基线)。
local function _stash_metrics(fs, path)
  if not fs.path_exists(path) then return nil end
  local backup = require("foundation.env").make_temp_path("dry_metrics_backup", ".edn")
  assert(fs.copy_file(path, backup), "dry: 无法备份 " .. path)
  fs.remove_path(path)
  return backup
end

-- 返回 nil 表示收尾完成;返回文本表示恢复失败(此时备份必须留在磁盘上,
-- 不能把唯一可用的基线也删掉)。
local function _settle_metrics(fs, path, backup, ok)
  if ok then
    if backup ~= nil then fs.remove_path(backup) end
    return nil
  end
  fs.remove_path(path)
  if backup ~= nil then
    if not fs.copy_file(backup, path) then
      return "无法恢复 " .. path .. "(备份保留在 " .. backup .. ")"
    end
    fs.remove_path(backup)
  end
  return nil
end

function M.main(args, env)
  env = env or {}
  args = args or {}
  for _, value in ipairs(args) do
    if value == "--help" or value == "-h" then
      io.write(M.usage())
      return 0
    end
  end

  local root = _absolute_root(env)
  local proc = env.proc or require("foundation.proc")
  local fs = env.fs or require("foundation.fs")

  local missing = dryer.availability(root, {
    checkout = fs.path_exists(dryer.checkout_dir(root) .. "/pyproject.toml"),
    python = fs.path_exists(dryer.python_path(root)),
  })
  if missing ~= nil then return _unavailable(missing) end

  local probed, message = _probe_python(root, proc, dryer.python_path(root))
  if not probed then
    io.stderr:write("[dry] " .. tostring(message) .. "\n")
    return 1
  end

  local metrics_root = dryer.metrics_root(args, root)
  local metrics = metrics_root and (metrics_root .. "/" .. dryer.METRICS) or nil
  local backup = metrics and _stash_metrics(fs, metrics) or nil

  local argv = { dryer.python_path(root), "-I", "-m", "dryer" }
  for _, value in ipairs(args) do argv[#argv + 1] = value end
  local result = proc.run_command(argv, { cwd = root })
  io.write(result.output or "")

  if metrics == nil then
    -- --root 缺值:dryer 自己报用法错(退 1),没有可核验的产物路径。
    return result.code == 0 and 1 or result.code
  end
  local verdict = dryer.judge(result.code, result.output, fs.path_exists(metrics))
  local restore_error = _settle_metrics(fs, metrics, backup, verdict.ok)
  if not verdict.ok then
    if restore_error ~= nil then
      io.stderr:write("[dry] " .. restore_error .. "\n")
    end
    io.stderr:write("[dry] " .. verdict.reason .. "\n")
    return 1
  end
  return 0
end

return M
