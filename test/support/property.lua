require("test.bootstrap").install_package_paths()
local luassert = require("packages.test_runner.cache_loader").verified_module("luassert")
  or assert(require("test.support.luassert_loader").load())
local property = {}

-- Exhaustive enumeration over a small integer range. Kept for specs that want
-- to assert a property holds for every value in a bounded domain.
function property.check_int_range(first_value, last_value, check)
  for value = first_value, last_value do
    local ok, err = pcall(check, value)
    luassert.truthy(ok, "case " .. tostring(value) .. " failed: " .. tostring(err))
  end
end

-- Deterministic linear congruential generator so generative property runs are
-- reproducible: the same seed always yields the same case sequence, and a
-- failing run reports the seed so it can be replayed. Constants are the glibc
-- LCG (modulus 2^31); the float ratio favours the high-order bits, which spread
-- test inputs well enough without any external dependency.
local LCG_MULTIPLIER = 1103515245
local LCG_INCREMENT = 12345
local LCG_MODULUS = 2147483648 -- 2^31

local Rng = {}
Rng.__index = Rng

function Rng.new(seed)
  return setmetatable({ state = math.floor(seed or 0) % LCG_MODULUS }, Rng)
end

-- Float in [0, 1).
function Rng:unit()
  self.state = (LCG_MULTIPLIER * self.state + LCG_INCREMENT) % LCG_MODULUS
  return self.state / LCG_MODULUS
end

-- Integer in [low, high] inclusive (order-tolerant).
function Rng:int(low, high)
  if high < low then
    low, high = high, low
  end
  return low + math.floor(self:unit() * (high - low + 1))
end

function Rng:bool()
  return self:unit() < 0.5
end

-- Uniformly pick one element of a non-empty array.
-- 断言只在空表时才调:fuzz 每分片 pick 数千次,成功路径不付 luassert 的消息格式化。
function Rng:pick(items)
  if #items == 0 then luassert.truthy(false, "cannot pick from an empty list") end
  return items[self:int(1, #items)]
end

property.Rng = Rng

-- Shallow rendering of a generated case for failure messages. Goes one table
-- level deep with sorted keys so the report is stable and readable.
local function _describe(value, depth)
  depth = depth or 0
  local value_type = type(value)
  if value_type == "string" then
    return string.format("%q", value)
  end
  if value_type ~= "table" then
    return tostring(value)
  end
  if depth >= 2 then
    return "{...}"
  end
  local parts = {}
  local length = #value
  for index = 1, length do
    parts[#parts + 1] = _describe(value[index], depth + 1)
  end
  local keys = {}
  for key in pairs(value) do
    local is_array_index = type(key) == "number" and key >= 1 and key <= length and math.floor(key) == key
    if not is_array_index then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys, function(left, right)
    return tostring(left) < tostring(right)
  end)
  for _, key in ipairs(keys) do
    parts[#parts + 1] = tostring(key) .. "=" .. _describe(value[key], depth + 1)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

property.describe = _describe

local DEFAULT_CASES = 200
local DEFAULT_SEED = 1804289383 -- fixed so runs are reproducible across machines

-- Run `check(value, rng)` against `count` generated cases. `generate(rng)` builds
-- each case from the seeded rng. A failing case re-raises with the seed, case
-- index, and a shallow rendering of the input so the failure can be reproduced
-- deterministically by re-running with the reported seed.
function property.for_all(generate, check, options)
  options = options or {}
  local count = options.cases or DEFAULT_CASES
  local seed = options.seed or DEFAULT_SEED
  local rng = Rng.new(seed)
  for index = 1, count do
    local value = generate(rng)
    local ok, err = pcall(check, value, rng)
    if not ok then
      error(string.format(
        "property failed (seed=%d, case=%d/%d, input=%s): %s",
        seed, index, count, _describe(value), tostring(err)), 0)
    end
  end
end

return property
