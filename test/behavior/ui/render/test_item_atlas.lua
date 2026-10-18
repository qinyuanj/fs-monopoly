-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
-- #293 批3 pin:src/ui/render/widgets/item_atlas.lua 的幸存者分四簇:
-- ① 卡片格刷新链(_refresh_card 的 item 存在性分支、纹理应用、显隐、
--    touch 开关,经 ui/runtime 双桩捕获击杀);
-- ② 分页箭头链(_refresh_page_arrows 的 page_count/page_index 比较与
--    双向箭头显隐);
-- ③ 放大卡链(show_enlarged 的 image_key 缺失早退、纹理应用、overlay
--    显隐与 close_blank touch);
-- ④ 隐藏链(hide_enlarged 的 overlay 整体隐藏)。
-- refs 走真实 asset_context 链(state.runtime_asset_context 直供),runtime 经
-- deps.runtime 直桩(query_nodes 双节点路径),assert 消息类幸存者为等价。


local item_atlas_view = require("src.ui.render.widgets.item_atlas")
local nodes = require("src.ui.schema.item_atlas")

local _PAGE_SIZE = #nodes.card_images

local function _assert_eq(a, b, msg)
  luassert.truthy(a == b, tostring(msg) .. ": expected " .. tostring(b) .. " got " .. tostring(a))
end

local function _env()
  local env = { visible = {}, touch = {}, textures = {}, global_calls = {} }
  env.runtime = {
    query_nodes = function(node_name)
      return { "n1_" .. node_name, "n2_" .. node_name }
    end,
    query_node = function(node_name)
      return "n_" .. node_name
    end,
    set_node_texture_keep_size = function(node, image_key)
      env.textures[#env.textures + 1] = { node = node, image_key = image_key }
    end,
  }
  env.deps = { runtime = env.runtime }
  env.ui = {
    set_visible = function(_, node_name, visible)
      env.visible[#env.visible + 1] = { node_name = node_name, visible = visible }
    end,
    -- #544 退役钉:global 广播变体已拆除;若被重新引入,调用落入 global_calls
    -- 并打破放大/隐藏用例的零调用断言(旁观者泄漏即由广播变体造成)。
    set_visible_global = function(_, node_name, visible)
      env.global_calls[#env.global_calls + 1] = { "set_visible_global", node_name, visible }
    end,
    set_touch_enabled = function(_, node_name, enabled)
      env.touch[#env.touch + 1] = { node_name = node_name, enabled = enabled }
    end,
    set_touch_enabled_global = function(_, node_name, enabled)
      env.global_calls[#env.global_calls + 1] = { "set_touch_enabled_global", node_name, enabled }
    end,
  }
  return env
end

local function _state(env, images)
  return {
    ui = env.ui,
    runtime_asset_context = { refs = { images = images or {} } },
  }
end

local function _catalog(first_id, count)
  local catalog = {}
  for i = 1, count do
    catalog[i] = { id = tostring(first_id + i - 1) }
  end
  return catalog
end

local function _visible_for(env, node_name)
  for _, call in ipairs(env.visible) do
    if call.node_name == node_name then
      return call.visible
    end
  end
  return "unset"
end

-- 与 _visible_for 同型:没摸到对应 touch 调用返回 "unset",断言直接红,不空转。
local function _touch_enabled_for(env, node_name)
  for _, call in ipairs(env.touch) do
    if call.node_name == node_name then
      return call.enabled
    end
  end
  return "unset"
end

describe("TestItemAtlas", function()

  it("test_refresh_page_applies_textures_and_visibility_for_first_page", function()
    -- 首版主契约:在场道具格应用纹理并可见,空格隐藏;touch 跟随 has_item。
    -- L31 image_key 直取链、L42/L62/L64/L67 调用换 nil、L60 item 换 nil
    -- (在场道具当空格处理)与 L59 has_item 的 ~= -> == 在此击杀。
    local env = _env()
    local images = { ["1001"] = "img_1001", ["1002"] = "img_1002" }
    local catalog = _catalog(1001, 16)
    item_atlas_view.refresh_page(_state(env, images), catalog, 1, env.deps)

    _assert_eq(#env.textures, 2 * 2, "two present cards must apply two textures each")
    _assert_eq(env.textures[1].image_key, "img_1001", "first card must apply its image key")
    _assert_eq(env.textures[3].image_key, "img_1002", "second card must apply its image key")
    for slot = 1, 2 do
      _assert_eq(_visible_for(env, nodes.card_images[slot]), true, "present card " .. slot .. " must be visible")
    end
    for slot = 1, 2 do
      _assert_eq(_touch_enabled_for(env, nodes.card_images[slot]), true, "present card " .. slot .. " touch must be enabled")
    end
    _assert_eq(_visible_for(env, nodes.page_prev), false, "first page must hide the prev arrow")
    _assert_eq(_visible_for(env, nodes.page_next), true, "first page must show the next arrow")
  end)

  it("test_refresh_page_hides_empty_slots_and_disables_their_touch", function()
    -- 空格契约:目录不足一页时尾部槽位必须隐藏且 touch 关。
    local env = _env()
    local images = { ["1001"] = "img_1001" }
    local catalog = _catalog(1001, 5)
    item_atlas_view.refresh_page(_state(env, images), catalog, 1, env.deps)
    for slot = 6, _PAGE_SIZE do
      _assert_eq(_visible_for(env, nodes.card_images[slot]), false, "empty slot " .. slot .. " must be hidden")
      _assert_eq(_touch_enabled_for(env, nodes.card_images[slot]), false, "empty slot " .. slot .. " touch must be disabled")
    end
  end)

  it("test_refresh_page_second_page_uses_offset_catalog_slots", function()
    -- L89 `(page_index - 1) * PAGE_SIZE` 的 - -> + 与 L92 槽位取数:第二页
    -- 的槽 1 必须取 catalog[PAGE_SIZE + 1] 起。
    local env = _env()
    local images = { ["1009"] = "img_1009" }
    local catalog = _catalog(1001, 16)
    item_atlas_view.refresh_page(_state(env, images), catalog, 2, env.deps)

    _assert_eq(env.textures[1].image_key, "img_1009", "page two slot one must be catalog[PAGE_SIZE+1]")
    _assert_eq(_visible_for(env, nodes.page_prev), true, "second page must show the prev arrow")
    _assert_eq(_visible_for(env, nodes.page_next), false, "second page must hide the next arrow")
  end)

  it("test_refresh_page_hides_both_arrows_on_out_of_range_page", function()
    -- L72 `page_count > 1` 的 > -> >=(单页目录在第 2 页误显 prev):页数
    -- 不足时两个箭头都必须隐藏。
    local env = _env()
    local catalog = _catalog(1001, 8)
    item_atlas_view.refresh_page(_state(env, {}), catalog, 2, env.deps)
    _assert_eq(_visible_for(env, nodes.page_prev), false, "single-page catalog must hide prev even at page two")
    _assert_eq(_visible_for(env, nodes.page_next), false, "single-page catalog must hide next at page two")
  end)

  it("test_show_enlarged_applies_texture_and_shows_overlay", function()
    -- 放大主契约:有图道具应用纹理(enlarged_card 双节点)、overlay 三节点
    -- 显 true、close_blank touch 开。L31 链、L104 `== nil` 的 == -> ~=、
    -- L110/L118 调用换 nil、L25 `visible == true` 的 == -> ~= 在此击杀。
    -- #544:显隐/触摸必须走 per-role 变体,global 广播变体零调用。
    local env = _env()
    item_atlas_view.show_enlarged(_state(env, { ["2001"] = "img_2001" }), "2001", env.deps)
    _assert_eq(#env.textures, 2, "enlarged card must apply its texture to matched nodes")
    _assert_eq(env.textures[1].image_key, "img_2001", "enlarged image key")
    for _, node_name in ipairs({ nodes.enlarged_card, nodes.close_hint_label, nodes.close_blank }) do
      _assert_eq(_visible_for(env, node_name), true, "overlay node " .. node_name .. " must be shown")
    end
    local blank_touch = nil
    for _, call in ipairs(env.touch) do
      if call.node_name == nodes.close_blank then
        blank_touch = call.enabled
      end
    end
    _assert_eq(blank_touch, true, "close blank must be touchable while enlarged")
    _assert_eq(#env.global_calls, 0, "enlarged overlay must not use global broadcast variants (#544)")
  end)

  it("test_show_enlarged_returns_early_without_image", function()
    -- 无图道具必须整体不落纹理、不显 overlay。
    local env = _env()
    item_atlas_view.show_enlarged(_state(env, {}), "9999", env.deps)
    _assert_eq(#env.textures, 0, "missing image must not apply a texture")
    _assert_eq(#env.visible, 0, "missing image must not show the overlay")
  end)

  it("test_show_enlarged_texture_failure_carries_context", function()
    -- #541:放大卡贴图推送失败时,冒出的错误文本须含宿主原文 + image_key
    -- + 节点名 + 道具 id,事后仅凭日志即可分辨失败现场。
    local env = _env()
    env.runtime.set_node_texture_keep_size = function()
      error("host_push_exploded")
    end
    local ok, err = pcall(item_atlas_view.show_enlarged, _state(env, { ["2001"] = "img_2001" }), "2001", env.deps)
    luassert.truthy(ok == false, "texture push failure must propagate")
    for _, fragment in ipairs({ "host_push_exploded", "img_2001", "2001", nodes.enlarged_card }) do
      luassert.truthy(tostring(err):find(fragment, 1, true) ~= nil, "error text must carry '" .. fragment .. "': " .. tostring(err))
    end
  end)

  it("test_hide_enlarged_hides_overlay_and_disables_touch", function()
    -- 隐藏主契约:overlay 三节点显 false、close_blank touch 关。
    -- #544:隐藏同样不得走 global 广播变体。
    local env = _env()
    item_atlas_view.hide_enlarged(_state(env, {}))
    for _, node_name in ipairs({ nodes.enlarged_card, nodes.close_hint_label, nodes.close_blank }) do
      _assert_eq(_visible_for(env, node_name), false, "overlay node " .. node_name .. " must be hidden")
    end
    local blank_touch = nil
    for _, call in ipairs(env.touch) do
      if call.node_name == nodes.close_blank then
        blank_touch = call.enabled
      end
    end
    _assert_eq(blank_touch, false, "close blank must lose touch while hidden")
    _assert_eq(#env.global_calls, 0, "hide enlarged must not use global broadcast variants (#544)")
  end)


end)
