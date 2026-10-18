local runtime = require("src.ui.render.support.runtime_ui")
local player_colors = require("src.ui.view.player_colors")
local ui_nodes = require("src.ui.render.support.node_ops")
local base_nodes = require("src.ui.schema.base")
local permanent_nodes = require("src.ui.schema.permanent")
local number_utils = require("src.foundation.number")
local runtime_assets = require("src.config.runtime_assets")

local M = {}

function M.init_ui_assets(state)
  assert(state ~= nil, "missing state")
  state.runtime_assets = runtime_assets
  state.runtime_asset_context = {}

  runtime.for_each_role_or_global(function()
    for index = 1, 5 do
      local icon = runtime_assets.startup_item_slot_icon(index)
      assert(icon.ok == true, "missing item icon: " .. tostring(icon.lookup_key))
      ui_nodes.set_item_slot_image(permanent_nodes.item_slots[index], icon.image_key)
    end
  end)
  runtime.set_client_role(nil)
end

local function _capture_base_panel_colors(colors_by_index)
  for index = 1, 4 do
    local node_name = string.format(base_nodes.player_color, index)
    local ok, node = pcall(runtime.query_node, node_name)
    if ok and node then
      local color = number_utils.to_integer(node.image_color)
      if color ~= nil then
        colors_by_index[index] = color
      end
    end
  end
end

local function _run_color_capture(capture_fn)
  if type(runtime.with_client_role) == "function" then
    runtime.with_client_role(nil, capture_fn)
  else
    runtime.set_client_role(nil)
    capture_fn()
  end
  runtime.set_client_role(nil)
end

local function _map_player_colors(players, colors_by_index)
  local owner_colors = {}
  local mapped_count = 0
  local unique_colors = {}
  for index = 1, 4 do
    local player = players[index]
    local color = colors_by_index[index]
    if player and player.id ~= nil and color ~= nil then
      owner_colors[player.id] = color
      mapped_count = mapped_count + 1
      unique_colors[color] = true
    end
  end
  return owner_colors, mapped_count, unique_colors
end

local function _count_unique(unique_colors)
  local count = 0
  for _ in pairs(unique_colors) do
    count = count + 1
  end
  return count
end

local function _game_players(game)
  return game and game.players or nil
end

-- 命中「按 owner 设置」:至少映射到一个玩家,且唯一色可区分
-- (单个玩家或唯一色多于 1 种)。
local function _should_set_owner_colors(mapped_count, unique_colors)
  if mapped_count <= 0 then
    return false
  end
  return mapped_count == 1 or _count_unique(unique_colors) > 1
end

function M.capture_player_colors(state, game)
  assert(state ~= nil, "missing state")
  local players = _game_players(game)
  if type(players) ~= "table" then
    return
  end
  local colors_by_index = {}
  _run_color_capture(function() _capture_base_panel_colors(colors_by_index) end)
  local owner_colors, mapped_count, unique_colors = _map_player_colors(players, colors_by_index)
  if _should_set_owner_colors(mapped_count, unique_colors) then
    player_colors.set_owner_colors(owner_colors)
    return
  end
  player_colors.remap_by_index(players)
end

return M

