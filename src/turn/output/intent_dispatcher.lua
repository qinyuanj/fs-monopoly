local monopoly_event = require("src.foundation.events")
local choice_contract = require("src.config.choice.contract")
local choice_route_policy = require("src.config.choice.route_policy")
local event_kinds = require("src.config.gameplay.event_kinds")
local event_feed = require("src.rules.ports.event_feed")
local dirty_tracker = require("src.state.dirty_tracker")
local choice_meta_validator = require("src.turn.output.choice_meta_validator")

local intent_dispatcher = {}

local function _build_choice_log_text(title, body_lines)
  local text = "等待选择：" .. tostring(title or "请选择")
  if type(body_lines) == "table" then
    local first_line = body_lines[1]
    if type(first_line) == "string" and first_line ~= "" then
      text = text .. "：" .. first_line
    end
  end
  return text
end


local function _choice_labels(choice_spec)
  return choice_spec.title or "请选择", choice_spec.cancel_label or "取消"
end

local function _build_choice_entry(choice_id, choice_spec)
  local title, cancel_label = _choice_labels(choice_spec)
  local entry = {
    id = choice_id,
    kind = choice_spec.kind,
    title = title,
    body_lines = choice_spec.body_lines or {},
    options = choice_spec.options or {},
    allow_cancel = choice_spec.allow_cancel ~= false,
    cancel_label = cancel_label,
    meta = choice_spec.meta,
  }
  choice_contract.copy_explicit_fields(choice_spec, entry)
  entry.route_key = choice_route_policy.resolve(choice_spec)
  entry.requires_confirm = choice_route_policy.requires_confirm(choice_spec) == true
  return entry
end

function intent_dispatcher.open_choice(game, choice_spec, opts)
  assert(game and game.turn, "Choice.open requires game.turn")
  assert(choice_spec ~= nil, "missing choice_spec")
  choice_meta_validator.validate(game, choice_spec)

  local seq = game.turn.choice_seq or 0
  seq = seq + 1
  game.turn.choice_seq = seq

  local entry = _build_choice_entry(seq, choice_spec)
  game.turn.pending_choice = entry
  dirty_tracker.mark(game.dirty, "turn")
  event_feed.publish(game, {
    kind = event_kinds.choice_picked,
    text = _build_choice_log_text(entry.title, entry.body_lines),
    tip = false,
  })
  local elapsed_seconds = opts and opts.elapsed_seconds or 0
  monopoly_event.emit_intent("need_choice", {
    choice = entry,
    choice_spec = choice_spec,
    elapsed_seconds = elapsed_seconds,
  })
  return entry
end

local function _resolve_popup_port(game)
  local popup_port = game and game.popup_port or nil
  assert(popup_port ~= nil, "missing popup_port")
  assert(popup_port.push_popup ~= nil, "missing popup_port.push_popup")
  return popup_port
end

function intent_dispatcher.push_popup(game, payload, opts)
  assert(payload ~= nil, "missing popup payload")
  opts = opts or {}
  local popup_port = _resolve_popup_port(game)
  popup_port:push_popup(payload, opts)
  monopoly_event.emit_intent("push_popup", { payload = payload })
  return true
end

local function _resolve_intent(payload)
  local intent = payload.intent or payload
  if not intent or type(intent) ~= "table" then
    return nil
  end
  return intent
end

local function _dispatch_push_popup(game, intent)
  local popup_opts = intent.popup_opts or intent.opts or nil
  return intent_dispatcher.push_popup(game, intent.payload, popup_opts)
end

local function _intent_matches(intent, kind, payload_key)
  return intent.kind == kind and intent[payload_key]
end

function intent_dispatcher.dispatch(game, payload)
  assert(payload ~= nil, "missing payload")
  local intent = _resolve_intent(payload)
  if intent == nil then
    return nil
  end

  if _intent_matches(intent, "need_choice", "choice_spec") then
    return intent_dispatcher.open_choice(game, intent.choice_spec)
  end

  if _intent_matches(intent, "push_popup", "payload") then
    return _dispatch_push_popup(game, intent)
  end

  return nil
end

function intent_dispatcher.build_port()
  return {
    open_choice = intent_dispatcher.open_choice,
    push_popup = intent_dispatcher.push_popup,
  }
end

return intent_dispatcher

