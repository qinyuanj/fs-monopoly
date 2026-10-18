local event_kinds = require("src.config.gameplay.event_kinds")
local board_query = require("src.rules.board.query")
local timing = require("src.config.gameplay.timing")
local event_feed = require("src.rules.ports.event_feed")
local action_anim_port = require("src.foundation.ports.action_anim")
local number_utils = require("src.foundation.number")
local facing_policy = require("src.rules.board.facing_policy")
local roadblock = {}
local action_anim_duration = timing.action_anim_default_seconds or 1.0
local ui_candidate_slots = 7

local function _make_candidate(board, player, idx, dir, step, seen)
  assert(idx ~= nil, "missing idx")
  if seen[idx] or idx == player.position then
    return nil
  end
  seen[idx] = true
  local tile = board:get_tile(idx)
  assert(tile ~= nil, "missing tile: " .. tostring(idx))
  return {
    idx = idx,
    tile = tile,
    dir = dir,
    step = step,
  }
end

local function _make_ui_candidate(board, idx, dir, step)
  local tile = board:get_tile(idx)
  assert(tile ~= nil, "missing tile: " .. tostring(idx))
  return {
    idx = idx,
    tile = tile,
    dir = dir,
    step = step,
    label = tile.name,
  }
end

local function _tile_distance(board, start_idx, idx)
  local start_tile = assert(board:get_tile(start_idx), "missing start tile: " .. tostring(start_idx))
  local tile = assert(board:get_tile(idx), "missing tile: " .. tostring(idx))
  return math.abs(start_tile.row - tile.row) + math.abs(start_tile.col - tile.col)
end

local function _build_manual_candidate(board, start_idx, idx)
  return _make_ui_candidate(board, idx, "nearby", _tile_distance(board, start_idx, idx))
end

local function _forward_indices(board, player, distance)
  local list = {}
  local current = player.position
  local facing = facing_policy.resolve_initial_facing("relative_forward", player)
  for step = 1, distance do
    local next_idx, _, next_facing = board:step_forward_by_facing(current, facing, 1)
    current = next_idx
    facing = next_facing
    table.insert(list, { idx = current, step = step, dir = "forward" })
  end
  return list
end

local function _backward_indices(board, player, distance)
  local list = {}
  local current = player.position
  local facing = facing_policy.resolve_initial_facing("relative_backward", player)
  for step = 1, distance do
    local prev_idx, _, next_facing = board:step_backward_by_facing(current, facing)
    current = prev_idx
    facing = next_facing
    table.insert(list, { idx = current, step = step, dir = "backward" })
  end
  return list
end

local function _append_unique_ui_candidate(list, seen, board, idx, dir, step)
  if seen[idx] then
    return false
  end
  seen[idx] = true
  list[#list + 1] = _make_ui_candidate(board, idx, dir, step)
  return true
end

local _FORWARD_PRIORITY_BY_TYPE = { item = 1, chance = 3 }

local function _forward_priority(tile, st)
  if tile.type == "land" then
    if st and not st.owner_id then
      return 2
    end
    return nil
  end
  return _FORWARD_PRIORITY_BY_TYPE[tile.type]
end

local function _own_land_backward(tile, st, player)
  return tile.type == "land" and st ~= nil and st.owner_id == player.id
end

local function _backward_priority(tile, st, player)
  if _own_land_backward(tile, st, player) then
    return 4
  end
  if tile.type == "hospital" then
    return 5
  end
  if tile.type == "tax" then
    return 6
  end
  if tile.type == "mountain" then
    return 7
  end
  return nil
end

local function _blocked_by_obstacle(board, cand)
  return board:has_roadblock(cand.idx) or board:has_mine(cand.idx)
end

local function _tile_state_for(tile, game)
  if tile.type == "land" then
    return tile.get_state(game, tile)
  end
  return nil
end

local function _priority_for_candidate(game, player, cand)
  local tile = cand.tile
  local board = game.board
  if _blocked_by_obstacle(board, cand) then
    return nil
  end

  local st = _tile_state_for(tile, game)
  if cand.dir == "forward" then
    return _forward_priority(tile, st)
  elseif cand.dir == "backward" then
    return _backward_priority(tile, st, player)
  end
  return nil
end

local function _format_label(cand)
  local dir_label = "后方"
  if cand.dir == "forward" then
    dir_label = "前方"
  end
  return dir_label .. number_utils.format_integer_part(cand.step) .. "格：" .. cand.tile.name .. " (" .. cand.tile.type .. ")"
end

local function _append_auto_candidate(list, game, player, board, seen, entry)
  local cand = _make_candidate(board, player, entry.idx, entry.dir, entry.step, seen)
  if not cand then
    return
  end
  cand.priority = _priority_for_candidate(game, player, cand)
  if cand.priority then
    table.insert(list, cand)
  end
end

-- #105:电脑候选先与真人 UI 接纳口径取交集——manual_candidates 的
-- 7 槽截断会把岔口/内环附近的格子挡在窗外,直放路径不能再落到窗外格。
local function _ui_accepted_indices(game, player, distance)
  local accepted = {}
  for _, cand in ipairs(roadblock.manual_candidates(game, player, distance)) do
    accepted[cand.idx] = true
  end
  return accepted
end

function roadblock.auto_candidates(game, player, distance)
  local board = game.board
  local seen = {}
  local list = {}
  distance = distance or 3

  for _, entry in ipairs(_forward_indices(board, player, distance)) do
    _append_auto_candidate(list, game, player, board, seen, entry)
  end

  for _, entry in ipairs(_backward_indices(board, player, distance)) do
    _append_auto_candidate(list, game, player, board, seen, entry)
  end

  table.sort(list, function(a, b)
    if a.priority == b.priority then
      return a.step < b.step
    end
    return a.priority < b.priority
  end)

  local accepted = _ui_accepted_indices(game, player, distance)
  local filtered = {}
  for _, cand in ipairs(list) do
    if accepted[cand.idx] then
      cand.label = _format_label(cand)
      filtered[#filtered + 1] = cand
    end
  end

  return filtered
end

function roadblock.manual_candidates(game, player, distance)
  local board = game.board
  local list = {}
  local seen = {}
  _append_unique_ui_candidate(list, seen, board, player.position, "current", 0)
  for _, idx in ipairs(board_query.indices_in_range(board, player.position, distance or 3)) do
    if not seen[idx] then
      seen[idx] = true
      list[#list + 1] = _build_manual_candidate(board, player.position, idx)
    end
    if #list >= ui_candidate_slots then
      break
    end
  end

  return list
end

function roadblock.is_ui_candidate(game, player, idx, distance)
  local target_idx = number_utils.to_integer(idx)
  if target_idx == nil then
    return false
  end
  for _, cand in ipairs(roadblock.manual_candidates(game, player, distance)) do
    if cand.idx == target_idx then
      return true
    end
  end
  return false
end

function roadblock.pick_best(candidates)
  assert(candidates ~= nil and #candidates > 0, "missing roadblock candidates")
  return candidates[1]
end

function roadblock.apply(game, player, idx)
  assert(idx ~= nil, "missing idx")
  assert(game.board ~= nil, "missing board")
  game:place_roadblock(idx)
  local tile = game.board:get_tile(idx)
  event_feed.publish(game, {
    kind = event_kinds.roadblock_placed,
    text = player.name .. " 放置路障在 " .. tile.name,
  })
  local queued = action_anim_port.queue(game, {
    kind = "roadblock",
    player_id = player.id,
    tile_index = idx,
    duration = action_anim_duration,
  })
  return { ok = true, action_anim = queued }
end

return roadblock

