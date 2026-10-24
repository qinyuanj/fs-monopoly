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
local gift_code_port = require("src.ui.seams.gift_code")
local skin_ownership = require("src.rules.skin_ownership")
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
  -- #199 / #204:礼包码屏经 seams/gift_code 调皮肤归属模块的兑换;闭包调用时读
  -- 模块字段,测试补丁仍可打在模块字段上。
  gift_code_port.configure({
    redeem = function(...)
      return skin_ownership.redeem(...)
    end,
  })
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

