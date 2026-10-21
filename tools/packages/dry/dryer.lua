-- packages/dry/dryer.lua —— dry 车道对邻接 dryer 检出的纯演算面(#148 / 父 spec #146)。
--
-- 结构重复检测由 qinyuanj/dryer 承接:检出放 uml-viewer 邻接目录 .uml-viewer/dryer,
-- 按文档手动 clone 并建 venv(与 crapper / mutator 同口径,见 tools/specs/dryer.prompt);
-- 本仓只核对、不安装,直接用 venv 的 Python 调 -m dryer(不依赖上游可执行位)。
-- 本模块不起进程、不落盘;起进程与写终端在 cli.lua。
local M = {}

M.TOOL = "dryer"
M.METRICS = ".metrics/dry.edn"

-- dryer 在零个源文件时打印这句并退 0、不写 .metrics/dry.edn(dryer/cli.py)。
M.NO_SOURCE_MESSAGE = "No source files to analyze."

local function _normalize(path)
  return (tostring(path or ""):gsub("\\", "/"):gsub("/+$", ""))
end

function M.checkout_dir(root)
  return _normalize(root) .. "/.uml-viewer/dryer"
end

function M.python_path(root)
  return M.checkout_dir(root) .. "/.venv/bin/python"
end

-- 探针:版本 + 包导入位置,交 uml_quality.runtime.python_verdict 同口径判定。
M.PYTHON_PROBE = "import sys, dryer; print('.'.join(map(str, sys.version_info[:3]))); print(dryer.__file__)"

-- 缺检出或缺 venv 是「不可用」(退 3,不启动工具);其余预检不过才是真实失败。
-- present 形如 { checkout = bool, python = bool }。
function M.availability(root, present)
  if not present.checkout then
    return { step = "checkout", detail = M.checkout_dir(root) .. " 缺失" }
  end
  if not present.python then
    return { step = "venv", detail = M.python_path(root) .. " 缺失" }
  end
  return nil
end

-- 取 --root 参数(未给则仓根);相对路径按仓根解析。--root 缺值时返回 nil,交 dryer 报用法错。
function M.metrics_root(args, root)
  local value = root
  for index, arg in ipairs(args or {}) do
    if arg == "--root" then
      value = args[index + 1]
      if value == nil or value == "" or value:sub(1, 1) == "-" then return nil end
    end
  end
  value = _normalize(value)
  if value:match("^%a:/") or value:sub(1, 1) == "/" then return value end
  return _normalize(root) .. "/" .. value
end

-- 有效结果判据:dryer 退 0、没有「零源文件」提示,且本次新写出了 .metrics/dry.edn
-- (调用方在运行前已把旧文件移走,所以「存在」即「本次写出」)。dryer 不输出候选文件数,
-- 但它在零文件时既不写文件也打 NO_SOURCE_MESSAGE,所以「新写出」蕴含候选文件数 > 0。
-- 重复项只提示,不进判据。返回 { ok = bool, reason = 失败原因 }。
function M.judge(code, output, wrote_metrics)
  if code ~= 0 then
    return { ok = false, reason = "dryer 退出码 " .. tostring(code) }
  end
  if tostring(output or ""):find(M.NO_SOURCE_MESSAGE, 1, true) ~= nil then
    return { ok = false, reason = "候选文件数为 0:目标下没有可分析的源文件;这不是「没有重复」" }
  end
  if not wrote_metrics then
    return { ok = false, reason = "本次未写出 " .. M.METRICS .. ";这不是「没有重复」" }
  end
  return { ok = true }
end

return M
