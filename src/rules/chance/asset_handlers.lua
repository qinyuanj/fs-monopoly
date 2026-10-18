local achievement_progress = require("src.rules.ports.achievement_progress")
local gain_reveal = require("src.rules.items.gain_reveal")

local asset_handlers = {}

function asset_handlers.register(handlers, common)
  local deps = common.dependencies()

  local function _has_building(t)
    return t.type == "land" and (t.level or 0) > 0
  end

  local function _resolve_owner(game, st)
    if st and st.owner_id then
      return game:find_player_by_id(st.owner_id)
    end
    return nil
  end

  local function _destroy_building_on_path_index(game, idx)
    local t = game.board:get_tile(idx)
    assert(t ~= nil, "missing tile: " .. tostring(idx))
    if not _has_building(t) then
      return
    end
    local st = deps.tile_state and deps.tile_state(game, t) or t
    local owner = _resolve_owner(game, st)
    game:set_tile_level(t, 0)
    if owner then
      achievement_progress.typhoon_demolished_building(game, owner)
    end
    common.emit_event(game, deps.monopoly_event.chance.applied, {
      card = { effect = "destroy_buildings_on_path" },
      effect = "destroy_buildings_on_path",
      tile = t,
      text = "台风摧毁 " .. t.name .. " 上的建筑",
    })
  end

  handlers.destroy_buildings_on_path = function(game, _, _, context)
    assert(context ~= nil and context.visited ~= nil, "missing context.visited")
    for _, idx in ipairs(context.visited) do
      _destroy_building_on_path_index(game, idx)
    end
  end

  local function _reset_tile_on_path_index(game, idx)
    local t = game.board:get_tile(idx)
    assert(t ~= nil, "missing tile: " .. tostring(idx))
    if t.type ~= "land" then
      return
    end
    local st = deps.tile_state(game, t)
    assert(st ~= nil, "missing tile state: " .. tostring(t.id))
    if st.owner_id then
      local owner = assert(game:find_player_by_id(st.owner_id), "missing owner: " .. tostring(st.owner_id))
      game:set_player_property(owner, t.id, false)
    end
    game:reset_tile(t)
    common.emit_event(game, deps.monopoly_event.chance.applied, {
      card = { effect = "reset_tiles_on_path" },
      effect = "reset_tiles_on_path",
      tile = t,
      text = "强制征地重置 " .. t.name,
    })
  end

  handlers.reset_tiles_on_path = function(game, _, _, context)
    assert(context ~= nil and context.visited ~= nil, "missing context.visited")
    for _, idx in ipairs(context.visited) do
      _reset_tile_on_path_index(game, idx)
    end
  end

  handlers.grant_item = function(game, player, card)
    local ok = deps.inventory.give(player, card.item_id, { game = game })
    if ok == true then
      gain_reveal.queue(game, player, card.item_id, { source = "chance" })
    end
  end

  local function _discard_count(player, card)
    local to_drop = card.count
    if to_drop == 0 then
      to_drop = deps.inventory.count(player)
    end
    return to_drop
  end

  local function _discard_random_items(game, player, to_drop)
    local dropped_names = {}
    local rng = assert(game and game.rng, "missing game.rng for discard_items")
    assert(type(rng.next_int) == "function", "missing game.rng.next_int for discard_items")
    for _ = 1, to_drop do
      local item_count = deps.inventory.count(player)
      if item_count == 0 then
        break
      end
      local item = deps.inventory.remove_nth_occupied(player, rng:next_int(1, item_count))
      table.insert(dropped_names, deps.inventory.item_name(item.id))
    end
    return dropped_names
  end

  local function _discard_items_text(player, dropped_names)
    local text = player.name .. " 丢弃道具 " .. #dropped_names .. " 张"
    if #dropped_names > 0 then
      text = text .. ": " .. table.concat(dropped_names, "、")
    end
    return text
  end

  handlers.discard_items = function(game, player, card)
    local dropped_names = _discard_random_items(game, player, _discard_count(player, card))
    local text = _discard_items_text(player, dropped_names)
    common.emit_event(game, deps.monopoly_event.chance.applied, {
      player = player,
      card = card,
      effect = card.effect,
      text = text,
    })
  end

  local function _sorted_property_ids(player)
    local ids = {}
    for tile_id in pairs(player.properties or {}) do
      ids[#ids + 1] = tile_id
    end
    table.sort(ids, function(a, b)
      local ai = deps.number_utils.to_integer(a)
      local bi = deps.number_utils.to_integer(b)
      if ai ~= nil and bi ~= nil then
        return ai < bi
      end
      return tostring(a) < tostring(b)
    end)
    return ids
  end

  local function _resolve_drop_rng(game, to_drop, count)
    if to_drop >= count then
      return nil
    end
    local rng = assert(game and game.rng, "missing game.rng for discard_properties")
    assert(type(rng.next_int) == "function", "missing game.rng.next_int for discard_properties")
    return rng
  end

  local function _pick_property_index(ids, rng)
    if rng then
      return rng:next_int(1, #ids)
    end
    return 1
  end

  handlers.discard_properties = function(game, player, card)
    local property_ids = _sorted_property_ids(player)
    local to_drop = card.count
    if to_drop == 0 then
      to_drop = #property_ids
    end
    local rng = _resolve_drop_rng(game, to_drop, #property_ids)

    for _ = 1, to_drop do
      if #property_ids == 0 then
        break
      end
      local tile_id = table.remove(property_ids, _pick_property_index(property_ids, rng))
      local t = game.board:get_tile_by_id(tile_id)
      assert(t ~= nil, "missing tile: " .. tostring(tile_id))
      game:reset_tile(t)
      common.emit_event(game, deps.monopoly_event.chance.applied, {
        player = player,
        card = card,
        effect = card.effect,
        tile = t,
        text = player.name .. " 丢失地块 " .. t.name,
      })
      game:set_player_property(player, tile_id, false)
    end
  end
end

return asset_handlers

