local host_slot = require("src.ui.seams.host_slot")

-- 宿主 scene UI port：3D 场景内 UI 层的可见性/销毁/节点访问。
-- has_scene_ui_support 未装配时返回 false，调用方走无 scene UI 路径。
return host_slot.new({
  { name = "set_scene_ui_visible" },
  { name = "destroy_scene_ui" },
  { name = "has_scene_ui_support", default = false },
  { name = "get_eui_node_at_scene_ui" },
})

