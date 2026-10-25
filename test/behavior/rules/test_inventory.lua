require("test.bootstrap").install_package_paths()
-- luacheck: ignore 143 (busted injects the verified luassert object)
local luassert = assert
local inventory = require("src.rules.items.inventory")
local inventory_class = require("src.player.actions.inventory")
local control = require("src.player.control")

local function _assert_eq(a, b, msg)
  luassert.is.same(b, a, msg)
end

-- 用真实 Inventory 类(CONTEXT「道具槽位」 稳定槽位):固定 5 槽、空槽以 false 占位、
-- #items 恒等于槽位数;手搓密集数组 stub 会把槽位语义测丢,禁用。
local function _make_inventory(items_list)
  local inv = inventory_class:new({ max_slots = 5 })
  for _, item in ipairs(items_list or {}) do
    inv:add(item)
  end
  return inv
end

local function _make_player(items_list, opts)
  opts = opts or {}
  local player = {
    id = opts.id or 1001,
    name = opts.name or "TestPlayer",
    is_ai = opts.is_ai,
    inventory = _make_inventory(items_list),
  }
  control.initialize(player)
  return player
end

do



  describe("TestInventory", function()
    before_each(function()
      require("test.support.config_reset").reset_all()
    end)
    it("test_cfg_known_id_returns_table_or_nil", function()
      local result = inventory.cfg("strong")
      luassert.truthy(result == nil or type(result) == "table", "cfg should return table or nil for any id")
    end)

    it("test_items_returns_items_list", function()
      local player = _make_player({ { id = "item_a" } })
      local items = inventory.items(player)
      _assert_eq(inventory.count(player), 1, "one item should be counted")
      _assert_eq(items[1].id, "item_a", "first item should be item_a")
    end)

    it("test_count_returns_item_count", function()
      local player = _make_player({ { id = "x" }, { id = "y" } })
      _assert_eq(inventory.count(player), 2, "count should return 2")
    end)

    it("test_count_empty_returns_zero", function()
      local player = _make_player({})
      _assert_eq(inventory.count(player), 0, "count of empty inventory is 0")
    end)

    it("test_is_full_when_at_limit", function()
      local player = _make_player({ {}, {}, {}, {}, {} })
      _assert_eq(inventory.is_full(player), true, "5 items should be full")
    end)

    it("test_is_full_when_not_full", function()
      local player = _make_player({ {}, {} })
      _assert_eq(inventory.is_full(player), false, "2 items should not be full")
    end)

    it("test_add_fills_the_first_free_slot", function()
      local player = _make_player({})
      inventory.add(player, { id = "sword" })
      _assert_eq(inventory.count(player), 1, "add should increase occupied count")
      _assert_eq(inventory.items(player)[1].id, "sword", "added item should take slot 1")
    end)

    it("test_add_refills_the_earliest_hole_left_by_removal", function()
      local player = _make_player({ { id = "a" }, { id = "b" }, { id = "c" } })
      inventory.remove_by_index(player, 2)
      inventory.add(player, { id = "d" })
      _assert_eq(inventory.items(player)[1].id, "a", "slot 1 must stay unmoved")
      _assert_eq(inventory.items(player)[2].id, "d", "the new item must fill the earliest hole")
      _assert_eq(inventory.items(player)[3].id, "c", "slot 3 must stay unmoved")
    end)

    it("test_find_index_found", function()
      local player = _make_player({ { id = "item_a" }, { id = "item_b" } })
      local idx = inventory.find_index(player, "item_b")
      _assert_eq(idx, 2, "find_index should return 2 for item_b")
    end)

    it("test_find_index_not_found", function()
      local player = _make_player({ { id = "item_a" } })
      local idx = inventory.find_index(player, "item_x")
      _assert_eq(idx, nil, "find_index should return nil when not found")
    end)

    it("test_remove_by_index_leaves_a_hole_and_keeps_other_slots", function()
      local player = _make_player({ { id = "item_a" }, { id = "item_b" } })
      inventory.remove_by_index(player, 1)
      _assert_eq(inventory.count(player), 1, "remove should decrease occupied count")
      _assert_eq(inventory.items(player)[1], false, "the removed slot must become a hole")
      _assert_eq(inventory.items(player)[2].id, "item_b", "item_b must stay in slot 2 unmoved")
    end)

    it("test_remove_by_index_out_of_range_or_hole_returns_nil_and_preserves_slots", function()
      local player = _make_player({ { id = "a" } })
      local hole = inventory.remove_by_index(player, 2)
      _assert_eq(hole, nil, "removing an empty hole must return nil")
      local raw_inv = player.inventory
      local out_of_range = raw_inv:remove_by_index(6)
      _assert_eq(out_of_range, nil, "out-of-range remove must return nil")
      _assert_eq(#raw_inv.items, 5, "#items must stay pinned to the slot count (CONTEXT「道具槽位」)")
      _assert_eq(inventory.count(player), 1, "occupied count must be unchanged")
      _assert_eq(raw_inv.items[1].id, "a", "slot 1 must stay unmoved")
    end)

    it("test_consume_removes_first_matching_item", function()
      local player = _make_player({ { id = "item_a" }, { id = "item_b" } })
      local ok = inventory.consume(player, "item_a")
      _assert_eq(ok, true, "consume should return true")
      _assert_eq(inventory.count(player), 1, "consume should reduce occupied count")
      _assert_eq(inventory.items(player)[1], false, "the consumed slot must become a hole")
      _assert_eq(inventory.items(player)[2].id, "item_b", "item_b must stay in slot 2 unmoved")
    end)

    it("test_find_index_skips_holes_and_returns_stable_slots", function()
      local player = _make_player({ { id = "a" }, { id = "b" }, { id = "c" } })
      inventory.remove_by_index(player, 1)
      _assert_eq(inventory.find_index(player, "b"), 2, "slot 2 still resolves")
      _assert_eq(inventory.find_index(player, "c"), 3, "slot 3 keeps its stable index")
    end)

    it("test_is_full_counts_occupied_slots_only", function()
      local player = _make_player({ {}, {}, {}, {}, {} })
      inventory.remove_by_index(player, 3)
      _assert_eq(inventory.is_full(player), false, "a hole means the bag is not full")
    end)

    it("test_remove_nth_occupied_maps_ordinal_to_slot", function()
      local player = _make_player({ { id = "a" }, { id = "b" }, { id = "c" } })
      inventory.remove_by_index(player, 1)
      local removed = inventory.remove_nth_occupied(player, 2)
      _assert_eq(removed.id, "c", "the second occupied card is the one in slot 3")
      _assert_eq(inventory.items(player)[3], false, "slot 3 becomes a hole")
      _assert_eq(inventory.items(player)[2].id, "b", "slot 2 stays unmoved")
      local first = inventory.remove_nth_occupied(player, 1)
      _assert_eq(first.id, "b", "the first occupied card is now slot 2")
    end)

    it("test_clear_removes_all_items", function()
      local player = _make_player({ { id = "item_a" }, { id = "item_b" } })
      player.inventory:clear()
      _assert_eq(inventory.count(player), 0, "clear should empty every slot")
      _assert_eq(inventory.items(player)[1], false, "cleared slots must be holes")
      _assert_eq(inventory.items(player)[5], false, "cleared slots must be holes through the tail")
    end)

    it("test_clear_empty_inventory_is_noop", function()
      local player = _make_player({})
      player.inventory:clear()
      _assert_eq(inventory.count(player), 0, "clear on empty should remain empty")
    end)

    it("test_give_adds_item_when_not_full", function()
      local player = _make_player({}, { name = "P1" })
      local item_ids = require("src.config.gameplay.item_ids")
      local ok = inventory.give(player, item_ids.missile, nil)
      _assert_eq(ok, true, "give should return true when not full")
      _assert_eq(inventory.count(player), 1, "count should be 1 after give")
    end)

    it("test_give_returns_false_when_full", function()
      local player = _make_player({ {}, {}, {}, {}, {} }, { name = "P1" })
      local result = inventory.give(player, "strong", nil)
      _assert_eq(result, false, "give should return false when full")
    end)

    it("test_give_full_with_game_no_popup_port", function()
      local player = _make_player({ {}, {}, {}, {}, {} }, { name = "P2" })
      local game = {}
      local result = inventory.give(player, "strong", { game = game })
      _assert_eq(result, false, "give full with no popup_port should return false")
    end)

    it("test_give_full_ai_player_skips_notify", function()
      local player = _make_player({ {}, {}, {}, {}, {} }, { name = "AI", is_ai = true })
      local default_ports = require("src.turn.output.default_ports")
      local game = default_ports.install({
        popup_port = { push_popup = function() error("should not call") end },
      })
      local result = inventory.give(player, "strong", { game = game })
      _assert_eq(result, false, "give full AI player should return false without error")
    end)

  -- T16 mutation-pinning addendum.

  -- 「clear toggles」(原嵌套 describe,无钩子 → 合并进外层类)
    it("test_clear_leaves_suspend_on_change_false", function()
      local player = _make_player({ { id = "a" }, { id = "b" } })
      -- Force pre-clear state to true so L79 'false' mutation is observable.
      player.inventory._suspend_on_change = true
      player.inventory:clear()
      _assert_eq(player.inventory._suspend_on_change, false,
        "clear must leave _suspend_on_change=false at exit; mutation L79 would leave it true")
    end)

    it("test_clear_sets_suspend_on_change_during_items_reset", function()
      -- Build inventory whose items field uses a __newindex hook to capture the
      -- _suspend_on_change value at the exact moment items is overwritten.
      local captured_during_write = nil
      local player = _make_player({ { id = "a" } })
      local raw_inv = player.inventory
      local proxy = setmetatable({}, {
        __index = raw_inv,
        __newindex = function(_, key, value)
          if key == "items" then
            captured_during_write = raw_inv._suspend_on_change
          end
          rawset(raw_inv, key, value)
        end,
      })
      player.inventory = proxy
      player.inventory:clear()
      _assert_eq(captured_during_write, true,
        "during items reset _suspend_on_change must be true; L77 mutation makes it false")
    end)

  -- 「_notify_full」(原嵌套 describe,无钩子 → 合并进外层类)
    it("test_notify_full_pushes_popup_via_intent_output_port", function()
      local pushed = {}
      local default_ports = require("src.turn.output.default_ports")
      local game = default_ports.install({
        popup_port = { push_popup = function() end },
        intent_output_port = {
          push_popup = function(_, payload)
            pushed[#pushed + 1] = payload
            return true
          end,
        },
      })
      local item_ids = require("src.config.gameplay.item_ids")
      local player = _make_player({ {}, {}, {}, {}, {} }, { name = "P3" })
      local result = inventory.give(player, item_ids.free_rent, { game = game })
      _assert_eq(result, false, "give full must report failure")
      luassert.truthy(#pushed >= 1, "_notify_full must invoke intent_output_port:push_popup with an installed popup port")
      luassert.truthy(pushed[1].title == "道具", "popup title must be '道具'; got " .. tostring(pushed[1].title))
      luassert.truthy(tostring(pushed[1].body):find("P3"), "popup body must include player name; got " .. tostring(pushed[1].body))
    end)
  end)
end

-- 「draw_random」(原嵌套 describe,带 before_each → 拆子类;子类 setUp 首行调父 setUp)
do
  local runtime_ports = require("src.foundation.ports.runtime_ports")
  local weighted_draw = require("src.rules.items.weighted_draw")



  describe("TestInventoryDrawRandom", function()
    before_each(function()
      require("test.support.config_reset").reset_all()
      -- draw_random 吃环境默认的 rng_next_int port。同 worker 里先跑的 spec 若在
      -- teardown 里 runtime_ports.reset_for_tests()（仓内惯例）会把 helper 装好的
      -- 默认 ports 清空——LPT 分桶重排后这里就假红（#190 分流时暴露）。
      -- 自给自足：进用例前恢复默认运行时 ports，不依赖同 worker 的历史。
      require("test.env_runtime").refresh_runtime_services()
    end)
    it("test_draw_random_returns_a_config_item_table_with_id_and_weight_fields", function()
      local picked = inventory.draw_random()
      luassert.truthy(type(picked) == "table", "draw_random must return a table; got " .. type(picked))
      luassert.truthy(picked.id ~= nil, "drawn item must carry an id field")
    end)

    it("test_draw_random_returns_the_picked_from_weight_list", function()
      -- Stub the rng port to pick the LAST item in the weighted list deterministically.
      -- weighted_draw.pick iterates items 1..N accumulating weight; first item whose
      -- cumulative weight >= rand wins. rng returning the max (total_weight) → last item wins.
      local items_cfg = require("src.config.content.items")
      local last_item = items_cfg[#items_cfg]
      luassert.truthy(last_item.id ~= items_cfg[1].id, "fixture invariant: last cfg item differs from first")

      local saved_rng = runtime_ports.rng_next_int
      runtime_ports.rng_next_int = function(_, max) return max end -- forces last bucket
      local picked = inventory.draw_random()
      runtime_ports.rng_next_int = saved_rng

      luassert.truthy(picked.id == last_item.id, "draw_random must return picked[1] from weighted choice (last item under rng=max); " ..
        "L86 'or→and' or first '1→0' mutation returns items_cfg[1].id=" ..
        tostring(items_cfg[1].id) .. " instead. Got id=" .. tostring(picked.id))
    end)

    it("test_draw_random_falls_back_to_items_cfg_first_when_pick_yields_nothing", function()
      -- Force the weighted picker to return an empty list so picked[1] is nil and the
      -- 'or items_cfg[1]' fallback branch executes.
      -- Original: returns items_cfg[1] (first config item, non-nil).
      -- Mut 'items_cfg[1]' -> 'items_cfg[0]': returns items_cfg[0] == nil.
      local items_cfg = require("src.config.content.items")
      local saved_pick = weighted_draw.pick
      weighted_draw.pick = function() return {} end
      local picked = inventory.draw_random()
      weighted_draw.pick = saved_pick

      luassert.truthy(picked ~= nil, "draw_random must fall back to a real config item when pick is empty; " ..
        "fallback '1→0' mutation returns items_cfg[0]=nil")
      luassert.truthy(picked == items_cfg[1], "empty-pick fallback must return items_cfg[1]; got " .. tostring(picked and picked.id))
    end)

    it("test_weight_fn_defaults_nil_to_zero_and_removes_nil_entries", function()
      -- #293:weight or 0 and remove_nil_entries true->false not yet covered.
      local captured_weight_fn, captured_remove_nil
      local saved_pick = weighted_draw.pick
      weighted_draw.pick = function(_, _, weight_fn, remove_nil)
        captured_weight_fn = weight_fn
        captured_remove_nil = remove_nil
        return { { id = 1 } }
      end
      inventory.draw_random()
      weighted_draw.pick = saved_pick
      luassert.is.same(true, captured_remove_nil, "remove_nil_entries passes true to filter nil weights")
      luassert.is.same(0, captured_weight_fn({ weight = nil }), "nil weight defaults to 0")
      luassert.is.same(10, captured_weight_fn({ weight = 10 }), "present weight passes through")
    end)
  end)
end

describe("TestInventory", function()
  before_each(function()
    require("test.support.config_reset").reset_all()
  end)
  it("test_items_asserts_missing_items_with_message", function()
    -- #293:inventory.items 的 missing inventory items 断言消息未测。
    local player = { inventory = { items = nil } }
    local ok, err = pcall(inventory.items, player)
    luassert.truthy(ok == false, "items without an items list should assert")
    luassert.truthy(tostring(err):find("missing inventory items", 1, true) ~= nil, "assert should carry its message: " .. tostring(err))
  end)

end)
