require("test.bootstrap").install_package_paths()
local luassert = assert
local achievement = require("src.app.host_integrations.achievement")

describe("TestAchievementMappedIdsForEvent", function()
  after_each(function()
    achievement.reset_for_tests()
  end)

  it("returns_a_copy_of_the_mapped_ids_for_a_known_event", function()
    local ids = achievement.mapped_ids_for_event("游戏胜利")
    luassert.same({ 1, 2, 3, 4 }, ids)
    ids[1] = -1
    luassert.same({ 1, 2, 3, 4 }, achievement.mapped_ids_for_event("游戏胜利"))
  end)

  it("returns_an_empty_table_for_an_unknown_event", function()
    luassert.same({}, achievement.mapped_ids_for_event("no_such_event_zzz"))
  end)
end)
