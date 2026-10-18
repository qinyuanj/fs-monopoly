local host_slot = require("src.ui.seams.host_slot")

-- 宿主音效 port：特效音/3D 音播放与音效挂接单位。未装配时返回 nil。
return host_slot.new({
  { name = "play_sfx_by_key" },
  { name = "play_3d_sound" },
  { name = "bind_sfx_to_unit" },
})

