-- state.board_runtime 切片:棋盘位置快照与 follow 目标。
-- 原 src/state/runtime.lua 的 board/follow 块;公共面仍由 runtime.lua 门面转发。
local tables = require("src.foundation.tables")

local M = {}

function M.ensure(state)
  assert(type(state) == "table", "missing state")
  local board_runtime = tables.ensure_table_field(state, "board_runtime")
  if board_runtime.board_last_positions == nil then
    board_runtime.board_last_positions = state.board_last_positions or {}
  end
  if board_runtime.follow_targets == nil then
    board_runtime.follow_targets = {}
  end
  tables.ensure_field(board_runtime, "board_sync_pending", state.board_sync_pending == true)
  tables.ensure_field(board_runtime, "board_last_phase", state.board_last_phase)
  return board_runtime
end

-- Out-of-order follow updates are dropped: a lower seq than the one already
-- recorded means this write is stale. Missing seqs never count as stale.
local function _is_stale_follow_seq(entry, next_seq)
  local last_seq = entry and entry.seq
  if next_seq == nil or last_seq == nil then
    return false
  end
  return next_seq < last_seq
end

local function _apply_follow_target(entry, position, opts, next_seq)
  entry.position = position
  entry.source = opts.source
  entry.seq = next_seq ~= nil and next_seq or entry.seq
end

local function _complete_args(state, player_id, position)
  return state ~= nil and player_id ~= nil and position ~= nil
end

local function _ensure_follow_entry(board_runtime, player_id)
  local entry = board_runtime.follow_targets[player_id]
  if entry == nil then
    entry = {}
    board_runtime.follow_targets[player_id] = entry
  end
  return entry
end

function M.set_follow_target_position(state, player_id, position, opts)
  if not _complete_args(state, player_id, position) then
    return false
  end
  local board_runtime = M.ensure(state)
  opts = opts or {}
  local next_seq = opts.seq
  if _is_stale_follow_seq(board_runtime.follow_targets[player_id], next_seq) then
    return false
  end
  local entry = _ensure_follow_entry(board_runtime, player_id)
  _apply_follow_target(entry, position, opts, next_seq)
  return true
end

function M.get_follow_target_position(state, player_id)
  if state == nil or player_id == nil then
    return nil
  end
  local board_runtime = M.ensure(state)
  local entry = board_runtime.follow_targets[player_id]
  return entry and entry.position or nil
end

return M

