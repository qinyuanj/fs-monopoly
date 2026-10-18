local facing_policy = require("src.rules.board.facing_policy")

local context = {}

local function _resolve_facing_mode(steps, opts)
  if opts.facing_mode then
    return opts.facing_mode
  end
  if steps < 0 then
    return "relative_backward"
  end
  if opts.direction ~= nil then
    return "resume_forward"
  end
  return "fresh_forward"
end

local function _resolve_step_fn(board, backward)
  if backward then
    return board.step_backward_by_facing
  end
  return board.step_forward_by_facing
end

local function _new_move_state(game, player, steps, opts, abs_steps)
  local backward = steps < 0
  return {
    game = game,
    player = player,
    steps = steps,
    abs_steps = abs_steps,
    opts = opts,
    board = game.board,
    branch_parity = opts.branch_parity or abs_steps,
    encountered = {},
    visited = {},
    pass_start = 0,
    pass_start_at_steps = {},
    stopped_on_roadblock = false,
    market_interrupt = nil,
    current = player.position,
    backward = backward,
    entered_inner = opts.entered_inner == true,
    skip_entry_on_tile_id = nil,
    consume_skip_inner_entry = false,
    exited_inner = false,
    -- move_dir stores the next forward heading from the player's landing tile.
    persisted_facing = player.status and player.status.move_dir or nil,
  }
end

local function _resolve_start_on_outer(ctx)
  if not (ctx.start_tile and ctx.board.map and ctx.board.map.outer_next) then
    return false
  end
  local start_on_outer = ctx.board.map.outer_next[ctx.start_tile.id] ~= nil
  if not start_on_outer then
    ctx.entered_inner = true
  end
  return start_on_outer
end

local function _start_tile_id(ctx)
  return ctx.start_tile and ctx.start_tile.id or nil
end

local function _apply_fresh_forward_entry_policy(ctx, start_on_outer)
  if facing_policy.should_skip_inner_entry(ctx.board, ctx.player) then
    ctx.skip_entry_on_tile_id = _start_tile_id(ctx)
    ctx.consume_skip_inner_entry = true
  end
  if ctx.entered_inner and not start_on_outer then
    ctx.facing = ctx.persisted_facing
  end
end

function context.build(game, player, steps, opts)
  opts = opts or {}
  local abs_steps = math.abs(steps)
  local ctx = _new_move_state(game, player, steps, opts, abs_steps)
  ctx.start_tile = ctx.board:get_tile(player.position)
  local start_on_outer = _resolve_start_on_outer(ctx)
  ctx.step_fn = _resolve_step_fn(ctx.board, ctx.backward)
  local facing_mode = _resolve_facing_mode(steps, opts)
  ctx.facing = facing_policy.resolve_initial_facing(facing_mode, player, opts)
  if facing_mode == "fresh_forward" then
    _apply_fresh_forward_entry_policy(ctx, start_on_outer)
  end
  return ctx
end

return context

