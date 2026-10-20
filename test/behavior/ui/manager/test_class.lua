-- class.lua branch-dense coverage: multi-inheritance lookup, getter/setter resolution.
local luassert = assert
local Class = require("src.ui.manager.class")

describe("TestClass", function()

it("test_resolves_methods_from_multiple_parent_classes", function()
  local A = Class("A")
  function A:a_method() return "A" end
  local B = Class("B")
  function B:b_method() return "B" end
  local C = Class("C", A, B)

  local instance = C:new()

  luassert.truthy(instance:a_method() == "A", "should resolve method from first parent")
  luassert.truthy(instance:b_method() == "B", "should resolve method from second parent")
end)

it("test_uses_get_as_getter_and_set_as_setter", function()
  local Widget = Class("Widget")
  function Widget:__get_value() return self._value end
  function Widget:__set_value(v) self._value = v end

  local w = Widget:new()
  w._value = 42

  luassert.truthy(w.value == 42, "getter should expose _value")
  w.value = 100
  luassert.truthy(w._value == 100, "setter should update _value")
end)

it("test_inherits_get_and_set_from_parent_classes", function()
  local Base = Class("Base")
  function Base:__get_value() return self._value end
  function Base:__set_value(v) self._value = v end
  local Derived = Class("Derived", Base)

  local d = Derived:new()
  d._value = 7

  luassert.truthy(d.value == 7, "derived instance should inherit base getter")
  d.value = 14
  luassert.truthy(d._value == 14, "derived instance should inherit base setter")
end)

it("test_prefers_own_getter_setter_over_inherited_ones", function()
  local Base = Class("Base")
  function Base:__get_value() return "base" end
  function Base:__set_value(v) self._base_value = v end
  local Derived = Class("Derived", Base)
  function Derived:__get_value() return "derived" end
  function Derived:__set_value(v) self._derived_value = v end

  local d = Derived:new()

  luassert.truthy(d.value == "derived", "own getter should shadow inherited getter")
  d.value = 1
  luassert.truthy(d._derived_value == 1, "own setter should shadow inherited setter")
  luassert.truthy(d._base_value == nil, "inherited setter should not run")
end)

it("test_resolves_methods_and_getters_across_more_than_one_inheritance_level", function()
  local Grand = Class("Grand")
  function Grand:grand_method() return "grand" end
  function Grand:__get_depth() return "grand_depth" end
  local Mid = Class("Mid", Grand)
  local Leaf = Class("Leaf", Mid)

  local leaf = Leaf:new()

  luassert.truthy(leaf:grand_method() == "grand", "grandparent method must resolve through the middle class")
  luassert.truthy(leaf.depth == "grand_depth", "grandparent getter must resolve through the middle class")
end)

it("test_prefers_the_first_declared_parent_when_both_parents_define_a_member", function()
  local First = Class("First")
  function First:tag() return "first" end
  function First:__get_label() return "first_label" end
  local Second = Class("Second")
  function Second:tag() return "second" end
  function Second:__get_label() return "second_label" end
  local Both = Class("Both", First, Second)

  local instance = Both:new()

  luassert.truthy(instance:tag() == "first", "declaration order must decide which parent wins")
  luassert.truthy(instance.label == "first_label", "declaration order must decide which parent getter wins")
end)

it("test_falls_back_to_rawset_when_no_setter_is_found", function()
  local Box = Class("Box")
  local b = Box:new()
  b.color = "red"

  luassert.truthy(b.color == "red", "plain field should be readable after rawset")
  luassert.truthy(rawget(b, "color") == "red", "plain field should be stored on instance")
end)

it("test_existing_instances_observe_dynamic_members_across_the_parent_chain", function()
  local Grand = Class("DynamicGrand")
  function Grand:tag() return "grand" end
  function Grand:__get_value() return "initial" end
  local First = Class("DynamicFirst", Grand)
  local Second = Class("DynamicSecond")
  function Second:tag() return "second" end
  local Leaf = Class("DynamicLeaf", First, Second)
  local one, two = Leaf:new(), Leaf:new()
  luassert.same({ "grand", "initial" }, { one:tag(), two.value })

  function Grand:tag() return "changed" end
  function Grand:__get_value() return "updated" end
  luassert.same({ "changed", "updated" }, { one:tag(), two.value })
  Grand.tag = nil
  luassert.equal("second", one:tag())
  function Leaf:tag() return "leaf" end
  luassert.equal("leaf", two:tag())
  function Second:tag() return "changed_later" end
  Leaf.tag = nil
  luassert.equal("changed_later", one:tag())
end)

it("test_getter_then_custom_index_then_class_member_priority_stays_dynamic", function()
  local Base = Class("ReadPriority")
  Base.label = "class"
  Base.flag = "class_flag"
  function Base:__custom_index(key)
    if key == "label" then return "custom" end
    if key == "flag" then return false end
  end
  function Base:__get_label() return "getter" end
  local Child = Class("ReadPriorityChild", Base)
  local one, two = Child:new(), Child:new()
  luassert.same({ "getter", false }, { one.label, two.flag })
  function Base:__get_label() return false end
  luassert.is_false(two.label)

  Base.__get_label = nil
  luassert.equal("custom", one.label)
  function Base:__custom_index() return nil end
  luassert.equal("class", two.label)
  function Child:__get_label() return nil end
  luassert.is_nil(one.label)
  one.label = "instance"
  luassert.equal("instance", one.label)
  luassert.is_nil(two.label)
end)

it("test_init_precedence_and_fallback_preserve_constructor_arguments_and_instance_state", function()
  local Base = Class("ConstructorBase")
  function Base:Init(name, value)
    self.path, self.name, self.value = "Init", name, value
  end
  function Base:init(name, value)
    self.path, self.name, self.value = "init", name, value
  end
  function Base:__get_value() return self._value end
  function Base:__set_value(value) self._value = value * 2 end
  local Child = Class("ConstructorChild", Base)
  function Child:init() error("inherited Init must win") end
  local one, two = Child:new("one", 3), Child:new("two", 5)
  luassert.same({ "Init", "one", 6, "Init", "two", 10 },
    { one.path, one.name, one.value, two.path, two.name, two.value })

  one.value, one.note = 7, "private"
  luassert.same({ 14, 10, "private" }, { one.value, two.value, one.note })
  luassert.is_nil(two.note)
  Base.Init = nil
  Child.init = nil
  local later = Child:new("later", 4)
  luassert.same({ "init", "later", 8 }, { later.path, later.name, later.value })

  function Child:__set_value(value) self._value = value + 1 end
  two.value = 20
  local sibling = Base:new("base", 6)
  luassert.same({ 14, 21, 12 }, { one.value, two.value, sibling.value })
end)

it("test_fixed_twelve_instance_budget_includes_each_classes_shared_dispatch", function()
  local Base = Class("BudgetBase")
  local Derived = Class("BudgetDerived", Base)
  local Other = Class("BudgetOther")
  local metas, readers, writers, representatives = {}, {}, {}, {}
  for _, class in ipairs({ Base, Derived, Other }) do
    for _ = 1, 4 do
      local instance = class:new()
      local meta = getmetatable(instance)
      representatives[class] = meta
      metas[meta] = true
      readers[meta.__index] = true
      writers[meta.__newindex] = true
    end
  end
  local function count(set)
    local size = 0
    for _ in pairs(set) do size = size + 1 end
    return size
  end

  -- #182 的结构预算：三个类、每类四个实例，共享结构自身各计一次。
  -- 类表的继承元表与查找闭包另各三份，优化前后不变；不作字节收益断言。
  luassert.same({ 3, 3, 3 }, { count(metas), count(readers), count(writers) })
  luassert.is_not.equal(representatives[Base], representatives[Derived])
  luassert.is_not.equal(representatives[Base].__index, representatives[Derived].__index)
  luassert.is_not.equal(representatives[Base].__newindex, representatives[Derived].__newindex)
end)

end)
