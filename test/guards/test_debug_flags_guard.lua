require("test.bootstrap").install_package_paths()

local luassert = assert
local guard = require("test.guards.lib.debug_flags_guard")
local fs_lib = require("foundation.fs")
local git_query = require("test.guards.lib.git_query")

-- 每一条都喂合成的配置内容,断言 guard 对「联调开关被翻成 true」真的会红、
-- 对合规内容放行——门禁的价值全在能变红。

local _PATH = "src/config/gameplay/debug_flags.lua"

local function _reader(files)
  return function(path)
    return files[path]
  end
end

local function _check(files)
  local paths = {}
  for path in pairs(files) do
    paths[#paths + 1] = path
  end
  return guard.check(paths, _reader(files))
end

local _OFF = "return resettable_defaults.build({\n  debug_auto_all_roles = false,\n})\n"

describe("TestDebugFlagsGuard", function()
  it("test_passes_when_debug_auto_all_roles_is_false", function()
    local violations = _check({ [_PATH] = _OFF })
    luassert.is.equal(0, #violations)
  end)

  it("test_flags_debug_auto_all_roles_true_as_a_release_leak", function()
    local violations = _check({
      [_PATH] = "return resettable_defaults.build({\n  debug_auto_all_roles = true,\n})\n",
    })
    luassert.is.equal(1, #violations)
    local message = violations[1]
    luassert.truthy(message:find(_PATH, 1, true))
    luassert.truthy(message:find("必须为 false", 1, true))
  end)

  it("test_reports_the_line_number_of_the_offending_assignment", function()
    local violations = _check({
      [_PATH] = "-- header\ndebug_auto_all_roles = true\n",
    })
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find(_PATH .. ":2", 1, true))
  end)

  it("test_ignores_the_flag_name_inside_comments", function()
    local violations = _check({
      [_PATH] = "-- 联调时临时改:debug_auto_all_roles = true\ndebug_auto_all_roles = false\n",
    })
    luassert.is.equal(0, #violations)
  end)

  it("test_ignores_unrelated_tracked_files", function()
    local violations = _check({
      ["src/config/gameplay/timing.lua"] = "debug_auto_all_roles = true\n",
    })
    luassert.is.equal(0, #violations)
  end)

  it("test_flags_an_unreadable_flags_file_instead_of_silently_skipping_it", function()
    local violations = guard.check({ _PATH }, function()
      return nil
    end)
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("读不到", 1, true))
  end)

  it("test_residue_flags_a_debug_directory_once_with_its_path", function()
    local violations = guard.check_residue({
      "test/behavior/debug_rt01/test_a.lua",
      "test/behavior/debug_rt01/sub/test_b.lua",
    }, _reader({}))
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("test/behavior/debug_rt01/ ", 1, true))
    luassert.truthy(violations[1]:find("2 个文件", 1, true))
  end)

  it("test_residue_flags_a_debug_directory_directly_under_test", function()
    local violations = guard.check_residue({ "test/debug_x/test_a.lua" }, _reader({}))
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("test/debug_x/ ", 1, true))
  end)

  it("test_residue_reports_each_debug_directory_separately", function()
    local violations = guard.check_residue({
      "test/behavior/debug_a/test_a.lua",
      "test/guards/debug_b/test_b.lua",
    }, _reader({}))
    luassert.is.equal(2, #violations)
  end)

  it("test_residue_ignores_files_that_only_share_the_debug_prefix", function()
    local violations = guard.check_residue({
      "test/guards/lib/debug_flags_guard.lua",
      "test/guards/test_debug_flags_guard.lua",
      "test/behavior/not_debug_dir/test_a.lua",
      "test/behavior/config/test_debug_flags_pin.lua",
    }, _reader({}))
    luassert.is.equal(0, #violations)
  end)

  it("test_residue_ignores_debug_directories_outside_test", function()
    local violations = guard.check_residue({ "src/debug_panel/view.lua" }, _reader({
      ["src/debug_panel/view.lua"] = "return {}\n",
    }))
    luassert.is.equal(0, #violations)
  end)

  it("test_residue_flags_debug_markers_in_src_with_path_line_and_tag", function()
    local violations = guard.check_residue({ "src/ui/a.lua" }, _reader({
      ["src/ui/a.lua"] = "local a = 1\nprint(\"[DEBUG-rdc] seat\", a)\n-- [DEBUG-x1] 注释里也算\n",
    }))
    luassert.is.equal(2, #violations)
    luassert.truthy(violations[1]:find("src/ui/a.lua:2", 1, true))
    luassert.truthy(violations[1]:find("[DEBUG-rdc]", 1, true))
    luassert.truthy(violations[2]:find("src/ui/a.lua:3", 1, true))
  end)

  it("test_residue_ignores_other_debug_words_and_markers_outside_src", function()
    local violations = guard.check_residue({ "src/ui/a.lua", "test/behavior/test_b.lua" }, _reader({
      ["src/ui/a.lua"] = "logger.debug(\"[DEBUG] plain\")\nlocal debug_mode = false\n",
      ["test/behavior/test_b.lua"] = "-- [DEBUG-rf01] 全链路复现\n",
    }))
    luassert.is.equal(0, #violations)
  end)

  it("test_residue_flags_an_unreadable_src_file_instead_of_skipping_it", function()
    local violations = guard.check_residue({ "src/ui/a.lua" }, _reader({}))
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("读不到 src/ui/a.lua", 1, true))
  end)

  describe("run", function()
    local original_run_git
    local original_read_file

    before_each(function()
      original_run_git = git_query.run_git
      original_read_file = fs_lib.read_file
    end)

    after_each(function()
      git_query.run_git = original_run_git
      fs_lib.read_file = original_read_file
    end)

    local function _stub(outputs, files)
      git_query.run_git = function(args)
        return outputs[table.concat(args, " ")] or ""
      end
      fs_lib.read_file = function(path)
        return files[path]
      end
    end

    it("test_run_reports_untracked_debug_directories_and_src_markers_together", function()
      _stub({
        ["ls-files src/config/gameplay"] = _PATH .. "\n",
        ["ls-files src"] = _PATH .. "\nsrc/ui/a.lua\n",
        ["ls-files --others --exclude-standard test"] = "test/behavior/debug_rt01/test_a.lua\n",
      }, {
        [_PATH] = "debug_auto_all_roles = true\n",
        ["src/ui/a.lua"] = "print(\"[DEBUG-rdc]\")\n",
      })
      local result = guard.run()
      luassert.is_false(result.ok)
      luassert.truthy(result.error:find("必须为 false", 1, true))
      luassert.truthy(result.error:find("test/behavior/debug_rt01/ ", 1, true))
      luassert.truthy(result.error:find("src/ui/a.lua:1", 1, true))
    end)

    it("test_run_passes_on_a_clean_tree", function()
      _stub({
        ["ls-files src/config/gameplay"] = _PATH .. "\n",
        ["ls-files src"] = _PATH .. "\n",
        ["ls-files test"] = "test/guards/lib/debug_flags_guard.lua\n",
      }, { [_PATH] = _OFF })
      local result = guard.run()
      luassert.is_true(result.ok, result.error)
      luassert.is.equal("debug_flags_guard ok", result.message)
    end)

    it("test_run_fails_when_the_residue_scan_cannot_list_files", function()
      git_query.run_git = function(args)
        if args[#args] == "test" then
          return nil, "git broke"
        end
        return ""
      end
      local result = guard.run()
      luassert.is_false(result.ok)
      luassert.truthy(result.error:find("git broke", 1, true))
    end)
  end)
end)
