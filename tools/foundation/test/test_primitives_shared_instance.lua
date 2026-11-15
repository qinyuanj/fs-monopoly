---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_primitives_shared_instance.lua") end
require("test.bootstrap").install_package_paths()

-- primitives 是全仓唯一的 os/io 原语叶子,但它在三种装载面下被取用:
--   require(装好 package.path)、dofile(bootstrap 链)、loadfile(lua_env 的受控环境)。
-- 每次 dofile/loadfile 都会**重新执行**文件,造出第二套 unique_name 计数器与 shared registry;
-- 那样临时脚本名会撞车、shared 会重复装载。这里钉住:无论经哪条路取,都是同一张表。
local check = require("luassert")

local function _foundation_dir()
  return debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/"):match("^(.*)/[^/]+$") .. "/.."
end

describe("primitives is one instance across every loading path", function()
  it("keeps the registered instance after dofile and loadfile loaders run", function()
    local via_require = require("foundation.primitives")
    local dir = _foundation_dir()

    -- path.lua 与 runtime_path_ops.lua 内部都会取 primitives;两者分别走 dofile 与 loadfile。
    check.equal("table", type(dofile(dir .. "/path.lua")))
    check.equal("table", type(assert(loadfile(dir .. "/runtime_path_ops.lua"))()))

    check.is_true(via_require == package.loaded["foundation.primitives"],
      "dofile/loadfile must not replace the registered primitives instance")
  end)

  it("never hands out colliding temp names across loaders", function()
    -- 若状态分裂,两个计数器各自从 1 数起,同名概率极高。
    local via_require = require("foundation.primitives")
    check.equal("table", type(dofile(_foundation_dir() .. "/path.lua")))

    local seen = {}
    for _ = 1, 300 do
      local name = via_require.unique_name("shared_instance", ".sh")
      check.is_nil(seen[name], "duplicate temp name across instances: " .. name)
      seen[name] = true
    end
  end)
end)
