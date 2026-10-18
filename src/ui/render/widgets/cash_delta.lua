local base_nodes = require("src.ui.schema.base")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local timing = require("src.config.gameplay.timing")
local number_utils = require("src.foundation.number")
local row_field = require("src.ui.render.widgets.row_field")
local tables = require("src.foundation.tables")

local panel_cash_delta = {}

local _cash_delta_names = {}
for _i = 1, 4 do
  _cash_delta_names[_i] = string.format(base_nodes.player_cash_delta, _i)
end

local function _safe_ui_call(ui, method_name, ...)
  if not ui or type(ui[method_name]) ~= "function" then
    return false
  end
  local ok = pcall(ui[method_name], ui, ...)
  return ok
end

local function _set_visible_safe(ui, name, visible)
  return _safe_ui_call(ui, "set_visible", name, visible)
end

local _resolve_integer_field = row_field.to_integer

local function _set_cash_delta_label(ui, index, text, visible)
  local label_name = _cash_delta_names[index]
  local shown = _safe_ui_call(ui, "set_label", label_name, text or "")
  if shown or visible ~= nil then
    _set_visible_safe(ui, label_name, visible == true)
  end
  return shown
end

local function _clear_cash_delta_label(ui, index)
  _set_cash_delta_label(ui, index, "", false)
end

local function _ensure_entry(ui, index)
  local entry = ui.player_cash_delta_state_by_index[index]
  if entry == nil then
    entry = { hide_token = 0, anchor_cash = nil, visible = false }
    ui.player_cash_delta_state_by_index[index] = entry
  end
  return entry
end

local function _bump_token(entry)
  entry.hide_token = (entry.hide_token or 0) + 1
  return entry.hide_token
end

local function _token_is_current(entry, token)
  return entry ~= nil and entry.hide_token == token
end

local function _schedule_hide_cash_delta(ui, index, entry, token)
  runtime_ports.schedule(timing.panel_cash_delta_visible_seconds or 3.0, function()
    if not _token_is_current(entry, token) then
      return
    end
    _clear_cash_delta_label(ui, index)
    entry.visible = false
    entry.anchor_cash = nil
  end)
end

local function _schedule_show_cash_delta(ui, index, text, entry, token)
  local show_delay = timing.panel_cash_delta_show_delay_seconds or 0.0
  local function _do_show()
    if not _token_is_current(entry, token) then
      return
    end
    local shown = _set_cash_delta_label(ui, index, text, true)
    if shown then
      entry.visible = true
      _schedule_hide_cash_delta(ui, index, entry, token)
    end
  end
  if show_delay <= 0 then
    _do_show()
    return
  end
  runtime_ports.schedule(show_delay, _do_show)
end

function panel_cash_delta.ensure_state(ui)
  tables.ensure_table_field(ui, "player_cash_value_cache_by_index")
  tables.ensure_table_field(ui, "player_cash_delta_state_by_index")
end

function panel_cash_delta.refresh_cash_delta_label(ui, index, row)
  local cash_value = _resolve_integer_field(row, "cash_value")
  local prev_cash_value = ui.player_cash_value_cache_by_index[index]
  local entry = _ensure_entry(ui, index)

  if cash_value == nil then
    _bump_token(entry)
    _clear_cash_delta_label(ui, index)
    ui.player_cash_value_cache_by_index[index] = nil
    entry.anchor_cash = nil
    entry.visible = false
    return
  end

  if prev_cash_value == nil then
    _bump_token(entry)
    _clear_cash_delta_label(ui, index)
    ui.player_cash_value_cache_by_index[index] = cash_value
    entry.anchor_cash = nil
    entry.visible = false
    return
  end

  ui.player_cash_value_cache_by_index[index] = cash_value

  if cash_value == prev_cash_value then
    return
  end

  -- 每次变化独立显示：始终以本次变化前的值为锚点，旧的 hide 回调由 token bump 取消，
  -- 显示窗口内的连续变化不再累加为净额。
  entry.anchor_cash = prev_cash_value
  local display_delta = cash_value - prev_cash_value

  local sign = "+"
  local magnitude = display_delta
  if display_delta < 0 then
    sign = "-"
    magnitude = -display_delta
  end
  local text = sign .. number_utils.format_integer_part(magnitude)
  local token = _bump_token(entry)
  _schedule_show_cash_delta(ui, index, text, entry, token)
end

return panel_cash_delta

