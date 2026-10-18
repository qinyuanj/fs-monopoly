-- ui 宿主能力 port 清单单一真源（#250/#251）：5 个 host 能力
-- port 槽的有序表。app 装配（host_install）、聚合面（host_runtime）与 spec 支撑
-- （shared_support / test_env）均批量消费本表——新增/删除一个 host port 只改这一处。
return {
  (require("src.ui.seams.host_events")),
  (require("src.ui.seams.host_roles")),
  (require("src.ui.seams.host_units")),
  (require("src.ui.seams.host_sfx")),
  (require("src.ui.seams.host_scene_ui")),
}

