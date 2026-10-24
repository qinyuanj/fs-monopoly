-- 皮肤交易请求/UI action 共用一套字段别名(type|action, slot_index|index|slot),
-- 归一化只住这里:别名链一变,skin_panel 门面各动作同步生效。
local request_shape = {}

function request_shape.kind(request)
  if type(request) == "table" then
    return request.type or request.action
  end
  return request
end

function request_shape.slot_index(request)
  if type(request) == "table" then
    return request.slot_index or request.index or request.slot or 1
  end
  return 1
end

function request_shape.unlock_source(request, fallback)
  if type(request) == "table" then
    return request.source
  end
  return fallback
end

return request_shape

