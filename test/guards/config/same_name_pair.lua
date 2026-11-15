-- 出生类配置（#298）：发现式包结构 guard 的存量同名对白名单
-- 快照。同名对 = <dir>/<name>.lua 与 <dir>/<name>/test/ 并存。只许减不许增:
-- 白名单条目由迁移工单(拓扑搬迁/同名对消灭)逐个销账删除;guard 拦的是白名单
-- 之外的一切新同名对——新测试一律随包(<pkg>/test/),不建 foo.lua + foo/test/。

return {
  pairs = {
    -- #234 F14:behavior_parallel 全仓零消费者(verify 的 behavior 车道已走 spec-lane),
    -- 模块+测试整删,白名单条目随销。
    -- #361 P3 销账:ring_map_builder 全仓零消费者,模块+测试整删,白名单条目随删。
    -- #320 包退场:test_harness_fail_fast 自 tools/wrappers/test/ 迁入,
    -- 为 test/support 测试支撑模块自有 test/ 目录(非 <pkg>/ 包,无包可随)。
    -- #561:模块去 test_ 前缀,条目随 test_harness → harness 改名平移。
    ["test/support/harness"] = true,
  },
}
