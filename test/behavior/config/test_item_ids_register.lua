require("test.bootstrap").install_package_paths()
local luassert = assert
local item_ids = require("src.config.gameplay.item_ids")
local items = require("src.config.content.items")
local support = require("test.support.shared_support")

-- 每次经模块装载边界重建完整映射；生产模块身份由 with_patches 在异常时恢复。
local function load_with_catalog(catalog)
  local loaded
  support.with_patches({
    { target = package.loaded, key = "src.config.content.items", value = catalog },
    { target = package.loaded, key = "src.config.gameplay.item_ids", value = nil },
  }, function()
    loaded = require("src.config.gameplay.item_ids")
  end, { skip_runtime_context_refresh = true })
  return loaded
end

describe("TestItemIdsCatalogLoading", function()
  it("publishes_the_configured_gameplay_ids", function()
    luassert.equal(2001, item_ids.free_rent)
    luassert.equal(2002, item_ids.remote_dice)
    luassert.equal(2004, item_ids.roadblock)
  end)

  it("ignores_entries_without_a_usable_key_when_loading_a_catalog", function()
    local ids = load_with_catalog({
      { id = 41 }, { key = "", id = 42 }, { key = "configured_item", id = 43 },
    })
    luassert.same({ configured_item = 43 }, ids)
  end)

  it("rejects_duplicate_keys_in_the_loaded_catalog", function()
    local catalog = {}
    for index, entry in ipairs(items) do catalog[index] = entry end
    catalog[#catalog + 1] = { key = "free_rent", id = 9999 }
    local ok, err = pcall(load_with_catalog, catalog)
    luassert.is_false(ok)
    luassert.truthy(tostring(err):find("duplicate item key in items config: free_rent", 1, true))
  end)
end)
