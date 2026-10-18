-- 选择屏注册表：惰性加载有序 Screen 定义并显式注册。
-- Screen 模块只返回定义，不依赖本注册表；所有聚合 API 共享同一装配结果。
--
-- 首次调用任意聚合 API 时才惰性加载清单中的屏模块，保持首次聚合惰性、
-- 重复调用幂等，以及 route spec 的既有顺序。
local registry = {}

local _screens = {}       -- 按注册序保留（route spec 拼接需保序）
local _by_key = {}
local _loaded = false

function registry.register(screen)
  assert(type(screen) == "table" and type(screen.key) == "string", "screen needs a string key")
  assert(_by_key[screen.key] == nil, "duplicate screen key: " .. screen.key)
  _screens[#_screens + 1] = screen
  _by_key[screen.key] = screen
end

-- 测试隔离:清空注册表并复位惰性加载标志,让聚合 API 的首次调用成为唯一装配源
-- (require 缓存会让同进程先加载的屏模块绕过 _ensure_loaded,遮蔽惰性加载行为)。
function registry.reset_for_tests()
  _screens = {}
  _by_key = {}
  _loaded = false
end

-- 强制加载所有屏模块并显式注册其返回定义。清单是唯一的 append-only 共享点。
--
-- 清单顺序 = 注册序 = build_route_specs 的发射序。当前全仓 81 条 route spec 的 node 名
-- 互不重复,所以发射序**尚不可观测**;但下游 canvas_event_router 是按 node 名注册点击
-- 回调的,一旦出现重名,谁先发射谁说了算 —— 顺序会当场变成行为面。
--
-- 保序是零成本的,别为了"看起来整齐"重排它 —— 那等于拿一个不可观测的性质去赌将来不会重名。
local function _ensure_loaded()
  if _loaded then
    return
  end
  _loaded = true
  local screen_modules = {
    "src.ui.screens.market",
    "src.ui.screens.skin_panel",
    "src.ui.screens.item_atlas",
    "src.ui.screens.target_choice",
    "src.ui.screens.remote_choice",
    "src.ui.screens.player_choice",
    "src.ui.screens.secondary_confirm",
  }
  for _, module_name in ipairs(screen_modules) do
    registry.register(require(module_name))
  end
end

-- descriptor 是**选择屏**的契约,不是所有屏的契约。market / skin_panel / item_atlas
-- 是 canvas 面:有 route specs,没有 option_buttons / confirm / cancel,给不出 descriptor。
-- 因此这里只收得出 descriptor 的屏 —— node_ops_spec 钉死的 4 个 key 不受影响。
-- choice_helpers.resolve_canvas_for_screen 独立维护选择屏画布映射；
-- open_choice_modal 对 market 直接返回 false，商店开屏由自身流程负责。
function registry.build_choice_screens()
  _ensure_loaded()
  local out = {}
  for _, s in ipairs(_screens) do
    if s.descriptor then
      out[s.key] = s.descriptor()
    end
  end
  return out
end

function registry.opener_for(key)
  _ensure_loaded()
  local s = _by_key[key]
  return s and s.open or nil
end

function registry.build_route_specs(state)
  _ensure_loaded()
  local specs = {}
  for _, s in ipairs(_screens) do
    if s.build_route_specs then
      for _, spec in ipairs(s.build_route_specs(state) or {}) do
        specs[#specs + 1] = spec
      end
    end
  end
  return specs
end

return registry

--[[ mutate4lua-manifest
version=4
projectHash=22906c719b49a161
scope.0.id=chunk:src/ui/screens_registry.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=98
scope.0.semanticHash=ecff22f2d0b00445
scope.1.id=function:registry.register
scope.1.kind=function
scope.1.startLine=12
scope.1.endLine=17
scope.1.semanticHash=80771c935545cf39
scope.2.id=function:registry.reset_for_tests
scope.2.kind=function
scope.2.startLine=21
scope.2.endLine=25
scope.2.semanticHash=071a591ca8aca8f1
scope.3.id=function:_ensure_loaded
scope.3.kind=function
scope.3.startLine=34
scope.3.endLine=51
scope.3.semanticHash=42dd59e77ea7efe6
scope.4.id=function:registry.build_choice_screens
scope.4.kind=function
scope.4.startLine=61
scope.4.endLine=70
scope.4.semanticHash=fc5d8fd2db45f151
scope.5.id=function:registry.opener_for
scope.5.kind=function
scope.5.startLine=72
scope.5.endLine=76
scope.5.semanticHash=c3943f49d4be04c7
scope.6.id=function:registry.canvas_for
scope.6.kind=function
scope.6.startLine=78
scope.6.endLine=82
scope.6.semanticHash=c3943f49d4be04c7
scope.7.id=function:registry.build_route_specs
scope.7.kind=function
scope.7.startLine=84
scope.7.endLine=95
scope.7.semanticHash=2d4c6771d24b67e6
]]
