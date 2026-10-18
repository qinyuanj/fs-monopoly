local tip_queue = require("src.foundation.tips")

local panel_tip = {}

function panel_tip.enqueue(source, text, key)
  tip_queue.enqueue({
    text = text,
    duration = 2.0,
    dedupe_key = key,
    blocks_inter_turn = false,
    source = source,
  })
end

return panel_tip

