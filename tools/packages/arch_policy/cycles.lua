-- 投影环路径兼容旧 arch_view:小 SCC 最小反馈边集,大 SCC Eades 顺序,
-- 在剩余 DAG 上为每条反馈边找 BFS 最短闭合路径。无需外部 rock。
local tables = require("foundation.tables")
local M = {}
local function key(e) return e.from .. "\0" .. e.to end
local function sorted_keys(set)
  local out = {}
  for id in pairs(set) do out[#out + 1] = id end
  table.sort(out)
  return out
end
local function maps(nodes, edges)
  local incoming, outgoing = {}, {}
  for _, id in ipairs(nodes) do incoming[id], outgoing[id] = {}, {} end
  for _, e in ipairs(edges) do incoming[e.to][e.from], outgoing[e.from][e.to] = true, true end
  return incoming, outgoing
end
local function dag(nodes, edges)
  local incoming, outgoing = maps(nodes, edges)
  local queue, count = {}, 0
  for _, id in ipairs(nodes) do if next(incoming[id]) == nil then queue[#queue + 1] = id end end
  table.sort(queue)
  while #queue > 0 do
    local id = table.remove(queue, 1)
    count = count + 1
    for _, to in ipairs(sorted_keys(outgoing[id])) do
      incoming[to][id] = nil
      if next(incoming[to]) == nil then queue[#queue + 1] = to; table.sort(queue) end
    end
  end
  return count == #nodes
end
local function exact(nodes, edges)
  local removed = {}
  local function choose(start, remaining)
    if remaining == 0 then
      local kept = {}
      for i, e in ipairs(edges) do if not removed[i] then kept[#kept + 1] = e end end
      if dag(nodes, kept) then
        local feedback = {}
        for i, e in ipairs(edges) do if removed[i] then feedback[key(e)] = true end end
        return feedback
      end
      return nil
    end
    for i = start, #edges - remaining + 1 do
      removed[i] = true
      local result = choose(i + 1, remaining - 1)
      removed[i] = nil
      if result then return result end
    end
  end
  for n = 0, #edges do
    local result = choose(1, n)
    if result then return result end
  end
end
local function greedy(nodes, edges)
  local active, left, right = {}, {}, {}
  for _, id in ipairs(nodes) do active[id] = true end
  while next(active) do
    local ids = sorted_keys(active)
    local kept = {}
    for _, e in ipairs(edges) do if active[e.from] and active[e.to] then kept[#kept + 1] = e end end
    local incoming, outgoing = maps(ids, kept)
    local id, sink
    for _, candidate in ipairs(ids) do if next(incoming[candidate]) == nil then id = candidate; break end end
    if not id then
      for _, candidate in ipairs(ids) do
        if next(outgoing[candidate]) == nil then
          id, sink = candidate, true
          break
        end
      end
    end
    if not id then
      local best = -math.huge
      for _, candidate in ipairs(ids) do
        local diff = tables.count(outgoing[candidate]) - tables.count(incoming[candidate])
        if diff >= best then id, best = candidate, diff end
      end
    end
    local side = sink and right or left
    side[#side + 1], active[id] = id, nil
  end
  for i = #right, 1, -1 do left[#left + 1] = right[i] end
  local position, feedback = {}, {}
  for i, id in ipairs(left) do position[id] = i end
  for _, e in ipairs(edges) do if position[e.from] >= position[e.to] then feedback[key(e)] = true end end
  return feedback
end
local function shortest(outgoing, start, goal)
  local queue, seen = { { start } }, { [start] = true }
  while #queue > 0 do
    local path = table.remove(queue, 1)
    local id = path[#path]
    if id == goal then return path end
    for _, to in ipairs(sorted_keys(outgoing[id])) do
      if not seen[to] then
        seen[to] = true
        local next_path = { table.unpack(path) }
        next_path[#next_path + 1] = to
        queue[#queue + 1] = next_path
      end
    end
  end
end
function M.paths(nodes, links, components)
  local edges = {}
  for _, from in ipairs(nodes) do
    for _, to in ipairs(links[from] or {}) do edges[#edges + 1] = { from = from, to = to } end
  end
  table.sort(edges, function(a, b) return a.from == b.from and a.to < b.to or a.from < b.from end)
  local feedback = {}
  for _, component in ipairs(components) do
    local members, internal = {}, {}
    for _, id in ipairs(component) do members[id] = true end
    for _, e in ipairs(edges) do if members[e.from] and members[e.to] then internal[#internal + 1] = e end end
    local selected = #component <= 8 and #internal <= 12 and exact(component, internal) or greedy(component, internal)
    for edge in pairs(selected) do feedback[edge] = true end
  end
  local kept = {}
  for _, e in ipairs(edges) do if not feedback[key(e)] then kept[#kept + 1] = e end end
  local _, outgoing = maps(nodes, kept)
  local paths, seen = {}, {}
  for _, e in ipairs(edges) do
    if feedback[key(e)] then
      local path = shortest(outgoing, e.to, e.from)
      if path then
        table.insert(path, 1, e.from)
        local signature = table.concat(path, "\0")
        if not seen[signature] then paths[#paths + 1], seen[signature] = path, true end
      end
    end
  end
  return paths
end
return M
