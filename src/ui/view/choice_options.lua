local M = {}

function M.resolve_option_id(option)
  return type(option) == "table" and option.id or option
end

local function _options_of(choice)
  return choice and choice.options or nil
end

local function _find_option(choice, predicate)
  local options = _options_of(choice)
  if type(options) ~= "table" then
    return nil
  end
  for _, option in ipairs(options) do
    local option_id = M.resolve_option_id(option)
    if predicate(option, option_id) then
      return option, option_id
    end
  end
  return nil
end

function M.resolve_option_label(option)
  if type(option) == "table" then
    return option.label or (option.id ~= nil and tostring(option.id)) or tostring(option)
  end
  return tostring(option)
end

function M.resolve_option_by_id(choice, option_id)
  if option_id == nil then
    return nil
  end
  local option = _find_option(choice, function(_, current_option_id)
    return current_option_id == option_id
  end)
  return type(option) == "table" and option or nil
end

function M.resolve_option_label_by_id(choice, option_id)
  local option, matched_option_id = _find_option(choice, function(_, current_option_id)
    return current_option_id == option_id
  end)
  if option == nil then
    return nil
  end
  return type(option) == "table" and option.label or tostring(matched_option_id)
end

return M

