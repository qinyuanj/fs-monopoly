local base = require("src.rules.land.effect_base")
local chance = require("src.rules.land.effect_chance")
local transit = require("src.rules.land.effect_transit")
local special = require("src.rules.land.effect_special")

local module = {}

local function _merge_executor_groups(groups)
  local merged = {}
  for _, group in ipairs(groups) do
    for key, value in pairs(group) do
      merged[key] = value
    end
  end
  return merged
end

local executors = _merge_executor_groups({
  base.executors,
  chance.executors,
  transit.executors,
  special.executors,
})

module.executors = executors

-- Export helper for testability
module._merge_executor_groups = _merge_executor_groups

return module

