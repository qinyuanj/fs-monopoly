-- array_read_only.lua 直测:只读视图透传底层 Array 的元素读、变更方法 fail-fast 报错。
-- #267：append/pop 报错（不穿透、不静默），索引写仅遮蔽视图实例。
-- 宿主无关(纯数据结构),底座仅用于窄车道共享基线自备(#217)。
local luassert = assert
local Array = require("src.ui.manager.array")
local ArrayReadOnly = require("src.ui.manager.array_read_only")
require("test.support.ui_manager_nodes_support")

describe("TestArrayReadOnly", function()

do
  local function _make_backing()
    local arr = Array:new()
    arr:append("a")
    arr:append("b")
    return arr
  end

  it("test_reads_pass_through_to_the_backing_array", function()
    local ro = ArrayReadOnly:new(_make_backing())

    luassert.truthy(ro.length == 2, "length mirrors backing array")
    luassert.truthy(ro[1] == "a", "index 1 passes through")
    luassert.truthy(ro[2] == "b", "index 2 passes through")
  end)

  it("test_length_tracks_backing_array_growth", function()
    local backing = _make_backing()
    local ro = ArrayReadOnly:new(backing)

    backing:append("c")

    luassert.truthy(ro.length == 3, "length reflects later appends on the backing array")
  end)

  it("test_append_raises_and_leaves_the_backing_array_untouched", function()
    -- #267:穿透曾借到 Array.append 写坏共享 backing(data 与 length 脱节);
    -- 裁定为 fail-fast 报错(与 Array:__set_length 同款)。
    local backing = _make_backing()
    local ro = ArrayReadOnly:new(backing)

    luassert.has_error(function()
      ro:append("z")
    end, "ArrayReadOnly is read-only")

    luassert.truthy(backing.length == 2, "backing length unchanged")
    luassert.truthy(backing[1] == "a" and backing[2] == "b", "backing elements unchanged")
  end)

  it("test_pop_raises_and_leaves_the_backing_array_untouched", function()
    local backing = _make_backing()
    local ro = ArrayReadOnly:new(backing)

    luassert.has_error(function()
      ro:pop()
    end, "ArrayReadOnly is read-only")

    luassert.truthy(backing.length == 2, "backing length unchanged")
  end)

  it("test_read_methods_resolve_from_the_views_own_class_chain_not_the_backing_instance", function()
    -- __custom_index 只代理数值下标（元素读），方法名落回类链（#267）；
    -- forEach 等只读方法经父类 Array 解析,行为与穿透期一致。
    local backing = _make_backing()
    local ro = ArrayReadOnly:new(backing)

    local seen = {}
    ro:forEach(function(e)
      seen[#seen + 1] = e
    end)

    luassert.truthy(#seen == 2 and seen[1] == "a" and seen[2] == "b", "forEach iterates backing elements")
    luassert.truthy(ro.forEach == ArrayReadOnly.forEach, "read method resolves from the view's own class")
  end)

  it("test_index_assignment_shadows_on_the_view_without_touching_the_backing_array", function()
    -- class.lua 的 __newindex 无 __set_<key> 时 rawset 到视图实例上, backing 不受污染(现状钉死)。
    local backing = _make_backing()
    local ro = ArrayReadOnly:new(backing)

    ro[1] = "z"

    luassert.truthy(ro[1] == "z", "instance shadow wins on read")
    luassert.truthy(backing[1] == "a", "backing array untouched")
  end)

  it("test_length_assignment_raises_via_the_inherited_array_setter", function()
    -- __set_length 未覆写,经父类链接解析到 Array 的报错 setter;此 case 同时钉住
    -- IS-A 父类链接本身(Array 父类被剪掉时此处不报错,退化为 rawset 静默成功)。
    local ro = ArrayReadOnly:new(_make_backing())

    luassert.has_error(function()
      ro.length = 99
    end, "Array length is read-only")

    luassert.truthy(ro.length == 2, "length still mirrors the backing array")
  end)

  it("test_two_arrays_and_views_keep_elements_lengths_and_local_shadows_isolated", function()
    local left, right = Array:new(), Array:new()
    local left_view, right_view = ArrayReadOnly:new(left), ArrayReadOnly:new(right)
    left:append("left")
    right:append("right")
    right:append("tail")
    left_view[1] = "local"

    luassert.same({ 1, "left", 1, "local", 2, "right" },
      { left.length, left[1], left_view.length, left_view[1], right_view.length, right_view[1] })
    luassert.has_error(function() left_view:pop() end, "ArrayReadOnly is read-only")
    luassert.equal("tail", right:pop())
    luassert.same({ 1, 1, "right" }, { left_view.length, right_view.length, right_view[1] })
  end)

  it("test_the_class_keeps_the_array_parent_link_while_owning_its_method_surface", function()
    -- 父类链接是声明式 IS-A 契约(类表 parents 链);方法面由视图类自带:
    -- forEach 委托 backing,append/pop 覆写为报错,均不再等于父类实现(#267)。
    luassert.truthy(ArrayReadOnly.forEach ~= Array.forEach, "forEach is owned by the view class")
    luassert.truthy(ArrayReadOnly.append ~= Array.append, "mutator is overridden on the view class")
    luassert.truthy(ArrayReadOnly.pop ~= Array.pop, "mutator is overridden on the view class")
  end)
end
end)
