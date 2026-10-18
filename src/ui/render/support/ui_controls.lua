local ui_controls = {}

local function _has_ui_method(ui, method_name)
  return ui ~= nil and type(ui[method_name]) == "function"
end

local function _clear_control_text(ui, name)
  if not name or ui == nil then
    return
  end
  if _has_ui_method(ui, "set_label") then
    ui:set_label(name, "")
  end
  if _has_ui_method(ui, "set_button") then
    ui:set_button(name, "")
  end
end

local function _apply_control_flag(ui, name, method_name, value)
  if value == nil or not _has_ui_method(ui, method_name) then
    return
  end
  ui[method_name](ui, name, value == true)
end

function ui_controls.set_control_state(ui, name, options)
  if not name or ui == nil then
    return
  end

  local control_options = options or {}
  _apply_control_flag(ui, name, "set_visible", control_options.visible)
  _apply_control_flag(ui, name, "set_touch_enabled", control_options.touch_enabled)
end

function ui_controls.set_controls_state(ui, names, options)
  if type(names) ~= "table" then
    return
  end

  for _, name in ipairs(names) do
    ui_controls.set_control_state(ui, name, options)
  end
end

function ui_controls.set_slot_state(ui, slot, options_by_key)
  if type(slot) ~= "table" then
    return
  end

  local key_options = options_by_key or {}
  for key, options in pairs(key_options) do
    ui_controls.set_control_state(ui, slot[key], options)
  end
end

-- descriptor 只收 ELabel / EButton：它们的文本与可点状态不随画布隐藏而清空，必须在这里
-- 显式复位，否则会跨屏残留。纯装饰 EImage（各屏的 _灰底 / _面板 / _选项区 / _弹窗背景）
-- 不入 descriptor，也不该在这里复位 —— screen.root 就是 ECanvas 本身，隐藏它（连同
-- canvas_coordinator 发的 隐藏X屏 事件）已经带走画布下的所有子节点，对已经不可见的节点
-- 再发一轮宿主调用没有收益。
function ui_controls.reset_choice_screen(ui, screen)
  if type(screen) ~= "table" then
    return
  end

  ui_controls.set_control_state(ui, screen.root, { visible = false })
  _clear_control_text(ui, screen.title)
  _clear_control_text(ui, screen.body)
  _clear_control_text(ui, screen.confirm)
  _clear_control_text(ui, screen.cancel)
  ui_controls.set_control_state(ui, screen.confirm, { visible = false, touch_enabled = false })
  ui_controls.set_control_state(ui, screen.cancel, { visible = false, touch_enabled = false })
  ui_controls.set_controls_state(ui, screen.option_buttons, { visible = false, touch_enabled = false })
  ui_controls.set_controls_state(ui, screen.slot_labels, { visible = false, touch_enabled = false })
  ui_controls.set_controls_state(ui, screen.slot_projections, { visible = false, touch_enabled = false })
  ui_controls.set_control_state(ui, screen.under_button, { visible = false, touch_enabled = false })
end

return ui_controls

