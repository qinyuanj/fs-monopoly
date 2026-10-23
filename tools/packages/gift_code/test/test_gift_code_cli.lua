---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/gift_code/test/test_gift_code_cli.lua") end

require("test.bootstrap").install_package_paths()

-- gift-code new(#203):从 main 入口驱动,注入随机源、时钟、码表路径(临时
-- 文件)与输出流;只观察退出码、stdout/stderr 与码表文件内容。
local check = require("luassert")
local gift_code_cli = require("packages.gift_code.cli")
local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")

local NOW = 1700000000
local DAY = 86400

-- 码表夹具:末条 id 3,停用 1 与 5 → 下一个 id 应为 6。
local FIXTURE = table.concat({
  "-- 夹具码表",
  "local gift_codes = {",
  "  codes = {",
  '    { id = 3, code_hash = "682f05b696b1ca1d9b2818d793b2b352f4128f8ba4fa9db8770cfb279fce1f3f", rewards = { 5005 }, note = "#1" },',
  "  },",
  "  retired_ids = { 1, 5 },",
  "}",
  "",
  "gift_codes.redeem_record_archive_key = 1056",
  "",
  "return gift_codes",
  "",
}, "\n")

-- 字节 0..11 依次映射到字符集前 12 个字符:ABCDEFGHJKMN;其 SHA-256 由外部
-- sha256sum 算出。
local SEQUENTIAL_CODE = "ABCD-EFGH-JKMN"
local SEQUENTIAL_HASH = "f798776cb4d1e5975b47ed94fcc91314bc8d5c6935ff56b33c03b08c52356818"

local function _byte_source(bytes)
  local cursor = 1
  return function(n)
    local out = {}
    for _ = 1, n do
      out[#out + 1] = string.char(bytes[cursor])
      cursor = cursor % #bytes + 1
    end
    return table.concat(out)
  end
end

local function _sequential_source()
  local bytes = {}
  for i = 0, 11 do
    bytes[#bytes + 1] = i
  end
  return _byte_source(bytes)
end

local function _sink()
  local chunks = {}
  return {
    write = function(_, ...)
      for _, chunk in ipairs({ ... }) do
        chunks[#chunks + 1] = tostring(chunk)
      end
    end,
    text = function()
      return table.concat(chunks)
    end,
  }
end

-- 在临时码表上跑一次 main,返回 (退出码, stdout, stderr, 跑后的码表内容)。
local function _run(args, overrides)
  local path = env_lib.make_temp_path("gift_code_cli_spec", ".lua")
  check.is_true(fs_lib.write_file(path, FIXTURE))
  local stdout, stderr = _sink(), _sink()
  local env = {
    repo_root = ".",
    code_table_path = path,
    random_bytes = _sequential_source(),
    now = function()
      return NOW
    end,
    stdout = stdout,
    stderr = stderr,
  }
  for key, value in pairs(overrides or {}) do
    env[key] = value
  end
  local ok, code = pcall(gift_code_cli.main, args, env)
  local content = fs_lib.read_raw(path)
  fs_lib.remove_path(path)
  if not ok then
    error(code)
  end
  return code, stdout.text(), stderr.text(), content
end

local function _appended(content)
  check.is_true(#content > #FIXTURE, "the code table should have grown")
  local head = FIXTURE:match("^(.-  codes = {\n.-\n)  },\n")
  local tail = FIXTURE:sub(#head + 1)
  check.equal(head, content:sub(1, #head), "everything before the new entry should be kept verbatim")
  check.equal(tail, content:sub(-#tail), "everything after the new entry should be kept verbatim")
  return content:sub(#head + 1, #content - #tail)
end

describe("gift-code cli", function()

it("new appends a hashed entry under the next free id and prints the plaintext once", function()
  local code, out, err, content = _run({ "new", "--rewards", "5005,5006", "--note", "#203 补偿" })

  check.equal(0, code, err)
  local line = _appended(content)
  check.truthy(line:find("id = 6,", 1, true), "new id should skip retired ids: " .. line)
  check.truthy(line:find('code_hash = "' .. SEQUENTIAL_HASH .. '"', 1, true), "hash should match the printed code: " .. line)
  check.truthy(line:find("rewards = { 5005, 5006 }", 1, true), line)
  check.truthy(line:find("expires_at = " .. (NOW + 180 * DAY), 1, true), "default expiry should be 180 days: " .. line)
  check.truthy(line:find('note = "#203 补偿"', 1, true), line)
  check.is_nil(content:find("ABCDEFGHJKMN", 1, true), "plaintext must not land in the file")
  check.is_nil(content:find(SEQUENTIAL_CODE, 1, true), "grouped plaintext must not land in the file")

  check.truthy(out:find("id: 6", 1, true), out)
  check.truthy(out:find("码: " .. SEQUENTIAL_CODE, 1, true), out)
  check.truthy(out:find("%d%d%d%d%-%d%d%-%d%d %(" .. (NOW + 180 * DAY) .. "%)"), out)
  check.truthy(out:find("奶龙、水豚嘟嘟", 1, true), out)
end)

it("days overrides the default expiry", function()
  local code, _, err, content = _run({ "new", "--rewards", "5005", "--note", "#203", "--days", "30" })

  check.equal(0, code, err)
  check.truthy(_appended(content):find("expires_at = " .. (NOW + 30 * DAY), 1, true))
end)

it("generated codes are 12 characters from the unambiguous alphabet", function()
  local seed = 7
  local function _pseudo_bytes(n)
    local out = {}
    for i = 1, n do
      seed = (seed * 1103515245 + 12345) % 2147483648
      out[i] = string.char(seed % 256)
    end
    return table.concat(out)
  end
  for _ = 1, 20 do
    local code, out, err = _run({ "new", "--rewards", "5005", "--note", "#203" }, { random_bytes = _pseudo_bytes })
    check.equal(0, code, err)
    local printed = out:match("码: (%S+)")
    check.truthy(printed:match("^%w%w%w%w%-%w%w%w%w%-%w%w%w%w$"), "code should print as XXXX-XXXX-XXXX: " .. printed)
    local raw = printed:gsub("%-", "")
    check.is_nil(raw:find("[^ABCDEFGHJKMNPQRSTUVWXYZ23456789]"), "code should avoid 0/O/1/I/L and lowercase: " .. raw)
  end
end)

-- 字节 ≥ 248 丢弃重抽(31 × 8 = 248),避免取模偏差。
it("random bytes outside the unbiased range are discarded", function()
  local bytes = { 255, 248 }
  for i = 0, 11 do
    bytes[#bytes + 1] = i
  end
  local code, out, err = _run({ "new", "--rewards", "5005", "--note", "#203" }, { random_bytes = _byte_source(bytes) })

  check.equal(0, code, err)
  check.truthy(out:find("码: " .. SEQUENTIAL_CODE, 1, true), out)
end)

it("an invalid reward fails and leaves the code table unchanged", function()
  for _, rewards in ipairs({ "9999", "5005,9999" }) do
    local code, out, err, content = _run({ "new", "--rewards", rewards, "--note", "#203" })

    check.equal(1, code, "rewards=" .. rewards)
    check.equal(FIXTURE, content, "code table should be rolled back")
    check.truthy(err:find("9999", 1, true), err)
    check.is_nil(out:find("码:", 1, true), "no code should be printed on failure")
  end
end)

it("an unavailable random source exits 3 without touching the code table", function()
  local code, out, err, content = _run({ "new", "--rewards", "5005", "--note", "#203" }, {
    random_bytes = function()
      return nil
    end,
  })

  check.equal(3, code)
  check.equal(FIXTURE, content)
  check.truthy(err:find("status=unavailable", 1, true), err)
  check.equal("", out)
end)

it("missing or malformed arguments are usage errors that touch nothing", function()
  local cases = {
    {},
    { "old" },
    { "new", "--note", "#203" },
    { "new", "--rewards", "5005" },
    { "new", "--rewards", "5005", "--note", "  " },
    { "new", "--rewards", "abc", "--note", "#203" },
    { "new", "--rewards", "5005", "--note", "#203", "--days", "0" },
    { "new", "--rewards", "5005", "--note", "#203", "--days", "1.5" },
    { "new", "--rewards", "5005", "--note", "#203", "--bogus" },
  }
  for _, args in ipairs(cases) do
    local code, out, _, content = _run(args)
    check.equal(2, code, table.concat(args, " "))
    check.equal(FIXTURE, content, table.concat(args, " "))
    check.equal("", out, table.concat(args, " "))
  end
end)

it("help prints usage and exits 0", function()
  for _, args in ipairs({ { "--help" }, { "new", "--help" } }) do
    local code, out, _, content = _run(args)

    check.equal(0, code, table.concat(args, " "))
    check.truthy(out:find("gift-code new", 1, true), out)
    check.equal(FIXTURE, content)
  end
end)

end)
