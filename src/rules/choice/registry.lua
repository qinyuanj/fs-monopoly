local Class = require("src.foundation.class")

local choice_registry = Class("ChoiceRegistry")

local _optional_field_types = {
  required_meta = "table",
  normalize_meta = "function",
  meta_validator = "function",
  normalize_action = "function",
}

local function _validate_descriptor_fields(kind, descriptor)
  assert(type(descriptor.execute) == "function", "choice descriptor missing execute: " .. tostring(kind))
  for field, expected in pairs(_optional_field_types) do
    if descriptor[field] ~= nil then assert(type(descriptor[field]) == expected, "choice descriptor " .. field .. " must be " .. expected .. ": " .. tostring(kind)) end
  end
end

local function _normalize_descriptor(kind, handler)
  if type(handler) == "function" then return kind, { execute = handler } end
  assert(type(handler) == "table", "choice handler must be function or table")
  local descriptor = {}
  for key, value in pairs(handler) do descriptor[key] = value end
  _validate_descriptor_fields(kind, descriptor)
  return kind, descriptor
end

function choice_registry:init()
  self.handlers = {}
end

function choice_registry:register(kind, handler)
  local normalized_kind, descriptor = _normalize_descriptor(kind, handler)
  self.handlers[normalized_kind] = descriptor
end

function choice_registry:descriptor_for(kind)
  return self.handlers[kind]
end

function choice_registry:register_defaults(groups)
  for _, group in ipairs(groups or {}) do
    for key, handler in pairs(group) do
      self:register(key, handler)
    end
  end
end

return choice_registry

