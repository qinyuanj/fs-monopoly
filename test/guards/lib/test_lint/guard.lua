-- 测试 lint 门禁(#127):扫全仓测试 spec(test/** 与 tools/**/test/** 的
-- test_*.lua),用 luacheck parser 的 AST 跑可插拔规则:vacuous-branch
-- (拦截断言只躲在条件分支里的空转测试,#127)与 call-count(拦截钉内部
-- 调用次数的计数器断言,#128)。骨架(枚举/AST/测试体识别/豁免解析/报告
-- 格式)两条规则共用。
require("test.bootstrap").install_package_paths()

local fs_lib = require("foundation.fs")
local git_query = require("test.guards.lib.git_query")
local files_mod = require("test.guards.lib.test_lint.files")
local ast_mod = require("test.guards.lib.test_lint.ast")
local bodies_mod = require("test.guards.lib.test_lint.bodies")
local allow_mod = require("test.guards.lib.test_lint.allow")
local report = require("test.guards.lib.test_lint.report")
local vacuous_branch = require("test.guards.lib.test_lint.rules.vacuous_branch")
local call_count = require("test.guards.lib.test_lint.rules.call_count")

local M = {}

local _GUARD = "test_lint_guard"

-- 规则注册表:新规则往这里加一条即可,骨架不动。
-- check_body 返回违规记录列表或 nil。
local RULES = { vacuous_branch, call_count }

-- 纯策略核:tracked 路径表 + read(path) -> content|nil,返回统一格式的违规
-- 字符串列表。opts.parse 可注入替代 parser;缺省走受控 Lua 环境的 luacheck。
-- spec 必须能拿合成违规输入喂进来证明它会红,不碰 git、不碰文件系统。
function M.check(paths, read, opts)
  opts = opts or {}
  local parse = opts.parse or ast_mod.parse
  local violations = {}

  for _, path in ipairs(files_mod.filter(paths)) do
    local content = read(path)
    if content == nil then
      violations[#violations + 1] =
        { rule = "read", path = path, line = 0, message = "读不到" }
    else
      local parsed, err = parse(content)
      if parsed == nil then
        violations[#violations + 1] =
          { rule = "parse", path = path, line = 0, message = "解析失败: " .. tostring(err) }
      else
        local bodies, locals = bodies_mod.collect(parsed.ast)
        local allows, allow_violations = allow_mod.parse(parsed.comments)
        for _, violation in ipairs(allow_violations) do
          violation.path = path
          violations[#violations + 1] = violation
        end
        -- 每条规则自备 ctx 构造(可选 build_ctx 钩子):新规则要不同的上下文
        -- 不改骨架本体,注册表即完整扩展点。
        for _, rule in ipairs(RULES) do
          local ctx = rule.build_ctx ~= nil and rule.build_ctx({ locals = locals }) or nil
          for _, body in ipairs(bodies) do
            for _, violation in ipairs(rule.check_body(body, ctx) or {}) do
              violation.path = path
              if not allow_mod.exempted(allows, violation.rule, violation.line) then
                violations[#violations + 1] = violation
              end
            end
          end
        end
      end
    end
  end

  return report.format_all(_GUARD, violations)
end

-- IO 壳:luacheck 是规则引擎,受控 Lua 环境不可用按真实失败报出,不冒充通过。
function M.run()
  local parser, err = ast_mod.parser()
  if parser == nil then
    return { ok = false, error = _GUARD .. " error: " .. tostring(err) }
  end

  local paths, list_err = git_query.list_files(".")
  if paths == nil then
    return { ok = false, error = _GUARD .. " error: " .. tostring(list_err) }
  end

  local violations = M.check(paths, fs_lib.read_file)
  if #violations > 0 then
    return { ok = false, error = table.concat(violations, "\n") }
  end
  return { ok = true, message = _GUARD .. " ok" }
end

return M
