-- 同主连片(same-owner connected component)的唯一走法。
--
-- 这张图上只有一种遍历：从一块地出发,沿 land 邻接扩散,收编所有同主地块。
-- 领域侧(src/rules/land/rent_math 算连片租金)和视图侧(src/ui/view/contiguous_count
-- 算连片数)以前各写了一遍 BFS——同一条不变量(「连片 = 同主 + 邻接可达」)有两个落点,
-- 视图侧那份的存在理由只是「不想让 ui require rules」。邻接表已经收敛到
-- src.state.land_adjacency,遍历本身同样是 state 上的纯图操作,于是一并收敛到这里。
--
-- owner_of / neighbors_of 是调用方接缝,严格程度由调用方决定：领域侧要求邻接齐全
-- (缺邻居即断言失败),视图侧面对可能残缺的局部投影时退化为空邻接。
--
-- 依赖方向：state 是内层,rules 与 ui 都向内依赖它(ui_no_rules 仍然成立)。

local land_component = {}

-- 未访问邻居收编进下一波;波次主循环只负责「同主才展开」的判定。
local function _collect_unvisited(visited, next_wave, neighbors)
  for _, next_id in ipairs(neighbors) do
    if visited[next_id] == nil then
      visited[next_id] = next_id
      next_wave[#next_wave + 1] = next_id
    end
  end
end

---@param start_tile_id any 起点地块 id(调用方保证非 nil)
---@param owner_id any 目标地主 id
---@param owner_of fun(tile_id: any): any 取地块当前地主
---@param neighbors_of fun(tile_id: any): table 取地块的 land 邻居 id 列表
---@return table component 按 BFS 顺序排列的同主地块 id 列表(起点不同主时为空表)
function land_component.same_owner(start_tile_id, owner_id, owner_of, neighbors_of)
  -- 波次 BFS(逐层推进,顺序与单队列 BFS 逐位一致)。选这个形态而不是 head 游标
  -- 单队列:游标 +1 / 布尔 visited 的变异体是不终止死循环,断言杀不掉只能等超时;
  -- 波次形态下每个位点的变异体都收敛为报错或结果错误,便于变异测试观测。
  -- visited 存地块 id 本身(不存 true),入会检查用 == nil 而非 not。
  local visited = { [start_tile_id] = start_tile_id }
  local component = {}
  local wave = { start_tile_id }

  while wave[1] ~= nil do
    local next_wave = {}
    for _, tile_id in ipairs(wave) do
      if owner_of(tile_id) == owner_id then
        component[#component + 1] = tile_id
        _collect_unvisited(visited, next_wave, neighbors_of(tile_id))
      end
    end
    wave = next_wave
  end

  return component
end

return land_component

