local runtime_assets = require("src.config.runtime_assets")
local runtime_refs = require("src.config.content.runtime_refs")

local catalog = {}

function catalog.get(cue_name, payload)
  local cue = runtime_assets.board_feedback_cue(cue_name, payload, {
    refs = runtime_refs,
  })
  if cue.ok ~= true then
    return nil
  end
  return cue
end

return catalog

