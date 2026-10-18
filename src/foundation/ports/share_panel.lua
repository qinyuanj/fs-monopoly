-- 「宿主分享面板」（GLOSSARY.md 词条）触发口的纯契约 port（#463）：resolve Role、
-- pcall 宿主方法属宿主逻辑（docs/architecture.md「宿主接口经 port 进入内层」），
-- 实现在 src/host/share_panel.lua，由装配侧 configure 注入（host_install / 测试
-- 基线）。契约留在
-- foundation/ports 的落层理由不变：两个调用方（turn 的托管首点、ui/ports 的
-- 分享按钮）都够不到 app 层，foundation 是唯一双方可达的层。签名与被转发实现
-- 同形，本模块不叠加任何规则结论。
local share_panel = {}
local configured_impl = nil

local function _assert_impl_shape(impl)
  assert(type(impl) == "table", "invalid share_panel implementation")
  assert(type(impl.try_show) == "function", "share_panel implementation missing try_show")
  return impl
end

function share_panel.configure(impl)
  configured_impl = _assert_impl_shape(impl)
end

function share_panel.reset_for_tests()
  configured_impl = nil
end

-- 车道守卫用:共享测试基线要求实现处于已配置态;spec teardown 拆到未配置态后
-- 不装回会让同进程后续 suite 静默走未配置降级(#217 同款教训)。
function share_panel.is_configured()
  return configured_impl ~= nil
end

-- 唤起宿主分享面板:成功 → true;role 缺失、方法缺失或宿主抛错 → warn + false
-- (语义由实现侧钉住)。tag 区分调用方日志前缀(托管首点沿用历史钉住的
-- "auto share panel")。未配置时安全降级返回 false,不抛错。
function share_panel.try_show(actor_role_id, tag)
  if configured_impl == nil then
    return false
  end
  return configured_impl.try_show(actor_role_id, tag)
end

return share_panel

