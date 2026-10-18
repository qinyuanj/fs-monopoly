local choice_meta_validator = {}

local function _validate_required_meta(choice_spec, required_meta)
  if type(required_meta) ~= "table" or #required_meta == 0 then
    return choice_spec.meta
  end

  local meta = choice_spec.meta
  assert(type(meta) == "table", tostring(choice_spec.kind) .. " requires meta")
  for _, key in ipairs(required_meta) do
    assert(meta[key] ~= nil, tostring(choice_spec.kind) .. " requires meta." .. tostring(key))
  end
  return meta
end

local function _resolve_descriptor(game, choice_spec)
  local registries = game and game.registries
  local choice_registry = registries and registries.choices
  if type(choice_registry) ~= "table" or type(choice_registry.descriptor_for) ~= "function" then
    return nil
  end
  return choice_registry:descriptor_for(choice_spec.kind)
end

local function _apply_normalize_meta(game, descriptor, choice_spec)
  if descriptor and descriptor.normalize_meta ~= nil then
    local normalized_meta = descriptor.normalize_meta(game, choice_spec.meta, choice_spec)
    if normalized_meta ~= nil then
      choice_spec.meta = normalized_meta
    end
  end
end

local function _run_meta_validation(game, descriptor, choice_spec)
  local required_meta = descriptor and descriptor.required_meta
  local meta = _validate_required_meta(choice_spec, required_meta)
  if descriptor and descriptor.meta_validator ~= nil then
    descriptor.meta_validator(game, meta, choice_spec)
  end
end

function choice_meta_validator.validate(game, choice_spec)
  local descriptor = _resolve_descriptor(game, choice_spec)
  _apply_normalize_meta(game, descriptor, choice_spec)
  _run_meta_validation(game, descriptor, choice_spec)
  return descriptor
end

return choice_meta_validator

