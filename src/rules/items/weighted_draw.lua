local runtime_ports = require("src.foundation.ports.runtime_ports")

--- 权重池抽取:按 weight_of 回调计算每个元素的权重,从数组中抽取 count 个元素。
--- 随机源接现有 rng port(runtime_ports.rng_next_int),不再直调宿主 LuaAPI.rand。
--- 收编自 vendor Utils.choice_weight_list(单消费者 inventory.draw_random 就近下沉)。
local weighted_draw = {}

local function _compute_weights(array, weight_of)
  local weights = {}
  local total_weight = 0
  for i, element in ipairs(array) do
    local weight = math.max(weight_of(element), 0)
    weights[i] = weight
    total_weight = total_weight + weight
  end
  return weights, total_weight
end

-- 在 weights/total_weight 上做一次加权抽取,返回命中元素的索引。
-- rand ∈ [1, total_weight];按顺序累加权重,首个累加值 >= rand 的桶命中。
-- 已抽取(权重置 0)的桶不增加累加值,故永远不会成为首个命中桶。
local function _draw_index(count, weights, total_weight)
  local rand = runtime_ports.rng_next_int(1, total_weight)
  local accumulated = 0
  for j = 1, count do
    accumulated = accumulated + weights[j]
    if accumulated >= rand then
      return j
    end
  end
  return count
end

-- 有放回抽取:每次都在完整权重上抽,允许重复命中同一元素。
local function _pick_repeatable(array, weights, total_weight, count)
  local result = {}
  for _ = 1, count do
    result[#result + 1] = array[_draw_index(#array, weights, total_weight)]
  end
  return result
end

-- 无放回抽取:命中后把该桶权重置 0 并扣减总权重,直到取够或权重耗尽。
local function _pick_unique(array, weights, total_weight, count)
  local remaining = {}
  for i, w in ipairs(weights) do
    remaining[i] = w
  end
  local remaining_total = total_weight
  local result = {}
  for _ = 1, math.min(count, #array) do
    if remaining_total <= 0 then
      break
    end
    local idx = _draw_index(#array, remaining, remaining_total)
    result[#result + 1] = array[idx]
    remaining_total = remaining_total - remaining[idx]
    remaining[idx] = 0
  end
  return result
end

--- @generic T
--- @param array T[] 候选数组
--- @param count integer 抽取数量
--- @param weight_of fun(element: T): integer 权重回调(负权重按 0 处理)
--- @param repeatable boolean 是否允许重复抽取(true 有放回,false 无放回)
--- @return T[] 抽取结果
function weighted_draw.pick(array, count, weight_of, repeatable)
  -- 「抽不出东西」只判一次:空数组的总权重必为 0,count <= 0 时两条抽取路径的
  -- 循环本就不迭代。再加一道 #array/count 的前置快路径不改变任何结果,
  -- 只会把同一个判断摊成两处。
  local weights, total_weight = _compute_weights(array, weight_of)
  if total_weight <= 0 then
    return {}
  end

  if repeatable then
    return _pick_repeatable(array, weights, total_weight, count)
  end
  return _pick_unique(array, weights, total_weight, count)
end

return weighted_draw

