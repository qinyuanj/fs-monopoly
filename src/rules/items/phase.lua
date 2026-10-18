local timing = require("src.config.gameplay.timing")
local auto_play_port = require("src.rules.ports.auto_play")
local strategy = require("src.rules.items.strategy")
local availability = require("src.rules.items.availability")
local inventory = require("src.rules.items.inventory")
local intent_output_port = require("src.rules.ports.intent_output")
local dirty_tracker = require("src.state.dirty_tracker")
local chain_args = require("src.foundation.chain_args")

local phase_module = {}

local repeatable_phases = {
  pre_action = true,
  pre_move = true,
  post_action = true,
}

local function _resolve_after_action_anim(args, res)
  return chain_args.resolve_after_action_anim(args, res, "move_followup")
end

local function _result_after_action_anim(result)
  return type(result) == "table" and result.after_action_anim or nil
end

function phase_module.is_enabled(phase)
  local queue = timing.item_phase_queue
  assert(type(queue) == "table", "invalid item_phase_queue")
  for _, name in ipairs(queue) do
    if name == phase then
      return true
    end
  end
  return false
end

function phase_module.is_repeatable(phase)
  return repeatable_phases[phase] == true
end

function phase_module.finish(game, phase)
  if type(phase) ~= "string" or phase == "" then
    game.turn.item_phase_active = ""
    return
  end
  game.turn.item_phase = game.turn.item_phase or {}
  game.turn.item_phase[phase] = { done = true }
  local active = game.turn.item_phase_active
  if active == phase then
    game.turn.item_phase_active = ""
  end
  dirty_tracker.mark(game.dirty, "turn")
end

local function _require_resume_next_state(meta)
  return assert(meta and meta.resume_next_state, "missing meta.resume_next_state")
end

function phase_module.build_wait_choice_args(meta)
  return {
    next_state = _require_resume_next_state(meta),
    next_args = meta and meta.resume_next_args or nil,
  }
end

local function _clear_finished_phase(game, phase)
  game.turn.item_phase = game.turn.item_phase or {}
  game.turn.item_phase[phase] = nil
  dirty_tracker.mark(game.dirty, "turn")
end

local function _resolve_finished_phase(game, phase_state, phase)
  if not (phase_state and phase_state.done) then
    return false
  end
  _clear_finished_phase(game, phase)
  return true
end

local function _mark_waiting_phase(game, phase)
  game.turn.item_phase_active = phase
  dirty_tracker.mark_turn(game)
end

function phase_module.mark_active(game, phase)
  game.turn.item_phase = game.turn.item_phase or {}
  game.turn.item_phase[phase] = { active = true }
  _mark_waiting_phase(game, phase)
end

local function _decorate_repeatable_cancel(choice_spec, phase)
  if phase_module.is_repeatable(phase) then
    choice_spec.allow_cancel = true
    choice_spec.cancel_label = choice_spec.cancel_label or "返回"
  end
end

function phase_module.decorate_followup_choice_spec(choice_spec, meta)
  if type(choice_spec) ~= "table" or type(meta) ~= "table" then
    return choice_spec
  end
  choice_spec.meta = choice_spec.meta or {}
  choice_spec.meta.phase = meta.phase
  choice_spec.meta.resume_next_state = meta.resume_next_state
  choice_spec.meta.resume_next_args = meta.resume_next_args
  _decorate_repeatable_cancel(choice_spec, meta.phase)
  return choice_spec
end

local function _assert_reopen_args(game, player, meta)
  assert(game ~= nil, "missing game")
  assert(player ~= nil, "missing player")
  assert(type(meta) == "table", "missing phase meta")
end

-- elapsed 缺省时保持传 nil(open_choice 用它区分「新开」与「续开」)。
local function _reopen_open_opts(opts)
  if opts.elapsed_seconds == nil then
    return nil
  end
  return { elapsed_seconds = opts.elapsed_seconds }
end

function phase_module.reopen_or_finish(game, player, meta, opts)
  _assert_reopen_args(game, player, meta)
  opts = opts or {}
  local spec = phase_module.build_passive_choice_spec(game, player, meta.phase, {
    next_state = meta.resume_next_state,
    next_args = meta.resume_next_args,
  })
  if spec == nil then
    phase_module.finish(game, meta.phase)
    return false
  end
  intent_output_port.open_choice(game, spec, _reopen_open_opts(opts))
  phase_module.mark_active(game, meta.phase)
  return true
end

-- 空/非串 phase 视为「无阶段」,completion 直接落地。
local function _completion_phase(meta)
  local phase = meta and meta.phase
  if type(phase) ~= "string" or phase == "" then
    return nil
  end
  return phase
end

local function _resolved_completion(after_action_anim)
  return { status = "resolved", stay = false, after_action_anim = after_action_anim }
end

-- 成功用卡后的续开刷新倒计时:主动用卡不是挂机,窗口时长预算按次重置。
-- followup 取消(返回)路径的续开由 item_completions 自带累计 elapsed(防反复
-- 开关刷时长),不走这里。
local function _reopen_elapsed_opts(_game)
  return { elapsed_seconds = 0 }
end

-- 重开成功后:有动画在跑就让动画收尾时回到 wait_choice,否则原地等待选择。
-- reopened 标记告诉调用方:pending_choice 已经是新开的道具窗口,谁都不许再 finish 它。
local function _reopened_completion(game, meta)
  if not game.turn.action_anim then
    return { status = "waiting", stay = true, reopened = true }
  end
  return {
    status = "resolved",
    stay = false,
    reopened = true,
    after_action_anim = {
      next_state = "wait_choice",
      next_args = phase_module.build_wait_choice_args(meta),
    },
  }
end

-- Deep-module completion entry: handles repeatable/non-repeatable phases,
-- reopen-or-finish, action-anim continuation, and elapsed preservation.
-- Callers no longer branch by phase.
-- Returns a normalized result: { status = "resolved/waiting", stay = bool, ... }.
function phase_module.resolve_completion(game, player, meta, result, _opts)
  result = result or {}
  local after_action_anim = _result_after_action_anim(result)
  local phase = _completion_phase(meta)
  if phase == nil then
    return _resolved_completion(after_action_anim)
  end
  if not phase_module.is_repeatable(phase) then
    phase_module.finish(game, phase)
    return _resolved_completion(after_action_anim)
  end

  if not phase_module.reopen_or_finish(game, player, meta, _reopen_elapsed_opts(game)) then
    return _resolved_completion(after_action_anim)
  end

  return _reopened_completion(game, meta)
end


local function _resolve_auto_phase_wait(game, phase, args, pre)
  if not (pre and pre.waiting) then
    return nil
  end
  _mark_waiting_phase(game, phase)
  return { waiting = true, next_state = args.next_state, next_args = args.next_args }
end

local function _resolve_auto_phase_action_anim(game, phase, args, pre, should_finish)
  if not game.turn.action_anim then
    return nil
  end
  local next_state, next_args = _resolve_after_action_anim(args, pre)
  if should_finish ~= false then
    phase_module.finish(game, phase)
  end
  if next_state == "move_followup" then
    game.turn.move_followup_pending = true
    dirty_tracker.mark(game.dirty, "turn")
  end
  return { waiting = true, wait_action_anim = true, next_state = next_state, next_args = next_args }
end

local function _dispatch_existing_anim(game, phase, args, pre, repeatable)
  if not repeatable then
    return _resolve_auto_phase_action_anim(game, phase, args, pre, true), false
  end
  return nil, true
end

local function _try_dispatch_animation(game, phase, args, pre, repeatable)
  if type(pre) == "table" and type(pre.after_action_anim) == "table" then
    return _resolve_auto_phase_action_anim(game, phase, args, pre, phase ~= "post_action"), false
  end
  if game.turn.action_anim then
    return _dispatch_existing_anim(game, phase, args, pre, repeatable)
  end
  if not repeatable then
    phase_module.finish(game, phase)
  end
  return nil, false
end

local function _dispatch_auto_pre_action(game, player, phase)
  local pre = strategy.auto_pre_action(game, player, phase)
  if pre then
    intent_output_port.dispatch(game, pre)
  end
  return pre
end

-- 循环耗尽后收尾:阶段落定;若途中见过动画且仍有动画在跑,挂到动画后续。
local function _finish_auto_phase(game, phase, args, saw_action_anim)
  phase_module.finish(game, phase)
  if not (saw_action_anim and game.turn.action_anim) then
    return nil
  end
  local next_state, next_args = _resolve_after_action_anim(args, {})
  return { waiting = true, wait_action_anim = true, next_state = next_state, next_args = next_args }
end

-- 单轮:auto pre 派发 → 等待判定 → 动画派发。
-- 返回 (result, saw_action_anim, cont):result 非 nil 终结整个 phase;
-- cont 为 false 且 result 为 nil 表示 pre 耗尽,跳出循环走收尾。
local function _auto_phase_round(game, player, phase, args, repeatable, saw_action_anim)
  local pre = _dispatch_auto_pre_action(game, player, phase)
  local wait_res = _resolve_auto_phase_wait(game, phase, args, pre)
  if wait_res ~= nil then
    return wait_res, saw_action_anim, false
  end
  if pre == nil then
    return nil, saw_action_anim, false
  end
  local dispatch_result, saw_anim = _try_dispatch_animation(game, phase, args, pre, repeatable)
  return dispatch_result, saw_action_anim or saw_anim, dispatch_result == nil
end

local function _run_auto_phase(game, player, phase, args)
  local repeatable = phase_module.is_repeatable(phase)
  local saw_action_anim = false
  while true do
    local result, cont
    result, saw_action_anim, cont = _auto_phase_round(game, player, phase, args, repeatable, saw_action_anim)
    if result ~= nil then
      return result
    end
    if not cont then
      break
    end
  end
  return _finish_auto_phase(game, phase, args, saw_action_anim)
end

local function _collect_if(slot_states, out, pred)
  for i = 1, 5 do
    if pred(slot_states[i]) then
      out[#out + 1] = slot_states[i]
    end
  end
end

local function _sort_slot_states(slot_states)
  local sorted = {}
  _collect_if(slot_states, sorted, function(ss) return ss.item_id ~= nil and ss.available end)
  _collect_if(slot_states, sorted, function(ss) return ss.item_id ~= nil and not ss.available end)
  _collect_if(slot_states, sorted, function(ss) return ss.item_id == nil end)
  return sorted
end

local function _build_item_alert(cfg, item_id, available)
  if not available or not cfg or cfg.prompt_style ~= "alert" then
    return false, nil
  end
  return true, (cfg.name or tostring(item_id)) .. "可用！"
end

local function _build_slot_state(game, player, item, phase)
  if type(item) ~= "table" or item.id == nil then
    return { available = false, alert = false, alert_text = nil, item_id = nil, deny_reason = nil }
  end
  local can_offer, dr = availability.can_offer_in_phase(game, player, item.id, phase)
  local available = can_offer == true
  local cfg = inventory.cfg(item.id)
  local deny_reason = nil
  if not available then deny_reason = dr end
  local alert, alert_text = _build_item_alert(cfg, item.id, available)
  return {
    available = available,
    alert = alert,
    alert_text = alert_text,
    item_id = item.id,
    deny_reason = deny_reason,
  }
end

local function _build_option_from_slot(ss)
  local cfg = inventory.cfg(ss.item_id)
  local name = cfg and cfg.name
  return {
    id = ss.item_id,
    label = name or tostring(ss.item_id),
    confirm_title = name,
    confirm_body = cfg and cfg.description,
  }
end

local function _build_slot_options(slot_states)
  local options = {}
  for _, ss in ipairs(slot_states) do
    if ss.available and ss.item_id ~= nil then
      options[#options + 1] = _build_option_from_slot(ss)
    end
  end
  return options
end

local function _run_player_phase(game, player, phase, args)
  local spec = phase_module.build_passive_choice_spec(game, player, phase, args)
  if spec == nil then
    phase_module.finish(game, phase)
    return nil
  end
  intent_output_port.open_choice(game, spec)
  phase_module.mark_active(game, phase)
  return { waiting = true, next_state = args.next_state, next_args = args.next_args }
end

function phase_module.build_passive_choice_spec(game, player, phase, args)
  assert(game ~= nil, "missing game")
  assert(player ~= nil, "missing player")
  args = args or {}

  local slot_states = {}
  local item_slots = inventory.items(player)
  for slot_index = 1, 5 do
    slot_states[slot_index] = _build_slot_state(game, player, item_slots[slot_index], phase)
  end
  slot_states = _sort_slot_states(slot_states)

  local options = _build_slot_options(slot_states)
  if #options == 0 then
    return nil
  end

  return {
    kind = "item_phase_passive",
    route_key = "item_phase_passive",
    owner_role_id = player.id,
    uses_item_slots = true,
    pre_confirm_before_slot_pick = false,
    slot_states = slot_states,
    options = options,
    allow_cancel = true,
    cancel_label = "完成",
    meta = {
      player_id = player.id,
      phase = phase,
      resume_next_state = args.next_state,
      resume_next_args = args.next_args,
    },
  }
end

function phase_module.run(turn_mgr, phase, args)
  local game = turn_mgr.game
  local player = args.player
  assert(player ~= nil, "missing player")
  if not phase_module.is_enabled(phase) then
    return nil
  end

  local item_phases = game.turn.item_phase
  local phase_state = item_phases and item_phases[phase]
  if _resolve_finished_phase(game, phase_state, phase) then
    return nil
  end

  if auto_play_port.is_computer_controlled(game, player) then
    return _run_auto_phase(game, player, phase, args)
  end

  return _run_player_phase(game, player, phase, args)
end

return phase_module

