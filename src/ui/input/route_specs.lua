local M = {}

function M.builder(intent_type)
  return function(specs, name, action)
    if not name then
      return
    end
    specs[#specs + 1] = {
      name = name,
      build_intent = function()
        return {
          type = intent_type,
          action = action,
        }
      end,
    }
  end
end

return M

