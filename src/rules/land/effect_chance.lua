local event_kinds = require("src.config.gameplay.event_kinds")
local timing = require("src.config.gameplay.timing")
local chance_cfg = require("src.config.content.chance_cards")
local chance_resolver = require("src.rules.chance.resolver")
local presenter = require("src.rules.land.presenter")
local achievement_progress = require("src.rules.ports.achievement_progress")
local event_feed = require("src.rules.ports.event_feed")

local popup_show_seconds = timing.popup_dwell_default_seconds or 1.0

local M = {}

local function _build_weights(config)
  local weights = {}
  for i, cfg in ipairs(config) do
    weights[i] = math.max(0, cfg.weight or 0)
  end
  return weights
end

local chance_weights = _build_weights(chance_cfg)

local function _collect_drawable_cards()
  local drawable = {}
  local first_drawable = nil
  for i, card in ipairs(chance_cfg) do
    first_drawable = first_drawable or card
    table.insert(drawable, { index = i, card = card })
  end
  return drawable, first_drawable
end

local function _calc_total_weight(drawable)
  local total = 0
  for _, item in ipairs(drawable) do
    total = total + (chance_weights[item.index] or 0)
  end
  return total
end

local function _pick_weighted_card(drawable, total_weight, rng)
  assert(rng and type(rng.next_int) == "function", "missing game.rng.next_int for chance draw")
  local pick = rng:next_int(1, total_weight)
  local accumulated = 0
  for _, item in ipairs(drawable) do
    accumulated = accumulated + (chance_weights[item.index] or 0)
    if accumulated >= pick then return item.card end
  end
  return nil
end

local function _fallback_chance_card(first_drawable)
  if #chance_cfg == 0 then return nil end
  return first_drawable
end

local function _pick_chance_card(game)
  local drawable, first_drawable = _collect_drawable_cards()

  if first_drawable == nil then return nil end

  local total_weight = _calc_total_weight(drawable)
  if total_weight <= 0 then return first_drawable end

  local picked = _pick_weighted_card(drawable, total_weight, game and game.rng)
  if picked then return picked end

  return _fallback_chance_card(first_drawable)
end

M.executors = {
  chance_draw_and_resolve = {
    can_apply = function(ctx)
      return ctx.game and ctx.player and ctx.tile and ctx.tile.type == "chance"
    end,
    apply = function(ctx)
      local card = _pick_chance_card(ctx.game) or chance_cfg[1]
      if not card then return end
      event_feed.publish(ctx.game, {
        kind = event_kinds.chance_card,
        text = ctx.player.name .. " 抽到机会卡 " .. card.description,
      })
      achievement_progress.chance_card_drawn(ctx.game, ctx.player)
      presenter.push_popup(ctx.game, "机会卡", ctx.player.name .. " 抽到机会卡：" .. card.description, {
        kind = "chance_card",
        image_ref = card.id,
        auto_close_seconds = popup_show_seconds,
        popup_opts = { policy = "defer" },
        broadcast = true,
      })
      presenter.queue_action_anim(ctx.game, {
        kind = "chance",
        player_id = ctx.player.id,
        card_id = card.id,
        card_desc = card.description,
        duration = popup_show_seconds,
      })
      return chance_resolver.resolve(ctx.game, ctx.player, card, ctx.move_result)
    end,
  },
}

M._build_weights = _build_weights
M._collect_drawable_cards = _collect_drawable_cards
M._calc_total_weight = _calc_total_weight

return M

