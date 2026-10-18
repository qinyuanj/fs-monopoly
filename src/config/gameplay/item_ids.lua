local items_cfg = require("src.config.content.items")

local item_ids = {}

local function _register_item(map, cfg)
  if not (cfg and cfg.key and cfg.key ~= "") then return end
  assert(map[cfg.key] == nil, "duplicate item key in items config: " .. tostring(cfg.key))
  map[cfg.key] = cfg.id
end

for _, cfg in ipairs(items_cfg) do
  _register_item(item_ids, cfg)
end

return item_ids

