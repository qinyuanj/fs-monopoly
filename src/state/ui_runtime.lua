-- state.ui_runtime 切片:UI 模型、pending choice 与 modal 计时。
-- 原 src/state/runtime.lua 的 ui 块;公共面仍由 runtime.lua 门面转发,调用方不变。
local tables = require("src.foundation.tables")

local M = {}

function M.ensure(state)
  assert(type(state) == "table", "missing state")
  local ui_runtime = tables.ensure_table_field(state, "ui_runtime")
  tables.ensure_field(ui_runtime, "ui_dirty", false)
  tables.ensure_field(ui_runtime, "ui_model", nil)
  tables.ensure_field(ui_runtime, "pending_choice", nil)
  tables.ensure_field(ui_runtime, "pending_choice_elapsed", 0)
  tables.ensure_field(ui_runtime, "pending_choice_id", nil)
  tables.ensure_field(ui_runtime, "ui_modal_elapsed", 0)
  tables.ensure_field(ui_runtime, "ui_modal_ref", nil)
  if ui_runtime.item_name_by_id == nil then
    ui_runtime.item_name_by_id = state.item_name_by_id or {}
  end
  return ui_runtime
end

local function _getter(field)
  return function(state)
    return M.ensure(state)[field]
  end
end

local function _setter(field)
  return function(state, value)
    local ui_runtime = M.ensure(state)
    ui_runtime[field] = value
    return value
  end
end

function M.is_ui_dirty(state)
  return M.ensure(state).ui_dirty == true
end

function M.set_ui_dirty(state, dirty)
  local ui_runtime = M.ensure(state)
  ui_runtime.ui_dirty = dirty == true
  return ui_runtime.ui_dirty
end

M.get_ui_model = _getter("ui_model")
M.set_ui_model = _setter("ui_model")
M.get_pending_choice = _getter("pending_choice")
M.get_pending_choice_id = _getter("pending_choice_id")
M.set_pending_choice_id = _setter("pending_choice_id")

M.get_pending_choice_elapsed = _getter("pending_choice_elapsed")

function M.set_pending_choice_elapsed(state, elapsed_seconds)
  local ui_runtime = M.ensure(state)
  local next_elapsed = elapsed_seconds or 0
  ui_runtime.pending_choice_elapsed = next_elapsed
  return next_elapsed
end

function M.set_pending_choice(state, choice, opts)
  local ui_runtime = M.ensure(state)
  opts = opts or {}
  local choice_id = opts.choice_id
  if choice_id == nil and choice ~= nil then
    choice_id = choice.id
  end
  local elapsed_seconds = opts.elapsed_seconds
  if elapsed_seconds == nil then
    elapsed_seconds = 0
  end
  ui_runtime.pending_choice = choice
  ui_runtime.pending_choice_id = choice_id
  ui_runtime.pending_choice_elapsed = elapsed_seconds
  return choice
end

M.get_modal_elapsed = _getter("ui_modal_elapsed")

function M.get_modal_ref(state)
  local ui_runtime = M.ensure(state)
  return ui_runtime.ui_modal_ref
end

function M.set_modal_timer(state, payload)
  local ui_runtime = M.ensure(state)
  payload = payload or {}
  local elapsed_seconds = payload.elapsed_seconds or 0
  local ref = payload.ref
  ui_runtime.ui_modal_elapsed = elapsed_seconds
  ui_runtime.ui_modal_ref = ref
  return ref, elapsed_seconds
end

return M

