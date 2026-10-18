local base_nodes = require("src.ui.schema.base")
local base_contract = require("src.ui.schema.base_contract")

local touch_policy = {}

-- 名单里允许有空洞（nil/false），跳过即可。
local function _apply_touch_enabled(ui, names, value)
  for _, name in ipairs(names) do
    if name then
      ui:set_touch_enabled(name, value)
    end
  end
end

function touch_policy.set_many_touch_enabled(ui, names, enabled)
  if not ui or not ui.set_touch_enabled then
    return
  end
  if type(names) ~= "table" then
    return
  end
  _apply_touch_enabled(ui, names, enabled == true)
end

local function resolve_auto_controls(ui, controls)
  return controls or ui.auto_control_nodes or { base_nodes.auto_button, base_nodes.auto_label }
end

local function apply_auto_controls(ui, auto_enabled, controls)
  local auto_effect_seen = false
  for _, name in ipairs(controls) do
    if name == base_nodes.auto_button then
      ui:set_touch_enabled(name, auto_enabled == true)
    else
      ui:set_touch_enabled(name, false)
    end
    if name == base_nodes.auto_effect then
      auto_effect_seen = true
    end
  end
  return auto_effect_seen
end

function touch_policy.set_auto_controls_touch(ui, auto_enabled, controls)
  if not ui or not ui.set_touch_enabled then
    return
  end
  controls = resolve_auto_controls(ui, controls)
  if not apply_auto_controls(ui, auto_enabled, controls) then
    ui:set_touch_enabled(base_nodes.auto_effect, false)
  end
end

function touch_policy.set_action_log_toggle_touch(ui, enabled)
  if not ui or not ui.set_touch_enabled then
    return
  end
  local value = enabled == true
  local targets = base_contract.action_log.toggle_targets
    or { base_nodes.action_log_button }
  for _, name in ipairs(targets) do
    ui:set_touch_enabled(name, value)
  end
end

-- 分享按钮装饰子节点（环/动效×2/文本）吸触摸会吞掉按钮点击（真机 #458 实证），
-- 每次锁定策略施加时统一压灭；同名两个动效靠 set_touch_enabled_all 全量命中。
function touch_policy.set_share_decor_touch(ui)
  if not ui or not ui.set_touch_enabled_all then
    return
  end
  for _, name in ipairs(base_nodes.share_decor_nodes or {}) do
    ui:set_touch_enabled_all(name, false)
  end
end

local function _disable_button(ui, name)
  if name then
    ui:set_touch_enabled(name, false)
  end
end

function touch_policy.set_choice_screen_locked(ui, screen)
  if not ui or not ui.set_touch_enabled or not screen then
    return
  end
  touch_policy.set_many_touch_enabled(ui, screen.option_buttons or {}, false)
  _disable_button(ui, screen.under_button)
  _disable_button(ui, screen.confirm)
  _disable_button(ui, screen.cancel)
end

return touch_policy

--[[ mutate4lua-manifest
version=4
projectHash=12e2272310b5b13c
scope.0.id=chunk:src/ui/input/touch.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=106
scope.0.semanticHash=30522d032e32cab0
scope.1.id=function:_apply_touch_enabled
scope.1.kind=function
scope.1.startLine=7
scope.1.endLine=13
scope.1.semanticHash=43d9c4fd429ed84c
scope.2.id=function:touch_policy.set_many_touch_enabled
scope.2.kind=function
scope.2.startLine=15
scope.2.endLine=23
scope.2.semanticHash=1b8854fa107ff086
scope.3.id=function:resolve_auto_controls
scope.3.kind=function
scope.3.startLine=25
scope.3.endLine=27
scope.3.semanticHash=8900fec3f54d342f
scope.4.id=function:apply_auto_controls
scope.4.kind=function
scope.4.startLine=29
scope.4.endLine=42
scope.4.semanticHash=ea87f1af165216f0
scope.5.id=function:touch_policy.set_auto_controls_touch
scope.5.kind=function
scope.5.startLine=44
scope.5.endLine=52
scope.5.semanticHash=49549f85daf7e37b
scope.6.id=function:touch_policy.set_action_log_toggle_touch
scope.6.kind=function
scope.6.startLine=54
scope.6.endLine=64
scope.6.semanticHash=6f217be356f8f507
scope.7.id=function:touch_policy.set_share_decor_touch
scope.7.kind=function
scope.7.startLine=68
scope.7.endLine=75
scope.7.semanticHash=254be4ed3dbf5cf9
scope.8.id=function:touch_policy.set_runtime_nodes_touch_enabled
scope.8.kind=function
scope.8.startLine=77
scope.8.endLine=87
scope.8.semanticHash=7849894852b28608
scope.9.id=function:_disable_button
scope.9.kind=function
scope.9.startLine=89
scope.9.endLine=93
scope.9.semanticHash=22985bb632246cb2
scope.10.id=function:touch_policy.set_choice_screen_locked
scope.10.kind=function
scope.10.startLine=95
scope.10.endLine=103
scope.10.semanticHash=91c416012bb2a918
]]
