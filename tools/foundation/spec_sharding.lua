--- Backend-neutral file discovery and deterministic LPT allocation.
local proc = require("foundation.proc")
local number = require("src.foundation.number")
local M = {}
function M.discover_files(roots, pattern)
  local files, seen = {}, {}
  for _, root in ipairs(roots or {}) do
    for _, path in ipairs(proc.collect_files(root, ".lua") or {}) do
      local base = path:match("([^/\\]+)%.lua$")
      if base and base:find(pattern or "test_") and not seen[path] then
        files[#files + 1] = path
        seen[path] = true
      end
    end
  end
  table.sort(files)
  return files
end
function M.discover_spec_files(root)
  if root == nil or root == "" then return {} end
  return M.discover_files({ root })
end
function M.file_cost(path)
  local file = io.open(path, "r")
  if not file then return 1 end
  local count = 0
  for line in file:lines() do
    if line:find("it(", 1, true) or line:match("[%.:]test_[%w_]*%s*%(")
      or line:match("%[%s*[\"']test_") then count = count + 1 end
  end
  file:close()
  return math.max(1, count)
end
-- 实测时长表的中位数:未测过的新文件按它计价,与已测文件同为秒数单位。
local function median(durations)
  local values = {}
  for _, seconds in pairs(durations) do values[#values + 1] = seconds end
  if #values == 0 then return nil end
  table.sort(values)
  local middle = (#values + 1) // 2
  if #values % 2 == 1 then return values[middle] end
  return (values[middle] + values[middle + 1]) / 2
end
-- durations(可选):path -> 实测秒数。给了就按秒数做 LPT(缺测文件计中位数),
-- 没给退回 it 计数估价;同一清单 + 同一时长表的分配确定性可复现。
function M.build_lpt_lanes(files, worker_count, durations)
  local lanes, ranked = {}, {}
  for i = 1, math.max(1, math.min(worker_count or 1, math.max(1, #files))) do
    lanes[i] = { index = i, total_cost = 0, files = {} }
  end
  local fallback = durations and median(durations)
  for index, path in ipairs(files) do
    local cost = fallback and (durations[path] or fallback) or M.file_cost(path)
    ranked[#ranked + 1] = { path = path, cost = cost, index = index }
  end
  table.sort(ranked, function(a, b)
    if a.cost ~= b.cost then return a.cost > b.cost end
    return a.index < b.index
  end)
  for _, entry in ipairs(ranked) do
    local target = lanes[1]
    for i = 2, #lanes do
      if lanes[i].total_cost < target.total_cost then target = lanes[i] end
    end
    target.total_cost = target.total_cost + entry.cost
    target.files[#target.files + 1] = entry.path
  end
  return lanes
end
-- 实测时长表的唯一文本格式(#107):每行「秒数<TAB>文件」,按文件名排序。
-- runner --durations-out 写、spec_lane 时长缓存读写共用这一处。
function M.format_durations(durations)
  local files, lines = {}, {}
  for file in pairs(durations) do files[#files + 1] = file end
  table.sort(files)
  for _, file in ipairs(files) do lines[#lines + 1] = string.format("%.2f\t%s", durations[file], file) end
  return table.concat(lines, "\n") .. "\n"
end
function M.parse_durations(text)
  local durations = {}
  for seconds, file in tostring(text or ""):gmatch("([%d%.]+)\t([^\r\n]+)") do
    durations[file] = tonumber(seconds)
  end
  return durations
end
function M.resolve_workers(env_var_name, file_count, default_workers)
  local capacity = math.max(1, file_count or 0)
  local resolved = default_workers or 1
  local raw = env_var_name and os.getenv(env_var_name)
  local parsed = raw and number.to_integer(raw)
  if parsed and parsed >= 1 then resolved = parsed end
  return math.max(1, math.min(resolved, capacity))
end
return M
