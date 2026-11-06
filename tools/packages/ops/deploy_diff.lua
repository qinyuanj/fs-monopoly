-- packages/ops/deploy_diff.lua —— deploy-diff 子命令(部署目录与工作区的只读漂移检查)
--
-- 真机验收的是部署目录里的代码,提交的是工作区:两边不一致时验收结论不适用于提交内容。
-- 本命令按 deploy.PAYLOAD_PATHS 逐字节比对两边,不写任何文件。
--
-- 独立于 deploy 而不是 deploy 的开关:deploy 会写部署目录,需要逐次确认;只读检查不能
-- 和写入共用入口,否则开关一旦丢失或路由失效,检查就变成一次真实部署。
--
-- 比对口径与 deploy 的镜像语义一致:src 目录递归含隐藏文件,目标侧多出的文件也算漂移
-- (下次部署会被清掉,但当前真机能加载到它);payload 之外的文件(编辑器导出、日志等)不看。
--
-- 退出码:0 一致 / 1 有漂移或比对失败 / 2 用法错误 / 3 不可用。多余参数退 2 而不是 deploy
-- 的退 1:这里 1 表示「两边不一致」,用法错误不能被读成漂移。
local M = {}

local boundary = require("foundation.platform_boundary")
local fs_lib = require("foundation.fs")
local path_lib = require("foundation.path")
local proc_lib = require("foundation.proc")
local text_lib = require("foundation.text")
local tool_cli = require("foundation.tool_cli")
local deploy = require("packages.ops.deploy")

local _REAL_FS = {
  is_dir = fs_lib.is_dir,
  path_exists = fs_lib.path_exists,
  read = fs_lib.read_raw,
  list_files = proc_lib.collect_files,
}

function M.usage()
  return table.concat({
    "用法: lua5.4 tools/cli.lua deploy-diff",
    "",
    "只读比对部署目录与工作区的 payload(与 deploy 同一张清单:src/、main.lua、",
    "Data/UIManagerNodes.lua、Data/Prefab.lua),不写入任何文件。真机验收后、提交前跑。",
    "逐字节比对;src/ 下部署目录多出的文件也算漂移,payload 之外的文件不看。",
    "目标路径: <家目录>/Desktop/dev/eggy/LuaSource_大富翁;家目录即 %USERPROFILE%",
    "(cmd.exe 取值、wslpath -u 换算),设了 MONOPOLY_DEPLOY_HOME 时以它为准。",
    "实际路径在运行输出的 Deploy target 行;--help 本身不起 cmd.exe。",
    "退出码: 0 一致 / 1 有漂移(列出文件)或比对失败 / 2 多余参数 /",
    "3 缺 cmd.exe、wslpath 或取不到家目录(status=unavailable,未比对)。",
    "行为真源见 tools/packages/ops/deploy_diff.lua。",
    "",
  }, "\n") .. "\n"
end

-- 把 root 下的 payload 展开成相对路径集合;两边都不存在的 payload 项不进集合。
local function _payload_files(root, fs)
  local files = {}
  for _, relative_path in ipairs(deploy.PAYLOAD_PATHS) do
    local full_path = path_lib.join_path(root, relative_path)
    if fs.is_dir(full_path) then
      local listed, err = fs.list_files(full_path)
      if listed == nil then
        error(err, 0)
      end
      for _, file_path in ipairs(listed) do
        files[relative_path .. file_path:sub(#full_path + 1)] = true
      end
    elseif fs.path_exists(full_path) then
      files[relative_path] = true
    end
  end
  return files
end

local function _read(fs, path)
  local content = fs.read(path)
  if content == nil then
    error("Cannot read file: " .. tostring(path), 0)
  end
  return content
end

-- 读不到的文件抛错:少读一个就可能把漂移报成一致。
function M.compare(project_root, target_path, fs)
  fs = fs or _REAL_FS
  local workspace_files = _payload_files(project_root, fs)
  local deployed_files = _payload_files(target_path, fs)
  local drift = { compared = 0, differs = {}, workspace_only = {}, deploy_only = {} }

  for relative_path in pairs(workspace_files) do
    if deployed_files[relative_path] then
      drift.compared = drift.compared + 1
      local workspace_content = _read(fs, path_lib.join_path(project_root, relative_path))
      if workspace_content ~= _read(fs, path_lib.join_path(target_path, relative_path)) then
        drift.differs[#drift.differs + 1] = relative_path
      end
    else
      drift.workspace_only[#drift.workspace_only + 1] = relative_path
    end
  end
  for relative_path in pairs(deployed_files) do
    if not workspace_files[relative_path] then
      drift.deploy_only[#drift.deploy_only + 1] = relative_path
    end
  end

  table.sort(drift.differs)
  table.sort(drift.workspace_only)
  table.sort(drift.deploy_only)
  return drift
end

local function _unavailable(stderr, step, reason)
  local verdict = boundary.unavailable_verdict("deploy-diff", " tool=deploy-diff step=" .. step, {
    reason,
    "未做任何比对;退出码 " .. boundary.UNAVAILABLE_EXIT_CODE .. " 表示环境不可用,不是漂移。",
    "处理: 在 WSL Ubuntu 中运行,并确认 /mnt/c 已挂载(cmd.exe 与 wslpath 可见)。",
  })
  stderr:write(verdict.message)
  return verdict.exit_code
end

local function _fail(stderr, message)
  stderr:write("ERROR: " .. tostring(message) .. "\n")
  return 1
end

local function _report(drift, stdout)
  local total = #drift.differs + #drift.workspace_only + #drift.deploy_only
  stdout:write("Compared: " .. tostring(drift.compared) .. " file(s)\n")
  if total == 0 then
    stdout:write("OK: deploy dir matches the working tree.\n")
    return 0
  end
  stdout:write("DRIFT: " .. tostring(total) .. " file(s) differ between deploy dir and working tree:\n")
  for _, group in ipairs({
    { label = "differs", paths = drift.differs },
    { label = "workspace-only", paths = drift.workspace_only },
    { label = "deploy-only", paths = drift.deploy_only },
  }) do
    for _, relative_path in ipairs(group.paths) do
      stdout:write("  " .. group.label .. ": " .. relative_path .. "\n")
    end
  end
  return 1
end

-- env 是测试注入缝:detect_interop、resolve_home、project_root、fs、stdout、stderr。
function M.main(args, env)
  local help = tool_cli.help_exit(args, M.usage)
  if help ~= nil then
    return help
  end

  env = env or {}
  local stdout = env.stdout or io.stdout
  local stderr = env.stderr or io.stderr
  if args ~= nil and #args > 0 then
    stderr:write("ERROR: Unexpected argument: " .. table.concat(args, " ") .. "\n")
    return 2
  end

  local missing = (env.detect_interop or deploy.detect_interop)()
  if #missing > 0 then
    return _unavailable(stderr, "interop", "比对需要 WSL 互操作面:缺 " .. table.concat(missing, ", ") .. "。")
  end
  local home_dir = (env.resolve_home or deploy.resolve_home_dir)()
  if text_lib.trim(home_dir) == "" then
    return _unavailable(stderr, "home", "cmd.exe 与 wslpath 都在,但取不到 %USERPROFILE%。")
  end

  local fs = env.fs or _REAL_FS
  local project_root = env.project_root or deploy.resolve_project_root()
  local target_path = deploy.target_path_for_home(home_dir)
  stdout:write("Project root: " .. tostring(project_root) .. "\n")
  stdout:write("Deploy target: " .. tostring(target_path) .. "\n")
  if not fs.is_dir(target_path) then
    return _fail(stderr, "Deploy target does not exist: " .. tostring(target_path))
  end

  local ok, drift = pcall(M.compare, project_root, target_path, fs)
  if not ok then
    return _fail(stderr, drift)
  end
  if drift.compared + #drift.workspace_only + #drift.deploy_only == 0 then
    return _fail(stderr, "No payload files found on either side; nothing was compared.")
  end
  return _report(drift, stdout)
end

return M
