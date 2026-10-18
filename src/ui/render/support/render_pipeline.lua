-- #329:三个刷新实现(board / panel presenter / turn effects)由 opts 注入,
-- support 不再静态 require 下游(拆 ui.render.support ↔ board/widgets 投影环)。
-- 缺实现的刷新分支当场报错,装配遗漏即刻暴露。
local canvas_store = require("src.ui.state.canvas_store")
local runtime_ui = require("src.ui.render.support.runtime_ui")
local ui_touch_policy = require("src.ui.input.touch")

local pipeline = {}
local _panel_opts = {}
local _effects_opts = {}

local function _flag_true(dirty, key)
  return dirty[key] == true
end

local function _has_struct_flags(dirty)
  return _flag_true(dirty, "permanent") or _flag_true(dirty, "base") or _flag_true(dirty, "board")
end

local function _has_model_flags(dirty)
  return _flag_true(dirty, "choice") or _flag_true(dirty, "effects") or _flag_true(dirty, "market")
end

local function _has_full_refresh_flags(dirty)
  return _has_struct_flags(dirty) or _has_model_flags(dirty)
end

local function _is_empty_dirty(dirty)
  if type(dirty) ~= "table" then
    return true
  end
  if _has_full_refresh_flags(dirty) then
    return false
  end
  return dirty.any ~= true
end

local function _resolve_dirty(state_ctx, opts)
  local dirty = opts and opts.dirty or nil
  if dirty then
    return dirty
  end
  return canvas_store.consume_dirty(state_ctx)
end

local function _should_refresh_panel(dirty)
  return dirty.any == true or dirty.base == true or dirty.permanent == true or dirty.choice == true or dirty.market == true
end

local function _opt_or(opts, key, fallback)
  return opts and opts[key] or fallback
end

local function _resolve_render_deps(opts)
  local panel = opts and opts.panel
  local board = opts and opts.board
  local effects = opts and opts.effects
  local refresh_item_slots = opts and opts.refresh_item_slots
  local runtime = _opt_or(opts, "runtime", runtime_ui)
  local ui_touch = _opt_or(opts, "ui_touch_policy", ui_touch_policy)
  return panel, board, effects, runtime, refresh_item_slots, ui_touch
end

local function _should_refresh_board(dirty)
  return dirty.any == true or dirty.board == true or dirty.base == true
end

local function _should_refresh_effects(dirty)
  return dirty.any == true or dirty.effects == true or dirty.base == true
end

function pipeline.render(state_ctx, ui_model, log_once, build_log_prefix, opts)
  local dirty = _resolve_dirty(state_ctx, opts)
  if _is_empty_dirty(dirty) then
    dirty.any = true
  end

  local panel, board, effects, runtime, refresh_item_slots, ui_touch = _resolve_render_deps(opts)
  if _should_refresh_panel(dirty) then
    assert(panel ~= nil, "render_pipeline: missing opts.panel implementation")
    _panel_opts.runtime = runtime
    _panel_opts.refresh_item_slots = refresh_item_slots
    _panel_opts.ui_touch_policy = ui_touch
    panel.refresh(state_ctx, ui_model, _panel_opts)
  end
  if _should_refresh_board(dirty) then
    assert(board ~= nil, "render_pipeline: missing opts.board implementation")
    board.refresh(state_ctx, ui_model, log_once, build_log_prefix)
  end
  if _should_refresh_effects(dirty) then
    assert(effects ~= nil, "render_pipeline: missing opts.effects implementation")
    _effects_opts.runtime = runtime
    effects.sync(state_ctx, ui_model, _effects_opts)
  end
end

return pipeline

