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

--[[ mutate4lua-manifest
version=4
projectHash=59ef568450be1ab7
scope.0.id=chunk:src/config/gameplay/item_ids.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=18
scope.0.semanticHash=d4686a286c2dc6c1
scope.1.id=function:_register_item
scope.1.kind=function
scope.1.startLine=5
scope.1.endLine=9
scope.1.semanticHash=dffcaaee55383b5d
]]
