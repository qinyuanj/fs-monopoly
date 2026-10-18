-- 道具 offer 阶段窗口判定(自 availability 拆出):策划案 offer_in_phases 窗口的
-- 解析、阶段命中与自动考虑资格。纯查询,无状态。
local inventory = require("src.rules.items.inventory")
local tables = require("src.foundation.tables")

local offer_window = {}

local phase_timing = {
  pre_action = { pre_action = true, turn = true },
  pre_move = { pre_move = true, turn = true },
  post_action = { post_action = true, turn = true },
}

function offer_window.resolve_offer_in_phases(_item_id, cfg)
  if type(cfg) ~= "table" then
    return nil
  end
  if type(cfg.offer_in_phases) == "table" and #cfg.offer_in_phases > 0 then
    return cfg.offer_in_phases
  end
  return nil
end

local function _offer_phase_allowed(offer_in_phases, phase, allow_missing_phase)
  if type(offer_in_phases) ~= "table" or #offer_in_phases == 0 then
    return false
  end
  if not phase then
    return allow_missing_phase
  end
  return tables.contains(offer_in_phases, phase)
end

function offer_window.trigger_timing_allowed(phase, timing, allow_missing_phase)
  if not phase then
    return allow_missing_phase
  end
  local allowed = phase_timing[phase]
  if not allowed or not timing then
    return false
  end
  return allowed[timing] == true
end

function offer_window.allowed(item_id, cfg, phase, allow_missing_phase)
  local offer_in_phases = offer_window.resolve_offer_in_phases(item_id, cfg)
  return _offer_phase_allowed(offer_in_phases, phase, allow_missing_phase)
end

function offer_window.can_auto_consider_item(item_id, phase, cfg)
  local item_cfg = cfg or inventory.cfg(item_id)
  if not item_cfg then
    return false
  end
  return offer_window.allowed(item_id, item_cfg, phase, true)
end

return offer_window

