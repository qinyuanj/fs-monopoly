require("test.bootstrap").install_package_paths()
local luassert = assert
local asset_handlers = require("src.rules.chance.handlers")._asset
local monopoly_event = require("src.foundation.events")
local number_utils = require("src.foundation.number")
local achievement_progress = require("src.rules.ports.achievement_progress")

local function _common_with_collectors(events, reset_tiles)
  return {
    emit_event = function(_, _, payload)
      events[#events + 1] = payload
    end,
    dependencies = function()
      return {
        monopoly_event = monopoly_event,
        number_utils = number_utils,
      }
    end,
  }, function(_, tile)
    reset_tiles[#reset_tiles + 1] = tile.id
  end
end

local function _new_handlers(common)
  local handlers = {}
  asset_handlers.register(handlers, common)
  return handlers
end

local function _player_with_properties(property_ids)
  local properties = {}
  for _, id in ipairs(property_ids) do
    properties[id] = true
  end
  return { name = "TestPlayer", properties = properties }
end

local function _board_with_named_tiles()
  return {
    get_tile_by_id = function(_, id)
      return { id = id, name = "Tile" .. tostring(id) }
    end,
  }
end

describe("TestChanceAssetHandlers", function()
it("test_destroy_buildings_on_path_emits_chance_applied_for_tile_with_buildings", function()
  local events = {}
  local common = {
    emit_event = function(_, _, payload)
      events[#events + 1] = payload
    end,
    dependencies = function()
      return { monopoly_event = monopoly_event }
    end,
  }
  local handlers = _new_handlers(common)
  local game = {
    board = {
      get_tile = function(_, idx)
        if idx == 1 then return { type = "land", level = 2, name = "Tile1" } end
        if idx == 2 then return { type = "land", level = 0, name = "Tile2" } end
        if idx == 3 then return { type = "chance", name = "Chance" } end
        return nil
      end,
    },
    set_tile_level = function(_, tile, level)
      tile.level = level
    end,
  }

  handlers.destroy_buildings_on_path(game, {}, {}, { visited = { 1, 2, 3 } })

  luassert.is.equal(1, #events, "only the land tile with buildings should emit")
  luassert.is.equal("destroy_buildings_on_path", events[1].effect, "event effect mismatch")
end)

it("test_destroy_buildings_on_path_credits_owner_resolved_from_tile_state", function()
  local events = {}
  local credited_owner = nil
  local common = {
    emit_event = function(_, _, payload)
      events[#events + 1] = payload
    end,
    dependencies = function()
      return {
        monopoly_event = monopoly_event,
        tile_state = function(_, tile)
          return { owner_id = tile.owner_from_state }
        end,
      }
    end,
  }
  local handlers = _new_handlers(common)
  local owner = { id = "p1" }
  local game = {
    board = {
      get_tile = function()
        return { type = "land", level = 2, name = "Tile1", owner_from_state = "p1" }
      end,
    },
    find_player_by_id = function(_, id)
      if id == "p1" then return owner end
      return nil
    end,
    set_tile_level = function(_, tile, level)
      tile.level = level
    end,
  }

  local original = achievement_progress.typhoon_demolished_building
  achievement_progress.typhoon_demolished_building = function(_, resolved_owner)
    credited_owner = resolved_owner
  end
  local ok, err = pcall(function()
    handlers.destroy_buildings_on_path(game, {}, {}, { visited = { 1 } })
  end)
  achievement_progress.typhoon_demolished_building = original

  luassert.truthy(ok, err)
  luassert.is.equal(owner, credited_owner, "destroyed building should credit owner from tile_state")
  luassert.is.equal(1, #events, "destroying owned building should still emit event")
end)

it("test_reset_tiles_on_path_resets_owned_and_unowned_land_tiles_skips_non_land", function()
  local events = {}
  local reset_tiles = {}
  local owner_writes = {}
  local common = {
    emit_event = function(_, _, payload)
      events[#events + 1] = payload
    end,
    dependencies = function()
      return {
        monopoly_event = monopoly_event,
        tile_state = function(_, tile)
          return { owner_id = tile.mock_owner }
        end,
      }
    end,
  }
  local handlers = _new_handlers(common)
  local game = {
    board = {
      get_tile = function(_, idx)
        if idx == 1 then return { type = "land", id = "t1", mock_owner = "p1", name = "Tile1" } end
        if idx == 2 then return { type = "land", id = "t2", mock_owner = nil, name = "Tile2" } end
        if idx == 3 then return { type = "chance", id = "t3", name = "Chance" } end
        return nil
      end,
    },
    find_player_by_id = function(_, id)
      return { id = id, properties = { t1 = true } }
    end,
    set_player_property = function(_, _, tile_id, owned)
      owner_writes[tile_id] = owned
    end,
    reset_tile = function(_, tile)
      reset_tiles[#reset_tiles + 1] = tile.id
    end,
  }

  handlers.reset_tiles_on_path(game, {}, {}, { visited = { 1, 2, 3 } })

  luassert.is.equal(2, #events, "only the two land tiles should emit")
  luassert.is.equal("reset_tiles_on_path", events[1].effect, "event effect mismatch")
  luassert.is_true(reset_tiles[1] == "t1" and reset_tiles[2] == "t2", "both land tiles should reset in order")
  luassert.is.equal(false, owner_writes["t1"], "owned land should clear its owner")
end)

it("test_path_handlers_reject_a_context_without_visited", function()
  -- context 存在但缺 visited 时须由前置断言点名,而不是让 ipairs(nil) 抛出无关错误。
  local events, reset_tiles = {}, {}
  local common = _common_with_collectors(events, reset_tiles)
  local handlers = _new_handlers(common)
  for _, name in ipairs({ "destroy_buildings_on_path", "reset_tiles_on_path" }) do
    local ok, err = pcall(handlers[name], {}, {}, {}, {})
    luassert.is_false(ok, name .. " must reject a context without visited")
    luassert.truthy(tostring(err):find("missing context.visited", 1, true),
      name .. " should name the missing field; got " .. tostring(err))
  end
end)

it("test_discard_properties_with_count_0_drops_every_property_the_player_owns", function()
  local events = {}
  local reset_tiles = {}
  local common, reset_tile = _common_with_collectors(events, reset_tiles)
  local handlers = _new_handlers(common)
  local game = {
    board = _board_with_named_tiles(),
    reset_tile = reset_tile,
    set_player_property = function() end,
  }
  local player = _player_with_properties({ "t1", "t2", "t3" })
  local card = { count = 0 }

  handlers.discard_properties(game, player, card)

  luassert.is.equal(3, #reset_tiles, "count=0 should drop all three properties")
  luassert.is.equal(3, #events, "one chance.applied event per dropped tile")
end)

it("test_discard_properties_stops_when_properties_run_out_before_count", function()
  local events = {}
  local reset_tiles = {}
  local common, reset_tile = _common_with_collectors(events, reset_tiles)
  local handlers = _new_handlers(common)
  local game = {
    board = _board_with_named_tiles(),
    reset_tile = reset_tile,
    set_player_property = function() end,
  }
  local player = _player_with_properties({ "t1" })
  local card = { count = 5 }

  handlers.discard_properties(game, player, card)

  luassert.is.equal(1, #reset_tiles, "loop should break after the only property is dropped")
  luassert.is.equal(1, #events, "only one event when only one property exists")
end)

it("test_discard_properties_is_a_no_op_when_the_player_owns_nothing", function()
  local events = {}
  local reset_tiles = {}
  local common, reset_tile = _common_with_collectors(events, reset_tiles)
  local handlers = _new_handlers(common)
  local game = {
    board = { get_tile_by_id = function() return nil end },
    reset_tile = reset_tile,
    set_player_property = function() end,
  }
  local player = _player_with_properties({})
  local card = { count = 2 }

  handlers.discard_properties(game, player, card)

  luassert.is.equal(0, #reset_tiles, "no properties means no resets")
  luassert.is.equal(0, #events, "no events should fire")
end)

it("test_discard_properties_sorts_numeric_ids_numerically", function()
  -- 数字键属性 id 必须按数字序丢弃(1,2,10),不能退化成字符串序(1,10,2)。
  -- L130/L131 `to_integer(a|b)` -> nil 与 L132 `~=`->`==` 变异会把数字
  -- 比较路径压回字符串比较,排序结果随之改变。
  local events = {}
  local reset_tiles = {}
  local common, reset_tile = _common_with_collectors(events, reset_tiles)
  local handlers = _new_handlers(common)
  local game = {
    board = {
      get_tile_by_id = function(_, id)
        return { id = id, name = "Tile" .. tostring(id) }
      end,
    },
    reset_tile = reset_tile,
    set_player_property = function() end,
  }
  local player = { name = "TestPlayer", properties = { [2] = true, [10] = true, [1] = true } }
  local card = { count = 0 }

  handlers.discard_properties(game, player, card)

  luassert.is.equal(3, #reset_tiles, "count=0 should drop all three numeric properties")
  luassert.truthy(reset_tiles[1] == 1 and reset_tiles[2] == 2 and reset_tiles[3] == 10,
    "numeric ids must be dropped in numeric order; got "
    .. tostring(reset_tiles[1]) .. "," .. tostring(reset_tiles[2]) .. "," .. tostring(reset_tiles[3]))
end)

it("test_discard_properties_mixed_numeric_and_string_ids_uses_string_fallback", function()
  -- L132 `and`->`or`:数字 id + 字符串 id 混合时,原代码走字符串比较兜底
  -- (数字非 nil 短路后 `ai < bi` 对 nil 比较会崩)。
  local events = {}
  local reset_tiles = {}
  local common, reset_tile = _common_with_collectors(events, reset_tiles)
  local handlers = _new_handlers(common)
  local game = {
    board = {
      get_tile_by_id = function(_, id)
        return { id = id, name = "Tile" .. tostring(id) }
      end,
    },
    reset_tile = reset_tile,
    set_player_property = function() end,
  }
  local player = { name = "TestPlayer", properties = { [1] = true, ["a"] = true } }
  local card = { count = 0 }

  local ok, err = pcall(function()
    handlers.discard_properties(game, player, card)
  end)

  luassert.truthy(ok, "mixed ids must not crash the sort comparator; " .. tostring(err))
  luassert.is.equal(2, #reset_tiles, "both mixed properties should be dropped")
end)


end)
