-- verify 的车道规划:按 opts(tooling / serial)决定跑哪些车道、跳过哪些、
-- 给出哪些警告。
--
-- 纯函数:环境探测的结果由调用方通过 opts.env 注入(lua54_bin),
-- 这里不自己探测,所以 verify_full_spec 能把任意 env 喂进来断言。
-- luacheck 不再走"PATH 上有没有"的探测——lint 车道经钉定 5.4 解释器,
-- 从受控 Lua 环境(机器 LuaRocks tree,#150)装载,只核对不安装。
-- 车道表本身在 lane_builders,这里只决定走哪张。
local builders = require("packages.verify.lane_builders")

local lanes_mod = {}

local UNTRACKED_LISTED_LIMIT = 10

-- 未跟踪测试会被车道发现,报错时却看不出来源。这是提示:新写的测试同样未跟踪,
-- 不能判失败,也不影响退出码;调试残留的硬拦截在 debug_flags_guard。
local function _untracked_tests_warning(paths)
  local listed = table.concat(paths, ", ", 1, math.min(#paths, UNTRACKED_LISTED_LIMIT))
  local rest = #paths - UNTRACKED_LISTED_LIMIT
  return "test/ 下有 " .. #paths .. " 个未跟踪文件会进车道,失败时先排除它们: " .. listed
    .. (rest > 0 and (" 等(另有 " .. rest .. " 个)") or "")
end

function lanes_mod.resolve(opts)
  opts = opts or {}
  local env = opts.env or {}
  local lanes, skipped = builders.default(env, opts.tooling == true, opts.serial == true, opts.evidence_dir)
  local warnings = {}
  if opts.untracked_tests ~= nil and #opts.untracked_tests > 0 then
    warnings[#warnings + 1] = _untracked_tests_warning(opts.untracked_tests)
  end
  return { lanes = lanes, skipped = skipped, warnings = warnings }
end

return lanes_mod
