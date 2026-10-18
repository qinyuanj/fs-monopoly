local base_nodes = require("src.ui.schema.base")
local role_id_utils = require("src.foundation.identity")
local with_client_role = require("src.ui.render.support.with_client_role")
local runtime_ui = require("src.ui.render.support.runtime_ui")

local turn_effects = {}

local function _find_player_index(players, current_id)
  for index, player in ipairs(players) do
    if player and role_id_utils.equals(player.id, current_id) then
      return index
    end
  end
  return nil
end

local function _model_board(ui_model)
  return ui_model and ui_model.board or nil
end

local function _board_players(board)
  return board and board.players or nil
end

local function _current_player_id(ui_model)
  return role_id_utils.normalize(ui_model and ui_model.current_player_id or nil)
end

local function _resolve_current_player_index(ui_model)
  local players = _board_players(_model_board(ui_model))
  local current_id = _current_player_id(ui_model)
  if not (players and current_id) then
    return nil
  end
  return _find_player_index(players, current_id)
end

local function _set_node_visible(node, visible)
  if not node then
    return
  end
  node.visible = visible == true
end

local function _set_highlight_visible(runtime, index)
  for i, name in ipairs(base_nodes.player_action_effects) do
    local node = runtime.query_node(name)
    _set_node_visible(node, index ~= nil and i == index)
  end
end

local _hl_runtime
local _hl_ui_model

local function _highlight_callback()
  local current_index = _resolve_current_player_index(_hl_ui_model)
  _set_highlight_visible(_hl_runtime, current_index)
end

local function _sync_current_turn_highlight(runtime, _, ui_model)
  _hl_runtime = runtime
  _hl_ui_model = ui_model
  with_client_role(runtime, nil, _highlight_callback)
end

local function _get_role_id(runtime, role)
  return role_id_utils.normalize(runtime.resolve_role_id(role))
end

local _prompt_nodes = {}

local function _get_prompt_nodes(runtime)
  _prompt_nodes.star = runtime.query_node(base_nodes.action_hint_effect)
  _prompt_nodes.label = runtime.query_node(base_nodes.action_hint)
  return _prompt_nodes
end

local function _set_prompt_visible(nodes, visible)
  _set_node_visible(nodes.star, visible)
  _set_node_visible(nodes.label, visible)
  if nodes.star then
    nodes.star.disabled = true
  end
  if nodes.label then
    nodes.label.disabled = true
  end
end

local function _is_turn_prompt_phase(phase)
  return phase == "wait_action"
end

local _ltp_runtime
local _ltp_current_player_id
local _ltp_can_show
local _ltp_role_id

local function _local_turn_prompt_inner()
  local nodes = _get_prompt_nodes(_ltp_runtime)
  local show = _ltp_role_id ~= nil and _ltp_current_player_id ~= nil
    and role_id_utils.equals(_ltp_role_id, _ltp_current_player_id) and _ltp_can_show
  _set_prompt_visible(nodes, show)
end

local function _local_turn_prompt_outer(role)
  _ltp_role_id = _get_role_id(_ltp_runtime, role)
  with_client_role(_ltp_runtime, role, _local_turn_prompt_inner)
end

local function _board_phase(board)
  return board and board.phase or nil
end

local function _sync_local_turn_prompt(runtime, _, ui_model)
  local phase = _board_phase(_model_board(ui_model))
  _ltp_runtime = runtime
  _ltp_current_player_id = _current_player_id(ui_model)
  _ltp_can_show = _is_turn_prompt_phase(phase)
  runtime.for_each_role_or_global(_local_turn_prompt_outer)
end

local _oap_runtime
local _oap_text
local _oap_visible

local function _other_action_prompt_callback()
  local node = _oap_runtime.query_node(base_nodes.other_player_hint)
  if node then
    node.text = _oap_text or ""
    node.visible = _oap_visible == true
  end
end

local function _set_other_action_prompt(runtime, role, text, visible)
  _oap_runtime = runtime
  _oap_text = text
  _oap_visible = visible
  with_client_role(runtime, role, _other_action_prompt_callback)
end

local _cached_prompt_name
local _cached_prompt_text

local function _current_player_name(ui_model)
  return ui_model and ui_model.current_player_name or nil
end

local function _resolve_other_action_prompt_text(ui_model)
  local current_player_name = _current_player_name(ui_model)
  if type(current_player_name) == "string" and current_player_name ~= "" then
    if current_player_name ~= _cached_prompt_name then
      _cached_prompt_name = current_player_name
      _cached_prompt_text = current_player_name .. "正在行动"
    end
    return _cached_prompt_text
  end
  return "其他玩家正在行动"
end

local _soap_runtime
local _soap_current_player_id
local _soap_prompt_text

local function _other_player_action_callback(role)
  local role_id = _get_role_id(_soap_runtime, role)
  local show = role_id ~= nil
    and _soap_current_player_id ~= nil
    and not role_id_utils.equals(role_id, _soap_current_player_id)
  if show then
    _set_other_action_prompt(_soap_runtime, role, _soap_prompt_text, true)
  else
    _set_other_action_prompt(_soap_runtime, role, "", false)
  end
end

local function _sync_other_player_action_prompt(runtime, _, ui_model)
  _soap_current_player_id = role_id_utils.normalize(ui_model and ui_model.current_player_id or nil)
  _soap_prompt_text = _resolve_other_action_prompt_text(ui_model)
  _soap_runtime = runtime
  runtime.for_each_role_or_global(_other_player_action_callback)
end

local function _presentation_runtime(state)
  return state and state.presentation_runtime and state.presentation_runtime.runtime or nil
end

local function _resolve_runtime(state, deps)
  return deps and deps.runtime or _presentation_runtime(state) or runtime_ui
end

function turn_effects.sync(state, ui_model, deps)
  local runtime = _resolve_runtime(state, deps)
  assert(runtime, "missing deps.runtime")
  _sync_current_turn_highlight(runtime, state, ui_model)
  _sync_local_turn_prompt(runtime, state, ui_model)
  _sync_other_player_action_prompt(runtime, state, ui_model)
  if type(runtime.set_client_role) == "function" then
    runtime.set_client_role(nil)
  end
end

return turn_effects

