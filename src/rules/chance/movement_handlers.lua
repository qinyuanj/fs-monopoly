local movement_handlers = {}

local teleport_tile_types = {
  hospital = true,
  mountain = true,
  tax = true,
  market = true,
}

function movement_handlers.register(handlers, common)
  local function _backward_move_opts(context)
    local move_opts = {
      facing_mode = "relative_backward",
      skip_market_check = true,
    }
    if context and context.arrival_direction ~= nil then
      move_opts.direction = context.arrival_direction
    end
    return move_opts
  end

  handlers.move_backward = function(game, player, card, context)
    local res = common.move_steps(game, player, -(card.steps or 0), _backward_move_opts(context))
    if res and res.move_result then
      res.move_result.allow_optional = true
    end
    return res
  end

  handlers.move_forward = function(game, player, card)
    return common.move_steps(game, player, card.steps or 0)
  end

  handlers.forced_move = function(game, player, card, context)
    local from_index = player.position
    local idx, t = game:player_relocate(player, {
      destination_tile_id = assert(card.destination_tile_id, "forced_move requires destination_tile_id"),
      move_dir_mode = "forced_move",
    })
    if teleport_tile_types[t.type] == true then
      common.queue_forced_relocation(game, player, from_index, idx)
    else
      common.queue_move_effect(game, player, from_index, idx, nil)
    end
    return {
      kind = "need_landing",
      player_id = player.id,
      board_index = idx,
      move_result = context,
    }
  end
end

return movement_handlers

