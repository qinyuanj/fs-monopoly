local tile_mod = require("src.rules.board.tile")
local board_query = require("src.rules.board.query")
local property_value = require("src.rules.commerce.property_value")
local target_query = require("src.rules.items.target_query")

local demolish_choice = {}

local tile_state = tile_mod.get_state

-- 打分口径:他人名下且有建筑(level > 0)的地产才是拆除目标。
local function _is_demolish_target(st, player_id)
  return st.owner_id and st.owner_id ~= player_id and (st.level or 0) > 0
end

function demolish_choice.find_target(game, player, distance)
  local idx, value = target_query.find_best_tile(game, player, distance, {
    score_fn = function(tile)
      if tile.type ~= "land" then
        return -1
      end
      local st = tile_state(game, tile)
      if not _is_demolish_target(st, player.id) then
        return -1
      end
      return property_value.total_invested(tile, st.level)
    end,
  })
  if value < 0 then
    return nil
  end
  return idx
end

local function _not_own_land(st, player)
  return st.owner_id and st.owner_id ~= player.id and st.level > 0
end

local function _is_demolishable_tile(game, player, idx)
  if not idx or idx == player.position then return nil end
  local tile = game.board:get_tile(idx)
  if tile.type ~= "land" then return nil end
  local st = tile_state(game, tile)
  if not _not_own_land(st, player) then
    return nil
  end
  return tile
end

function demolish_choice.build_human_choice(game, player, distance, best_idx, opts)
  local idxs = board_query.indices_in_range(game.board, player.position, distance)
  local options = {}
  local body_lines = {}

  local function _push_option(idx)
    local tile = _is_demolishable_tile(game, player, idx)
    if not tile then return end
    table.insert(body_lines, "#" .. tostring(idx) .. " " .. tile.name)
    table.insert(options, { id = idx, label = tile.name })
  end

  for _, idx in ipairs(idxs) do
    _push_option(idx)
  end
  if #options == 0 then
    _push_option(best_idx)
  end
  if #options == 0 then
    return nil
  end

  local title = opts.title or "选择目标"
  local arranged, slot_layout = board_query.arrange_target_options(game.board, player, options)
  return {
    waiting = true,
    intent = {
      kind = "need_choice",
      choice_spec = {
        kind = "demolish_target",
        route_key = "target",
        owner_role_id = player.id,
        title = title .. "：选择目标格子",
        body_lines = body_lines,
        options = arranged,
        target_slot_layout = slot_layout,
        allow_cancel = true,
        cancel_label = "取消",
        meta = {
          player_id = player.id,
          item_id = opts.item_id,
          injure = opts.injure,
          title = opts.title
        },
      },
    },
  }
end

return demolish_choice

