-- 是否展示/调试日志、tip 文案构造、请求装配与入队,全部与时长/派发链解耦。
local number_utils = require("src.foundation.number")
local logger = require("src.foundation.log")
local handlers = require("src.ui.render.anim.handlers")

local tip_chain = {}

local user_tip_whitelist = {
  monster = true,
  missile = true,
  item_target_player = true,
  teleport_effect = true,
  clear_obstacles = true,
}

local function _should_debug_log(anim)
  return anim
    and anim.kind ~= "roll"
    and logger.is_anim_debug_enabled()
    or false
end

local function _should_show_tip(anim)
  if not anim or anim.kind == "roll" then
    return false
  end
  if anim.tip_policy == "user" then
    return true
  end
  return user_tip_whitelist[anim.kind] == true
end

local function _to_fixed_duration(duration)
  local ok, as_fixed = pcall(math.tofixed, duration)
  if ok and as_fixed ~= nil then
    return as_fixed
  end
  return duration
end

local function _resolve_tip_duration(duration)
  if number_utils.is_numeric(duration) and math and math.tofixed then
    return _to_fixed_duration(duration)
  end
  return duration
end

local function _resolve_tip_text(state, anim)
  local should_show_tip = _should_show_tip(anim)
  local should_debug_log = _should_debug_log(anim)
  local tip_text = nil
  if should_show_tip or should_debug_log then
    tip_text = handlers.build_tip(state, anim)
  end
  return tip_text, should_show_tip, should_debug_log
end

local function _tip_request_field(anim, key)
  return anim and anim[key] or nil
end

local function _anim_kind(anim)
  return anim and anim.kind or nil
end

-- tip 的 source:显式 tip_source 优先,缺省时按 kind 组 action_anim.* 名。
local function _tip_source(anim)
  local source = anim and anim.tip_source or nil
  if source ~= nil then
    return source
  end
  return "action_anim." .. tostring(_anim_kind(anim) or "tip")
end

local function _build_tip_request(anim, tip_text, tip_duration)
  return {
    text = tip_text,
    duration = tip_duration,
    dedupe_key = _tip_request_field(anim, "dedupe_key"),
    blocks_inter_turn = anim and anim.blocks_inter_turn == true or false,
    source = _tip_source(anim),
    chain_key = _tip_request_field(anim, "chain_key"),
  }
end

local function _enqueue_tip_text(host_runtime, anim, tip_text, tip_duration)
  if not host_runtime then
    return
  end
  host_runtime.enqueue_tip(_build_tip_request(anim, tip_text, tip_duration))
end

local function _log_tip_debug(should_debug_log, has_tip, tip_text)
  if should_debug_log and has_tip then
    logger.info_unlimited("[ActionAnim]", tip_text)
  end
end

local function _emit_tip_text(host_runtime, anim, tip_text, should_show_tip, should_debug_log, tip_duration)
  local has_tip = tip_text ~= nil and tip_text ~= ""
  _log_tip_debug(should_debug_log, has_tip, tip_text)
  if should_show_tip and has_tip then
    _enqueue_tip_text(host_runtime, anim, tip_text, tip_duration)
  end
end

-- 播放期 tip 全链:时长定稿 → 文案/展示判定 → 调试日志 → 入队。
function tip_chain.emit(state, anim, host_runtime, duration)
  local tip_duration = _resolve_tip_duration(duration)
  local tip_text, should_show_tip, should_debug_log = _resolve_tip_text(state, anim)
  _emit_tip_text(host_runtime, anim, tip_text, should_show_tip, should_debug_log, tip_duration)
end

return tip_chain

