local modal = require("src.ui.coord.modal")
local popup_presenter = require("src.ui.coord.popup_presenter")
local secondary_confirm_screen = require("src.ui.screens.secondary_confirm")

local modal_ports = {}

function modal_ports.build()
  return {
    close_choice_modal = function(state)
      modal.close_choice_modal(state)
    end,
    open_choice_modal = function(state, choice, market)
      modal.open_choice_modal(state, choice, market)
    end,
    open_pre_confirm_screen = function(state, choice, option_id, title, body)
      secondary_confirm_screen.open_pre_confirm(state, choice, option_id, title, body)
    end,
    close_popup = function(state)
      popup_presenter.close_popup(state)
    end,
  }
end

return modal_ports

