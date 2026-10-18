local items_cfg = require("src.config.content.items")

local item_config = {}

local function _build_cfg_by_id()
  local cfg_by_id = {}
  for _, cfg in ipairs(items_cfg) do
    cfg_by_id[cfg.id] = cfg
  end
  return cfg_by_id
end

item_config.cfg_by_id = _build_cfg_by_id()

return item_config

