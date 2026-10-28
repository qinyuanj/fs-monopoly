-- platform_boundary.lua —— 平台保证边界的唯一真源(#96 / 母规格 #69 / ADR 0073)。
--
-- 当前开发与工具链保证面是 WSL Ubuntu 与 macOS(ADR 0073),声明表为空:没有「本平台
-- 不支持」的能力需要登记。
-- 保留不可用/显式跳过的通用演算,工具不可用诊断也复用渲染器。
--
-- 三态必须互相可辨(工单验收):不可用 / 显式跳过 / 真实失败。
--   * 不可用:本平台不在能力的保证面内 → stderr 诊断 + 退出码 3,不安装、不 spawn、
--     不报通过;
--   * 显式跳过:调用方加 --skip-if-unavailable 确认边界 → stdout 诊断 + 退出码 0,
--     状态词 status=skipped,同样不冒充跑过;
--   * 真实失败:平台在保证面内 → 本模块不下判定(evaluate 返回只有 args 的表),
--     由真实工具自己的输出与退出码说话(1 业务失败 / 2 用法错误)。
--
-- 边界是「声明」而不是运行时探测:探测「这台机器上有没有某个 shell」会把
-- 非受支持前提重新变成隐式依赖(ADR 0073 明文否掉),声明则让「在某平台上不可用」
-- 成为可断言的显式事实。
--
-- 纯演算砖:不落盘、不起进程。evaluate 只分类,写终端由 emit 一处收口
-- (四个调用点各自挑 stdout/stderr 会分叉出四份流选择规则)。

local boundary = {}

boundary.WINDOWS = "windows"
boundary.POSIX = "posix"
boundary.LINUX = "linux"
boundary.MACOS = "macos"

-- 状态词会出现在诊断文本里(可机读)与测试断言里,不要改字面量。
boundary.UNAVAILABLE = "unavailable"
boundary.SKIPPED = "skipped"

-- 显式跳过开关。由本模块消费:漏给上游会被当成未知选项退 2,把平台边界
-- 伪装成用法错误。
boundary.SKIP_FLAG = "--skip-if-unavailable"

-- 退出码约定扩展(#300 Q2 → #96):0 成功 / 1 业务失败 / 2 用法错误 / 3 不可用。
-- 必须是新码,否则调用方分不清「工具没跑」与「工具跑了但失败」。
boundary.UNAVAILABLE_EXIT_CODE = 3
boundary.SKIPPED_EXIT_CODE = 0

-- 声明的平台专用能力表。reason 是取证过的机制,不是泛泛的「不支持」。
local _DECLARED = {}

-- 保证面:Linux(WSL Ubuntu 开发机与 ubuntu-24.04 CI)与 macOS(ADR 0073)。
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
-- 不看 WSL_DISTRO_NAME:ubuntu-24.04 CI 不是 WSL,但与开发机同属保证面(#191 故事 9)。
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

-- 已声明能力 id 清单(排序,供未登记 id 的报错文案与文档对账)。
function boundary.declared_ids()
  local ids = {}
  for id in pairs(_DECLARED) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

-- 剥掉跳过开关,返回 (剩余 argv, 是否带了开关)。evaluate 统一消费,
-- 调用方继续执行时只向工具传递剩余 argv。
function boundary.strip_skip_flag(args)
  local argv, skip = {}, false
  for _, value in ipairs(args or {}) do
    if value == boundary.SKIP_FLAG then
      skip = true
    else
      argv[#argv + 1] = value
    end
  end
  return argv, skip
end

-- 不可用诊断的唯一渲染:首行 `[tag] status=unavailable<fields>`,其余每行带同一前缀。
-- 平台声明与工具预检共用,两处不再各写一份格式。
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

local function _declared_unavailable_lines(entry)
  return {
    "「" .. entry.title .. "」当前按平台专用能力声明,当前宿主不在保证面内(#96 / ADR 0073)。",
    "原因: " .. entry.reason,
    "本次未安装工具、未运行、未报通过;这个退出码不是检测结论。",
    "确认边界后要显式跳过,加 " .. boundary.SKIP_FLAG
      .. "(退出码 " .. boundary.SKIPPED_EXIT_CODE .. ",状态 status=" .. boundary.SKIPPED .. ")。",
  }
end

local function _skipped_text(entry)
  local tag = "[" .. entry.id .. "] "
  return table.concat({
    tag .. "status=" .. boundary.SKIPPED,
    tag .. "调用方以 " .. boundary.SKIP_FLAG .. " 显式确认了「" .. entry.title
      .. "」的 POSIX 专用边界:未安装、未运行。",
    tag .. "跳过不等于通过 —— 该能力在当前平台上仍然没有结果。",
    "",
  }, "\n")
end

-- 分类一次请求。返回表:
--   平台在保证面内 → { args = <剥掉跳过开关后的 argv> }(status/exit_code 为 nil,
--                     调用方继续走真实工具路径);
--   不可用         → { status, exit_code, stream, message, entry };
--   显式跳过       → { status, exit_code, stream, message, entry }。
-- platform 显式注入只为单测(纯函数可喂合成平台);生产调用不传,取 host_platform()。
function boundary.evaluate(id, args, platform, declarations)
  local entry = (declarations or _DECLARED)[id]
  assert(entry ~= nil,
    "platform_boundary: 未登记的能力 id " .. tostring(id)
      .. "(已登记: " .. table.concat(boundary.declared_ids(), ", ") .. ")")

  local argv, skip = boundary.strip_skip_flag(args)
  if boundary.supported_platform(platform) then
    return { args = argv }
  end

  if skip then
    return {
      args = argv,
      entry = entry,
      status = boundary.SKIPPED,
      exit_code = boundary.SKIPPED_EXIT_CODE,
      stream = "stdout",
      message = _skipped_text(entry),
    }
  end

  local verdict = boundary.unavailable_verdict(entry.id, nil, _declared_unavailable_lines(entry))
  verdict.args = argv
  verdict.entry = entry
  return verdict
end

-- 写诊断。stream 由 evaluate 给定,调用点不再各自挑输出流。
function boundary.emit(verdict)
  local stream = verdict.stream == "stderr" and io.stderr or io.stdout
  stream:write(verdict.message)
  stream:flush()
  return verdict.exit_code
end

return boundary
