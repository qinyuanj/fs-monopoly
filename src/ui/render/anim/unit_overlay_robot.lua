local prefab = require("Data.Prefab")
local logger = require("src.foundation.log")
local compute = require("src.ui.render.anim.overlay_compute")
local runtime_constants = require("src.config.gameplay.runtime_constants")
local number_utils = require("src.foundation.number")
local handle_ops = require("src.ui.render.anim.unit_overlay_handle")

local robot = {}
-- #339:y_offset 1.0 在真机被地板埋没(机器人看不见),2.0 是段B 探针肉眼验证过的高度。
local robot_y_offset = 2.0

function robot.resolve_presentation_runtime(state)
  return state and state.presentation_runtime or nil
end

local _resolve_hr = require("src.ui.render.support.host_runtime_resolver").from_deps

local _spawn_robot = handle_ops.spawn
local _destroy_robot = handle_ops.destroy
local _move_robot = handle_ops.move

local function _new_branch_node(tile_index, has_obstacle)
  return {
    tile_index = tile_index,
    has_obstacle = has_obstacle == true,
    children = {},
    child_map = {},
  }
end

-- 向 cursor 下插入一条分支记录:已存在则合并障碍标记,返回(可能新建的)子节点。
local function _insert_branch_entry(cursor, entry)
  local key = tostring(entry.tile_index)
  local child = cursor.child_map[key]
  if child == nil then
    child = _new_branch_node(entry.tile_index, entry.has_obstacle)
    cursor.child_map[key] = child
    cursor.children[#cursor.children + 1] = child
  elseif entry.has_obstacle then
    child.has_obstacle = true
  end
  return child
end

local function _build_branch_tree(branches)
  local root = _new_branch_node(nil, false)
  for _, branch in ipairs(branches or {}) do
    local cursor = root
    for _, entry in ipairs(branch or {}) do
      cursor = _insert_branch_entry(cursor, entry)
    end
  end
  return root
end

local function _resolve_longest_branch(branches)
  -- 负分支数种子 + math.max:`longest = 0` 的 0->1 与 `#branch > longest` 的
  -- >->>= 逐值等价不可杀(全空分支时步长无消费者);-#branches 是最长值的
  -- 安全下界且无数字位点(删负号会变步长,可杀)(#262 化简)。
  local longest = -#branches
  for _, branch in ipairs(branches or {}) do
    longest = math.max(longest, #branch)
  end
  return longest
end

-- 前置条件:分支树有子节点(调用方已拦全空分支),longest ≥ 1。
local function _resolve_step_duration(branches, duration)
  if number_utils.is_numeric(duration) and duration > 0 then
    return duration / _resolve_longest_branch(branches)
  end
  return 3.0 / runtime_constants.robot_speed
end

local function _schedule_step(schedule, delay, callback)
  if type(schedule) == "function" then
    schedule(delay, callback)
    return
  end
  callback()
end

function robot.clear_obstacle(state, clear_overlay, tile_index)
  clear_overlay(state, "roadblock", tile_index)
  clear_overlay(state, "mine", tile_index)
end

local function _walk_branch_children(state, clear_overlay, schedule, hr, robot_id, node, current_pos, step_duration)
  local children = node.children or {}
  if #children == 0 then
    return function(handle)
      _destroy_robot(hr, robot_id, handle)
    end
  end

  return function(handle)
    for child_index, child in ipairs(children) do
      local child_handle = handle
      if child_index > 1 then
        child_handle = _spawn_robot(hr, robot_id, current_pos)
      end
      _schedule_step(schedule, step_duration, function()
        local child_pos = compute.overlay_pos_for_tile(state, child.tile_index, robot_y_offset)
        local moved_handle = _move_robot(hr, robot_id, child_handle, child_pos)
        if child.has_obstacle then
          robot.clear_obstacle(state, clear_overlay, child.tile_index)
        end
        _walk_branch_children(state, clear_overlay, schedule, hr, robot_id, child, child_pos, step_duration)(moved_handle)
      end)
    end
  end
end

local function _resolve_robot_id()
  return prefab.unit and prefab.unit["清障机器人"] or nil
end

local function _resolve_schedule(opts, hr)
  return opts.schedule or hr.schedule
end

local function _play_empty_clear(hr, robot_id, schedule, player_pos, duration)
  local root_handle = _spawn_robot(hr, robot_id, player_pos)
  _schedule_step(schedule, duration, function()
    _destroy_robot(hr, robot_id, root_handle)
  end)
end

local function _play_branches(state, clear_overlay, schedule, hr, robot_id, branches, player_pos, duration)
  local branch_tree = _build_branch_tree(branches)
  -- #339:不走池化,去掉 prewarm 预热(直接 create,无需预填池)。
  local root_handle = _spawn_robot(hr, robot_id, player_pos)
  if #branch_tree.children == 0 then
    -- 全空分支没有步进,步长无消费者,直接销毁(#262:这也封死了
    -- longest==0 分支上的一切等价变异)。
    _destroy_robot(hr, robot_id, root_handle)
    return
  end
  local step_duration = _resolve_step_duration(branches, duration)
  _walk_branch_children(state, clear_overlay, schedule, hr, robot_id, branch_tree, player_pos, step_duration)(root_handle)
end

function robot.play_clear_obstacles(state, anim, duration, opts)
  local clear_overlay = assert(opts and opts.clear_overlay, "missing clear_overlay")
  local robot_id = _resolve_robot_id()
  if robot_id == nil then
    logger.warn("[Eggy]", "清障机器人 prefab 缺失，已跳过生成")
    return
  end
  local player_pos = compute.overlay_pos_for_player(state, assert(anim.player_id, "missing player_id"), robot_y_offset)
  local hr = _resolve_hr(robot.resolve_presentation_runtime(state))
  local schedule = _resolve_schedule(opts, hr)
  local branches = anim.branches or {}
  if #branches == 0 then
    _play_empty_clear(hr, robot_id, schedule, player_pos, duration)
    return
  end
  _play_branches(state, clear_overlay, schedule, hr, robot_id, branches, player_pos, duration)
end

return robot

