local host_slot = require("src.ui.seams.host_slot")

-- 宿主自定义事件 port：注册/注销全局自定义事件。register 装配后透传宿主的
-- (true, trigger) 双返回值；未装配时返回 false，与宿主缺 LuaAPI 的降级一致。
return host_slot.new({
  { name = "register_custom_event", default = false },
  { name = "unregister_custom_event", default = false },
  -- #199:输入框「输入完成」触发器,透传宿主 (true, trigger);未装配时 false。
  { name = "register_input_text_end", default = false },
})

