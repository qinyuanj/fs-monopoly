local item_phase = require("src.rules.items.phase")
local intent_output_port = require("src.rules.ports.intent_output")
local completions = require("src.rules.choice_handlers.item_completions")
local normalize = require("src.rules.choice_handlers.item_normalize")

local phase_handlers = {}

local function _decorate_phase_followup(choice_spec, meta, item_id, player)
  choice_spec.meta = choice_spec.meta or {}
  choice_spec.meta.item_id = choice_spec.meta.item_id or item_id
  choice_spec.meta.player_id = choice_spec.meta.player_id or player.id
  choice_spec.meta.passive_origin = true
  item_phase.decorate_followup_choice_spec(choice_spec, meta)
end

local function _handle_passive_waiting_result(game, result, meta, player, item_id)
  local intent = result.intent or {}
  local choice_spec = intent.choice_spec
  if type(choice_spec) == "table" then
    _decorate_phase_followup(choice_spec, meta, item_id, player)
  end
  intent_output_port.dispatch(game, intent)
  return { stay = true }
end

local function _item_phase_handler(kind, execute_fn)
  return {
    required_meta = { "player_id", "phase" },
    cancel = {
      resolve = function(game, choice)
        item_phase.finish(game, choice.meta and choice.meta.phase or nil)
      end,
    },
    normalize_meta = normalize.item_phase_meta,
    meta_validator = normalize.validate_item_phase_meta,
    normalize_action = function(_, _, action)
      return normalize.choice_action_option_id(kind, action)
    end,
    execute = execute_fn,
  }
end

function phase_handlers.build(helpers)
  local complete = completions.build(helpers)
  local begin_item_use = assert(helpers.begin_item_use, "missing begin_item_use helper")

  -- 「completion 收尾后这扇窗该不该清」只有一个裁决点:item_completions
  -- .settle_choice_window。直用道具与跟随选择道具走同一份判定。
  local settle_choice_window = complete.settle_choice_window

  local function _handle_item_phase_passive(game, choice, action)
    local meta = choice.meta
    local player = normalize.validate_item_player(game, choice.kind, meta)
    local item_id = action.option_id

    local result = begin_item_use(game, player, item_id, { phase = meta.phase })
    assert(result ~= nil, "missing use_item result")
    if type(result) == "table" and result.waiting then
      return _handle_passive_waiting_result(game, result, meta, player, item_id)
    end

    return settle_choice_window(game, item_phase.resolve_completion(game, player, meta, result))
  end

  return {
    item_phase_passive = _item_phase_handler("item_phase_passive", _handle_item_phase_passive),
  }
end

return phase_handlers

