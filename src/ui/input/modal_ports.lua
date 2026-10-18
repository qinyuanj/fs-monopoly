local M = {}

function M.resolve(state)
  local ports = state and state.gameplay_loop_ports or nil
  return ports and ports.modal or {}
end

function M.close_choice_modal(state)
  local modal = M.resolve(state)
  if type(modal.close_choice_modal) == "function" then
    modal.close_choice_modal(state)
  end
end

return M

