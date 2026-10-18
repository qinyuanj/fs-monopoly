local visual_sync_shared = {}

function visual_sync_shared.deps(state)
  return state and state.presentation_runtime or nil
end

function visual_sync_shared.resolve_board(state)
  local game = state and state.game or nil
  return game and game.board or nil
end

function visual_sync_shared.resolve_scene(state)
  return state and state.board_scene or nil
end

return visual_sync_shared

