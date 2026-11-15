-- 环境探测与临时空间分配:当前平台、当前目录、临时目录落点。
--
-- 与 path.lua 划清界限——那边是纯路径演算,这边要读环境变量、起子进程、建目录。
-- 与 proc.lua 划清界限——那边是"跑一条命令拿结果",这边只是"问环境是什么样"。
--
-- 原生 Windows 单平台(ADR 0083):当前目录是 D:/… 正斜杠形态,临时目录落在
-- 原生 TEMP 下。注意别把「工具链跑在哪个 OS」与「部署目标是哪个 OS」搞混:
-- 部署落点活在 tools/packages/ops/deploy.lua 里,与本文件无关。
local path_lib = require("foundation.path")
local fs_lib = require("foundation.fs")
local runtime_path_ops = require("foundation.runtime_path_ops")

local env = {}

local _temp_counter = 0

local function _entropy_token()
  local pointer = tostring({}):gsub("[^%w]+", "")
  if pointer == "" then
    pointer = "ptr"
  end
  _temp_counter = _temp_counter + 1
  return table.concat({
    tostring(os.time()),
    tostring(_temp_counter),
    pointer,
  }, "_")
end

-- 当前目录真源是 runtime_path_ops.current_dir(`pwd -L`,PWD 只兜底):
-- 继承来的 PWD 可能已被子进程的 cwd 改动作废,详见该文件注释。
function env.current_dir()
  return runtime_path_ops.current_dir()
end

-- 临时目录取**原生进程**的 TEMP / TMP,缺省 C:/Windows/Temp(ADR 0083)。
-- 不读 TMPDIR,也不用 /tmp:原生 Lua 的 io.open 打不开 MSYS 的 /tmp,
-- 而 Git Bash 会把继承来的 TMP 覆盖成 /tmp——所以只能读本进程自己的值。
function env.system_tmp_dir()
  local value = os.getenv("TEMP")
  if value == nil or value == "" then
    value = os.getenv("TMP")
  end
  if value == nil or value == "" then
    value = "C:/Windows/Temp"
  end
  return path_lib.normalize_path(value)
end

function env.make_temp_path(prefix, suffix)
  local base_dir = path_lib.join_path(env.system_tmp_dir(), "eggy_script_tools")
  fs_lib.ensure_dir(base_dir)
  local name = table.concat({
    tostring(prefix or "tmp"),
    _entropy_token(),
  }, "_")
  return path_lib.join_path(base_dir, name .. tostring(suffix or ""))
end

return env
