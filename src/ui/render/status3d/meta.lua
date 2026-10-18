local logger = require("src.foundation.log")
local specs = require("src.ui.render.status3d.specs")

local M = {}

function M.ensure_cache(state)
  assert(state ~= nil, "missing state")
  if state.ui_status_3d == nil then
    state.ui_status_3d = {
      layers = {},
      text_nodes = {},
      last_status_key_by_player = {},
      warned_once = {},
      disabled = false,
      meta = nil,
    }
  end
  return state.ui_status_3d
end

function M.warn_once(cache, key, ...)
  if cache.warned_once[key] then
    return
  end
  cache.warned_once[key] = true
  logger.warn(...)
end

function M.build_meta(cache)
  if cache.meta ~= nil then
    return cache.meta
  end
  local layouts = {}
  for status_key in pairs(specs.status_specs) do
    local layout_id = specs.get_layout_id(status_key)
    if not layout_id then
      return nil, "missing scene_eui layout for status: " .. tostring(status_key)
    end
    layouts[status_key] = layout_id
  end
  cache.meta = { layouts = layouts }
  return cache.meta
end

return M

