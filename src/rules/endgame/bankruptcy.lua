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

--[[ mutate4lua-manifest
version=4
projectHash=bc1967d12e2709ab
scope.0.id=chunk:src/rules/endgame/bankruptcy.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=150
scope.0.semanticHash=d55ccc8f51cc3703
scope.1.id=function:_resolve_bankruptcy_text
scope.1.kind=function
scope.1.startLine=12
scope.1.endLine=17
scope.1.semanticHash=87d51f3b32a40f97
scope.2.id=function:_player_field
scope.2.kind=function
scope.2.startLine=19
scope.2.endLine=21
scope.2.semanticHash=cd6b189045fad21d
scope.3.id=function:_push_bankruptcy_popup
scope.3.kind=function
scope.3.startLine=23
scope.3.endLine=34
scope.3.semanticHash=3da2b9b74a52ab3a
scope.4.id=function:_collect_owned_tile_ids
scope.4.kind=function
scope.4.startLine=36
scope.4.endLine=45
scope.4.semanticHash=b672ff9ece28610c
scope.5.id=function:_resolve_owned_tiles
scope.5.kind=function
scope.5.startLine=47
scope.5.endLine=61
scope.5.semanticHash=5ea3eacf234105f6
scope.6.id=function:_collect_owned_tiles
scope.6.kind=function
scope.6.startLine=63
scope.6.endLine=67
scope.6.semanticHash=41f031eab82d50ea
scope.7.id=function:_publish_bankruptcy
scope.7.kind=function
scope.7.startLine=69
scope.7.endLine=74
scope.7.semanticHash=2d58fb52006fd291
scope.8.id=function:_clear_owned_tiles
scope.8.kind=function
scope.8.startLine=76
scope.8.endLine=88
scope.8.semanticHash=ab1f79fb5f1c7f66
scope.9.id=function:_mark_player_eliminated
scope.9.kind=function
scope.9.startLine=90
scope.9.endLine=101
scope.9.semanticHash=2ee07f757a1ae03e
scope.10.id=function:_notify_runtime_role_loss
scope.10.kind=function
scope.10.startLine=103
scope.10.endLine=107
scope.10.semanticHash=abb4b85e763994cc
scope.11.id=function:_clear_occupant_lists
scope.11.kind=function
scope.11.startLine=112
scope.11.endLine=120
scope.11.semanticHash=6a3a7adb26f69647
scope.12.id=function:bankruptcy.eliminate
scope.12.kind=function
scope.12.startLine=122
scope.12.endLine=138
scope.12.semanticHash=a043306ebc5ba022
]]
