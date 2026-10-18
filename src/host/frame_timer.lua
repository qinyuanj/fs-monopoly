--- 帧定时器 host adapter:收编 vendor Utils.SetFrameOut 的被用面。
--- 只实现可取消的无限重复帧回调(gameplay tick loop 唯一用法),不做 pause/resume;
--- 宿主全局 RegisterTriggerEvent / UnregisterTriggerEvent / EVENT / math.tofixed 只在本 host 层触碰。
local frame_timer = {}

-- 宿主帧率:interval(帧)换算为 EVENT.REPEAT_TIMEOUT 的秒间隔;Eggy Fixed 参数用浮点。
local FRAMES_PER_SECOND = 30.0

--- 注册一个每 interval 帧无限触发的回调。
--- @param interval integer 触发间隔(单位:帧)
--- @param callback fun() 每次触发调用的回调
--- @return table handle 取消凭证
function frame_timer.repeat_every(interval, callback)
  assert(type(callback) == "function", "frame_timer.repeat_every requires callback")
  local trigger_id = RegisterTriggerEvent(
    { EVENT.REPEAT_TIMEOUT, math.tofixed(interval) / FRAMES_PER_SECOND }, callback
  )
  return { trigger_id = trigger_id }
end

--- 取消重复帧回调;同一凭证可安全重复停止。
--- @param handle table|nil repeat_every 返回的取消凭证
function frame_timer.stop(handle)
  if handle == nil or handle.trigger_id == nil then
    return
  end
  UnregisterTriggerEvent(handle.trigger_id)
  handle.trigger_id = nil
end

return frame_timer

