require("test.bootstrap").install_package_paths()

local luassert = assert
local guard = require("test.guards.lib.eggy_json_guard")

-- eggy.json 入库只为让 editor-cli 判 FS/SE(isSEMap)。editor-cli 的 code init /
-- 地图解析自愈会写回 projectID / playerNid / mapDir 等本机信息,afa9e0c 曾借此泄露。
-- 用 M.check 喂合成文本:真实仓库已合规时测不出拦截是否生效。
describe("TestEggyJsonGuard", function()
  it("test_only_is_se_map_boolean_passes", function()
    luassert.is.same({}, guard.check('{ "isSEMap": false }'))
    luassert.is.same({}, guard.check('{ "isSEMap": true }'))
  end)

  it("test_editor_written_binding_fields_are_flagged", function()
    local violations = guard.check(
      '{ "isSEMap": false, "projectID": "x", "playerNid": "1", "mapDir": "C:\\\\m" }')
    luassert.is.same({
      "eggy_json_guard: disallowed key: mapDir",
      "eggy_json_guard: disallowed key: playerNid",
      "eggy_json_guard: disallowed key: projectID",
    }, violations)
  end)

  it("test_non_boolean_is_se_map_is_flagged", function()
    luassert.is.same({ "eggy_json_guard: isSEMap must be a boolean" },
      guard.check('{ "isSEMap": "false" }'))
  end)

  it("test_missing_is_se_map_is_flagged", function()
    luassert.is.same({ "eggy_json_guard: isSEMap must be a boolean" }, guard.check("{}"))
  end)

  it("test_invalid_json_is_flagged", function()
    local violations = guard.check("{ not json")
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("eggy_json_guard: invalid json", 1, true), violations[1])
  end)

  it("test_non_object_is_flagged", function()
    luassert.is.same({ "eggy_json_guard: top level must be an object" }, guard.check('"x"'))
  end)
end)
