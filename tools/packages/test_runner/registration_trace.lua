-- 纯模块、零 require:busted_backend 经 require、stock busted 的 test/busted_helper.lua
-- (插件 uml_crap / uml_mutate,tools/ 尚不在 package.path)经 dofile 共用这一份。
local M = {}

-- busted 注册每个 describe / it / hook 时(core 的 publisher,住在 busted.register
-- 函数体内)都经 getTrace 构造完整 debug.traceback,实测占 behavior 车道 ~85% CPU;
-- 注册 trace 本仓只读 source / currentline(tap_handler、helper)。注册路径把
-- traceback 置空,错误路径(busted.safe / fail 等)原样走真实 getTrace。
-- 调用点按 register 的行号区间识别,不硬编码 busted 版本行号。
local function _empty_traceback() return "" end
function M.install(busted)
  local register = debug.getinfo(busted.register, "S")
  local get_trace = busted.getTrace
  busted.getTrace = function(element, level, msg)
    local caller = debug.getinfo(2, "Sl")
    if caller.source ~= register.source or caller.currentline < register.linedefined
      or caller.currentline > register.lastlinedefined then
      return get_trace(element, level, msg) -- 尾调用:层级与直调一致
    end
    local traceback = debug.traceback
    rawset(debug, "traceback", _empty_traceback)
    -- +2:pcall(C) 与本包装各占一层
    local ok, info = pcall(get_trace, element, (level or 3) + 2, msg)
    rawset(debug, "traceback", traceback)
    if not ok then error(info, 0) end
    return info
  end
end

return M
