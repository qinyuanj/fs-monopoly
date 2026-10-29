local handlers = require("src.ui.render.anim.handlers")
local support = require("test.support.shared_support")

local M = {}

function M.build_min_state(opts)
  opts = opts or {}
  local state = {
    ui = {},
    board_scene = {
      ground = {
        get_position = function()
          return math.Vector3(0.0, 0.0, 0.0)
        end,
      },
      tiles = {
        [1] = {
          get_position = function()
            return math.Vector3(0.0, 0.0, 0.0)
          end,
        },
      },
      buildings = {
        [1] = {
          get_position = function()
            return math.Vector3(10.0, 0.0, 0.0)
          end,
        },
      },
      units_by_player_id = {},
    },
    game = {
      board = {
        get_tile = function(_, _tile_index)
          return { name = "测试地块" }
        end,
      },
      find_player_by_id = function()
        return { position = 1, name = "测试玩家" }
      end,
    },
  }

  if type(opts.tile_getter) == "function" then
    state.game.board.get_tile = opts.tile_getter
  end
  if type(opts.find_player_by_id) == "function" then
    state.game.find_player_by_id = opts.find_player_by_id
  end
  if type(opts.mutate) == "function" then
    opts.mutate(state)
  end
  return state
end

function M.capture_handler_duration(handler_key, payload)
  local captured_anim = nil
  local duration = nil
  return {
    patches = {
      {
        target = handlers,
        key = handler_key,
        value = function(_, anim)
          captured_anim = anim
          return duration or 0
        end,
      },
    },
    set_duration = function(value)
      duration = value
    end,
    captured_anim = function()
      return captured_anim
    end,
    payload = payload,
  }
end

M.with_patches = support.with_patches

return M
