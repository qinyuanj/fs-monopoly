-- #203:SHA-256 纯 Lua 实现。期望值取 NIST FIPS 180-2 示例向量与外部
-- sha256sum 的输出,写死在测试里,不用同一算法重算。
require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local sha256 = require("src.foundation.sha256")

describe("TestSha256", function()
  it("test_nist_empty_string", function()
    luassert.equal("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", sha256.hex(""))
  end)

  it("test_nist_abc", function()
    luassert.equal("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", sha256.hex("abc"))
  end)

  -- 448 比特输入:填充后跨两个块。
  it("test_nist_448_bit_message_spans_two_blocks", function()
    luassert.equal("248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
      sha256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))
  end)

  it("test_nist_one_million_a", function()
    luassert.equal("cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
      sha256.hex(string.rep("a", 1000000)))
  end)

  it("test_utf8_chinese_input_matches_sha256sum", function()
    luassert.equal("f23e7db4ccdd4d12063b4be5b48a0b6a7712331bd56f5723018ee57726c63252", sha256.hex("礼包码补偿"))
  end)
end)
