local control = require("src.player.control")

local decision_engine = {}

local function _first_option_id(options)
  if not options or #options == 0 then
    return nil
  end
  return options[1].id or options[1]
end

local function _choice_owner(game, choice)
  local meta = choice.meta or {}
  if meta.player_id and game.find_player_by_id then
    local player = game:find_player_by_id(meta.player_id)
    if player then
      return player
    end
  end
  return game:current_player()
end

local function _build_choice_action(choice, actor, option_id, action_type)
  return {
    type = action_type or "choice_select",
    choice_id = choice.id,
    option_id = option_id,
    actor_role_id = actor.id,
  }
end

local function _find_preferred(options, preferred_id)
  for _, opt in ipairs(options or {}) do
    local option_id = opt.id or opt
    if option_id == preferred_id then
      return option_id
    end
  end
  return nil
end

local function _resolve_target_option(options, preferred_ids)
  for _, preferred_id in ipairs(preferred_ids) do
    local found = _find_preferred(options, preferred_id)
    if found ~= nil then
      return found
    end
  end
  return _first_option_id(options)
end

local function _board_target_resolver(agent_ref, kind)
  return kind == "roadblock_target" and agent_ref.pick_roadblock_target or agent_ref.pick_demolish_target
end

-- build returns auto_action_for_choice bound to the given agent_ref table.
-- agent_ref must expose: pick_remote_dice_value, pick_roadblock_target,
-- pick_demolish_target, pick_target_player (looked up at call time to allow patching).
function decision_engine.build(agent_ref)
  local function _handle_remote_dice_choice(game, actor, choice)
    local dice_count = choice.meta.dice_count
    local value = agent_ref.pick_remote_dice_value(game, actor, dice_count)
    return _build_choice_action(choice, actor, value or _first_option_id(choice.options))
  end

  local function _handle_board_target_choice(game, actor, choice)
    local resolver = _board_target_resolver(agent_ref, choice.kind)
    local option_id = choice.kind == "roadblock_target"
      and resolver(game, actor)
      or resolver(game, actor, 3)
    -- #105:pick 非 nil 但不在 choice 选项内会被结算拒绝、choice 卡 pending
    -- 死锁,与 pick 为 nil 一样回退到第一个 UI 选项。
    if option_id ~= nil and _find_preferred(choice.options, option_id) == nil then
      option_id = nil
    end
    return _build_choice_action(choice, actor, option_id or _first_option_id(choice.options))
  end

  local function _handle_target_player_choice(game, actor, choice)
    local target = agent_ref.pick_target_player(game, actor, choice.meta.item_id, choice.options)
    if target then
      return _build_choice_action(choice, actor, target.id)
    end
    return _build_choice_action(choice, actor, nil, "choice_cancel")
  end

  local function _handle_landing_optional_effect(game, actor, choice)
    local _ = game
    local target = _resolve_target_option(choice.options or {}, { "buy_land", "upgrade_land" })
    if target then
      return _build_choice_action(choice, actor, target)
    end
    return _build_choice_action(choice, actor, nil, "choice_cancel")
  end

  local function _handle_card_prompt_choice(game, actor, choice)
    local _ = game
    return _build_choice_action(choice, actor, "use")
  end

  local function _handle_cancel_choice(game, actor, choice)
    local _ = game
    return _build_choice_action(choice, actor, nil, "choice_cancel")
  end

  -- Every handler takes (game, actor, choice); kinds absent here get no auto action.
  local _handlers_by_kind = {
    remote_dice_value = _handle_remote_dice_choice,
    roadblock_target = _handle_board_target_choice,
    demolish_target = _handle_board_target_choice,
    item_target_player = _handle_target_player_choice,
    rent_card_prompt = _handle_card_prompt_choice,
    tax_card_prompt = _handle_card_prompt_choice,
    landing_optional_effect = _handle_landing_optional_effect,
    item_phase_passive = _handle_cancel_choice,
    market_buy = _handle_cancel_choice,
  }

  return function(game, choice)
    local actor = _choice_owner(game, choice)
    if not control.is_computer_controlled(actor) then
      return nil
    end
    local handler = _handlers_by_kind[choice.kind]
    if handler == nil then
      return nil
    end
    return handler(game, actor, choice)
  end
end

return decision_engine

