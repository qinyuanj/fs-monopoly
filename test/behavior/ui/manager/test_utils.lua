-- utils.lua 直测:对外 facade 的查询函数与枚举表,以及 _G.UIManager 发布。
-- 查询函数操作 context 的 nodes_list / name_node_mapping(原表原地增删,与簇内约定一致)。
--
-- 地雷:require utils 会把真 facade 发布到 _G.UIManager,顶掉 test_env 给 scenario
-- suite 装的 query_nodes_by_name 假节点 stub(全车道同进程,stub 一没 scenario 全红)。
-- 故抓到 facade 引用后立刻装回原全局;发布断言用装回前快照(published)做。
local luassert = assert
local context = require("src.ui.manager.context")
local saved_global_facade = _G.UIManager
local UIManager = require("src.ui.manager.utils")
local published_facade = _G.UIManager
_G.UIManager = saved_global_facade
require("test.support.ui_manager_nodes_support")

describe("TestUtils", function()

before_each(function()
  for k in pairs(context.nodes_list) do
    context.nodes_list[k] = nil
  end
  for k in pairs(context.name_node_mapping) do
    context.name_node_mapping[k] = nil
  end
end)

after_each(function()
  for k in pairs(context.nodes_list) do
    context.nodes_list[k] = nil
  end
  for k in pairs(context.name_node_mapping) do
    context.name_node_mapping[k] = nil
  end
end)

it("test_publishes_the_facade_table_to_the_global_ui_manager", function()
  luassert.truthy(published_facade == UIManager, "require 时 _G.UIManager 应被替换为 facade 表")
end)

it("test_facade_carries_every_node_class_builder_listener_and_array_classes", function()
  local class_slots = {
    "ECanvas", "ENode", "ELabel", "EButton", "EImage",
    "EProgressbar", "EInputField", "Builder", "Listener", "Array", "ArrayReadOnly",
  }
  for _, slot in ipairs(class_slots) do
    luassert.truthy(type(UIManager[slot]) == "table" or type(UIManager[slot]) == "function",
      slot .. " should be registered on the facade")
  end
  luassert.truthy(UIManager.ELabel.__name == "UIManager.ELabel", "ELabel slot is the ELabel class")
  luassert.truthy(UIManager.Array.__name == "Array", "Array slot is the Array class")
end)

it("test_enode_type_and_event_enums_carry_the_full_documented_values", function()
  luassert.truthy(UIManager.ENodeType.ELabel == "UIManager.ELabel", "ENodeType.ELabel pinned")
  luassert.truthy(UIManager.ENodeType.EButton == "UIManager.EButton", "ENodeType.EButton pinned")
  luassert.truthy(UIManager.ENodeType.EImage == "UIManager.EImage", "ENodeType.EImage pinned")
  luassert.truthy(UIManager.ENodeType.ENode == "UIManager.ENode", "ENodeType.ENode pinned")
  luassert.truthy(UIManager.EVENT.CLICK == "CLICK", "EVENT.CLICK pinned")
end)

it("test_query_node_by_id_reads_nodes_list_by_id", function()
  local node = { __name = "UIManager.ENode" }
  context.nodes_list[101] = node

  luassert.truthy(UIManager.query_node_by_id(101) == node, "id lookup returns the node")
  luassert.truthy(UIManager.query_node_by_id(999) == nil, "unknown id yields nil")
end)

it("test_get_first_node_by_name_returns_the_first_mapped_node_or_nil", function()
  local first = { __name = "UIManager.ENode" }
  local second = { __name = "UIManager.ENode" }
  context.name_node_mapping["hp"] = { first, second }

  luassert.truthy(UIManager.get_first_node_by_name("hp") == first, "first mapped node")
  luassert.truthy(UIManager.get_first_node_by_name("missing") == nil, "unknown name yields nil")
end)

it("test_query_nodes_by_name_returns_the_mapped_array_or_an_empty_table", function()
  local nodes = { { __name = "UIManager.ENode" } }
  context.name_node_mapping["mp"] = nodes

  luassert.truthy(UIManager.query_nodes_by_name("mp") == nodes, "mapped array returned as-is")
  local empty = UIManager.query_nodes_by_name("missing")
  luassert.truthy(type(empty) == "table" and #empty == 0, "unknown name yields empty table")
end)


end)
