require("test.bootstrap").install_package_paths()

-- busted injects the extensible assertion object into each file environment.
-- luacheck: ignore 143
local luassert = assert
local memo = require("src.foundation.memo")

describe("TestMemo", function()

  -- ===== 惰性求值 =====

  it("test_compute_does_not_run_until_first_get", function()
    local calls = 0
    local cell = memo.new(function(snapshot)
      calls = calls + 1
      return snapshot
    end)
    luassert.is_not_nil(cell)
    -- lint-allow: call-count memo 的公共契约即 compute 执行次数(惰性求值 + 快照命中缓存)
    luassert.is.equal(0, calls, "compute should not run at construction")
  end)

  -- ===== 输入快照未变不重算 =====

  it("test_unchanged_snapshot_returns_cached_value_without_recompute", function()
    local calls = 0
    local cell = memo.new(function(snapshot)
      calls = calls + 1
      return snapshot.a
    end)
    local first = cell:get({ a = 1 })
    local second = cell:get({ a = 1 })
    luassert.is.equal(1, first)
    luassert.is.equal(1, second)
    -- lint-allow: call-count memo 的公共契约即 compute 执行次数(惰性求值 + 快照命中缓存)
    luassert.is.equal(1, calls, "equal snapshot should not recompute")
  end)

  it("test_same_table_identity_hit_counts_as_unchanged", function()
    local calls = 0
    local cell = memo.new(function(snapshot)
      calls = calls + 1
      return snapshot.a
    end)
    local input = { a = 1 }
    cell:get(input)
    cell:get(input)
    -- lint-allow: call-count memo 的公共契约即 compute 执行次数(惰性求值 + 快照命中缓存)
    luassert.is.equal(1, calls, "same table with same content should not recompute")
  end)

  -- ===== 输入变化重算 =====

  it("test_changed_snapshot_recomputes", function()
    local calls = 0
    local cell = memo.new(function(snapshot)
      calls = calls + 1
      return snapshot.a
    end)
    luassert.is.equal(1, cell:get({ a = 1 }))
    luassert.is.equal(2, cell:get({ a = 2 }))
    -- lint-allow: call-count memo 的公共契约即 compute 执行次数(惰性求值 + 快照命中缓存)
    luassert.is.equal(2, calls, "changed snapshot should recompute")
  end)

  it("test_field_removal_counts_as_change", function()
    local calls = 0
    local cell = memo.new(function(snapshot)
      calls = calls + 1
      return snapshot.a
    end)
    cell:get({ a = 1 })
    local value = cell:get({})
    luassert.is_nil(value, "removed field should produce recomputed value")
    -- lint-allow: call-count memo 的公共契约即 compute 执行次数(惰性求值 + 快照命中缓存)
    luassert.is.equal(2, calls)
  end)

  -- ===== 快照冻结：防御调用方复用并原地改写的输入表 =====

  it("test_caller_mutated_input_table_does_not_corrupt_stored_snapshot", function()
    local calls = 0
    local cell = memo.new(function(snapshot)
      calls = calls + 1
      return snapshot.a
    end)
    local input = { a = 1 }
    luassert.is.equal(1, cell:get(input))
    input.a = 2
    luassert.is.equal(2, cell:get(input), "mutated input should be seen as change")
    input.a = 1
    luassert.is.equal(1, cell:get(input), "snapshot should be frozen, not aliasing caller table")
    -- lint-allow: call-count memo 的公共契约即 compute 执行次数(惰性求值 + 快照命中缓存)
    luassert.is.equal(3, calls)
  end)

  -- ===== take_snapshot 投影 =====

  it("test_take_snapshot_projects_inputs_and_ignores_noise", function()
    local calls = 0
    local cell = memo.new(function(snapshot)
      calls = calls + 1
      return snapshot.flag
    end, function(input)
      return { flag = input.flag }
    end)
    -- 注意:这里比的是**值** true/false(原 lu.assertEquals 口径),不是 truthiness
    -- ——换成 truthy 会把「返回了 1」也放过,是静默放松。
    luassert.is.equal(true, cell:get({ flag = true, noise = 1 }))
    cell:get({ flag = true, noise = 2 })
    -- lint-allow: call-count memo 的公共契约即 compute 执行次数(惰性求值 + 快照命中缓存)
    luassert.is.equal(1, calls, "change outside projection should not recompute")
    luassert.is.equal(false, cell:get({ flag = false, noise = 2 }))
    -- lint-allow: call-count memo 的公共契约即 compute 执行次数(惰性求值 + 快照命中缓存)
    luassert.is.equal(2, calls, "change inside projection should recompute")
  end)

  it("test_compute_receives_snapshot_not_raw_input", function()
    local received = nil
    local cell = memo.new(function(snapshot)
      received = snapshot
      return snapshot.projected
    end, function(input)
      return { projected = input.raw }
    end)
    luassert.is.equal("x", cell:get({ raw = "x" }))
    luassert.is.equal("x", received.projected, "compute should receive the projected snapshot")
    luassert.is_nil(received.raw, "compute should not see raw input fields")
  end)

  -- ===== 标量输入 =====

  it("test_scalar_snapshot_compared_by_value", function()
    local calls = 0
    local cell = memo.new(function(snapshot)
      calls = calls + 1
      return snapshot
    end)
    luassert.is.equal("x", cell:get("x"))
    luassert.is.equal("x", cell:get("x"))
    -- lint-allow: call-count memo 的公共契约即 compute 执行次数(惰性求值 + 快照命中缓存)
    luassert.is.equal(1, calls)
    luassert.is.equal("y", cell:get("y"))
    -- lint-allow: call-count memo 的公共契约即 compute 执行次数(惰性求值 + 快照命中缓存)
    luassert.is.equal(2, calls)
  end)

  -- ===== 派生链：下游派生显式消费上游值，不自动级联 =====

  it("test_derived_chain_composes_explicitly_without_cascade", function()
    local upstream_calls = 0
    local is_alive = memo.new(function(snapshot)
      upstream_calls = upstream_calls + 1
      return snapshot.hp > 0
    end, function(snapshot)
      return { hp = snapshot.hp }
    end)
    local is_animating = memo.new(function(snapshot)
      return is_alive:get(snapshot) and not snapshot.frozen
    end)
    luassert.is.equal(true, is_animating:get({ hp = 10, frozen = false }))
    luassert.is.equal(false, is_animating:get({ hp = 10, frozen = true }))
    -- lint-allow: call-count memo 的公共契约即 compute 执行次数(惰性求值 + 快照命中缓存)
    luassert.is.equal(1, upstream_calls, "upstream memo should cache across downstream recomputes")
  end)

  -- ===== 单元间独立 =====

  it("test_cells_do_not_share_state", function()
    local cell_a = memo.new(function(snapshot)
      return snapshot
    end)
    local cell_b = memo.new(function(snapshot)
      return snapshot
    end)
    luassert.is.equal(1, cell_a:get(1))
    luassert.is.equal(2, cell_b:get(2))
    luassert.is.equal(1, cell_a:get(1), "cell A cache should be unaffected by cell B")
  end)

  -- ===== 构造校验 =====

  it("test_new_snapshot_with_extra_field_recomputes", function()
    local cell = memo.new(function(snapshot)
      local total = 0
      for _, value in pairs(snapshot) do
        total = total + value
      end
      return total
    end)
    luassert.is.equal(1, cell:get({ a = 1 }))
    luassert.is.equal(3, cell:get({ a = 1, b = 2 }), "an added field in the new snapshot should invalidate the cache")
  end)

  it("test_switching_between_table_and_scalar_snapshot_recomputes", function()
    local cell = memo.new(function(snapshot)
      return type(snapshot)
    end)
    luassert.is.equal("number", cell:get(5))
    luassert.is.equal("table", cell:get({ a = 1 }), "scalar -> table snapshot should recompute")
    luassert.is.equal("number", cell:get(5), "table -> scalar snapshot should recompute")
  end)

  it("test_first_get_with_nil_snapshot_still_computes", function()
    local cell = memo.new(function()
      return 42
    end)
    luassert.is.equal(42, cell:get(), "a constant selector must compute on the first get even without input")
  end)

  it("test_new_rejects_non_function_compute", function()
    -- 原义是「memo.new("not a function") 会抛」,尾参是传给 memo.new 的实参。
    luassert.has_error(function()
      memo.new("not a function")
    end)
  end)

  it("test_new_rejects_non_function_take_snapshot", function()
    luassert.has_error(function()
      memo.new(function()
        return true
      end, "not a function")
    end)
  end)

end)
