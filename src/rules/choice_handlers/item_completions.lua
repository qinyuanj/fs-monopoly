local item_phase = require("src.rules.items.phase")
local normalize = require("src.rules.choice_handlers.item_normalize")

local completions = {}

function completions.build(helpers)
  local finish_choice = helpers.finish_choice
  local finish_active_item_phase = helpers.finish_active_item_phase

  local function _resolve_phase_completion(game, player, meta, result)
    return item_phase.resolve_completion(game, player, meta, result)
  end

  -- 道具 completion 收尾后「这扇窗该不该清」的唯一裁决点。原先 item_phase_handlers
  -- 的 _keeps_choice_open/_finish_unless_open 与本模块的 _clear_unless_open 各写了
  -- 一份同款判定(直用道具一份、跟随选择道具一份),两处逐字重复 —— 正是残留能藏住的
  -- 土壤(5ce62507:跟随选择道具作为阶段最后一张牌用掉时,少清一次就把 choice 门控
  -- 带进下一位玩家的回合)。二者收敛到此。
  --
  -- completion 重开了道具窗口(reopened)或原地等待(stay)时,pending_choice 是那个
  -- 要继续用的窗口,不能动;否则 pending_choice 还是刚结算掉的那扇窗,必须清。
  -- completion 为 nil 时不在这里兜底:resolver._build_resolve_result 是 resolve
  -- 结果的唯一兜底点,这里再补一个就又是两个 owner。
  local function _settle_choice_window(game, completion)
    if completion ~= nil and (completion.stay == true or completion.reopened == true) then
      return completion
    end
    finish_choice(game, false)
    return completion
  end

  local function _resolve_followup_completion(game, choice, player, result)
    local meta = choice.meta or {}
    if normalize.is_repeatable_phase_meta(meta) then
      return _settle_choice_window(game, item_phase.resolve_completion(game, player, meta, result))
    end
    finish_active_item_phase(game)
    return normalize.merge_after_action_anim(result, finish_choice(game, false))
  end

  local function _meta_of(choice)
    return choice and choice.meta or nil
  end

  local function _resolve_followup_cancel(game, choice)
    local meta = _meta_of(choice)
    if normalize.is_repeatable_phase_meta(meta) then
      local player = normalize.validate_item_player(game, choice.kind, meta)
      local open_opts = {
        elapsed_seconds = game.turn.choice_elapsed_seconds or 0,
      }
      if item_phase.reopen_or_finish(game, player, meta, open_opts) then
        return { stay = true }
      end
      return nil
    end
    finish_active_item_phase(game)
    return nil
  end

  return {
    phase_completion = _resolve_phase_completion,
    followup_completion = _resolve_followup_completion,
    followup_cancel = _resolve_followup_cancel,
    settle_choice_window = _settle_choice_window,
  }
end

function completions.item_target_handler(kind, execute_fn, complete, opts)
  opts = opts or {}
  return {
    required_meta = { "player_id", "item_id" },
    cancel = {
      resolve = function(game, choice)
        return complete.followup_cancel(game, choice)
      end,
    },
    normalize_meta = opts.normalize_meta or normalize.item_target_meta,
    meta_validator = opts.meta_validator or normalize.validate_item_owner_meta,
    normalize_action = function(_, _, action)
      return normalize.choice_action_option_id(kind, action)
    end,
    execute = execute_fn,
  }
end

return completions

