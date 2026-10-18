local contract_helper = {}

function contract_helper.resolve_required_port(game, field_name, port_name)
  assert(game ~= nil, "missing game for " .. tostring(port_name))
  local port = game[field_name]
  assert(type(port) == "table", "missing game." .. tostring(field_name))
  return port
end

function contract_helper.resolve_required_method(game, field_name, port_name, method_name)
  local port = contract_helper.resolve_required_port(game, field_name, port_name)
  local fn = port[method_name]
  assert(type(fn) == "function", "missing " .. tostring(port_name) .. "." .. tostring(method_name))
  return fn
end

function contract_helper.resolve_method(game, field_name, method_name)
  return contract_helper.resolve_required_method(game, field_name, field_name, method_name)
end

function contract_helper.resolve_optional_port(game, field_name, fallback_port)
  if game ~= nil then
    local port = game[field_name]
    if type(port) == "table" then
      return port
    end
  end
  if type(fallback_port) == "table" then
    return fallback_port
  end
  return nil
end

function contract_helper.resolve_optional_method(game, field_name, method_name, opts)
  local options = opts or {}
  local port = contract_helper.resolve_optional_port(game, field_name, options.fallback_port)
  if type(port) ~= "table" then
    return nil
  end
  local fn = port[method_name]
  if type(fn) ~= "function" then
    return nil
  end
  return fn, port
end

function contract_helper.call_required_method(game, field_name, port_name, method_name, ...)
  local fn = contract_helper.resolve_required_method(game, field_name, port_name, method_name)
  return fn(...)
end

function contract_helper.call_optional_method(game, field_name, method_name, opts, ...)
  local fn = contract_helper.resolve_optional_method(game, field_name, method_name, opts)
  if type(fn) ~= "function" then
    local options = opts or {}
    return options.default_result
  end
  return fn(...)
end

return contract_helper

