require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local achievement = require("src.app.host_integrations.achievement")
local achievement_runtime = require("src.app.host_integrations.achievement_runtime")
local achievement_progress_port = require("src.rules.ports.achievement_progress")
local runtime_ports = require("src.foundation.ports.runtime_ports")

local function _make_progress_role(calls)
  return {
    add_achievement_progress = function(id, amount)
      calls[#calls + 1] = { id = id, amount = amount }
      return true
    end,
  }
end

local function _clear(list)
  for index = #list, 1, -1 do
    list[index] = nil
  end
end

local function _assert_progress_calls(calls, expected_ids, expected_amount, label)
  _assert_eq(#calls, #expected_ids, label .. " call count")
  for index, id in ipairs(expected_ids) do
    _assert_eq(calls[index].id, id, label .. " id " .. tostring(index))
    _assert_eq(calls[index].amount, expected_amount, label .. " amount " .. tostring(index))
  end
end

describe("TestAchievement", function()

  after_each(function()
  achievement.reset_for_tests()
  achievement_progress_port.reset_for_tests()
  runtime_ports.reset_for_tests()
  -- 拆了共享端口基线必须装回,否则 mutate 车道窄 suite 子集会撞空端口(#217)。
  support.restore_runtime_services()
  end)

local function _test_finds_achievements_by_editor_id()
  local first = achievement.find(1)
  luassert.truthy(first ~= nil, "achievement 1 should exist")
  _assert_eq(first.name, "最强大富翁I", "achievement 1 name")
  _assert_eq(first.category, "简单", "achievement 1 category")
  _assert_eq(first.condition, "获得1场游戏的胜利", "achievement 1 condition")
  _assert_eq(first.target_progress, 1, "achievement 1 target progress")

  local hidden = achievement.find("42")
  luassert.truthy(hidden ~= nil, "achievement 42 should exist")
  _assert_eq(hidden.name, "海绵宝宝！", "achievement 42 name")
  _assert_eq(hidden.category, "传奇", "achievement 42 category")
  _assert_eq(hidden.condition, "使用海绵宝宝皮肤1次", "achievement 42 condition")
  _assert_eq(hidden.target_progress, 1, "achievement 42 target progress")

  _assert_eq(achievement.find(0), nil, "unknown achievement should not resolve")
end

local function _test_routes_direct_progress_additions_to_the_configured_host_adapter()
  local calls = {}
  local progress = {}
  achievement.configure_progress_adapter({
    add_achievement_progress = function(id, amount)
      calls[#calls + 1] = { id = id, amount = amount }
      progress[id] = (progress[id] or 0) + amount
      return true
    end,
    get_achievement_progress = function(id)
      return progress[id] or 0
    end,
  })

  _assert_eq(achievement.add_progress(1, 2), true, "known achievement should route to host")
  _assert_eq(calls[1].id, 1, "host adapter should receive achievement id")
  _assert_eq(calls[1].amount, 2, "host adapter should receive progress delta")
  _assert_eq(achievement.current_progress(1), 2, "progress reads should come from host adapter")
end

local function _test_routes_progress_through_the_first_resolved_runtime_role_when_no_test_adapter_is_configured()
  local calls = {}
  local progress = {}
  local role = {
    add_achievement_progress = function(id, amount)
      calls[#calls + 1] = { id = id, amount = amount }
      progress[id] = (progress[id] or 0) + amount
      return true
    end,
    get_achievement_progress = function(id)
      return progress[id] or 0
    end,
  }
  runtime_ports.configure({
    resolve_roles = function()
      return { role }
    end,
  })

  _assert_eq(achievement.add_progress(1, 3), true, "runtime role should receive progress")
  _assert_eq(calls[1].id, 1, "runtime role should receive achievement id")
  _assert_eq(calls[1].amount, 3, "runtime role should receive amount")
  _assert_eq(achievement.current_progress(1), 3, "runtime role should serve progress reads")
end

local function _test_rejects_invalid_progress_args_before_calling_the_host_adapter()
  local calls = 0
  achievement.configure_progress_adapter({
    add_achievement_progress = function()
      calls = calls + 1
      return true
    end,
  })

  _assert_eq(achievement.add_progress(1, "not-a-number"), false, "invalid amount should be rejected")
  _assert_eq(achievement.add_progress(999, 1), false, "unknown achievement should be rejected")
  _assert_eq(calls, 0, "invalid progress should not call host")
end

local function _test_treats_explicit_host_progress_refusal_as_failure()
  achievement.configure_progress_adapter({
    add_achievement_progress = function()
      return false
    end,
  })

  _assert_eq(achievement.add_progress(1, 1), false, "host refusal should fail progress routing")
end

local function _test_fans_cumulative_gameplay_events_out_to_every_mapped_achievement()
  local calls = {}
  local progress = {}
  achievement.configure_progress_adapter({
    add_achievement_progress = function(id, amount)
      calls[#calls + 1] = { id = id, amount = amount }
      progress[id] = (progress[id] or 1000) + amount
      return true
    end,
    get_achievement_progress = function(id)
      return progress[id] or 0
    end,
  })

  _assert_eq(achievement.record_gameplay_event("收取金币", 500), true, "mapped event should advance achievements")
  _assert_eq(#calls, 4, "cash collection should update four achievement ids")
  for index, id in ipairs({ 9, 10, 11, 12 }) do
    _assert_eq(calls[index].id, id, "cash collection achievement id " .. tostring(index))
    _assert_eq(calls[index].amount, 500, "cash collection progress delta")
    _assert_eq(achievement.current_progress(id), 1500, "cash collection current progress")
  end
end

local function _test_advances_single_mapped_gameplay_events_by_one_point()
  local calls = {}
  achievement.configure_progress_adapter({
    add_achievement_progress = function(id, amount)
      calls[#calls + 1] = { id = id, amount = amount }
      return true
    end,
  })

  _assert_eq(achievement.record_gameplay_event("使用海绵宝宝皮肤"), true, "skin event should advance achievement")
  _assert_eq(#calls, 1, "skin event should update one achievement")
  _assert_eq(calls[1].id, 42, "skin event achievement id")
  _assert_eq(calls[1].amount, 1, "single event progress delta")
end

local function _test_does_not_advance_unmapped_or_failed_gameplay_events()
  local calls = {}
  achievement.configure_progress_adapter({
    add_achievement_progress = function(id, amount)
      calls[#calls + 1] = { id = id, amount = amount }
      return true
    end,
  })

  _assert_eq(achievement.record_gameplay_event("未映射事件"), false, "unknown event should be ignored")
  _assert_eq(achievement.record_gameplay_event("黑市购买失败"), false, "failed purchase should be ignored")
  _assert_eq(achievement.record_gameplay_event("皮肤装备失败"), false, "failed skin equip should be ignored")
  _assert_eq(#calls, 0, "ignored events should not call host adapter")
end

local function _test_reports_mapped_gameplay_events_as_unadvanced_when_every_host_call_fails()
  local calls = 0
  achievement.configure_progress_adapter({
    add_achievement_progress = function()
      calls = calls + 1
      return false
    end,
  })

  _assert_eq(achievement.record_gameplay_event("游戏胜利"), false, "all-failed event should not advance")
  _assert_eq(calls, 4, "mapped event should attempt every achievement id")
end

local function _test_rejects_progress_when_no_host_adapter_is_available()
  _assert_eq(achievement.add_progress(1, 1), false, "Lua should not fake achievement progress")
end

local function _test_routes_runtime_gameplay_events_to_the_matching_host_role()
  local calls = {}
  local role = {
    add_achievement_progress = function(id, amount)
      calls[#calls + 1] = { id = id, amount = amount }
      return true
    end,
  }
  runtime_ports.configure({
    resolve_role = function(player_id)
      if player_id == 2 then
        return role
      end
      return nil
    end,
  })
  achievement_progress_port.configure(achievement_runtime.build_port())

  _assert_eq(achievement_progress_port.cash_received(nil, { id = 2 }, 500), true,
    "runtime cash event should advance the matched role")
  _assert_eq(#calls, 4, "cash event should fan out to four achievements")
  _assert_eq(calls[1].id, 9, "cash achievement id")
  _assert_eq(calls[1].amount, 500, "cash achievement amount")
end

local function _test_maps_every_runtime_achievement_fact_to_the_configured_gameplay_event()
  local calls = {}
  local role = _make_progress_role(calls)
  local player = { id = 7 }
  local port = achievement_runtime.build_port()
  runtime_ports.configure({
    resolve_role = function(player_id)
      if player_id == player.id then
        return role
      end
      return nil
    end,
  })

  local cases = {
    {
      label = "game win",
      expected_ids = { 1, 2, 3, 4 },
      expected_amount = 1,
      run = function() return port.game_won(nil, player) end,
    },
    {
      label = "land purchase",
      expected_ids = { 5, 6, 7, 8 },
      expected_amount = 1,
      run = function() return port.land_purchased(nil, player) end,
    },
    {
      label = "cash received",
      expected_ids = { 9, 10, 11, 12 },
      expected_amount = 1,
      run = function() return port.cash_received(nil, player, 1) end,
    },
    {
      label = "tax paid",
      expected_ids = { 13, 14, 15, 16 },
      expected_amount = 2500,
      run = function() return port.tax_paid(nil, player, 2500) end,
    },
    {
      label = "item used",
      expected_ids = { 17, 18, 19, 20 },
      expected_amount = 1,
      run = function() return port.item_used(nil, player) end,
    },
    {
      label = "chance card",
      expected_ids = { 21, 22, 23, 24 },
      expected_amount = 1,
      run = function() return port.chance_card_drawn(nil, player) end,
    },
    {
      label = "market item bought",
      expected_ids = { 25, 26, 27, 28 },
      expected_amount = 1,
      run = function() return port.market_item_bought(nil, player) end,
    },
    {
      label = "level one upgrade",
      expected_ids = { 29 },
      expected_amount = 1,
      run = function() return port.building_upgraded(nil, player, 1) end,
    },
    {
      label = "level two upgrade",
      expected_ids = { 30 },
      expected_amount = 1,
      run = function() return port.building_upgraded(nil, player, 2) end,
    },
    {
      label = "level three upgrade",
      expected_ids = { 31 },
      expected_amount = 1,
      run = function() return port.building_upgraded(nil, player, 3) end,
    },
    {
      label = "angel attached",
      expected_ids = { 32 },
      expected_amount = 1,
      run = function() return port.deity_attached(nil, player, "angel") end,
    },
    {
      label = "rich attached",
      expected_ids = { 33 },
      expected_amount = 1,
      run = function() return port.deity_attached(nil, player, "rich") end,
    },
    {
      label = "poor attached",
      expected_ids = { 34 },
      expected_amount = 1,
      run = function() return port.deity_attached(nil, player, "poor") end,
    },
    {
      label = "hospital",
      expected_ids = { 35 },
      expected_amount = 1,
      run = function() return port.location_effect(nil, player, "hospital") end,
    },
    {
      label = "mountain",
      expected_ids = { 36 },
      expected_amount = 1,
      run = function() return port.location_effect(nil, player, "mountain") end,
    },
    {
      label = "contiguous lands",
      expected_ids = { 37 },
      expected_amount = 1,
      run = function() return port.contiguous_lands(nil, player) end,
    },
    {
      label = "monster demolish",
      expected_ids = { 38 },
      expected_amount = 1,
      run = function() return port.monster_demolished_building(nil, player) end,
    },
    {
      label = "typhoon demolish",
      expected_ids = { 39 },
      expected_amount = 1,
      run = function() return port.typhoon_demolished_building(nil, player) end,
    },
  }

  for _, case in ipairs(cases) do
    _clear(calls)
    _assert_eq(case.run(), true, case.label .. " should advance achievement progress")
    _assert_progress_calls(calls, case.expected_ids, case.expected_amount, case.label)
  end
end

local function _test_records_direct_runtime_events_through_host_capable_role_subjects()
  local calls = {}
  local role = _make_progress_role(calls)

  _assert_eq(achievement_runtime.record_event(role, "游戏胜利"), true,
    "direct host role subject should receive runtime achievement progress")
  _assert_progress_calls(calls, { 1, 2, 3, 4 }, 1, "direct role game win")
end

local function _test_rejects_runtime_facts_with_invalid_amounts_or_unknown_event_variants()
  local calls = {}
  local role = _make_progress_role(calls)
  local player = { id = 7 }
  local port = achievement_runtime.build_port()
  runtime_ports.configure({
    resolve_role = function(player_id)
      if player_id == player.id then
        return role
      end
      return nil
    end,
  })

  _assert_eq(port.cash_received(nil, player, 0), false, "zero cash should not advance")
  _assert_eq(port.cash_received(nil, player, nil), false, "missing cash amount should not advance")
  _assert_eq(port.tax_paid(nil, player, -1), false, "negative tax should not advance")
  _assert_eq(port.building_upgraded(nil, player, 4), false, "unknown building level should not advance")
  _assert_eq(port.deity_attached(nil, player, "unknown"), false, "unknown deity should not advance")
  _assert_eq(port.location_effect(nil, player, "unknown"), false, "unknown location effect should not advance")
  _assert_eq(achievement_runtime.record_event(player, nil), false, "missing runtime event should not advance")
  _assert_eq(#calls, 0, "invalid runtime facts should not call the role")
end

local function _test_rejects_malformed_runtime_skin_equip_facts_before_resolving_a_role()
  local calls = {}
  local resolve_calls = 0
  local role = _make_progress_role(calls)
  local port = achievement_runtime.build_port()
  runtime_ports.configure({
    resolve_role = function()
      resolve_calls = resolve_calls + 1
      return role
    end,
  })

  _assert_eq(port.skin_equipped(nil, 7, nil), false, "missing skin should be rejected")
  _assert_eq(port.skin_equipped(nil, 7, {}), false, "skin without a name should be rejected")
  _assert_eq(port.skin_equipped(nil, 7, { name = "" }), false, "blank skin name should be rejected")
  _assert_eq(resolve_calls, 0, "malformed skin facts should not resolve a role")
  _assert_eq(#calls, 0, "malformed skin facts should not call the role")
end

local function _test_does_not_fall_back_to_another_role_for_player_specific_runtime_events()
  local calls = 0
  runtime_ports.configure({
    resolve_roles = function()
      return {
        {
          add_achievement_progress = function()
            calls = calls + 1
            return true
          end,
        },
      }
    end,
    resolve_role = function()
      return nil
    end,
  })
  achievement_progress_port.configure(achievement_runtime.build_port())

  _assert_eq(achievement_progress_port.item_used(nil, { id = 99 }), false,
    "unresolved player event should not advance another role")
  _assert_eq(calls, 0, "fallback role should not receive player-specific progress")
end

local function _test_maps_runtime_skin_equips_by_configured_skin_name()
  local calls = {}
  local role = {
    add_achievement_progress = function(id, amount)
      calls[#calls + 1] = { id = id, amount = amount }
      return true
    end,
  }
  runtime_ports.configure({
    resolve_role = function(player_id)
      if player_id == 7 then return role end
      return nil
    end,
  })
  achievement_progress_port.configure(achievement_runtime.build_port())

  _assert_eq(achievement_progress_port.skin_equipped(nil, 7, { name = "海绵宝宝" }), true,
    "skin equip should map by skin name")
  _assert_eq(#calls, 1, "skin equip should update one achievement")
  _assert_eq(calls[1].id, 42, "spongebob skin achievement id")
  _assert_eq(calls[1].amount, 1, "skin equip amount")
end

it("test_finds_achievements_by_editor_id", _test_finds_achievements_by_editor_id)
it("test_routes_direct_progress_additions_to_the_configured_host_adapter", _test_routes_direct_progress_additions_to_the_configured_host_adapter)
it("test_routes_progress_through_the_first_resolved_runtime_role_when_no_test_adapter_is_configured", _test_routes_progress_through_the_first_resolved_runtime_role_when_no_test_adapter_is_configured)
it("test_rejects_invalid_progress_args_before_calling_the_host_adapter", _test_rejects_invalid_progress_args_before_calling_the_host_adapter)
it("test_treats_explicit_host_progress_refusal_as_failure", _test_treats_explicit_host_progress_refusal_as_failure)
it("test_fans_cumulative_gameplay_events_out_to_every_mapped_achievement", _test_fans_cumulative_gameplay_events_out_to_every_mapped_achievement)
it("test_advances_single_mapped_gameplay_events_by_one_point", _test_advances_single_mapped_gameplay_events_by_one_point)
it("test_does_not_advance_unmapped_or_failed_gameplay_events", _test_does_not_advance_unmapped_or_failed_gameplay_events)
it("test_reports_mapped_gameplay_events_as_unadvanced_when_every_host_call_fails", _test_reports_mapped_gameplay_events_as_unadvanced_when_every_host_call_fails)
it("test_rejects_progress_when_no_host_adapter_is_available", _test_rejects_progress_when_no_host_adapter_is_available)
it("test_routes_runtime_gameplay_events_to_the_matching_host_role", _test_routes_runtime_gameplay_events_to_the_matching_host_role)
it("test_maps_every_runtime_achievement_fact_to_the_configured_gameplay_event", _test_maps_every_runtime_achievement_fact_to_the_configured_gameplay_event)
it("test_records_direct_runtime_events_through_host_capable_role_subjects", _test_records_direct_runtime_events_through_host_capable_role_subjects)
it("test_rejects_runtime_facts_with_invalid_amounts_or_unknown_event_variants", _test_rejects_runtime_facts_with_invalid_amounts_or_unknown_event_variants)
it("test_rejects_malformed_runtime_skin_equip_facts_before_resolving_a_role", _test_rejects_malformed_runtime_skin_equip_facts_before_resolving_a_role)
it("test_does_not_fall_back_to_another_role_for_player_specific_runtime_events", _test_does_not_fall_back_to_another_role_for_player_specific_runtime_events)
it("test_maps_runtime_skin_equips_by_configured_skin_name", _test_maps_runtime_skin_equips_by_configured_skin_name)
end)

-- ===== 迁自 test/property/test_achievement.lua（#190）=====
describe("TestAchievementProgressProperties", function()
  local property = require("test.support.property")
  local event_progress = require("src.config.content.achievement_progress_events")

  local EVENTS = {}
  for name, mapped in pairs(event_progress) do
    EVENTS[#EVENTS + 1] = { name = name, default_amount = mapped.default_amount }
  end
  table.sort(EVENTS, function(left, right)
    return left.name < right.name
  end)

  local function _prop_assert_eq(actual, expected, message)
    luassert.is.equal(expected, actual, message)
  end

  local function _copy(ids)
    local result = {}
    for index, id in ipairs(ids) do
      result[index] = id
    end
    return result
  end

  local function _same_array(left, right)
    if #left ~= #right then
      return false
    end
    for index, value in ipairs(left) do
      if right[index] ~= value then
        return false
      end
    end
    return true
  end

  local function _progress_adapter(progress, added)
    return {
      add_achievement_progress = function(id, amount)
        progress[id] = (progress[id] or 0) + amount
        added[id] = (added[id] or 0) + amount
        return true
      end,
      get_achievement_progress = function(id)
        return progress[id] or 0
      end,
    }
  end

  after_each(function()
    achievement.reset_for_tests()
  end)

  local function _test_mapped_id_lists_are_read_only_snapshots_from_the_caller_perspective()
    property.for_all(function(rng)
      return rng:pick(EVENTS).name
    end, function(event_name)
      local first = achievement.mapped_ids_for_event(event_name)
      local expected = _copy(first)
      first[1] = -1

      local second = achievement.mapped_ids_for_event(event_name)
      luassert.truthy(_same_array(second, expected), "mutating returned ids must not change mapping")
    end)
  end

  local function _test_gameplay_event_routing_adds_exactly_one_explicit_event_delta_to_every_mapped_achievement()
    property.for_all(function(rng)
      local event = rng:pick(EVENTS)
      return {
        event = event,
        base_progress = rng:int(0, 100000),
        generated_amount = rng:int(1, 100000),
      }
    end, function(case)
      local progress = {}
      local added = {}
      local ids = achievement.mapped_ids_for_event(case.event.name)
      for _, id in ipairs(ids) do
        progress[id] = case.base_progress
      end

      achievement.configure_progress_adapter(_progress_adapter(progress, added))

      _prop_assert_eq(achievement.record_gameplay_event(case.event.name, case.generated_amount), true,
        "known event should route progress")

      for _, id in ipairs(ids) do
        _prop_assert_eq(added[id], case.generated_amount, "event should add exactly one delta")
        _prop_assert_eq(achievement.current_progress(id), case.base_progress + case.generated_amount,
          "current progress should include exactly one delta")
      end
    end)
  end

  local function _test_gameplay_event_routing_uses_the_configured_default_when_no_event_value_is_supplied()
    property.for_all(function(rng)
      local event = rng:pick(EVENTS)
      return {
        event = event,
        base_progress = rng:int(0, 100000),
      }
    end, function(case)
      local progress = {}
      local added = {}
      local ids = achievement.mapped_ids_for_event(case.event.name)
      for _, id in ipairs(ids) do
        progress[id] = case.base_progress
      end

      achievement.configure_progress_adapter(_progress_adapter(progress, added))

      _prop_assert_eq(achievement.record_gameplay_event(case.event.name), true,
        "known event should route default progress")

      for _, id in ipairs(ids) do
        _prop_assert_eq(added[id], case.event.default_amount, "event should add the configured default")
        _prop_assert_eq(achievement.current_progress(id), case.base_progress + case.event.default_amount,
          "current progress should include the configured default")
      end
    end)
  end
  it("test_mapped_id_lists_are_read_only_snapshots_from_the_caller_perspective", _test_mapped_id_lists_are_read_only_snapshots_from_the_caller_perspective)
  it("test_gameplay_event_routing_adds_exactly_one_explicit_event_delta_to_every_mapped_achievement", _test_gameplay_event_routing_adds_exactly_one_explicit_event_delta_to_every_mapped_achievement)
  it("test_gameplay_event_routing_uses_the_configured_default_when_no_event_value_is_supplied", _test_gameplay_event_routing_uses_the_configured_default_when_no_event_value_is_supplied)
end)

describe("TestAchievement", function()
  after_each(function()
    achievement.reset_for_tests()
    achievement_progress_port.reset_for_tests()
    runtime_ports.reset_for_tests()
    support.restore_runtime_services()
  end)

local function _test_rejects_runtime_event_with_nil_subject()
  local calls = {}
  local role = _make_progress_role(calls)
  runtime_ports.configure({
    resolve_role = function()
      return role
    end,
  })

  _assert_eq(achievement_runtime.record_event(nil, "游戏胜利"), false,
    "nil subject should not advance achievement progress")
  _assert_eq(#calls, 0, "nil subject should not call the role")
end

local function _test_resolves_player_id_through_role_id_field_first()
  -- #293:_resolve_player_id 的 role_id → id → get_roleid 链首臂未测;
  -- 带 role_id 的 subject 必须走第一臂,其余臂变异可分。
  local resolved = {}
  runtime_ports.configure({
    resolve_role = function(player_id)
      resolved[#resolved + 1] = player_id
      return _make_progress_role({})
    end,
  })

  _assert_eq(achievement_runtime.record_event({ role_id = 7 }, "游戏胜利"), true,
    "subject with role_id should resolve and record")
  _assert_eq(resolved[1], 7, "player id must come from the role_id field first")
end

local function _test_resolves_player_id_through_get_roleid_method_last()
  -- #293:_resolve_player_id 链末臂 get_roleid 未测;无 role_id/id 字段、
  -- 只有 get_roleid 方法的 subject 必须走末臂。
  local resolved = {}
  runtime_ports.configure({
    resolve_role = function(player_id)
      resolved[#resolved + 1] = player_id
      return _make_progress_role({})
    end,
  })

  local subject = {
    get_roleid = function() return 9 end,
  }
  _assert_eq(achievement_runtime.record_event(subject, "游戏胜利"), true,
    "subject with get_roleid method should resolve and record")
  _assert_eq(resolved[1], 9, "player id must come from the get_roleid method")
end


it("test_rejects_runtime_event_with_nil_subject", _test_rejects_runtime_event_with_nil_subject)
it("test_resolves_player_id_through_role_id_field_first", _test_resolves_player_id_through_role_id_field_first)
it("test_resolves_player_id_through_get_roleid_method_last", _test_resolves_player_id_through_get_roleid_method_last)
end)
