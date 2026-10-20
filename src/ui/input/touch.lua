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
  -- 可点灰底(点背景关闭,#177)是退出口,锁定时与按钮一并关闭;穿透灰底本就关着。
  if screen.underlay_touch == true then
    _disable_button(ui, screen.underlay)
  end
  _disable_button(ui, screen.confirm)
  _disable_button(ui, screen.cancel)
end

return touch_policy

