local panel_view = require("src.ui.view.panel_builder")
local role_id_utils = require("src.foundation.identity")
local tables = require("src.foundation.tables")

local panel_slice = {}

local function _resolve_no_action_notice(turn)
  if not turn then
    return false, "本回合无法行动"
  end
  local visible = turn.no_action_notice_active == true or turn.detained_wait_active == true
  local text = turn.no_action_notice_text or "本回合无法行动"
  return visible, text
end

local _auto_labels = {}

local function _normalized_player_id(player)
  return role_id_utils.normalize(player and player.id or nil)
end

local function _build_auto_label_by_player(players, enabled_by_player)
  tables.clear(_auto_labels)
  for _, player in ipairs(players or {}) do
    local player_id = _normalized_player_id(player)
    if player_id then
      local enabled = role_id_utils.read(enabled_by_player, player_id) == true
      role_id_utils.write(_auto_labels, player_id, panel_view.build_auto_label(enabled))
    end
  end
  return _auto_labels
end

local function _resolve_countdown_visible(turn)
  return turn and turn.countdown_active == true or false
end

function panel_slice.build(game, env, turn, current_player_id, delegated_by_player)
  local auto_label_by_player = _build_auto_label_by_player(game.players, delegated_by_player)
  local normalized_current_player_id = role_id_utils.normalize(current_player_id)
  local no_action_visible, no_action_text = _resolve_no_action_notice(turn)
  return {
    turn_label = panel_view.build_turn_label(
      turn.turn_count,
      turn.countdown_seconds or 0
    ),
    player_rows = panel_view.build_player_statuses(game, env.game, 4),
    auto_label_by_player = auto_label_by_player,
    auto_label = role_id_utils.read(auto_label_by_player, normalized_current_player_id) or panel_view.build_auto_label(false),
    countdown_visible = _resolve_countdown_visible(turn),
    no_action_visible = no_action_visible,
    no_action_text = no_action_text,
  }
end

local function _update_turn_label(panel, turn)
  panel.turn_label = panel_view.build_turn_label(
    turn.turn_count,
    turn.countdown_seconds or 0
  )
  panel.countdown_visible = _resolve_countdown_visible(turn)
end

local function _update_player_rows(panel, game, env)
  panel.player_rows = panel_view.build_player_statuses(game, env.game, 4)
end

local function _update_auto_labels(panel, game, current_player_id, delegated_by_player)
  local normalized_current_player_id = role_id_utils.normalize(current_player_id)
  panel.auto_label_by_player = _build_auto_label_by_player(game.players, delegated_by_player)
  panel.auto_label = role_id_utils.read(panel.auto_label_by_player, normalized_current_player_id)
    or panel_view.build_auto_label(false)
end

local function _update_no_action_notice(panel, turn)
  local no_action_visible, no_action_text = _resolve_no_action_notice(turn)
  panel.no_action_visible = no_action_visible
  panel.no_action_text = no_action_text
end

local function _update_flagged_rows(panel, game, env, current_player_id, delegated_by_player, flags)
  if flags.player_rows then
    _update_player_rows(panel, game, env)
  end
  if flags.auto_label then
    _update_auto_labels(panel, game, current_player_id, delegated_by_player)
  end
end

-- turn_label 这个 flag 同时驱动回合标签与「无法行动」提示两段更新，中间隔着
-- player_rows / auto_label，顺序按原样保留。
function panel_slice.update(panel, game, env, turn, current_player_id, delegated_by_player, flags)
  panel = panel or {}
  flags = flags or {}
  if flags.turn_label then
    _update_turn_label(panel, turn)
  end
  _update_flagged_rows(panel, game, env, current_player_id, delegated_by_player, flags)
  if flags.turn_label then
    _update_no_action_notice(panel, turn)
  end
  return panel
end

return panel_slice

