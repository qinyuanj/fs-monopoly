local debug_flags = require("src.config.gameplay.debug_flags")

local M = {}

local function _add_debug_auto_player(auto_players, entry)
  if entry == nil or entry.role_id == nil then
    return auto_players
  end
  auto_players = auto_players or {}
  auto_players[entry.role_id] = true
  return auto_players
end

-- 起始席位：全托管联调开关打开时从 1 号位(真人)开始全席位托管,关闭则不建表。
local function _first_auto_slot()
  if debug_flags.debug_auto_all_roles == true then
    return 1
  end
  return nil
end

function M.build_auto_players(role_roster)
  local first_slot = _first_auto_slot()
  if first_slot == nil then
    return nil
  end
  local auto_players = nil
  for i = first_slot, #role_roster do
    auto_players = _add_debug_auto_player(auto_players, role_roster[i])
  end
  return auto_players
end

return M

