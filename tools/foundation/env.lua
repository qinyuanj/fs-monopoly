-- 环境探测与临时空间分配:当前平台、当前目录、临时目录落点。
--
-- 与 path.lua 划清界限——那边是纯路径演算,这边要读环境变量、起子进程、建目录。
-- 与 proc.lua 划清界限——那边是"跑一条命令拿结果",这边只是"问环境是什么样"。
--
-- 原生 Windows 单平台(ADR 0083):当前目录是 D:/… 正斜杠形态,临时目录落在
-- 原生 TEMP 下。注意别把「工具链跑在哪个 OS」与「部署目标是哪个 OS」搞混:
-- 部署落点活在 tools/packages/ops/deploy.lua 里,与本文件无关。
local path_lib = require("foundation.path")
local primitives = require("foundation.primitives")
local fs_lib = require("foundation.fs")
local runtime_path_ops = require("foundation.runtime_path_ops")

local env = {}

-- 当前目录真源是 runtime_path_ops.current_dir(`pwd -L`,PWD 只兜底):
-- 继承来的 PWD 可能已被子进程的 cwd 改动作废,详见该文件注释。
function env.current_dir()
  return runtime_path_ops.current_dir()
end

-- 临时目录真源已下沉到零依赖叶子 foundation.primitives(ADR 0083 / #234 F10):执行缝
-- 要用它落临时脚本,又不能反向依赖 env(否则 shell→env→fs→shell 成环),所以真源留在
-- 执行缝够得着的那一层;本函数只做转发,不再留一份会漂移的副本。
-- 取**原生进程**的 TEMP / TMP,缺省 C:/Windows/Temp;不读 TMPDIR、不用 /tmp
-- (原生 Lua 的 io.open 打不开 MSYS 的 /tmp,Git Bash 又会把继承来的 TMP 覆盖成 /tmp)。
-- 不再过 path.normalize_path:primitives 已经返回正斜杠、去尾斜杠的形态。
function env.system_tmp_dir()
  return primitives.tmp_dir()
end

function env.make_temp_path(prefix, suffix)
  local base_dir = path_lib.join_path(env.system_tmp_dir(), "eggy_script_tools")
  fs_lib.ensure_dir(base_dir)
  -- 唯一名原先是本文件自己数计数器 + 拼对象地址;那套与执行缝的临时脚本名各数各的,
  -- 现在统一由 primitives.unique_name 发号,同一进程内不会再撞。
  local name = primitives.unique_name(tostring(prefix or "tmp"), tostring(suffix or ""))
  return path_lib.join_path(base_dir, name)
end

return env
