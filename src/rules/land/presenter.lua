local intent_output_port = require("src.rules.ports.intent_output")
local action_anim_port = require("src.foundation.ports.action_anim")

local presenter = {}

function presenter.push_popup(game, title, body, opts)
  if not game then
    return false
  end
  opts = opts or {}
  return intent_output_port.push_popup(game, {
    title = title,
    body = body,
    kind = opts.kind,
    image_ref = opts.image_ref,
    auto_close_seconds = opts.auto_close_seconds,
    broadcast = opts.broadcast,
  }, opts.popup_opts) == true
end

presenter.queue_action_anim = action_anim_port.queue

return presenter

