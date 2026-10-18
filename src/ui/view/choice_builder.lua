local choice_contract = require("src.config.choice.contract")

local choice = {}

local function _copy_option_view(opt, label)
  local view = {
    label = label,
    id = opt.id or opt,
    raw = opt,
  }
  if type(opt) ~= "table" then
    return view
  end
  view.can_buy = opt.can_buy
  view.sold_out = opt.sold_out
  view.requires_pre_confirm = opt.requires_pre_confirm == true
  view.pre_confirm_kind = opt.pre_confirm_kind
  view.confirm_title = opt.confirm_title
  view.confirm_body = opt.confirm_body
  return view
end

local function _join_lines(lines)
  assert(lines ~= nil, "missing body lines")
  return table.concat(lines, "\n")
end

local function _default_option_label(opt)
  assert(opt ~= nil, "missing option")
  if opt.label then
    return opt.label
  end
  local id = opt.id
  if type(id) ~= "nil" then
    return tostring(id)
  end
  return tostring(opt)
end

local function _resolve_choice_body(pending, opts)
  if pending.body_lines then
    return _join_lines(pending.body_lines)
  end
  if not opts.body_lines_only and pending.body then
    return pending.body
  end
  return ""
end

local function _build_options(pending, option_label)
  local options = {}
  for _, opt in ipairs(pending.options or {}) do
    local label = option_label(opt)
    assert(label ~= nil, "missing option label")
    options[#options + 1] = _copy_option_view(opt, label)
  end
  return options
end

local function _assemble_view(pending, title, body, options)
  local view = {
    id = pending.id,
    kind = pending.kind,
    title = title,
    body = body,
    options = options,
    meta = pending.meta,
    cancel_label = pending.cancel_label or "取消",
    allow_cancel = pending.allow_cancel ~= false,
  }
  choice_contract.copy_explicit_fields(pending, view)
  return view
end

function choice.build_choice_view(pending, opts)
  assert(pending ~= nil, "missing pending choice")
  opts = opts or {}
  local option_label = opts.option_label or _default_option_label
  local title = pending.title or "请选择"
  local body = _resolve_choice_body(pending, opts)
  local options = _build_options(pending, option_label)
  return _assemble_view(pending, title, body, options)
end

return choice

