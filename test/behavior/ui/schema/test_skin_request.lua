require("test.bootstrap").install_package_paths()
local luassert = assert
local property = require("test.support.property")
local request_shape = require("src.ui.schema.skin_request")

-- request_shape 是皮肤交易请求/UI action 字段别名的单一所有者(type|action,
-- slot_index|index|slot)。这里把别名优先级与非表输入的兜底钉成属性,任何一边的
-- 消费者(skin_panel 门面)都以此为准。

local KINDS = { "open", "close", "buy", "gift", "equip", "activate_slot", "unequip", "page_next", "prev" }

local SLOT_ALIASES = { "slot_index", "index", "slot" }

local function _build_case(rng)
  local request = {}
  local kind_value, action_value
  if rng:bool() then
    kind_value = rng:pick(KINDS)
    request.type = kind_value
  end
  if rng:bool() then
    action_value = rng:pick(KINDS)
    request.action = action_value
  end
  local slots = {}
  for _, alias in ipairs(SLOT_ALIASES) do
    if rng:bool() then
      slots[alias] = rng:int(1, 99)
      request[alias] = slots[alias]
    end
  end
  if rng:bool() then
    request.source = "src" .. rng:int(1, 9)
  end
  return { request = request, kind_value = kind_value, action_value = action_value, slots = slots }
end

describe("TestRequestShape", function()

local function _test_kind_honours_type_over_action_precedence_for_any_table_request()
  property.for_all(_build_case, function(case)
    local expected = case.kind_value or case.action_value
    luassert.truthy(request_shape.kind(case.request) == expected,
      "kind must be type, then action, then nil")
  end)
end

local function _test_slot_index_honours_slot_index_index_slot_precedence_and_defaults_to_1()
  property.for_all(_build_case, function(case)
    local expected = case.slots.slot_index or case.slots.index or case.slots.slot or 1
    luassert.truthy(request_shape.slot_index(case.request) == expected,
      "slot_index must follow the alias chain and default to 1")
  end)
end

local function _test_unlock_source_reads_source_from_tables_and_falls_back_otherwise()
  property.for_all(_build_case, function(case, rng)
    local fallback = "fb" .. rng:int(1, 9)
    luassert.truthy(request_shape.unlock_source(case.request, fallback) == case.request.source,
      "table requests must expose their own source (or nil), never the fallback")
    luassert.truthy(request_shape.unlock_source(rng:pick(KINDS), fallback) == fallback,
      "non-table requests must yield the fallback")
  end)
end

local function _test_non_table_requests_pass_through_kind_unchanged_and_pin_slot_to_1()
  property.for_all(function(rng)
    local candidates = { rng:pick(KINDS), rng:int(-99, 99), rng:bool(), nil }
    return { value = candidates[rng:int(1, 3)] }
  end, function(case)
    luassert.truthy(request_shape.kind(case.value) == case.value,
      "non-table kind must be identity")
    luassert.truthy(request_shape.slot_index(case.value) == 1,
      "non-table slot_index must default to 1")
  end)
end

local function _test_normalization_is_idempotent_rebuilding_a_request_from_normalized_fields_is_stable()
  property.for_all(_build_case, function(case)
    local normalized = {
      type = request_shape.kind(case.request),
      slot_index = request_shape.slot_index(case.request),
      source = request_shape.unlock_source(case.request, nil),
    }
    luassert.truthy(request_shape.kind(normalized) == request_shape.kind(case.request),
      "kind must survive a normalize round trip")
    luassert.truthy(request_shape.slot_index(normalized) == request_shape.slot_index(case.request),
      "slot_index must survive a normalize round trip")
    luassert.truthy(request_shape.unlock_source(normalized, nil) == request_shape.unlock_source(case.request, nil),
      "source must survive a normalize round trip")
  end)
end


it("test_kind_honours_type_over_action_precedence_for_any_table_request", _test_kind_honours_type_over_action_precedence_for_any_table_request)
it("test_slot_index_honours_slot_index_index_slot_precedence_and_defaults_to_1", _test_slot_index_honours_slot_index_index_slot_precedence_and_defaults_to_1)
it("test_unlock_source_reads_source_from_tables_and_falls_back_otherwise", _test_unlock_source_reads_source_from_tables_and_falls_back_otherwise)
it("test_non_table_requests_pass_through_kind_unchanged_and_pin_slot_to_1", _test_non_table_requests_pass_through_kind_unchanged_and_pin_slot_to_1)
it("test_normalization_is_idempotent_rebuilding_a_request_from_normalized_fields_is_stable", _test_normalization_is_idempotent_rebuilding_a_request_from_normalized_fields_is_stable)
end)
