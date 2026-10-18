-- skip flag 入口契约(#129)的上游 argv 观测点。经 LUA_INIT_5_4 注入,入口进程
-- 及其派生的每个 Lua 子进程都先跑这里,入口本身照常真实执行:
--   * process:<脚本>  每个 Lua 进程启动时的 argv(观测跨进程转发,如车道 → mutator);
--   * module:<函数>   进程内上游入口函数收到的 argv(观测 dry4lua 直调)。
-- 只记录不改行为;未设 SKIP_FLAG_CONTRACT_LOG 时什么也不做。
local log_path = os.getenv("SKIP_FLAG_CONTRACT_LOG")
if log_path == nil or log_path == "" then
  return
end

local function _record(where, values)
  local parts = {}
  for _, value in ipairs(values or {}) do
    parts[#parts + 1] = tostring(value)
  end
  local handle = io.open(log_path, "ab")
  if handle ~= nil then
    -- 字段以 \31(单元分隔符)拼接,argv 里不会出现。
    handle:write(where, "\t", table.concat(parts, "\31"), "\n")
    handle:close()
  end
end

local script = tostring(arg and arg[0] or ""):gsub("\\", "/")
_record("process:" .. script, arg)

-- 进程内上游:模块名 → 被包装的入口函数名。
local module_hooks = {
  ["dry4lua.cli"] = "run",
}

local wrapped = {}
local original_require = require
require = function(name, ...)
  local module, extra = original_require(name, ...)
  local field = module_hooks[name]
  if field ~= nil and type(module) == "table" and not wrapped[module] then
    wrapped[module] = true
    local inner = module[field]
    module[field] = function(args, ...)
      _record("module:" .. name .. "." .. field, args)
      return inner(args, ...)
    end
  end
  return module, extra
end
