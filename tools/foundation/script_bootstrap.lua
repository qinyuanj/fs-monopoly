-- script_bootstrap.lua —— 直跑脚本入口的引导共享块。
--
-- 消费者:tools/packages/lint/runner.lua、tools/packages/encoding/encoding.lua、
-- tools/packages/spec_lane/spec_lane.lua、tools/packages/ops/deploy.lua(只在直跑时
-- install,被 require 时跳过)。样板逻辑(normalize / match / dofile /
-- install 的 source 选择)唯一出处在这里,每个入口头部只剩 3 行:
--
--   local _self = debug.getinfo(1, "S").source or "@tools/packages/<pkg>/<entry>.lua"
--   local _sb = dofile(_self:gsub("\\", "/"):gsub("^@", ""):match("^(.*)/[^/]+$")
--     .. "/../../foundation/script_bootstrap.lua")
--   local env, bootstrap = _sb.install(_self)
--
-- 为什么入口仍要自定位本文件:install 前 package.path 未装(require 不可用),
-- 且脚本可能被绝对路径从非仓根 cwd 调用——「第一块砖」只能由调用方算出的
-- 自身目录之上 dofile 到。
--
-- install 的 script_source 选择:
--   (arg and arg[0]) or self_source —— 进程入口 arg[0] 优先(脚本/被 cli.lua 转发时
--   均为真实入口),否则退回调用方 chunk 的 source。两者 bootstrap.install
--   都能从 dirname 上溯定位 repo_root。

local function _module_dir()
  local source = debug.getinfo(1, "S").source or "@tools/foundation/script_bootstrap.lua"
  return tostring(source):gsub("\\", "/"):gsub("^@", ""):match("^(.*)/[^/]+$") or "tools/foundation"
end

local _bootstrap = dofile(_module_dir() .. "/bootstrap.lua")

local sb = {}

-- install(self_source) -> env, bootstrap
--   self_source: 调用方 chunk 的 source(debug.getinfo(1,"S").source)。
function sb.install(self_source)
  local script_source = (arg and arg[0]) or self_source
  local env = _bootstrap.install(script_source)
  return env, _bootstrap
end

return sb