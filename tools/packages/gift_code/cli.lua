-- packages/gift_code/cli.lua —— gift-code 子命令(#203 / ADR 0075 修订)。
--
-- 统一接口形态(#300 决议):
--   M.main(args, env) -> 退出码(0 成功 / 1 失败 / 2 用法错误 / 3 随机源不可用)
--   M.usage()         -> 完整 usage 文本(包内单一真源)
--
-- gift-code new 一条命令为一名受损玩家生成补偿码:读安全随机源生成 12 位码 →
-- 分配 id(max(现有 id, 停用 id) + 1)→ 用 gift_code_catalog.code_hash(与游戏
-- 查码同一份规范化 + SHA-256)算哈希 → 在码表 codes 列表末尾追加一条,其余
-- 内容逐字保留 → 立即用码表模块重新加载校验,不过则回滚文件退 1。明文码只
-- 打印到 stdout,不落盘。
--
-- env 注入面(测试用;缺省即真实环境):code_table_path、random_bytes(n) ->
-- string|nil、now() -> Unix 秒、stdout / stderr(带 :write 的对象)。
local M = {}

local boundary = require("foundation.platform_boundary")
local fs_lib = require("foundation.fs")
local path_lib = require("foundation.path")
local number_utils = require("src.foundation.number")
local gift_code_catalog = require("src.config.content.gift_code_catalog")
local skins = require("src.config.content.skins")

local CODE_TABLE = "src/config/content/gift_codes.lua"
-- 31 个字符:去掉 0、O、1、I、L。
local ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
local CODE_LENGTH = 12
-- 字节落在 [0, 248) 才取模,248 = 31 × 8,避免取模偏差。
local UNBIASED_LIMIT = (256 // #ALPHABET) * #ALPHABET
local DEFAULT_DAYS = 180
local DAY_SECONDS = 86400

function M.usage()
  return table.concat({
    "用法: lua5.4 tools/cli.lua gift-code new --rewards <product_id>[,...] --note <文本> [--days N]",
    "",
    "为一名受损玩家生成一人一码的补偿码,并追加到 " .. CODE_TABLE .. "。",
    "  --rewards  奖励皮肤 product_id,逗号分隔;须在 skins.lua 且配了 archive_key",
    "  --note     工单号或补偿原因(必填,不写玩家昵称)",
    "  --days     有效天数,正整数,默认 " .. DEFAULT_DAYS,
    "",
    "码表只存 code_hash;明文码只在终端打印这一次,不写进任何文件,当场记进仓外发放记录。",
    "退出码:0 成功 / 1 失败(码表已回滚)/ 2 用法错误 / 3 安全随机源(/dev/urandom)不可用",
    "",
  }, "\n") .. "\n"
end

local function _urandom(n)
  local file = io.open("/dev/urandom", "rb")
  if file == nil then
    return nil
  end
  local bytes = file:read(n)
  file:close()
  if type(bytes) ~= "string" or #bytes ~= n then
    return nil
  end
  return bytes
end

local function _parse_positive_integer(text)
  if text == nil or not text:match("^%d+$") then
    return nil
  end
  local value = number_utils.to_integer(text)
  if value == nil or value <= 0 then
    return nil
  end
  return value
end

local function _parse_rewards(text)
  local rewards = {}
  for item in (text .. ","):gmatch("([^,]*),") do
    local product_id = _parse_positive_integer((item:gsub("^%s+", ""):gsub("%s+$", "")))
    if product_id == nil then
      return nil
    end
    rewards[#rewards + 1] = product_id
  end
  return rewards
end

local function _parse_new_args(args)
  local options = {}
  local i = 2
  while i <= #args do
    local flag, value = args[i], args[i + 1]
    if (flag ~= "--rewards" and flag ~= "--note" and flag ~= "--days") or value == nil then
      return nil, "未知或缺值的参数: " .. tostring(flag)
    end
    options[flag:sub(3)] = value
    i = i + 2
  end
  if options.rewards == nil then
    return nil, "缺少 --rewards"
  end
  local rewards = _parse_rewards(options.rewards)
  if rewards == nil then
    return nil, "--rewards 须是逗号分隔的 product_id: " .. options.rewards
  end
  if options.note == nil or options.note:match("^%s*$") then
    return nil, "缺少 --note(工单号或补偿原因)"
  end
  local days = DEFAULT_DAYS
  if options.days ~= nil then
    days = _parse_positive_integer(options.days)
    if days == nil then
      return nil, "--days 须是正整数: " .. options.days
    end
  end
  return { rewards = rewards, note = options.note, days = days }
end

local function _load_table(path)
  local chunk, err = loadfile(path, "t", {})
  if chunk == nil then
    return nil, err
  end
  local ok, value = pcall(chunk)
  if not ok or type(value) ~= "table" then
    return nil, "码表未返回 table: " .. tostring(value)
  end
  return value
end

local function _next_id(code_table)
  local max_id = 0
  for _, entry in ipairs(code_table.codes or {}) do
    if number_utils.is_numeric(entry.id) and entry.id > max_id then
      max_id = entry.id
    end
  end
  for _, id in ipairs(code_table.retired_ids or {}) do
    if number_utils.is_numeric(id) and id > max_id then
      max_id = id
    end
  end
  return number_utils.to_integer(max_id) + 1
end

-- 拒绝采样凑满 12 个字符;随机源取不到返回 nil。
local function _generate_code(random_bytes)
  local chars = {}
  while #chars < CODE_LENGTH do
    local bytes = random_bytes(CODE_LENGTH)
    if type(bytes) ~= "string" or #bytes == 0 then
      return nil
    end
    for i = 1, #bytes do
      local byte = bytes:byte(i)
      if byte < UNBIASED_LIMIT and #chars < CODE_LENGTH then
        local index = byte % #ALPHABET + 1
        chars[#chars + 1] = ALPHABET:sub(index, index)
      end
    end
  end
  return table.concat(chars)
end

local function _group(code)
  return code:sub(1, 4) .. "-" .. code:sub(5, 8) .. "-" .. code:sub(9, 12)
end

local function _entry_line(id, code, rewards, expires_at, note)
  local reward_texts = {}
  for i, product_id in ipairs(rewards) do
    reward_texts[i] = tostring(product_id)
  end
  return string.format('    { id = %d, code_hash = "%s", rewards = { %s }, expires_at = %d, note = %q },\n',
    id, gift_code_catalog.code_hash(code), table.concat(reward_texts, ", "), expires_at, note)
end

-- 在 `  codes = {` 之后第一个 `  },` 行前插入;定位不到返回 nil。
local function _insert_entry(content, line)
  local codes_start = content:find("\n  codes = {[ \t]*\n")
  if codes_start == nil then
    return nil
  end
  local close_start = content:find("\n  },[ \t]*\n", codes_start + 1)
  if close_start == nil then
    return nil
  end
  return content:sub(1, close_start) .. line .. content:sub(close_start + 1)
end

-- 从文件重新加载并用码表模块校验,且新码的明文必须查回新 id。
local function _verify_written(path, id, code)
  local code_table, load_err = _load_table(path)
  if code_table == nil then
    return false, load_err
  end
  local ok, catalog = pcall(gift_code_catalog.build, code_table.codes, skins, code_table.retired_ids)
  if not ok then
    return false, tostring(catalog)
  end
  local entry = catalog.find(_group(code))
  if entry == nil or entry.id ~= id then
    return false, "新码未能按哈希查回 id " .. id
  end
  return true
end

local function _skin_names(rewards)
  local by_product = {}
  for _, skin in ipairs(skins) do
    by_product[skin.product_id] = skin.name
  end
  local names = {}
  for i, product_id in ipairs(rewards) do
    names[i] = by_product[product_id] or tostring(product_id)
  end
  return table.concat(names, "、")
end

local function _new(options, env, stdout, stderr)
  local path = env.code_table_path or path_lib.join_path(env.repo_root or ".", CODE_TABLE)
  local original = fs_lib.read_raw(path)
  local code_table, load_err = nil, "无法读取码表: " .. path
  if original ~= nil then
    code_table, load_err = _load_table(path)
  end
  if code_table == nil then
    stderr:write("gift-code new 失败: " .. tostring(load_err) .. "\n")
    return 1
  end
  local code = _generate_code(env.random_bytes or _urandom)
  if code == nil then
    stderr:write(boundary.unavailable_verdict("gift-code", " tool=gift-code step=random", {
      "读不到安全随机源 /dev/urandom;不退回伪随机,码表未改动。",
    }).message)
    return boundary.UNAVAILABLE_EXIT_CODE
  end
  local id = _next_id(code_table)
  local now = (env.now or os.time)()
  local expires_at = number_utils.to_integer(now) + options.days * DAY_SECONDS
  local updated = _insert_entry(original, _entry_line(id, code, options.rewards, expires_at, options.note))
  if updated == nil then
    stderr:write("gift-code new 失败: 码表里定位不到 `  codes = {` … `  },` 列表\n")
    return 1
  end
  if not fs_lib.write_file(path, updated) then
    stderr:write("gift-code new 失败: 无法写入码表 " .. path .. "\n")
    return 1
  end
  local verified, verify_err = _verify_written(path, id, code)
  if not verified then
    fs_lib.write_file(path, original)
    stderr:write("gift-code new 失败(码表已回滚): " .. tostring(verify_err) .. "\n")
    return 1
  end
  stdout:write(table.concat({
    "id: " .. id,
    "码: " .. _group(code),
    "过期: " .. os.date("%Y-%m-%d", expires_at) .. " (" .. expires_at .. ")",
    "奖励: " .. _skin_names(options.rewards),
    "",
  }, "\n"))
  return 0
end

function M.main(args, env)
  args = args or {}
  env = env or {}
  local stdout = env.stdout or io.stdout
  local stderr = env.stderr or io.stderr
  local first = args[1]
  if first == "--help" or first == "-h" then
    stdout:write(M.usage())
    return 0
  end
  if first ~= "new" then
    stderr:write("未知子命令: " .. tostring(first) .. "\n\n" .. M.usage())
    return 2
  end
  local options, usage_err = _parse_new_args(args)
  if options == nil then
    stderr:write(usage_err .. "\n\n" .. M.usage())
    return 2
  end
  return _new(options, env, stdout, stderr)
end

return M
