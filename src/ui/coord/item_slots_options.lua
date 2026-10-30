local tables = require("src.foundation.tables")

local M = {}

local _option_id_set = {}
local _cached_option_choice_ref

local function _option_id(option)
  if type(option) == "table" then
    return option.id
  end
  return option
end

local function _fill_option_id_set(options)
  tables.clear(_option_id_set)
  for _, option in ipairs(options) do
    local option_id = _option_id(option)
    if option_id ~= nil then
      _option_id_set[tostring(option_id)] = true
    end
  end
end

function M.build(choice)
  if not (choice and type(choice.options) == "table") then
    -- 无效 choice(回合推进后 choice 清空/缺 options):清空集合并作废旧引用,
    -- 否则上一条 choice 的可选项永久残留(高亮错挂,真机实证 #340);
    -- 引用不置 nil 的话,同一 options 表复用会被「引用相同」短路跳过重建。
    tables.clear(_option_id_set)
    _cached_option_choice_ref = nil
    return _option_id_set
  end
  if choice.options == _cached_option_choice_ref then
    return _option_id_set
  end
  _cached_option_choice_ref = choice.options
  _fill_option_id_set(choice.options)
  return _option_id_set
end

return M

