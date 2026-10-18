local items = require("src.config.content.items")

local item_atlas = {}

for index, item in ipairs(items) do
  item_atlas[index] = {
    id = item.id,
    key = item.key,
    name = item.name,
    description = item.description,
    usage = item.usage,
    tier = item.tier,
  }
end

return item_atlas

