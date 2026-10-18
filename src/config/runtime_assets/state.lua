local default_refs = require("src.config.content.runtime_refs")
local default_skins = require("src.config.content.skins")
local default_constants = require("src.config.gameplay.runtime_constants")

local M = {}

local active_refs = default_refs
local active_skins = default_skins
local active_constants = default_constants
local active_startup_item_ids

local function _default_startup_item_ids()
  return { 3001, 3002, 3003, 3004, 3005 }
end

active_startup_item_ids = _default_startup_item_ids()

function M.refs(opts)
  if type(opts) == "table" and type(opts.refs) == "table" then
    return opts.refs
  end
  if type(opts) == "table" and type(opts.images) == "table" then
    return opts
  end
  return active_refs
end

function M.images(opts)
  return M.refs(opts).images or {}
end

function M.skins()
  return active_skins
end

function M.constants()
  return active_constants
end

function M.startup_item_ids()
  return active_startup_item_ids
end

function M.asset_context(root_state)
  if type(root_state) ~= "table" then
    return nil
  end
  local context = root_state.runtime_asset_context
  if type(context) ~= "table" then
    return nil
  end
  -- 空表(init_ui_assets 的占位)须归一为 nil:落到 refs() 时空表与 nil 一样
  -- 回落默认 refs,但 market _asset_opts 一类的包装缝会把空表当空 images,
  -- 吞掉默认查找(黑市道具图因此不加载)。
  if next(context) == nil then
    return nil
  end
  return context
end

-- startup_item_ids 单独成助手:短路 or 保证 opts 显式给值时不再求值
-- 默认构建(与 configure_for_tests 其余字段的 or 语义一致)。
local function _pick_startup_item_ids(opts)
  return opts.startup_item_ids or _default_startup_item_ids()
end

function M.configure_for_tests(opts)
  opts = opts or {}
  active_refs = opts.refs or default_refs
  active_skins = opts.skins or default_skins
  active_constants = opts.constants or default_constants
  active_startup_item_ids = _pick_startup_item_ids(opts)
end

function M.reset_for_tests()
  active_refs = default_refs
  active_skins = default_skins
  active_constants = default_constants
  active_startup_item_ids = _default_startup_item_ids()
end

return M

