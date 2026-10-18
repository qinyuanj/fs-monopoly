local state_ports = {}

function state_ports.build()
  return {
    apply_role_control_lock = function(state, enabled)
      local ui_view = require("src.ui.coord.ui_runtime")
      ui_view.apply_role_control_lock(state, enabled)
    end,
    install_event_handlers = function(game, log, state)
      local event_handlers = require("src.ui.coord.event_handlers")
      event_handlers.install(game, log, state)
    end,
    on_bankruptcy_tiles_cleared = function(game, _, owned_tile_ids)
      local state = game and game.landing_visual_hold_state or nil
      if state and type(state.on_board_visual_sync) == "function" then
        return state:on_board_visual_sync({
          tile_ids = owned_tile_ids,
        }) == true
      end
      return false
    end,
  }
end

return state_ports

