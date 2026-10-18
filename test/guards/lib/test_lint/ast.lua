-- 测试 lint 骨架(#127):AST 获取。parser 从受控 Lua 环境(GLOSSARY)
-- 装载,与 lint 车道同一份真身校验;缺包或版本越界由预检报告,本仓不安装。
require("test.bootstrap").install_package_paths()

local M = {}

local _parser

-- 返回 luacheck.parser 模块;受控环境不可用时返回 nil, err。
function M.parser()
  if _parser ~= nil then
    return _parser
  end
  local lua_env = require("foundation.lua_env")
  local roots, roots_err = lua_env.roots()
  if roots == nil then
    return nil, roots_err
  end
  -- 进程内测试辅助:require 结束后恢复原装载面,避免后续 spec 的 require 失去
  -- 仓内路径;lint 子进程走默认的持续受限口径。
  local ok, mod = pcall(lua_env.require_controlled, "luacheck.parser", roots, { restore_paths = true })
  if not ok then
    return nil, tostring(mod)
  end
  -- 与 lint 车道同口径的真身校验:必须解析自受控 Lua 环境。
  local origin = package.searchpath("luacheck.parser", package.path) or ""
  assert(
    lua_env.is_inside(origin:gsub("\\", "/"), roots),
    "luacheck.parser must resolve from the controlled Lua environment, got: " .. origin
  )
  _parser = mod
  return _parser
end

-- 解析一份 spec 源码,返回 { ast, comments };语法错误返回 nil + 含行号的
-- 可读错误(不抛异常,调用方必须把解析失败报出来而不是静默跳过)。
function M.parse(source)
  local parser, err, unavailable = M.parser()
  if parser == nil then
    return nil, err, unavailable
  end
  -- luacheck 1.2.0 的 lexer 不吃裸字符串,源码要先经 decoder 包成 Chars 对象。
  local chars = require("luacheck.decoder").decode(tostring(source or ""))
  local ok, ast, comments = pcall(parser.parse, chars)
  if not ok then
    local syntax = ast
    if type(syntax) == "table" and syntax.msg ~= nil then
      return nil, "syntax error: " .. tostring(syntax.msg) .. " (line " .. tostring(syntax.line) .. ")"
    end
    return nil, "syntax error: " .. tostring(syntax)
  end
  return { ast = ast, comments = comments or {} }
end

-- 规则共用的节点小工具(bodies/规则不再各自复制一份)。
-- Id 节点 -> 变量名;其他节点 -> nil。
function M.id_name(node)
  if type(node) == "table" and node.tag == "Id" then
    return node[1]
  end
  return nil
end

-- 调用节点 -> 调用链根名(剥掉多级 Index,含 luassert.is.equal 与 a:b 方法调用)。
function M.callee_root_name(call_node)
  local base = call_node[1]
  while type(base) == "table" and base.tag == "Index" do
    base = base[1]
  end
  return M.id_name(base)
end

return M
