local effect_executor = {}

function effect_executor.validate(effect_id, executor)
  assert(effect_id ~= nil and effect_id ~= "", "missing effect_id")
  assert(type(executor) == "table", "invalid executor: " .. tostring(effect_id))
  assert(type(executor.apply) == "function", "missing executor apply: " .. tostring(effect_id))
end

return effect_executor

