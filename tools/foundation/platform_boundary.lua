-- platform_boundary.lua —— 平台保证边界的唯一真源(#96 / 母规格 #69 / ADR 0073)。
--
-- 当前开发与工具链保证面是 WSL Ubuntu 与 macOS(ADR 0073)。
-- 只保留保证面判定与不可用判决,工具不可用诊断也复用同一渲染器。
--
-- 两态必须互相可辨:不可用 / 真实失败。
--   * 不可用:平台或工具不在保证面内 → stderr 诊断 + 退出码 3,不安装、不 spawn、
--     不报通过;
--   * 真实失败:平台在保证面内 → 本模块不下判定,由真实工具自己的输出与退出码说话
--     (1 业务失败 / 2 用法错误)。
--
-- 保证面是「声明」而不是运行时探测:探测「这台机器上有没有某个 shell」会把
-- 非受支持前提重新变成隐式依赖(ADR 0073 明文否掉)。
--
-- 纯演算砖:不落盘、不起进程。unavailable_verdict 只组装判决,写终端由 emit 一处收口
-- (调用点各自挑 stdout/stderr 会分叉出多份流选择规则)。

local boundary = {}

boundary.WINDOWS = "windows"
boundary.POSIX = "posix"
boundary.LINUX = "linux"
boundary.MACOS = "macos"

-- 状态词会出现在诊断文本里(可机读)与测试断言里,不要改字面量。
boundary.UNAVAILABLE = "unavailable"

-- 退出码约定扩展(#300 Q2 → #96):0 成功 / 1 业务失败 / 2 用法错误 / 3 不可用。
-- 必须是新码,否则调用方分不清「工具没跑」与「工具跑了但失败」。
boundary.UNAVAILABLE_EXIT_CODE = 3

-- 保证面:Linux(WSL Ubuntu 开发机)与 macOS(ADR 0073)。
-- 原生 Windows 只是部署目标。
local _SUPPORTED = { [boundary.LINUX] = true, [boundary.MACOS] = true }

local function _readable(file)
  local handle = io.open(file, "r")
  if handle == nil then return false end
  handle:close()
  return true
end

-- 宿主平台。package.config 首字符是路径分隔符(Windows "\\" / POSIX "/");
-- POSIX 侧以 /proc/version 是否可读区分 Linux,以 SystemVersion.plist 区分 macOS,
-- 其余 POSIX 归 posix。
-- 不看 WSL_DISTRO_NAME:保证面按内核判 Linux,不要求必须是 WSL(#191 故事 9)。
-- 只用标准库读文件,不起进程。
function boundary.host_platform()
  if package.config:sub(1, 1) ~= "/" then
    return boundary.WINDOWS
  end
  if _readable("/proc/version") then
    return boundary.LINUX
  end
  if _readable("/System/Library/CoreServices/SystemVersion.plist") then
    return boundary.MACOS
  end
  return boundary.POSIX
end

-- 保证面判定:当前宿主是否在 ADR 0073 的保证面内。
function boundary.supported_platform(platform)
  return _SUPPORTED[platform or boundary.host_platform()] == true
end

-- 不可用诊断的唯一渲染:首行 `[tag] status=unavailable<fields>`,其余每行带同一前缀。
-- 各入口的互操作与工具预检共用,不再各写一份格式。
local function _unavailable_text(tag, fields, lines)
  local prefix = "[" .. tostring(tag) .. "] "
  local out = { prefix .. "status=" .. boundary.UNAVAILABLE .. (fields or "") }
  for _, line in ipairs(lines) do
    out[#out + 1] = prefix .. line
  end
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

-- 不可用判定(stderr + 退 3),交 emit 写出。fields 是首行状态词后的可机读字段
-- (如 " tool=luacheck step=install"),lines 是不带前缀的诊断正文。
function boundary.unavailable_verdict(tag, fields, lines)
  return {
    status = boundary.UNAVAILABLE,
    exit_code = boundary.UNAVAILABLE_EXIT_CODE,
    stream = "stderr",
    message = _unavailable_text(tag, fields, lines),
  }
end

-- 写诊断。stream 由判决给定,调用点不再各自挑输出流。
function boundary.emit(verdict)
  local stream = verdict.stream == "stderr" and io.stderr or io.stdout
  stream:write(verdict.message)
  stream:flush()
  return verdict.exit_code
end

return boundary
