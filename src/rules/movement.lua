local movement_context = require("src.rules.movement_context")
local movement_events = require("src.rules.movement_events")
local mine_effect = require("src.rules.effects.mine")

local movement = {}

-- interrupt handler

local function _check_roadblock(ctx)
  if not ctx.board:has_roadblock(ctx.current) then
    return false
  end
  if ctx.opts.dry == true then
    return true
  end
  local tile = ctx.board:get_tile(ctx.current)
  -- #550:先入队 roadblock_trigger、再清 board 状态,堵死 state sync 窗口——
  -- sync_many 同拍到达时 pending 守卫(visual_sync_overlay)仍能查到 trigger,
  -- overlay 活到 trigger handler 接管,不再提前销毁。
  movement_events.emit_roadblock_hit(ctx.game, ctx.player, ctx.current, tile)
  ctx.game:clear_roadblock(ctx.current)
  return true
end

local function _check_market(ctx, step)
  if ctx.opts.skip_market_check then
    return nil
  end
  local tile = ctx.board:get_tile(ctx.current)
  assert(tile ~= nil, "missing tile: " .. tostring(ctx.current))
  if tile.type ~= "market" or step >= ctx.steps then
    return nil
  end
  local remaining = ctx.abs_steps - step
  if ctx.opts.dry ~= true then
    movement_events.emit_market_interrupt(ctx, remaining)
  end
  return {
    position = nil,
    remaining_steps = remaining,
    facing = ctx.facing,
    branch_parity = ctx.branch_parity,
    entered_inner = ctx.entered_inner == true,
  }
end

-- 出发格与到达格共用的障碍判定:路障先于地雷。
local function _check_obstacles(ctx)
  if _check_roadblock(ctx) then
    ctx.stopped_on_roadblock = true
    return true
  end
  if mine_effect.can_trigger(ctx.game, ctx.player, ctx.current) then
    return true
  end
  return false
end

local function _resolve_step_interrupt(ctx, step)
  if _check_obstacles(ctx) then
    return true
  end
  ctx.market_interrupt = _check_market(ctx, step)
  if ctx.market_interrupt then
    ctx.market_interrupt.position = ctx.current
    return true
  end
  return false
end

-- step executor

local function _outer_next(ctx)
  local map = ctx.board.map
  if not (map and map.outer_next) then
    return nil
  end
  return map.outer_next
end

local function _is_inner_exit_transition(ctx, previous_tile, current_tile)
  if not (previous_tile and current_tile) then
    return false
  end
  local outer_next = _outer_next(ctx)
  if outer_next == nil then
    return false
  end
  return outer_next[previous_tile.id] == nil and outer_next[current_tile.id] ~= nil
end

local function _sync_inner_transition(ctx, entered_inner, previous_tile, current_tile)
  if entered_inner then
    ctx.entered_inner = true
    return
  end
  if _is_inner_exit_transition(ctx, previous_tile, current_tile) then
    ctx.exited_inner = true
  end
end

local function _record_passed_step(ctx, step, passed)
  if passed > 0 then
    ctx.pass_start_at_steps[#ctx.pass_start_at_steps + 1] = step
  end
end

local function _sync_arrival_direction(ctx, previous_tile, current_tile, previous_index)
  if previous_tile and current_tile and ctx.board and ctx.board.map then
    ctx.arrival_direction = ctx.board.map.direction(previous_tile.id, current_tile.id)
    ctx.arrival_from_index = previous_index
  end
end

local function _step_move(ctx, step)
  local next_index, passed, next_facing, entered_inner
  local previous_index = ctx.current
  if ctx.backward then
    next_index, passed, next_facing = ctx.step_fn(ctx.board, ctx.current, ctx.facing)
  else
    next_index, passed, next_facing, entered_inner = ctx.step_fn(ctx.board, ctx.current, ctx.facing, {
      parity = ctx.branch_parity,
      entered_inner = ctx.entered_inner,
      skip_entry_on_tile_id = ctx.skip_entry_on_tile_id,
    })
  end
  ctx.pass_start = ctx.pass_start + passed
  _record_passed_step(ctx, step, passed)
  ctx.facing = next_facing
  local previous_tile = ctx.board:get_tile(ctx.current)
  ctx.current = next_index
  local current_tile = ctx.board:get_tile(ctx.current)
  _sync_arrival_direction(ctx, previous_tile, current_tile, previous_index)
  _sync_inner_transition(ctx, entered_inner, previous_tile, current_tile)
  ctx.visited[#ctx.visited + 1] = ctx.current
  return step
end

-- pass_through=true: intermediate step, player is passing through.
-- pass_through=false: final step (landing tile), encounters are not "passing".
local function _collect_encountered(ctx, pass_through)
  for _, pid in ipairs(ctx.game.occupants[ctx.current] or {}) do
    if pid ~= ctx.player.id then
      if pass_through then
        ctx.encountered[#ctx.encountered + 1] = pid
      end
    end
  end
end

local function _run_move_steps(ctx)
  for step = 1, ctx.abs_steps do
    _step_move(ctx, step)
    local pass_through = step < ctx.abs_steps
    _collect_encountered(ctx, pass_through)
    if _resolve_step_interrupt(ctx, step) then
      break
    end
  end
end

local function _resolve_persisted_facing(ctx)
  if not ctx.backward then
    ctx.persisted_facing = ctx.facing
  end
end

local function _build_move_result(ctx, landing_tile)
  return {
    encountered_players = ctx.encountered,
    passed_start = ctx.pass_start,
    arrival_direction = ctx.arrival_direction,
    arrival_from_index = ctx.arrival_from_index,
    stopped_on_roadblock = ctx.stopped_on_roadblock,
    visited = ctx.visited,
    landing_tile = landing_tile,
    steps = ctx.steps,
    branch_parity = ctx.branch_parity,
    market_interrupt = ctx.market_interrupt,
  }
end

-- public API

function movement.move(game, player, steps, opts)
  local ctx = movement_context.build(game, player, steps, opts)
  -- 出发格按到达格对待:布雷后才同格的玩家出发也必须触发,否则直接走过。
  -- 黑市不参与出发判定:恢复流与已购物的落点不能重复开市。
  if not _check_obstacles(ctx) then
    _run_move_steps(ctx)
  end
  _resolve_persisted_facing(ctx)
  local landing_tile = ctx.board:get_tile(ctx.current)
  movement_events.emit_move_completed(ctx, landing_tile)
  ctx.game:update_player_position(ctx.player, ctx.current)
  ctx.game:set_player_status(ctx.player, "move_dir", ctx.persisted_facing)
  local should_skip_next_inner_entry = ctx.exited_inner == true
    and landing_tile ~= nil
    and ctx.board.map.entry_points[landing_tile.id] ~= nil
  ctx.game:set_player_status(ctx.player, "skip_next_inner_entry", should_skip_next_inner_entry)
  return _build_move_result(ctx, landing_tile)
end

-- #102:纯预测走与 move 完全相同的步进/障碍/黑市判定（dry 模式只跳过事件与落账），
-- 黑市中断按 move 阶段 continue_from_market 的同一映射恢复剩余步数。
local function _predict_walk(game, player, steps, opts)
  -- 不改调用方传入的 opts:复制一份再钉 dry。
  local dry_opts = { dry = true }
  for key, value in pairs(opts or {}) do
    dry_opts[key] = value
  end
  local ctx = movement_context.build(game, player, steps, dry_opts)
  if not _check_obstacles(ctx) then
    _run_move_steps(ctx)
  end
  return ctx
end

local function _predict_market_resume(game, player, interrupt)
  -- 真实恢复流用同一玩家（位置已被 move 更新到黑市格）；预测不改状态,
  -- 用同 id/状态的影子玩家从黑市格继续。影子拷全表再覆盖落点,
  -- movement_context.build 今后新增字段读取不会在预测与真实路径间静默分叉。
  local shadow = {}
  for key, value in pairs(player) do
    shadow[key] = value
  end
  shadow.position = interrupt.position
  return _predict_walk(game, shadow, interrupt.remaining_steps, {
    direction = interrupt.facing,
    branch_parity = interrupt.branch_parity,
    entered_inner = interrupt.entered_inner,
  })
end

function movement.predict_landing(game, player, steps)
  local ctx = _predict_walk(game, player, steps, {})
  while ctx.market_interrupt and ctx.market_interrupt.remaining_steps > 0 do
    ctx = _predict_market_resume(game, player, ctx.market_interrupt)
  end
  return ctx.current
end

return movement

