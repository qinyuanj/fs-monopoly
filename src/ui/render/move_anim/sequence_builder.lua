local runtime_constants = require("src.config.gameplay.runtime_constants")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local runtime_state = require("src.ui.state.runtime")

local sequence_builder = {}

local _ZERO_VEC = (math and math.Vector3) and math.Vector3(0.0, 0.0, 0.0) or { x = 0.0, y = 0.0, z = 0.0 }

local function _zero_vector()
  return _ZERO_VEC
end

local function _calc_step_vector(scene, from_index, to_index)
  local start_tile = scene.tiles[from_index]
  local end_tile = scene.tiles[to_index]
  local pos_s = start_tile.get_position()
  local pos_e = end_tile.get_position()
  local dist = pos_e - pos_s
  local len = dist:length()
  if len <= 0 then
    return _zero_vector(), 0
  end
  local dir = math.Vector3(dist.x / len, dist.y / len, dist.z / len)
  return dir, len
end

local function _calc_walk_step_time(len)
  if len <= 0 then
    return 0
  end
  local walk_speed = runtime_constants.walk_speed or 0
  if walk_speed <= 0 then
    return 0
  end
  return len / walk_speed
end

sequence_builder.calc_step_vector = _calc_step_vector

function sequence_builder.calc_step_time(scene, from_index, to_index, _anim_ctx)
  local _, len = _calc_step_vector(scene, from_index, to_index)
  return _calc_walk_step_time(len)
end

function sequence_builder.resolve_role(player_id)
  if player_id == nil then
    return nil
  end
  local ok, role = pcall(runtime_ports.resolve_role, player_id)
  if not ok then
    return nil
  end
  return role
end

-- 合成 AI 身份唯一真源是 runtime_ports.is_synthetic_player(#611 端口,注册表实现、
-- 退役不擦除);不再从 resolve_role 的适配器标志推断——退役后适配器解析不到,
-- 两条真源会给出相反结论。退役后本模块拿不到单位,各消费方按 nil 单位自然短路。
function sequence_builder.is_synthetic_actor(player_id)
  if player_id == nil then
    return false
  end
  return runtime_ports.is_synthetic_player(player_id) == true
end

local function _direction_from_steps(steps)
  if steps and steps < 0 then
    return runtime_constants.v3_right
  end
  if steps and steps > 0 then
    return runtime_constants.v3_left
  end
  return nil
end

function sequence_builder.resolve_direction(anim_ctx)
  if anim_ctx.direction then
    return anim_ctx.direction
  end
  return _direction_from_steps(anim_ctx.steps)
end

function sequence_builder.build_steps(board_scene, from_index, to_index, visited, anim_ctx, step_duration_fn)
  local steps = {}
  local total_time = 0
  local function _push_step(step_from, step_to)
    if step_from == step_to then
      return
    end
    local step_time = step_duration_fn(board_scene, step_from, step_to, anim_ctx)
    if step_time <= 0 then
      return
    end
    local delay = total_time
    total_time = total_time + step_time
    steps[#steps + 1] = { from = step_from, to = step_to, delay = delay }
  end

  if not visited or #visited <= 1 then
    if from_index ~= to_index then
      _push_step(from_index, to_index)
    end
  else
    local step_from = from_index
    for i = 1, #visited do
      local step_to = visited[i]
      _push_step(step_from, step_to)
      step_from = step_to
    end
  end

  return steps, total_time
end

function sequence_builder.format_visited(visited)
  if type(visited) ~= "table" or #visited == 0 then
    return "nil"
  end
  local out = {}
  for i, value in ipairs(visited) do
    out[i] = tostring(value)
  end
  return table.concat(out, ",")
end

local _follow_opts = {}

local function _follow_ctx(anim_ctx)
  return anim_ctx and anim_ctx.state or nil
end

local function _has_follow_args(state, player_id, position)
  return state ~= nil and player_id ~= nil and position ~= nil
end

local function _follow_seq(anim_ctx)
  return anim_ctx and anim_ctx.seq or nil
end

function sequence_builder.publish_follow_target(anim_ctx, player_id, position, source)
  local state = _follow_ctx(anim_ctx)
  if not _has_follow_args(state, player_id, position) then
    return false
  end
  _follow_opts.source = source
  _follow_opts.seq = _follow_seq(anim_ctx)
  return runtime_state.set_follow_target_position(state, player_id, position, _follow_opts)
end

return sequence_builder

