require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
local support = require("test.support.shared_support")
local default_map = require("src.config.content.default_map")
local land_rules = require("src.rules.land.landing_rules")
local rent_payment = require("src.rules.land.rent_payment")
local rent_resolver = require("src.rules.land.rent_resolver")

local _new_game = function()
  return support.new_game({ map = default_map })
end

local function _ensure_land_neighbors(board)
  if board.land_neighbors then
    return board.land_neighbors
  end
  -- Mirrors src.rules.land.rent_resolver._ensure_land_neighbors so tests share the same topology.
  local neighbors = assert(board.map and board.map.neighbors, "missing board.map.neighbors")
  local land_neighbors = {}
  for _, tile in ipairs(board.path or {}) do
    if tile and tile.type == "land" then
      local list = {}
      for _, next_id in pairs(neighbors[tile.id] or {}) do
        local next_tile = board:get_tile_by_id(next_id)
        if next_tile and next_tile.type == "land" then
          list[#list + 1] = next_id
        end
      end
      land_neighbors[tile.id] = list
    end
  end
  board.land_neighbors = land_neighbors
  return land_neighbors
end

local function _find_largest_connected_strip(board)
  local land_neighbors = _ensure_land_neighbors(board)
  local visited = {}
  local best_component = {}
  for _, tile in ipairs(board.path) do
    if tile.type == "land" and not visited[tile.id] then
      local component = { tile }
      visited[tile.id] = true
      local head = 1
      local queue = { tile.id }
      while head <= #queue do
        local tid = queue[head]
        head = head + 1
        for _, next_id in ipairs(land_neighbors[tid] or {}) do
          if not visited[next_id] then
            visited[next_id] = true
            local next_tile = board:get_tile_by_id(next_id)
            component[#component + 1] = next_tile
            queue[#queue + 1] = next_id
          end
        end
      end
      if #component > #best_component then
        best_component = component
      end
    end
  end
  return best_component
end

local function _find_strip(board, min_length)
  local strip = _find_largest_connected_strip(board)
  luassert.truthy(#strip >= min_length,
    "board has no connected land strip of length >= " .. tostring(min_length)
      .. " (largest = " .. tostring(#strip) .. ")")
  -- truncate to requested length while keeping connectivity (BFS order is contiguous)
  local out = {}
  for i = 1, min_length do out[i] = strip[i] end
  return out
end

local function _grant_strip_to_owner(game, owner, strip)
  for _, tile in ipairs(strip) do
    game:set_tile_owner(tile, owner.id)
    game:set_player_property(owner, tile.id, true)
  end
end


describe("TestDomainLandRentContiguousBehavior", function()
  it("test_execute_pay_rent_emits_payload_with_contiguous_count_single_rent_deity_multiplier", function()
    local g = _new_game()
    local payer = g.players[1]
    local owner = g.players[2]
    local three_strip = _find_strip(g.board, 3)
    _grant_strip_to_owner(g, owner, three_strip)

    local hit_tile = three_strip[2]
    payer.position = assert(g.board:index_of_tile_id(hit_tile.id), "hit index missing")
    local result = land_rules.execute_pay_rent(g, payer.id, hit_tile.id)
    luassert.truthy(result and result.ok, "execute_pay_rent should succeed")

    local payload = result.payload
    luassert.is.same(3, payload.contiguous_count, "payload should expose contiguous_count")
    luassert.is_true(payload.single_rent > 0, "payload should expose single_rent")
    luassert.is.same(1, payload.deity_multiplier, "no deity → multiplier == 1")

    local pricing = require("src.rules.land.pricing")
    local expected = 0
    for _, tile in ipairs(three_strip) do
      expected = expected + pricing.rent_for_level(tile, 0)
    end
    luassert.is.same(expected, payload.amount, "amount should equal contiguous sum without deity")
  end)

  it("test_rent_paid_multiplier_text_includes_contiguous_indicator_when_count_gt_1", function()
    local g = _new_game()
    local payer = g.players[1]
    local owner = g.players[2]
    local strip = _find_largest_connected_strip(g.board)
    luassert.truthy(#strip >= 2, "test requires a strip with count > 1")
    _grant_strip_to_owner(g, owner, strip)

    local hit_tile = strip[1]
    payer.position = assert(g.board:index_of_tile_id(hit_tile.id), "hit index missing")
    local result = land_rules.execute_pay_rent(g, payer.id, hit_tile.id)
    luassert.truthy(result and result.payload, "missing payload")
    local text = result.payload.text
    luassert.truthy(text:find("金币", 1, true), "rent text should include the currency")
    luassert.truthy(text:find("（连片）", 1, true) ~= nil, "rent text should show a compact contiguous breakdown, got: " .. text)
  end)

  it("test_multi_part_breakdown_joins_parts_with_comma", function()
    -- #293:breakdown_parts 的 "，" 连接(多部件文本)变异未测——连片部件与
    -- 神部件并存时才出现第二个部件。
    local g = _new_game()
    local payer = g.players[1]
    local owner = g.players[2]
    local three_strip = _find_strip(g.board, 3)
    _grant_strip_to_owner(g, owner, three_strip)
    payer.status = { deity = { type = "poor", remaining = 2 } }

    local hit_tile = three_strip[2]
    payer.position = assert(g.board:index_of_tile_id(hit_tile.id), "hit index missing")
    local result = land_rules.execute_pay_rent(g, payer.id, hit_tile.id)
    luassert.truthy(result and result.ok, "strip + deity rent should succeed")
    luassert.truthy(result.payload.text:find("（连片、穷神）", 1, true) ~= nil, "multi-part breakdown should use a compact summary, got: "
        .. tostring(result.payload.text))
  end)

  it("test_rent_paid_multiplier_text_is_nil_when_count_eq_1_and_no_deity", function()
    local g = _new_game()
    local payer = g.players[1]
    local owner = g.players[2]
    -- Find an isolated land tile: pick one whose all land-neighbors have no owner
    local land_neighbors = _ensure_land_neighbors(g.board)
    local isolated = nil
    for _, tile in ipairs(g.board.path) do
      if tile.type == "land" and #(land_neighbors[tile.id] or {}) == 0 then
        isolated = tile
        break
      end
    end
    if not isolated then
      -- fall back: grant only one tile from a multi-tile strip
      local strip = _find_largest_connected_strip(g.board)
      isolated = strip[1]
    end
    g:set_tile_owner(isolated, owner.id)
    g:set_player_property(owner, isolated.id, true)

    payer.position = assert(g.board:index_of_tile_id(isolated.id), "hit index missing")
    local result = land_rules.execute_pay_rent(g, payer.id, isolated.id)
    luassert.is.same(1, result.payload.contiguous_count, "isolated tile should report contiguous_count == 1")
    luassert.is_nil(result.payload.multiplier_text, "multiplier_text should be nil when no contiguous bonus and no deity")
    luassert.is_nil(result.payload.text:find("连片", 1, true), "main text should NOT mention contiguous when count == 1, got: " .. result.payload.text)
  end)

  it("test_contiguous_count_is_owner_symmetric_ai_owned_vs_human_owned_same_strip", function()
    local g = _new_game()
    local ai = g.players[2]
    local strip = _find_largest_connected_strip(g.board)
    luassert.truthy(#strip >= 2, "test requires a strip with count > 1")
    _grant_strip_to_owner(g, ai, strip)

    local hit_tile = strip[1]
    local idx = assert(g.board:index_of_tile_id(hit_tile.id), "hit index missing")
    local breakdown = rent_resolver.contiguous_breakdown(g, g.board, idx, ai.id)
    luassert.is.same(#strip, breakdown.count, "owner being AI does not change contiguous_count semantics")

    local g2 = _new_game()
    local human2 = g2.players[1]
    local strip2 = _find_largest_connected_strip(g2.board)
    _grant_strip_to_owner(g2, human2, strip2)
    local idx2 = assert(g2.board:index_of_tile_id(strip2[1].id), "hit index missing")
    local b2 = rent_resolver.contiguous_breakdown(g2, g2.board, idx2, human2.id)
    luassert.is.same(breakdown.count, b2.count, "AI-owned strip and human-owned strip share contiguous_count semantics")
  end)

  it("test_pin_paying_exactly_full_rent_leaves_payer_at_zero_but_not_bankrupt", function()
    local g = _new_game()
    local payer, owner = g.players[1], g.players[2]
    local strip = _find_strip(g.board, 1)
    _grant_strip_to_owner(g, owner, strip)
    local hit = strip[1]
    payer.position = assert(g.board:index_of_tile_id(hit.id))

    -- 先探出这次租金额,再把 payer 现金精确设为 rent。
    local probe = rent_payment.execute_pay_rent(g, payer.id, hit.id)
    local rent = probe.payload.amount
    -- 复位一局重来,精确边界:cash == rent
    g = _new_game(); payer, owner = g.players[1], g.players[2]
    _grant_strip_to_owner(g, owner, _find_strip(g.board, 1))
    local hit2 = _find_strip(g.board, 1)[1]
    payer.position = assert(g.board:index_of_tile_id(hit2.id))
    g:set_player_cash(payer, rent)

    local result = rent_payment.execute_pay_rent(g, payer.id, hit2.id)

    luassert.truthy(g:player_cash(payer) == 0, "payer drained to exactly zero")
    luassert.truthy(result.event == "rent_paid", "paying full rent is rent_paid, not rent_bankrupt")
    luassert.is_nil(result.bankrupt_reason, "exact-full payment is not bankruptcy")
  end)

  it("test_pin_paying_less_than_full_rent_is_rent_bankrupt_with_owner_credited_the_partial", function()
    local g = _new_game()
    local payer, owner = g.players[1], g.players[2]
    _grant_strip_to_owner(g, owner, _find_strip(g.board, 1))
    local hit = _find_strip(g.board, 1)[1]
    payer.position = assert(g.board:index_of_tile_id(hit.id))
    local received = {}
    g.achievement_progress_port = {
      cash_received = function(_, p, amt) received[#received+1] = { id = p.id, amount = amt }; return true end,
    }
    g:set_player_cash(payer, 1)  -- 远小于任何 rent

    local owner_before = g:player_cash(owner)
    local result = rent_payment.execute_pay_rent(g, payer.id, hit.id)

    luassert.truthy(result.event == "rent_bankrupt", "short payer triggers rent_bankrupt")
    luassert.is_not_nil(result.bankrupt_reason, "bankrupt_reason set for land_events to eliminate")
    luassert.truthy(g:player_cash(payer) == 0, "payer fully drained")
    luassert.truthy(g:player_cash(owner) == owner_before + 1, "owner credited the partial 1")
    luassert.truthy(received[1] and received[1].id == owner.id and received[1].amount == 1, "cash_received telemetry fires for the partial amount")
    luassert.is.same(payer.name .. " 余额不足，实际支付租金 1 金币后破产", result.payload.text, "bankruptcy text should show the actual paid amount")
    luassert.is_not.same(true, payer.eliminated, "eliminate deferred to land_events")
  end)

-- Synthetic single-land-tile board so version/cache/topology boundaries are
-- directly controllable, which the default_map fixtures cannot exercise.
end)
local function _make_board(tiles, neighbors)
  local by_id = {}
  for _, t in ipairs(tiles) do
    by_id[t.id] = t
  end
  return {
    map = { neighbors = neighbors },
    path = tiles,
    get_tile_by_id = function(_, id) return by_id[id] end,
    get_tile = function(_, index) return tiles[index] end,
  }
end

-- price 200, upgrade_costs {100} → rent_for_level 0 = 100, level 1 = 200.
local function _single_land(owner_id, level)
  return {
    id = 1,
    type = "land",
    price = 200,
    owner_id = owner_id,
    level = level or 0,
    upgrade_costs = { 100 },
  }
end


describe("TestDomainLandRentContiguousCacheAndBoundaryBehavior", function()
  it("test_contiguous_rent_and_contiguous_count_return_numeric_values_for_an_owned_tile", function()
    local game = {}
    local tile = _single_land("p1", 0)
    local board = _make_board({ tile }, { [1] = {} })
    -- kills L114 replace _resolve_component(...) with nil (would return nil rent).
    luassert.is.same(100, rent_resolver.contiguous_rent(game, board, 1, "p1"))
    luassert.is.same(1, rent_resolver.contiguous_count(game, board, 1, "p1"))
  end)

  it("test_returns_zero_rent_zero_count_and_a_zero_breakdown_when_the_query_owner_does_not_own_the_tile", function()
    local game = {}
    local tile = _single_land(nil, 0) -- unowned
    local board = _make_board({ tile }, { [1] = {} })
    -- kills both L97 replace 0 with 1 (rent slot and count slot of the early return).
    luassert.is.same(0, rent_resolver.contiguous_rent(game, board, 1, "p1"))
    luassert.is.same(0, rent_resolver.contiguous_count(game, board, 1, "p1"))
    -- kills all three L126 replace 0 with 1 (count/single_rent/total_rent of the zero breakdown).
    local breakdown = rent_resolver.contiguous_breakdown(game, board, 1, "p1")
    luassert.is.same(0, breakdown.count)
    luassert.is.same(0, breakdown.single_rent)
    luassert.is.same(0, breakdown.total_rent)
  end)

  it("test_level_less_land_tile_prices_at_level_zero", function()
    -- #293:`state.level or 0` 的 `0`→`1` 变异只在 level 缺失(而非 0)时可分。
    local game = {}
    local tile = {
      id = 1,
      type = "land",
      price = 200,
      owner_id = "p1",
      upgrade_costs = { 100 },
    }
    local board = _make_board({ tile }, { [1] = {} })
    local breakdown = rent_resolver.contiguous_breakdown(game, board, 1, "p1")
    -- level 0 → rent_for_level = 100;变异(level or 1)会按 200 计。
    luassert.is.same(100, breakdown.single_rent)
    luassert.is.same(100, breakdown.total_rent)
  end)

  it("test_explicit_level_drives_the_start_tile_rent", function()
    -- #293:L119 `start_state.level or 0` 的 or→and 变异在 level 显式非零时可分
    -- (and 会让它塌成 0 级租金)。
    local game = {}
    local tile = _single_land("p1", 1)
    local board = _make_board({ tile }, { [1] = {} })
    -- level 1 → rent_for_level = 200;or→and 变异会塌成 0 级租金 100。
    luassert.is.same(200, rent_resolver.contiguous_breakdown(game, board, 1, "p1").single_rent)
  end)

  it("test_keeps_the_cached_total_stale_until_the_rent_version_changes", function()
    local game = {}
    local tile = _single_land("p1", 0)
    local board = _make_board({ tile }, { [1] = {} })
    game._land_rent_version = 5

    local first = rent_resolver.contiguous_breakdown(game, board, 1, "p1")
    luassert.is.same(100, first.total_rent)

    -- Raise the level (fresh rent would be 200) but keep the same version.
    -- The cached total must remain 100.
    tile.level = 1
    local second = rent_resolver.contiguous_breakdown(game, board, 1, "p1")
    -- kills L37 replace ~= with == (would rebuild on equal version) and
    -- L50 replace not with removed not (would reset tile_count and force recompute).
    luassert.is.same(100, second.total_rent)
    -- kills L53 replace not with removed not (would reset tile_rents, dropping cached rents).
    luassert.is.same(1, #second.rents)
    luassert.is.same(100, second.rents[1])
  end)

  it("test_bumping_rent_version_from_the_implicit_zero_default_invalidates_the_cache", function()
    local game = {}
    local tile = _single_land("p1", 0)
    local board = _make_board({ tile }, { [1] = {} })
    -- No _land_rent_version set → version defaults to 0.
    luassert.is.same(100, rent_resolver.contiguous_rent(game, board, 1, "p1"))

    tile.level = 1
    game._land_rent_version = 1
    -- kills L35 replace 0 with 1 (default of nil version): a 1-default would match the
    -- stored cache version and wrongly reuse the stale 100.
    luassert.is.same(200, rent_resolver.contiguous_rent(game, board, 1, "p1"))
  end)

  it("test_changing_rent_version_away_from_a_truthy_value_invalidates_the_cache", function()
    local game = {}
    local tile = _single_land("p1", 0)
    local board = _make_board({ tile }, { [1] = {} })
    game._land_rent_version = 7
    luassert.is.same(100, rent_resolver.contiguous_rent(game, board, 1, "p1"))

    tile.level = 1
    game._land_rent_version = 0
    -- kills L35 replace or with and: `version and 0` would collapse the stored version to 0,
    -- matching the new 0 version and wrongly reusing the stale 100.
    luassert.is.same(200, rent_resolver.contiguous_rent(game, board, 1, "p1"))
  end)

  it("test_skips_non_land_path_tiles_when_building_land_neighbors", function()
    local game = {}
    local land = _single_land("p1", 0) -- id 1
    local non_land = { id = 2, type = "toolshop" }
    -- Only the land tile has a neighbors entry; the non-land tile deliberately has none.
    local board = _make_board({ land, non_land }, { [1] = {} })
    -- kills L16 replace and with or: touching tile id 2 would hit
    -- `assert(neigh ~= nil)` on the missing neighbors entry and throw.
    luassert.is.same(100, rent_resolver.contiguous_rent(game, board, 1, "p1"))
  end)

  it("test_drops_neighbor_ids_that_resolve_to_no_tile", function()
    local game = {}
    local land = _single_land("p1", 0) -- id 1
    -- Neighbor id 99 has no corresponding tile → get_tile_by_id returns nil.
    local board = _make_board({ land }, { [1] = { 99 } })
    -- kills L22 replace and with or: a nil next_tile would be indexed (`next_tile.type`) and throw.
    luassert.is.same(100, rent_resolver.contiguous_rent(game, board, 1, "p1"))
  end)

  it("test_ignores_non_land_ids_that_reach_it_through_the_shared_land_neighbors_cache", function()
    local game = {}
    local land = _single_land("p1", 0) -- id 1
    local shop = { id = 2, type = "toolshop" }
    local board = _make_board({ land, shop }, { [1] = {} })
    -- board.land_neighbors 由 src.state.land_adjacency 独家构建,它保证只含 land id。
    -- 但这个槽是 board 上的公开可写字段(不是 rent_resolver 的私有表示),
    -- 所以邻居取值器仍要在边界上过滤非 land 的 id,而不是把商店算进同色连片租金。
    board.land_neighbors = { [1] = { 2 } }
    luassert.is.same(100, rent_resolver.contiguous_rent(game, board, 1, "p1"))
    luassert.is.same(1, rent_resolver.contiguous_count(game, board, 1, "p1"))
  end)

-- 神灵租金修正 / 深山 / 无主地(工单 #126 变异补测)。
--
-- 这整片此前零护栏:变异测试显示 _compute_deity_rent 的两处 `rent * 2`、两处
-- `multiplier * 2` 全可以改成 `/`,execute_pay_rent 里 player_has_deity 两处调用可以整个
-- 删掉,`skip.reason == "mountain"` 可以反转成 `~=` —— 77 个位点存活 32 个,测试一条都不响。
-- 也就是说「穷神让付租人多掏一倍」「财神让收租人多收一倍」「地主在深山不收租」这三条规则,
-- 在此之前完全靠约定维持。下面把它们钉死。
end)
local function _set_deity(player, kind)
  player.status = player.status or {}
  player.status.deity = { type = kind, remaining = 2 }
end

local function _clear_deity(player)
  player.status = player.status or {}
  player.status.deity = { type = "", remaining = 0 }
end

-- 一局全新的牌面:owner 独占一格地,payer 正好踩在上面,双方都无神灵、payer 不差钱。
local function _rent_setup()
  local game = _new_game()
  local payer, owner = game.players[1], game.players[2]
  local strip = _find_strip(game.board, 1)
  _grant_strip_to_owner(game, owner, strip)
  local hit = strip[1]
  payer.position = assert(game.board:index_of_tile_id(hit.id))
  _clear_deity(payer)
  _clear_deity(owner)
  game:set_player_cash(payer, 1000000)
  return game, payer, owner, hit
end

-- 不经 execute_pay_rent 就把基准租金算出来,免得「探一次」本身扣掉现金。
local function _base_rent(game, owner, hit)
  local idx = assert(game.board:index_of_tile_id(hit.id))
  return rent_resolver.contiguous_breakdown(game, game.board, idx, owner.id).total_rent
end


describe("TestDomainLandRentDeityMultipliers", function()
  it("test_no_deity_rent_is_the_plain_contiguous_total_multiplier_1", function()
    local game, payer, owner, hit = _rent_setup()
    local base = _base_rent(game, owner, hit)

    local result = rent_payment.execute_pay_rent(game, payer.id, hit.id)

    luassert.is.same("rent_paid", result.event)
    luassert.is.same(base, result.payload.amount)
    luassert.is.same(1, result.payload.deity_multiplier)
  end)

-- 杀 `if poor_active then rent = rent * 2 end` 与 player_has_deity(player, "poor")。
  it("test_poor_deity_on_the_payer_doubles_the_rent", function()
    local game, payer, owner, hit = _rent_setup()
    local base = _base_rent(game, owner, hit)
    _set_deity(payer, "poor")

    local result = rent_payment.execute_pay_rent(game, payer.id, hit.id)

    luassert.is.same(base * 2, result.payload.amount)
    luassert.is.same(2, result.payload.deity_multiplier)
    luassert.truthy(result.payload.text:find("（穷神）", 1, true))
  end)

-- 杀 `if rich_active then rent = rent * 2 end` 与 player_has_deity(owner, "rich")。
-- 注意神灵是**认人不认位**的:穷神看付租人,财神看收租人。把这两个调用的实参对调也必须红。
  it("test_rich_deity_on_the_owner_doubles_the_rent", function()
    local game, payer, owner, hit = _rent_setup()
    local base = _base_rent(game, owner, hit)
    _set_deity(owner, "rich")

    local result = rent_payment.execute_pay_rent(game, payer.id, hit.id)

    luassert.is.same(base * 2, result.payload.amount)
    luassert.is.same(2, result.payload.deity_multiplier)
    luassert.truthy(result.payload.text:find("（财神）", 1, true))
  end)

-- 认人不认位的反向钉子:神灵挂错人身上就一律不生效。
  it("test_rich_on_the_payer_poor_on_the_owner_changes_nothing", function()
    local game, payer, owner, hit = _rent_setup()
    local base = _base_rent(game, owner, hit)
    _set_deity(payer, "rich")
    _set_deity(owner, "poor")

    local result = rent_payment.execute_pay_rent(game, payer.id, hit.id)

    luassert.is.same(base, result.payload.amount)
    luassert.is.same(1, result.payload.deity_multiplier)
    luassert.is_nil(result.payload.multiplier_text)
  end)

-- 杀两处 `multiplier = multiplier * 2` 的复合:两神叠加是 ×4,不是 ×2、也不是 +2。
  it("test_poor_on_payer_and_rich_on_owner_stack_to_x4", function()
    local game, payer, owner, hit = _rent_setup()
    local base = _base_rent(game, owner, hit)
    _set_deity(payer, "poor")
    _set_deity(owner, "rich")

    local result = rent_payment.execute_pay_rent(game, payer.id, hit.id)

    luassert.is.same(base * 4, result.payload.amount)
    luassert.is.same(4, result.payload.deity_multiplier)
    luassert.truthy(result.payload.text:find("（穷神、财神）", 1, true))
  end)

-- 无神灵时倍率标记不得出现。杀 _build_multiplier_text 里 `deity_multiplier > 1` 被放宽成
-- `>= 1` / `> 0` 的变异:那会让连片租金的文案变成「租金 ×1(连片 …)」。
-- 必须是连片(count > 1)才能触到这一行 —— 单格时 breakdown_parts 为空会提前 return nil。
  it("test_contiguous_rent_with_no_deity_shows_no_multiplier_marker", function()
    local game = _new_game()
    local payer, owner = game.players[1], game.players[2]
    local strip = _find_strip(game.board, 2)
    _grant_strip_to_owner(game, owner, strip)
    local hit = strip[1]
    payer.position = assert(game.board:index_of_tile_id(hit.id))
    _clear_deity(payer)
    _clear_deity(owner)
    game:set_player_cash(payer, 1000000)

    local result = rent_payment.execute_pay_rent(game, payer.id, hit.id)

    luassert.is.same(1, result.payload.deity_multiplier)
    local text = result.payload.text
    luassert.truthy(text, "contiguous rent must still explain itself")
    luassert.truthy(text:find("（连片）", 1, true))
    luassert.is_nil(text:find("穷神", 1, true), "no deity marker when no deity is active, got: " .. tostring(text))
  end)

-- remaining 归零的神灵是过期的,不该再翻倍(player_has_deity 要求 remaining > 0)。
  it("test_an_expired_deity_remaining_0_does_not_multiply", function()
    local game, payer, owner, hit = _rent_setup()
    local base = _base_rent(game, owner, hit)
    payer.status.deity = { type = "poor", remaining = 0 }

    local result = rent_payment.execute_pay_rent(game, payer.id, hit.id)

    luassert.is.same(base, result.payload.amount)
    luassert.is.same(1, result.payload.deity_multiplier)
  end)

end)
local function _mountain_index(board)
  for idx, tile in ipairs(board.path) do
    if tile.type == "mountain" then
      return idx
    end
  end
  return nil
end


-- 杀 `skip.reason == "mountain"` 的反转、`ok = false` 的翻转,以及那条事件名/文案。
-- 地主本人在深山时租金不收取 —— 反转判据后 payer 会被照常扣钱,此前没有任何东西会响。
describe("TestDomainLandRentSkipPaths", function()
  it("test_owner_in_the_mountain_skips_rent_entirely_and_charges_nobody", function()
    local game = _new_game()
    local payer, owner = game.players[1], game.players[2]
    local strip = _find_strip(game.board, 1)
    _grant_strip_to_owner(game, owner, strip)
    local hit = strip[1]
    payer.position = assert(game.board:index_of_tile_id(hit.id))
    game:set_player_cash(payer, 1000)

    local mountain_idx = _mountain_index(game.board)
    luassert.truthy(mountain_idx, "default map must have a mountain tile")
    owner.position = mountain_idx

    local result = rent_payment.execute_pay_rent(game, payer.id, hit.id)

    luassert.is_false(result.ok)
    luassert.is.same("rent_skipped_mountain", result.event)
    luassert.is.same(owner, result.payload.owner)
    luassert.truthy(result.payload.text:find("深山", 1, true))
    luassert.is.same(1000, game:player_cash(payer), "a skipped rent must not move any cash")
  end)

-- 杀 `return { ok = false, reason = "no_owner" }`。
  it("test_an_unowned_tile_yields_no_owner_and_charges_nobody", function()
    local game = _new_game()
    local payer = game.players[1]
    local strip = _find_strip(game.board, 1)
    local hit = strip[1]
    game:set_tile_owner(hit, nil)
    payer.position = assert(game.board:index_of_tile_id(hit.id))
    game:set_player_cash(payer, 1000)

    local result = rent_payment.execute_pay_rent(game, payer.id, hit.id)

    luassert.is_false(result.ok)
    luassert.is.same("no_owner", result.reason)
    luassert.is.same(1000, game:player_cash(payer), "an unowned tile must not move any cash")
  end)

-- ===== 迁自 test/property/test_rent_math.lua（#190, 测试极简化决策：property 车道退场，性质并入 behavior）=====
end)
local property = require("test.support.property")
local rent_math = require("src.rules.land.rent_math")

-- Build a random tile graph: ids 1..N, each tile owned by one of a small pool
-- (so contiguous same-owner clusters actually occur), carrying a non-negative
-- rent, with a random neighbour list drawn from the same id space. Every id has
-- a neighbour entry so the BFS never trips its missing-neighbours assertion.
local OWNER_POOL = { 1, 2, 3 }

local function _gen_graph(rng)
  local tile_count = rng:int(1, 12)
  local owners, rents, neighbors = {}, {}, {}
  for id = 1, tile_count do
    owners[id] = rng:pick(OWNER_POOL)
    rents[id] = rng:int(0, 500)
    local list = {}
    for _ = 1, rng:int(0, 3) do
      list[#list + 1] = rng:int(1, tile_count)
    end
    neighbors[id] = list
  end
  return {
    tile_count = tile_count,
    owner_id = rng:pick(OWNER_POOL),
    start_tile_id = rng:int(1, tile_count),
    owners = owners,
    rents = rents,
    neighbors = neighbors,
  }
end

local function _resolver_for(graph)
  return function(tile_id)
    return graph.owners[tile_id], graph.rents[tile_id]
  end
end

local function _compute(graph, neighbors)
  return rent_math.compute_contiguous_rent(
    graph.start_tile_id, graph.owner_id, neighbors or graph.neighbors, _resolver_for(graph))
end

local function _set(list)
  local seen = {}
  for _, value in ipairs(list) do
    seen[value] = true
  end
  return seen
end


describe("TestRentMathComputeContiguousRentProperties", function()
  it("test_reports_a_sum_equal_to_the_per_tile_rents_it_returns", function()
    property.for_all(_gen_graph, function(graph)
      local sum, component, rents = _compute(graph)
      luassert.truthy(#component == #rents, "component and rents lists must stay aligned")
      local total = 0
      for _, rent in ipairs(rents) do
        total = total + rent
      end
      luassert.truthy(sum == total, "the reported sum must equal the sum of the reported rents")
    end)
  end)

  it("test_only_includes_tiles_owned_by_the_queried_owner", function()
    property.for_all(_gen_graph, function(graph)
      local _, component = _compute(graph)
      for _, tile_id in ipairs(component) do
        luassert.truthy(graph.owners[tile_id] == graph.owner_id, "component tile " .. tostring(tile_id) .. " is not owned by the queried owner")
      end
    end)
  end)

  it("test_includes_the_start_tile_when_owned_and_is_empty_otherwise", function()
    property.for_all(_gen_graph, function(graph)
      local sum, component = _compute(graph)
      if graph.owners[graph.start_tile_id] == graph.owner_id then
        luassert.truthy(_set(component)[graph.start_tile_id] == true, "an owned start tile must appear in the component")
      else
        luassert.truthy(#component == 0, "an unowned start tile must yield an empty component")
        luassert.truthy(sum == 0, "an unowned start tile must yield zero rent")
      end
    end)
  end)

  it("test_is_independent_of_neighbour_ordering", function()
    property.for_all(_gen_graph, function(graph)
      local sum_forward, component_forward = _compute(graph)

      local reversed = {}
      for id, list in pairs(graph.neighbors) do
        local flipped = {}
        for index = #list, 1, -1 do
          flipped[#flipped + 1] = list[index]
        end
        reversed[id] = flipped
      end
      local sum_reverse, component_reverse = _compute(graph, reversed)

      luassert.truthy(sum_forward == sum_reverse, "rent sum must not depend on neighbour ordering")
      luassert.truthy(#component_forward == #component_reverse, "component size must not depend on neighbour ordering")
      local reverse_set = _set(component_reverse)
      for tile_id in pairs(_set(component_forward)) do
        luassert.truthy(reverse_set[tile_id] == true, "component membership must not depend on neighbour ordering")
      end
    end)
  end)

-- resolve 返回 nil 租金的地块按 0 计(rent_by_id 的 or 0 缺省):property 生成器
-- 恒给非负租金,这条缺省只有确定性用例能驱动。
  it("test_counts_a_nil_resolver_rent_as_zero", function()
    local neighbors = { [1] = { 2 }, [2] = { 1 } }
    local start_tile_id, owner_id = 1, 7
    local resolve_owner_and_rent = function(tile_id)
      if tile_id == 1 then
        return owner_id, nil -- 租金缺省:按 0 计
      end
      return owner_id, 100
    end
    local sum = rent_math.compute_contiguous_rent(
      start_tile_id, owner_id, neighbors, resolve_owner_and_rent)
    luassert.truthy(sum == 100, "a nil per-tile rent must count as zero")
  end)

  it("test_never_reports_a_negative_total_for_non_negative_rents", function()
    property.for_all(_gen_graph, function(graph)
      local sum = _compute(graph)
      luassert.truthy(sum >= 0, "non-negative rents cannot sum to a negative total")
    end)
  end)

end)

describe("TestRentResolverEntryGuardClosure", function()
  it("test_contiguous_rent_rejects_a_nil_board_with_the_guard_message", function()
    -- kills _require_land_neighbors' "missing board" -> nil.
    luassert.has_error(function()
      rent_resolver.contiguous_rent({}, nil, 1, "p1")
    end, "missing board")
  end)
end)
