-- tool_availability.lua —— 工具自举「不可用」的分类与诊断(#112)。
--
-- 背景:上游工具首次自举要打网络(luarocks 拉依赖与 rock 包)。网络瞬时失败时,
-- 调用方曾把它和测试失败一样退 1、摘要 failed=1,开发者与 CI 会把断网误读成
-- 测试回归。
--
-- 三态沿用 platform_boundary(#96):不可用退 3、status=unavailable 写 stderr,
-- 本次未运行、不报通过也不报失败。仓内缺陷(配置缺失)不归这里,照旧是真实失败。
--
-- 纯演算砖:保留 classify / message 供仍可能自行下载的工具与子进程诊断使用;
-- 本仓已没有项目内工具缓存,工具缺失/版本越界由受控 Lua 环境预检按真实失败报出。

-- 按本文件所在目录 dofile 兄弟模块:bootstrap 在 package.path 装好之前就加载本文件。
local function _module_dir()
  local source = debug.getinfo(1, "S").source or "@tools/foundation/tool_availability.lua"
  local normalized = tostring(source):gsub("\\", "/"):gsub("^@", "")
  return normalized:match("^(.*)/[^/]+$") or "tools/foundation"
end

local boundary = dofile(_module_dir() .. "/platform_boundary.lua")

local availability = {}

availability.EXIT_CODE = boundary.UNAVAILABLE_EXIT_CODE

-- 步骤词会出现在诊断文本里(可机读)与测试断言里,不要改字面量。
local _STEPS = {
  install = "安装 rock(luarocks install)",
}

function availability.unavailable(tool, step, detail)
  assert(_STEPS[step] ~= nil, "tool_availability: 未登记的自举步骤 " .. tostring(step))
  return {
    status = boundary.UNAVAILABLE,
    exit_code = availability.EXIT_CODE,
    tool = tool,
    step = step,
    detail = detail,
  }
end

-- 网络/下载类失败的输出特征(luarocks 的英文报错,小写子串比对)。
-- 只有命中才判不可用:编译/构建错误说明锁定版本或源码坏了,是真实失败;
-- 认不出的报错也保守按真实失败处理(宁红勿假)——包括本地化报错
-- (如中文 luarocks),认不出就退 1,这是有意的取舍。
-- 只收具体短语:裸 "ssl"/"tls"/"proxy"/"timed out" 会把 openssl/ssl.h 编译错误、
-- 编译超时、带这些字样的文件名误判成不可用。
local _HOST_PATTERNS = {
  "could not resolve host",
  "temporary failure in name resolution",
  "connection refused",
  "connection reset",
}

-- luarocks 安装:只认下载类(构建期间的超时、编译错误不算)。
local _DOWNLOAD_PATTERNS = {
  "failed downloading",
  "failed fetching",
  "error fetching",
  "could not fetch",
  "unable to download",
}

local _STEP_PATTERNS = {
  install = { _HOST_PATTERNS, _DOWNLOAD_PATTERNS },
}

local function _is_network_failure(step, detail)
  local text = tostring(detail or ""):lower()
  for _, patterns in ipairs(_STEP_PATTERNS[step]) do
    for _, pattern in ipairs(patterns) do
      if text:find(pattern, 1, true) ~= nil then
        return true
      end
    end
  end
  return false
end

-- 按失败原因分类:网络/下载类返回不可用记录,其余返回 nil(调用方按真实失败报)。
function availability.classify(tool, step, detail)
  assert(_STEPS[step] ~= nil, "tool_availability: 未登记的自举步骤 " .. tostring(step))
  if _is_network_failure(step, detail) then
    return availability.unavailable(tool, step, detail)
  end
  return nil
end

-- 渲染成 platform_boundary 的不可用判定({status, exit_code, stream, message}),
-- 入口直接交 boundary.emit 写出或取 message 放进结果字段。
-- tag 是调用方前缀(如 "spec-lane"),诊断每行都带上,便于在聚合输出里认领。
function availability.verdict(record, tag)
  return boundary.unavailable_verdict(tag,
    " tool=" .. tostring(record.tool) .. " step=" .. tostring(record.step), {
      "工具 " .. tostring(record.tool) .. " 自举失败于「" .. _STEPS[record.step]
        .. "」,通常是网络不可达或瞬时失败。",
      "本次未运行任何检查;退出码 " .. availability.EXIT_CODE .. " 表示环境不可用,不是测试/检查结论。",
      "详情: " .. tostring(record.detail),
      "处理: 检查网络(能否访问上游仓库)后重试;或在联网环境先按预检给出的命令"
        .. "把工具装进受控 Lua 环境(机器 LuaRocks tree)。",
    })
end

function availability.message(record, tag)
  return availability.verdict(record, tag).message
end

-- 入口进程认领子进程的不可用(#131:test_runner 自举 busted 断网退 3)。退 3 与
-- 状态词俱在才算,返回子进程原样输出作诊断;缺一按真实失败(宁红勿假)。
function availability.child_diagnostic(code, output)
  local text = tostring(output or "")
  if code == availability.EXIT_CODE and text:find("status=" .. boundary.UNAVAILABLE, 1, true) ~= nil then
    return text
  end
  return nil
end

return availability
