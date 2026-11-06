-- indexed-case-table:spec 里 `local X = { function() ... end, ... }` 这种只装函数
-- 的数组,再由 it 按下标分派(`it(名, X[i])`)。用例体不在 it 里,bodies 认不出,
-- vacuous-branch 与 call-count 都扫不到;漏注册的条目也不会被跑到。用例体直接
-- 写进各自的 it。判定:任意作用域的 local 赋值,值是非空表且每项都是函数字面量。
-- 混入数据或具名字段的表(stub、用例数据表)不算。
local ast_mod = require("test.guards.lib.test_lint.ast")

local M = {}

M.name = "indexed-case-table"

local function _is_function_array(node)
  if type(node) ~= "table" or node.tag ~= "Table" or #node == 0 then
    return false
  end
  for _, item in ipairs(node) do
    if type(item) ~= "table" or item.tag ~= "Function" then
      return false
    end
  end
  return true
end

local function _walk(node, visit)
  if type(node) ~= "table" then
    return
  end
  visit(node)
  for _, child in ipairs(node) do
    _walk(child, visit)
  end
end

function M.check_file(ast)
  local violations = {}
  _walk(ast, function(node)
    if node.tag ~= "Local" or node[2] == nil then
      return
    end
    for index, value in ipairs(node[2]) do
      if _is_function_array(value) then
        violations[#violations + 1] = {
          rule = M.name,
          line = node.line,
          message = "函数数组 " .. tostring(ast_mod.id_name(node[1][index]))
            .. " 按下标分派用例,用例体躲开测试 lint;把每个函数体直接写进对应的 it",
        }
      end
    end
  end)
  return violations
end

return M
