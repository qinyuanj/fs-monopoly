local nodes = require("src.ui.schema.item_atlas")
local number_utils = require("src.foundation.number")
local panel_runtime = require("src.ui.render.support.panel_runtime")
local runtime_assets = require("src.config.runtime_assets")

local item_atlas_view = {}

local PAGE_SIZE = #nodes.card_images

local _enlarged_overlay_nodes = {
  nodes.enlarged_card,
  nodes.close_hint_label,
  nodes.close_blank,
}

local _resolve_runtime = panel_runtime.resolve

-- #544 真机原型实证:覆盖层三节点住图鉴 canvas,per-role 查询可达(#512 的
-- 「常驻屏节点查不到」结论已不成立),且 canvas 显隐在客户端门控子树渲染——
-- 显隐/触摸走普通 per-role 路径,同步只路由到浏览者客户端,旁观者天然不可见;
-- #512 时代的 set_visible_global 广播 workaround 已退役。
local function _set_enlarged_overlay_visible(ui, visible)
  for _, node_name in ipairs(_enlarged_overlay_nodes) do
    if ui.set_visible then
      ui:set_visible(node_name, visible)
    end
  end
  if ui.set_touch_enabled then
    ui:set_touch_enabled(nodes.close_blank, visible == true)
    -- #178:放大态下背景不接点击,点空白只收起放大卡(逐层退出)。
    ui:set_touch_enabled(nodes.background, visible ~= true)
  end
end

local function _disable_passthrough_touch(ui)
  if not ui.set_touch_enabled then
    return
  end
  for _, node_name in ipairs(nodes.passthrough_nodes) do
    ui:set_touch_enabled(node_name, false)
  end
end

-- #176 review:开屏路径自身就要把 passthrough 文字(关闭文字/提示文字)的
-- 触摸关掉、把背景触摸打开,不依赖后续翻页的 refresh_page 顺手兜底。
function item_atlas_view.prepare_open(state)
  local ui = assert(state.ui, "missing ui")
  if ui.set_touch_enabled then
    ui:set_touch_enabled(nodes.background, true)
  end
  _disable_passthrough_touch(ui)
end

local function _item_image_key(refs, item_id)
  local image = runtime_assets.image_for_item(item_id, refs)
  return image.ok == true and image.image_key or nil
end

local function _apply_card_texture(runtime, refs, node_name, item)
  local image_key = _item_image_key(refs, item.id)
  if not image_key then
    return
  end
  if type(runtime.query_nodes) == "function" then
    local matched_nodes = runtime.query_nodes(node_name)
    for _, node in ipairs(matched_nodes) do
      runtime.set_node_texture_keep_size(node, image_key)
    end
  else
    local node = runtime.query_node(node_name)
    if node then
      runtime.set_node_texture_keep_size(node, image_key)
    end
  end
end

local function _set_card_visibility(ui, node_name, visible)
  if ui.set_visible then
    ui:set_visible(node_name, visible)
  end
end

local function _refresh_card(ui, runtime, refs, node_name, item)
  local has_item = item ~= nil
  if item then
    _apply_card_texture(runtime, refs, node_name, item)
    _set_card_visibility(ui, node_name, true)
  else
    _set_card_visibility(ui, node_name, false)
  end
  if ui.set_touch_enabled then
    ui:set_touch_enabled(node_name, has_item)
  end
end

local function _refresh_page_arrows(ui, page_index, page_count)
  local has_multiple_pages = page_count > 1
  local prev_visible = has_multiple_pages and page_index > 1
  local next_visible = has_multiple_pages and page_index < page_count
  if ui.set_visible then
    ui:set_visible(nodes.page_prev, prev_visible)
    ui:set_visible(nodes.page_next, next_visible)
  end
  if ui.set_touch_enabled then
    ui:set_touch_enabled(nodes.page_prev, prev_visible)
    ui:set_touch_enabled(nodes.page_next, next_visible)
  end
end

function item_atlas_view.refresh_page(state, catalog, page_index, deps)
  local ui = assert(state.ui, "missing ui")
  local runtime = _resolve_runtime(state, deps)
  local refs = runtime_assets.asset_context(state)
  local offset = (page_index - 1) * PAGE_SIZE

  for slot, node_name in ipairs(nodes.card_images) do
    _refresh_card(ui, runtime, refs, node_name, catalog[offset + slot])
  end

  _refresh_page_arrows(ui, page_index, number_utils.page_count(#catalog, PAGE_SIZE))
  _disable_passthrough_touch(ui)
end

local function _apply_enlarged_texture(runtime, image_key)
  if type(runtime.query_nodes) == "function" then
    local matched_nodes = runtime.query_nodes(nodes.enlarged_card)
    for _, node in ipairs(matched_nodes) do
      runtime.set_node_texture_keep_size(node, image_key)
    end
  else
    local node = runtime.query_node(nodes.enlarged_card)
    if node then
      runtime.set_node_texture_keep_size(node, image_key)
    end
  end
end

-- #541:贴图推送失败(宿主侧 image_key 无效/节点缺失/role 异常)时,冒出的
-- 错误文本须带 item/节点/image_key 上下文与宿主原文,事后仅凭日志可定位。
local function _push_enlarged_texture(runtime, image_key, item_id)
  local ok, err = pcall(_apply_enlarged_texture, runtime, image_key)
  if not ok then
    error(("show_enlarged texture push failed for item=%s node=%s image_key=%s: %s"):format(
      tostring(item_id), tostring(nodes.enlarged_card), tostring(image_key), tostring(err)), 0)
  end
end

function item_atlas_view.show_enlarged(state, item_id, deps)
  local ui = assert(state.ui, "missing ui")
  local runtime = _resolve_runtime(state, deps)
  local refs = runtime_assets.asset_context(state)

  local image_key = _item_image_key(refs, item_id)
  if image_key == nil then
    return
  end
  _push_enlarged_texture(runtime, image_key, item_id)
  _set_enlarged_overlay_visible(ui, true)
end

function item_atlas_view.hide_enlarged(state)
  local ui = assert(state.ui, "missing ui")
  _set_enlarged_overlay_visible(ui, false)
end

return item_atlas_view

