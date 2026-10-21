require("test.bootstrap").install_package_paths()
-- busted injects the extensible assertion object into each file environment.
-- luacheck: ignore 143
local luassert = assert

describe("TestSkins", function()

  it("test_prices_every_default_skin_as_a_jindou_purchase", function()
    package.loaded["src.config.content.skins"] = nil
    local skins = require("src.config.content.skins")
    local expected_price = { [5005] = 68, [5006] = 98, [5003] = 198, [5004] = 198 }

    for _, skin in ipairs(skins) do
      luassert.truthy(skin.unlock == "purchase", "default skin should be purchase: " .. tostring(skin.product_id))
      luassert.truthy(skin.currency == "金豆", "default skin currency should be 金豆: " .. tostring(skin.product_id))
      luassert.truthy(skin.price == expected_price[skin.product_id], "default skin price mismatch: " .. tostring(skin.product_id))
    end
  end)

  it("test_pins_default_skin_identity_and_ordering", function()
    package.loaded["src.config.content.skins"] = nil
    local skins = require("src.config.content.skins")
    local expected = {
      { order = 1, product_id = 5005, name = "奶龙", creature_key = "nailong" },
      { order = 2, product_id = 5006, name = "水豚嘟嘟", creature_key = "capybara_dudu" },
      { order = 5, product_id = 5003, name = "海绵宝宝", creature_key = "spongebob" },
      { order = 6, product_id = 5004, name = "派大星", creature_key = "patrick_star" },
    }

    luassert.truthy(#skins == #expected, "default skin count mismatch")
    for i, fields in ipairs(expected) do
      local skin = skins[i]
      luassert.truthy(skin.order == fields.order, "skin order mismatch at " .. tostring(i))
      luassert.truthy(skin.product_id == fields.product_id, "skin product_id mismatch at " .. tostring(i))
      luassert.truthy(skin.name == fields.name, "skin name mismatch at " .. tostring(i))
      luassert.truthy(skin.creature_key == fields.creature_key, "skin creature key mismatch at " .. tostring(i))
    end
  end)

  it("test_registers_host_archive_keys_per_adr_0074", function()
    package.loaded["src.config.content.skins"] = nil
    local skins = require("src.config.content.skins")
    local expected_key = { [5004] = 1052, [5006] = 1053, [5005] = 1054, [5003] = 1055 }

    luassert.truthy(skins.equipped_archive_key == 1051, "equipped skin archive key should be 1051")
    for _, skin in ipairs(skins) do
      luassert.truthy(skin.archive_key == expected_key[skin.product_id],
        "archive key mismatch: " .. tostring(skin.product_id))
    end
  end)

end)
