local runtime_context = require("src.host.context")
local default_ports = require("src.host.default_ports")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local global_aliases = require("src.host.global_aliases")
local paid_purchase_port = require("src.rules.ports.paid_purchase")
local achievement_progress_port = require("src.rules.ports.achievement_progress")
local share_panel_port = require("src.foundation.ports.share_panel")
local host_share_panel = require("src.host.share_panel")
local screen_openers_port = require("src.ui.seams.screen_openers")
local resolver_seam = require("src.ui.seams.local_actor_resolver")
local config_sanity = require("src.config.gameplay.config_sanity")
local runtime_assets = require("src.config.runtime_assets")
local skin_panel = require("src.ui.screens.skin_panel")
local skin_equip = require("src.rules.cosmetics")
local achievement_runtime = require("src.app.host_integrations.achievement_runtime")
local host_runtime = require("src.host.init")
local sign_in_rewards = require("src.app.host_integrations.sign_in_rewards")
local leaderboard_settlement = require("src.app.host_integrations.leaderboard_settlement")

-- ui 宿主能力由本组合根经 port 注入（#250）：ui 对 host 零静态依赖，
-- 宿主实现由本装配层注入。src.host.init 是各 port 声明面的超集，同一实现表
-- 喂给所有槽位，每个槽只读取自己声明的函数名。清单单一真源见 host_ports（#251）。
local ui_host_ports = require("src.ui.seams.host_ports")

local M = {}

-- #328:运行资产目录校验经装配侧注入——config_sanity 只声明需求,真实
-- validate_catalog 在本组合根接线,config_sanity 不再反向依赖 config.runtime_assets
-- (拆 config 视图投影环)。thunk 在调用时读模块字段,测试补丁仍可打在字段上。
config_sanity.configure_runtime_asset_validator(function()
  return runtime_assets.validate_catalog()
end)

-- 从皮肤取装备资源 id:皮肤缺失/未登记产品/模型无资源时统一 nil,
-- 交给 skin_equip.equip 走其缺省语义。
local function _resolve_skin_resource(skin)
  local model = skin and runtime_assets.skin_model_for_product(skin.product_id) or nil
  return model and model.asset_id or nil
end

-- 装配 skin_panel 的 equip 回调:装配成功后记一次遥测。
local function _equip_skin(role_id, skin)
  local equipped = skin_equip.equip(role_id, _resolve_skin_resource(skin))
  if equipped then
    achievement_progress_port.skin_equipped(nil, role_id, skin)
  end
  return equipped
end

local function _reject_removed_options(opts)
  if opts.context_policy ~= nil then
    error("context_policy option removed; runtime install is strict-only")
  end
  if opts.enable_legacy_helper_fallback ~= nil then
    error("enable_legacy_helper_fallback option removed; runtime install is strict-only")
  end
end

local function _install_context(install_globals)
  local runtime_ctx = runtime_context.new({
    GameAPI = GameAPI,
    LuaAPI = LuaAPI,
  })
  runtime_context.set_current(runtime_ctx)
  runtime_context.install_environment(runtime_ctx)
  global_aliases.install(runtime_ctx.env)
  runtime_context.install_runtime_helpers(runtime_ctx, { install_globals = install_globals })
  return runtime_ctx
end

local function _setup_context(opts)
  if opts.skip_context_install == true then
    runtime_context.set_current(nil)
    return
  end
  _install_context(opts.install_globals == true)
  runtime_ports.configure(default_ports.build(runtime_context))
end

local function _load_required_modules(opts)
  paid_purchase_port.configure(require("src.host.paid_purchase_gateway"))
  achievement_progress_port.configure(achievement_runtime.build_port())
  -- share_panel 的宿主实现由装配侧接线；闭包在调用时读模块字段，
  -- 测试对实现模块字段的 patch 仍可截获。
  share_panel_port.configure({
    try_show = function(...) return host_share_panel.try_show(...) end,
  })
  -- #332:local_actor_resolver 接缝接线(input 层经它解析点击者身份,不反向
  -- require 实现)。
  resolver_seam.configure(require("src.ui.render.support.local_actor_resolver"))
  -- #332:screen_openers 契约接缝的实现接线(coord 开屏不反向 require screens)。
  -- thunk 惰性 require 屏模块(屏是 require 时自注册的深模块)并在调用时读
  -- 字段(测试补丁仍可打在字段上)。
  screen_openers_port.configure({
    open_secondary_confirm = function(...)
      return require("src.ui.screens.secondary_confirm").open(...)
    end,
    open_pre_confirm = function(...)
      return require("src.ui.screens.secondary_confirm").open_pre_confirm(...)
    end,
    open_item_phase_pre_confirm = function(...)
      return require("src.ui.screens.secondary_confirm").open_item_phase_pre_confirm(...)
    end,
    refresh_secondary_confirm_copy = function(...)
      return require("src.ui.screens.secondary_confirm").refresh_copy(...)
    end,
    open_market = function(...)
      return require("src.ui.screens.market").open(...)
    end,
    close_market = function(...)
      return require("src.ui.screens.market").close(...)
    end,
  })
  skin_panel.configure_equip(_equip_skin)
  skin_panel.configure_unequip(function(role_id)
    return skin_equip.unequip(role_id, runtime_assets.default_skin_model().asset_id)
  end)
  sign_in_rewards.install(opts)
  leaderboard_settlement.install(opts)
  require "src.rules.endgame"
  require "src.computer.agent"
  require "src.app.compose_game"
end

local function _configure_ui_host_ports()
  for _, port in ipairs(ui_host_ports) do
    port.configure(host_runtime)
  end
end

function M.install(opts)
  opts = opts or {}
  config_sanity.validate()
  _reject_removed_options(opts)
  runtime_ports.reset_for_tests()
  paid_purchase_port.reset_for_tests()
  achievement_progress_port.reset_for_tests()
  share_panel_port.reset_for_tests()
  screen_openers_port.reset_for_tests()
  resolver_seam.reset_for_tests()
  for _, port in ipairs(ui_host_ports) do
    port.reset_for_tests()
  end
  _setup_context(opts)
  _configure_ui_host_ports()
  _load_required_modules(opts)
end

return M

--[[ mutate4lua-manifest
version=4
projectHash=42bad74e415e221b
scope.0.id=chunk:src/app/host_install.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=164
scope.0.semanticHash=af5d630ed00c3858
scope.1.id=function:<anonymous>
scope.1.kind=function
scope.1.startLine=34
scope.1.endLine=36
scope.1.semanticHash=04a3b0c01baa0aa1
scope.2.id=function:_resolve_skin_resource
scope.2.kind=function
scope.2.startLine=40
scope.2.endLine=43
scope.2.semanticHash=2c32e2a0e47135f7
scope.3.id=function:_equip_skin
scope.3.kind=function
scope.3.startLine=46
scope.3.endLine=52
scope.3.semanticHash=f6186e1d732fe9f7
scope.4.id=function:_reject_removed_options
scope.4.kind=function
scope.4.startLine=54
scope.4.endLine=61
scope.4.semanticHash=16b84653cdb662d5
scope.5.id=function:_install_context
scope.5.kind=function
scope.5.startLine=63
scope.5.endLine=73
scope.5.semanticHash=93d8f7ab821a966d
scope.6.id=function:_setup_context
scope.6.kind=function
scope.6.startLine=75
scope.6.endLine=82
scope.6.semanticHash=b4143a2fb398b290
scope.7.id=function:_load_required_modules
scope.7.kind=function
scope.7.startLine=84
scope.7.endLine=136
scope.7.semanticHash=8d7995366641a478
scope.8.id=function:<anonymous>#2
scope.8.kind=function
scope.8.startLine=91
scope.8.endLine=91
scope.8.semanticHash=7aaca51d4b37242b
scope.9.id=function:<anonymous>#3
scope.9.kind=function
scope.9.startLine=92
scope.9.endLine=92
scope.9.semanticHash=7aaca51d4b37242b
scope.10.id=function:<anonymous>#4
scope.10.kind=function
scope.10.startLine=93
scope.10.endLine=93
scope.10.semanticHash=7aaca51d4b37242b
scope.11.id=function:<anonymous>#5
scope.11.kind=function
scope.11.startLine=99
scope.11.endLine=99
scope.11.semanticHash=7aaca51d4b37242b
scope.12.id=function:<anonymous>#6
scope.12.kind=function
scope.12.startLine=108
scope.12.endLine=110
scope.12.semanticHash=7aaca51d4b37242b
scope.13.id=function:<anonymous>#7
scope.13.kind=function
scope.13.startLine=111
scope.13.endLine=113
scope.13.semanticHash=7aaca51d4b37242b
scope.14.id=function:<anonymous>#8
scope.14.kind=function
scope.14.startLine=114
scope.14.endLine=116
scope.14.semanticHash=7aaca51d4b37242b
scope.15.id=function:<anonymous>#9
scope.15.kind=function
scope.15.startLine=117
scope.15.endLine=119
scope.15.semanticHash=7aaca51d4b37242b
scope.16.id=function:<anonymous>#10
scope.16.kind=function
scope.16.startLine=120
scope.16.endLine=122
scope.16.semanticHash=7aaca51d4b37242b
scope.17.id=function:<anonymous>#11
scope.17.kind=function
scope.17.startLine=123
scope.17.endLine=125
scope.17.semanticHash=7aaca51d4b37242b
scope.18.id=function:<anonymous>#12
scope.18.kind=function
scope.18.startLine=128
scope.18.endLine=130
scope.18.semanticHash=31dcd80be61eedfc
scope.19.id=function:_configure_ui_host_ports
scope.19.kind=function
scope.19.startLine=138
scope.19.endLine=142
scope.19.semanticHash=7aef32a35b2a1d8e
scope.20.id=function:M.install
scope.20.kind=function
scope.20.startLine=144
scope.20.endLine=161
scope.20.semanticHash=686b1781792d853d
]]
