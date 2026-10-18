local M = {}

function M.build(kind)
  local wait_field = "wait_" .. kind .. "_anim"
  local queue_method = "queue_" .. kind .. "_anim"
  local port = {}

  function port.is_enabled(game)
    if not game then
      return false
    end
    local anim_gate_port = assert(game.anim_gate_port, "missing anim_gate_port")
    return anim_gate_port[wait_field] == true
  end

  function port.queue(game, payload)
    if not port.is_enabled(game) then
      return false
    end
    if not game[queue_method] then
      return false
    end
    game[queue_method](game, payload)
    return true
  end

  return port
end

return M

