local canvas_store = {}
local _allowed_dirty_keys = {
  permanent = true,
  base = true,
  board = true,
  choice = true,
  effects = true,
  market = true,
}

local function _assert_valid_dirty_key(key)
  if key == nil then
    return
  end
  assert(_allowed_dirty_keys[key] == true, "unsupported canvas dirty key: " .. tostring(key))
end

local function _resolve_ui(state_or_ui)
  if type(state_or_ui) ~= "table" then
    return nil
  end
  if type(state_or_ui.ui) == "table" then
    return state_or_ui.ui
  end
  return state_or_ui
end

local function _init_store(ui)
  local store = ui.__canvas_store
  if type(store) == "table" then
    return store
  end
  store = {
    slices = ui.canvas_state or {},
    dirty = { any = true },
    version = 1,
  }
  ui.__canvas_store = store
  ui.canvas_store = store
  return store
end

function canvas_store.ensure(state_or_ui)
  local ui = _resolve_ui(state_or_ui)
  if not ui then
    return nil
  end
  return _init_store(ui)
end

function canvas_store.get_slice(state_or_ui, key)
  local store = canvas_store.ensure(state_or_ui)
  if not store or not key then
    return nil
  end
  _assert_valid_dirty_key(key)
  local slices = store.slices
  if type(slices[key]) ~= "table" then
    slices[key] = {}
  end
  return slices[key]
end

function canvas_store.mark_dirty(state_or_ui, key)
  local store = canvas_store.ensure(state_or_ui)
  if not store then
    return
  end
  _assert_valid_dirty_key(key)
  local dirty = store.dirty
  dirty.any = true
  if key then
    dirty[key] = true
  end
  store.version = (store.version or 0) + 1
end

-- 函数 patch 拿到 (slice, ui, state_or_ui) 自行改写；表 patch 直接浅合并。
local function _apply_patch(slice, patch, state_or_ui)
  if type(patch) == "function" then
    patch(slice, _resolve_ui(state_or_ui), state_or_ui)
    return
  end
  if type(patch) ~= "table" then
    error("canvas_store.patch_slice expects table/function patch")
  end
  for patch_key, patch_value in pairs(patch) do
    slice[patch_key] = patch_value
  end
end

function canvas_store.patch_slice(state_or_ui, key, patch)
  assert(key ~= nil, "missing canvas slice key")
  _assert_valid_dirty_key(key)
  local slice = canvas_store.get_slice(state_or_ui, key)
  if patch == nil then
    canvas_store.mark_dirty(state_or_ui, key)
    return slice
  end
  _apply_patch(slice, patch, state_or_ui)
  canvas_store.mark_dirty(state_or_ui, key)
  return slice
end

function canvas_store.consume_dirty(state_or_ui)
  local store = canvas_store.ensure(state_or_ui)
  if not store then
    return { any = false }
  end
  local dirty = store.dirty
  local spare = store._dirty_spare
  if spare ~= nil then
    spare.any = false
    spare.permanent = nil
    spare.base = nil
    spare.board = nil
    spare.choice = nil
    spare.effects = nil
    spare.market = nil
  else
    spare = { any = false }
  end
  store.dirty = spare
  store._dirty_spare = dirty
  return dirty
end

return canvas_store

