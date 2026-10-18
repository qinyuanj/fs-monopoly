-- Transient turn-state predicates for the 3D player-status overlay: detect
-- whether a player has a pending roadblock trigger, just stopped on a roadblock,
-- or is detained on the current frozen turn. Pure boolean queries over
-- game/turn state, consumed by src.ui.render.status3d.status_resolve.
local M = {}

local function _is_roadblock_trigger_for_player(anim, player_id)
  return anim
      and anim.kind == "roadblock_trigger"
      and anim.player_id == player_id
end

local function _queued_roadblock_trigger_for_player(queue, player_id)
  if type(queue) ~= "table" then
    return false
  end
  for _, entry in ipairs(queue) do
    if _is_roadblock_trigger_for_player(entry, player_id) then
      return true
    end
  end
  return false
end

local function _trigger_context_ready(game, player)
  return game and game.turn and player and player.id ~= nil
end

function M.has_pending_roadblock_trigger(game, player)
  if not _trigger_context_ready(game, player) then
    return false
  end
  if _is_roadblock_trigger_for_player(game.turn.action_anim, player.id) then
    return true
  end
  return _queued_roadblock_trigger_for_player(game.turn.action_anim_queue, player.id)
end

function M.check_roadblock_status(last_turn, player)
  if not last_turn then
    return false
  end
  if last_turn.player_id ~= player.id then
    return false
  end
  local move_result = last_turn.move_result
  return move_result ~= nil and move_result.stopped_on_roadblock == true
end

local function _has_detention_wait(turn)
  if not turn then
    return false
  end
  local notice_active = turn.no_action_notice_active == true
  local detained_active = turn.detained_wait_active == true or turn.phase == "detained_wait"
  return notice_active or detained_active, notice_active
end

local function _last_turn_matches_player(last_turn, player)
  return last_turn
      and last_turn.player_id == player.id
      and last_turn.skipped == true
      and last_turn.stay_turns ~= nil
end

local function _notice_matches_player(turn, player, notice_active)
  return not notice_active or turn.no_action_notice_player_id == player.id
end

function M.is_player_detained_this_turn(game, player)
  if game == nil or player == nil then
    return false
  end
  local wait_active, notice_active = _has_detention_wait(game.turn)
  if not wait_active then
    return false
  end
  if not _last_turn_matches_player(game.last_turn, player) then
    return false
  end
  return _notice_matches_player(game.turn, player, notice_active)
end

return M

