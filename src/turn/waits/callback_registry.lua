local callback_registry = {}
callback_registry.callback_keys = {
  after_action_anim = "after_action_anim",
  after_landing_visual = "after_landing_visual",
}
callback_registry.wait_keys = {
  landing_visual = "landing_visual",
}

local function _ensure_runtime(game)
  assert(type(game) == "table", "missing game")
  local runtime = game.wait_callback_runtime
  if type(runtime) ~= "table" then
    runtime = {
      callbacks = {},
      seq_by_key = {},
      pending_seq_by_key = {},
      ready_seq_by_key = {},
    }
    game.wait_callback_runtime = runtime
  end
  return runtime
end

function callback_registry.register(game, key, callback)
  assert(type(key) == "string" and key ~= "", "missing callback key")
  assert(type(callback) == "function", "missing callback")
  local runtime = _ensure_runtime(game)
  runtime.callbacks[key] = callback
  return callback
end

local function _runtime_map_getter(field)
  return function(game, key)
    return _ensure_runtime(game)[field][key]
  end
end

callback_registry.peek = _runtime_map_getter("callbacks")

function callback_registry.take(game, key)
  local runtime = _ensure_runtime(game)
  local callback = runtime.callbacks[key]
  runtime.callbacks[key] = nil
  return callback
end

function callback_registry.clear(game, key)
  local runtime = _ensure_runtime(game)
  if key ~= nil then
    runtime.callbacks[key] = nil
    runtime.pending_seq_by_key[key] = nil
    runtime.ready_seq_by_key[key] = nil
    return
  end
  runtime.callbacks = {}
  runtime.pending_seq_by_key = {}
  runtime.ready_seq_by_key = {}
end

function callback_registry.reset_runtime(game)
  -- wait_callback_runtime is runtime-only state and should be cleared with
  -- presentation/runtime rebinding instead of leaking into gameplay state.
  return callback_registry.clear(game)
end

function callback_registry.begin_wait(game, key)
  assert(type(key) == "string" and key ~= "", "missing wait key")
  local runtime = _ensure_runtime(game)
  local next_seq = (runtime.seq_by_key[key] or 0) + 1
  runtime.seq_by_key[key] = next_seq
  runtime.pending_seq_by_key[key] = next_seq
  return next_seq
end

callback_registry.pending_wait_seq = _runtime_map_getter("pending_seq_by_key")

function callback_registry.mark_wait_ready(game, key, seq)
  local runtime = _ensure_runtime(game)
  if runtime.pending_seq_by_key[key] ~= seq then
    return false
  end
  runtime.ready_seq_by_key[key] = seq
  return true
end

function callback_registry.is_wait_ready(game, key)
  local runtime = _ensure_runtime(game)
  local pending_seq = runtime.pending_seq_by_key[key]
  return pending_seq ~= nil and runtime.ready_seq_by_key[key] == pending_seq
end

function callback_registry.finish_wait(game, key, seq)
  local runtime = _ensure_runtime(game)
  if runtime.pending_seq_by_key[key] ~= seq then
    return false
  end
  runtime.pending_seq_by_key[key] = nil
  runtime.ready_seq_by_key[key] = nil
  return true
end

return callback_registry

