-- #293 批3 pin:src/ui/schema/remote_choice.lua 为纯数据表,幸存者均为
-- 字段值换 nil。逐字段钉死数据契约(遥控骰子屏的节点名与六选项槽)。

-- luacheck: ignore 143 (genuine busted injects luassert)
local luassert = assert
local remote_choice = require("src.ui.schema.remote_choice")

local function _assert_eq(a, b, msg)
  luassert.is.equal(b, a, msg)
end

describe("TestRemoteChoiceSchema", function()

it("test_canvas_and_screen_node_names_are_pinned", function()
  -- canvas / title / body / underlay 换 nil:四个节点名必须稳定。
  _assert_eq(remote_choice.canvas, "遥控骰子屏", "canvas node name")
  _assert_eq(remote_choice.title, "遥控骰子_标题", "title node name")
  _assert_eq(remote_choice.body, "遥控骰子_正文", "body node name")
  _assert_eq(remote_choice.underlay, "遥控骰子_退出灰底", "underlay node name")
end)

it("test_every_referenced_node_name_exists_in_the_ui_node_table", function()
  -- #177:编辑器改名(遥控骰子_灰底 → 遥控骰子_退出灰底)后 schema 必须跟上,
  -- 否则按名设置触摸/注册点击会落到不存在的节点上。
  local known = {}
  for _, entry in pairs(require("Data.UIManagerNodes")) do
    if type(entry) == "table" then
      known[entry[1]] = true
    end
  end
  local referenced = { remote_choice.canvas, remote_choice.title, remote_choice.body, remote_choice.underlay }
  for _, name in ipairs(remote_choice.options) do
    referenced[#referenced + 1] = name
  end
  for _, name in ipairs(referenced) do
    luassert.is_true(known[name] == true, "schema node missing from UI node table: " .. tostring(name))
  end
end)

it("test_options_has_six_slots", function()
  -- options 表与各槽换 nil:六个选项节点必须齐全。
  _assert_eq(#remote_choice.options, 6, "options slot count")
  local expected = {
    "遥控骰子_选项_01", "遥控骰子_选项_02", "遥控骰子_选项_03",
    "遥控骰子_选项_04", "遥控骰子_选项_05", "遥控骰子_选项_06",
  }
  for index, node_name in ipairs(expected) do
    _assert_eq(remote_choice.options[index], node_name, "option slot " .. index)
  end
end)

end)
