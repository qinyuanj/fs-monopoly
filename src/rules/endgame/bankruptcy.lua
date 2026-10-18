local logger = require("src.foundation.log")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local event_kinds = require("src.config.gameplay.event_kinds")
local bankruptcy_feedback_port = require("src.rules.ports.bankruptcy_feedback")
local event_feed = require("src.rules.ports.event_feed")
local inventory = require("src.rules.items.inventory")
local monopoly_event = require("src.foundation.events")
local life_loss = require("src.rules.endgame.life_loss")

local bankruptcy = {}

local function _resolve_bankruptcy_text(player, opts)
  if opts and opts.reason and opts.reason ~= "" then
    return opts.reason
  end
  return player.name .. " 破产出局"
end

local function _player_field(player, key)
  return player and player[key] or nil
end

local function _push_bankruptcy_popup(game, player, opts)
  local popup_port = game and game.popup_port or nil
  if not (popup_port and popup_port.push_popup) then
    return
  end
  popup_port:push_popup({
    kind = "bankruptcy",
    player_id = _player_field(player, "id"),
    player_name = _player_field(player, "name"),
    text = _resolve_bankruptcy_text(player, opts),
  })
end

local function _collect_owned_tile_ids(player)
  local owned_tile_ids = {}
  local props = player.properties or {}
  for tile_id, owned in pairs(props) do
    if owned == true then
      table.insert(owned_tile_ids, tile_id)
    end
  end
  return owned_tile_ids
end

local function _resolve_owned_tiles(game, owned_tile_ids)
  local owned_tiles = {}
  local names = {}
  for _, tile_id in ipairs(owned_tile_ids) do
    local tile = game.board:get_tile_by_id(tile_id)
    if tile then
      table.insert(owned_tiles, tile)
      table.insert(names, tile.name)
    else
      logger.warn("bankruptcy skip missing tile:", tostring(tile_id))
    end
  end

  return owned_tiles, names
end

local function _collect_owned_tiles(game, player)
  local owned_tile_ids = _collect_owned_tile_ids(player)
  local owned_tiles, names = _resolve_owned_tiles(game, owned_tile_ids)
  return owned_tile_ids, owned_tiles, names
end

local function _publish_bankruptcy(game, player)
  event_feed.publish(game, {
    kind = event_kinds.bankruptcy,
    text = player.name .. " 破产出局",
  })
end

local function _clear_owned_tiles(game, player, owned_tile_ids, owned_tiles, names)
  if #owned_tile_ids > 0 then
    event_feed.publish(game, {
      kind = event_kinds.bankruptcy_liquidation,
      text = player.name .. " 破产，清空地块: " .. table.concat(names, "、"),
    })

    for _, tile in ipairs(owned_tiles) do
      game:reset_tile(tile)
      game:set_player_property(player, tile.id, false)
    end
  end
end

local function _mark_player_eliminated(game, player, opts)
  inventory.clear(player)
  game:clear_player_deity(player)

  game:set_player_eliminated(player, true)
  _push_bankruptcy_popup(game, player, opts)
  monopoly_event.emit(monopoly_event.feedback.bankruptcy, {
    player = player,
    player_id = player.id,
    reason = _resolve_bankruptcy_text(player, opts),
  })
end

local function _notify_runtime_role_loss(player)
  local role = runtime_ports.resolve_role(player.id)
  life_loss.try_call_life_die(role)
  runtime_ports.mark_role_lose(role)
end

-- _clear_occupant_lists 反向清除(table.remove 前移语义要求从尾部开始)。
-- 下界 1 的 1→0 变异在常规数组下不可观测(list[0] 恒 nil),由 _M_test
-- 直驱 + [0] 探针用例封死。
local function _clear_occupant_lists(game, player)
  for _, list in pairs(game.occupants) do
    for i = #list, 1, -1 do
      if list[i] == player.id then
        table.remove(list, i)
      end
    end
  end
end

function bankruptcy.eliminate(game, player, opts)
  if player.eliminated then
    return
  end
  _publish_bankruptcy(game, player)

  local owned_tile_ids, owned_tiles, names = _collect_owned_tiles(game, player)
  _clear_owned_tiles(game, player, owned_tile_ids, owned_tiles, names)
  _mark_player_eliminated(game, player, opts)
  _notify_runtime_role_loss(player)

  if #owned_tile_ids > 0 then
    bankruptcy_feedback_port.on_tiles_cleared(game, player, owned_tile_ids)
  end

  _clear_occupant_lists(game, player)
end

bankruptcy._try_call_life_die = life_loss.try_call_life_die
bankruptcy._resolve_bankruptcy_text = _resolve_bankruptcy_text
bankruptcy.resolve_bankruptcy_text = _resolve_bankruptcy_text

bankruptcy._M_test = {
  _clear_occupant_lists = _clear_occupant_lists,
}

return bankruptcy

