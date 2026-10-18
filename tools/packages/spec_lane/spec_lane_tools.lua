local proc = require("foundation.proc")

local spec_lane_tools = {}

-- #298 的发现式包结构：tooling 车道 33 行
-- 手维护 ROOT 清单废除,塌缩为 tools/**/test/ + test/support/**/test/ 双口径
-- 自动收养。双口径同时匹配新旧两种布局——同名对时代(foo.lua + foo/test/)
-- 与目录即包时代(<pkg>/test/)下,测试目录都以 "test" 为名,无需区分布局。
-- 由 spec_profiles.lua 的 tooling profile 调用(runner 裸 root 优先于
-- profile.ROOT,串行/并行两条 tooling 入口共用同一口径)。
function spec_lane_tools.discover_test_roots()
  local roots = {}
  local seen = {}
  for _, base in ipairs({ "tools", "test/support" }) do
    local result = proc.run_command('(dir /b /s /ad "' .. base:gsub("/", "\\") .. '\\*" 2>nul & ver >nul)')
    if result.ok ~= true then
      return nil, "discover test roots failed under " .. base .. ": " .. tostring(result.output)
    end
    for line in (tostring(result.output or "") .. "\n"):gmatch("(.-)\n") do
      local root = line:gsub("\r$", ""):gsub("\\", "/"):gsub("/+$", "")
      root = root:match("/(" .. base .. "/.*)$") or root
      if root:match("/test$") and not seen[root] then
        roots[#roots + 1] = root
        seen[root] = true
      end
    end
  end
  table.sort(roots)
  return roots
end

return spec_lane_tools
