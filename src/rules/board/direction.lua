local direction_constants = require("src.rules.board.directions")
local opposite = direction_constants.opposite

local direction = {}

-- 内圈入口门控的唯一权威判据：branch parity 为偶数才允许拐入内圈。
function direction.parity_allows_inner(parity)
  return parity ~= nil and parity % 2 == 0
end

-- 优先级由序数组派生:被消费的维度只有相对次序,字面量绝对值不构成语义。
local dir_order = { "up", "right", "down", "left" }
local dir_priority = {}
for index, dir in ipairs(dir_order) do
  dir_priority[dir] = index
end

local function _sorted_dirs_comparator(a, b)
  local pa = dir_priority[a] or 100
  local pb = dir_priority[b] or 100
  -- 单 return 形态:pa == pb 时(双未知名同落兜底 100)必须由名字决胜,
  -- `<` 写成 `<=` 会直接短路真值,行为可观测。
  return pa < pb or (pa == pb and tostring(a) < tostring(b))
end

local function _sorted_dirs(neigh)
  local keys = {}
  for dir in pairs(neigh) do
    table.insert(keys, dir)
  end
  table.sort(keys, _sorted_dirs_comparator)
  return keys
end

local function _pick_any_dir(neigh, avoid_dir)
  assert(neigh ~= nil, "missing neighbors")
  for _, dir in ipairs(_sorted_dirs(neigh)) do
    if dir ~= avoid_dir then
      return dir, neigh[dir]
    end
  end
  return nil, nil
end

local function _entry_allowed(entry, can_enter_inner, skip_entry_on_tile_id, current_id, parity)
  return entry ~= nil and can_enter_inner and skip_entry_on_tile_id ~= current_id
    and direction.parity_allows_inner(parity)
end

local function _resolve_outer_next(map, current_id, step_context)
  local parity = step_context.parity
  local can_enter_inner = not step_context.entered_inner
  local skip_entry_on_tile_id = step_context.skip_entry_on_tile_id
  if not map.outer_next[current_id] then
    return nil, false
  end
  local next_id = map.outer_next[current_id]
  local entry = map.entry_points[current_id]
  if _entry_allowed(entry, can_enter_inner, skip_entry_on_tile_id, current_id, parity) then
    next_id = entry.inner_id
    return next_id, true
  end
  return next_id, false
end

local function _resolve_fresh_forward_next(map, current_id, facing)
  if facing ~= nil then
    return nil
  end
  local fresh_forward_next = map.fresh_forward_next or nil
  return fresh_forward_next and fresh_forward_next[current_id] or nil
end

local function _resolve_facing_next(neigh, facing)
  if facing == nil then
    return nil
  end
  return neigh[facing]
end

-- 非回头优先,绝路才回头。唯一非回头邻居的情形不需要单列:
-- _pick_any_dir 在只剩一个候选时必然选中它(#167 删除了冗余 unique 阶段)。
local function _resolve_fallback_next(neigh, facing)
  local back_dir = opposite[facing]
  local _, fallback_id = _pick_any_dir(neigh, back_dir)
  if fallback_id then
    return fallback_id
  end

  local _, any_id = _pick_any_dir(neigh, nil)
  return any_id
end

function direction.resolve_forward_next_id(map, current_id, neigh, facing, parity, can_enter_inner, skip_entry_on_tile_id)
  local outer_next, entered_inner = _resolve_outer_next(
    map,
    current_id,
    {
      parity = parity,
      entered_inner = not can_enter_inner,
      skip_entry_on_tile_id = skip_entry_on_tile_id,
    }
  )
  if outer_next then
    return outer_next, entered_inner
  end

  local fresh_next = _resolve_fresh_forward_next(map, current_id, facing)
  if fresh_next ~= nil then
    return fresh_next, false
  end

  local facing_next = _resolve_facing_next(neigh, facing)
  if facing_next then
    return facing_next, false
  end

  return _resolve_fallback_next(neigh, facing), false
end

function direction.resolve_forward_facing(map, current_id, facing, step_context)
  local neigh = map.neighbors[current_id]
  if neigh == nil then
    return facing
  end

  local next_id = direction.resolve_forward_next_id(
    map,
    current_id,
    neigh,
    facing,
    step_context.parity,
    not step_context.entered_inner,
    step_context.skip_entry_on_tile_id
  )
  if next_id == nil then
    return facing
  end
  return map.direction(current_id, next_id)
end

function direction.normalize_forward_step_context(parity_or_context)
  if type(parity_or_context) == "table" then
    return parity_or_context
  end
  return {
    parity = parity_or_context,
    entered_inner = false,
    skip_entry_on_tile_id = nil,
  }
end

local function _resolve_backward_by_facing(neigh, facing)
  if not facing then
    return nil
  end
  local back_dir = opposite[facing]
  if not back_dir then
    return nil
  end
  return neigh[back_dir]
end

local function _resolve_backward_from_map(map, current_id)
  if map.outer_prev[current_id] then
    return map.outer_prev[current_id]
  end
  local backward_fallback = map.backward_fallback or nil
  if backward_fallback and backward_fallback[current_id] then
    return backward_fallback[current_id]
  end
  return nil
end

local function _resolve_backward_from_neighbors(neigh, facing)
  local _, fallback_id = _pick_any_dir(neigh, facing)
  if fallback_id then
    return fallback_id
  end

  local _, any_id = _pick_any_dir(neigh, nil)
  return any_id
end

direction.try_resolve_forward_next_id = direction.resolve_forward_next_id

local function _initial_facing(player)
  return player.status and player.status.move_dir or nil
end

function direction.collect_forward_indices(board, player, max_steps)
  local map = board.map
  local facing = _initial_facing(player)
  local set = {}
  local list = {}
  local current_id = board:get_tile(player.position).id
  for step = 1, max_steps do
    local neigh = map.neighbors[current_id]
    local next_id = direction.try_resolve_forward_next_id(map, current_id, neigh, facing, nil, true, nil)
    if next_id == nil then
      break
    end
    local next_index = board:index_of_tile_id(next_id)
    if next_index == nil then
      break
    end
    set[next_index] = true
    list[#list + 1] = { index = next_index, step = step }
    local travel_dir = map.direction(current_id, next_id)
    facing = direction.resolve_forward_facing(map, next_id, travel_dir, { parity = nil, entered_inner = false })
    current_id = next_id
  end
  return { set = set, list = list }
end

function direction.collect_backward_indices(board, player, max_steps)
  local map = board.map
  local facing = _initial_facing(player)
  local set = {}
  local list = {}
  local current_id = board:get_tile(player.position).id
  for step = 1, max_steps do
    local neigh = map.neighbors[current_id]
    local result = direction.resolve_backward_next_source(map, current_id, neigh, facing)
    local next_id = result.next_id
    if next_id == nil then
      break
    end
    local next_index = board:index_of_tile_id(next_id)
    if next_index == nil then
      break
    end
    set[next_index] = true
    list[#list + 1] = { index = next_index, step = step }
    facing = map.direction(next_id, current_id)
    current_id = next_id
  end
  return { set = set, list = list }
end

-- map 直查命中后的来源标注:外环前驱表里登记过则 outer_prev,否则 backward_fallback。
local function _mapped_source(map, current_id, mapped_next_id)
  local outer_prev = map.outer_prev or nil
  if outer_prev and outer_prev[current_id] then
    return {
      next_id = mapped_next_id,
      source = "outer_prev",
    }
  end
  return {
    next_id = mapped_next_id,
    source = "backward_fallback",
  }
end

function direction.resolve_backward_next_source(map, current_id, neigh, facing)
  local reverse_facing_next_id = _resolve_backward_by_facing(neigh, facing)
  if reverse_facing_next_id then
    return {
      next_id = reverse_facing_next_id,
      source = "facing_reverse_neighbor",
    }
  end

  local mapped_next_id = _resolve_backward_from_map(map, current_id)
  if mapped_next_id then
    return _mapped_source(map, current_id, mapped_next_id)
  end

  local fallback_next_id = _resolve_backward_from_neighbors(neigh, facing)
  if fallback_next_id then
    return {
      next_id = fallback_next_id,
      source = "neighbor_fallback",
    }
  end

  return {
    next_id = nil,
    source = nil,
  }
end

direction._M_test = {
  _resolve_outer_next = _resolve_outer_next,
  _resolve_fresh_forward_next = _resolve_fresh_forward_next,
  _resolve_facing_next = _resolve_facing_next,
  _resolve_fallback_next = _resolve_fallback_next,
  _resolve_backward_from_neighbors = _resolve_backward_from_neighbors,
}

return direction

