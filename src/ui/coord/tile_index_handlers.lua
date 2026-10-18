-- tile 索引定位事件处理器(自 event_handlers.lua 拆分,行为保持):踩雷/地块
-- 命中的 payload→棋盘索引解析,返回索引供事件消费方使用。
local tile_index_handlers = {}
local context = { state = nil }

local function _event_data(data)
  if type(data) == "table" then
    return data
  end
  return nil
end

local function _resolve_tile_id(payload)
  if type(payload) ~= "table" then
    return nil
  end
  if payload.tile and payload.tile.id then
    return payload.tile.id
  end
  return payload.tile_id
end

local function _board_from_context()
  local ctx = context.state
  return ctx and ctx.game and ctx.game.board or nil
end

local function _index_of_tile_id_from_context(tile_id)
  local board = _board_from_context()
  if tile_id == nil or type(board and board.index_of_tile_id) ~= "function" then
    return nil
  end
  return board:index_of_tile_id(tile_id)
end

local function _resolve_tile_index_from_payload(payload)
  if type(payload) ~= "table" then
    return nil
  end
  if payload.tile_index ~= nil then
    return payload.tile_index
  end
  return _index_of_tile_id_from_context(_resolve_tile_id(payload))
end

function tile_index_handlers.set_context(state)
  context.state = state
end

function tile_index_handlers.install(register_handler, monopoly_event)
  register_handler(monopoly_event.movement.roadblock_hit, function(data)
    return _resolve_tile_index_from_payload(_event_data(data))
  end)

  register_handler(monopoly_event.land.mine_hit, function(data)
    return _resolve_tile_index_from_payload(_event_data(data))
  end)
end

return tile_index_handlers

