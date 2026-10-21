local spec_lane_args = {}

function spec_lane_args.usage()
  return table.concat({
    "用法: lua5.4 tools/cli.lua spec-lane --profile <name> [--serial] [--verbose] [--evidence-dir=<目录>]",
    "     lua5.4 tools/cli.lua spec-lane --recount <证据目录>",
    "",
    "--profile 选车道:behavior(七层 + foundation 全量)/ tooling(工具模块单测,不在 verify 管线内);",
    "--profile 也可直接给存在的目录（如 test/behavior/turn）按需点跑，按 behavior 默认构造临时 profile；其余语义见 `lua5.4 tools/cli.lua verify --help`。",
    "文件数超过 30 的具名 profile 默认按实测时长分片并行,lane 分配随时长缓存变化;失败时打印 lane → 文件清单,复现请用 --serial 或按清单点跑。",
    "计数真源是 runner 的 # COUNTS(#130):TAP 的 ok 行可能被 stdout/stderr 合流串流切开,只作交叉核对,不一致会打 COUNT MISMATCH。",
    "--evidence-dir 把每条 lane 的原始输出(.tap)、文件清单(.files)与汇总值(summary.txt)落盘;",
    "--recount 只凭该目录重算 COUNTS 与 TAP 计数并核对汇总值,一致退 0、不一致退 1。",
    "--busted-bin / BUSTED_BIN 已删除，PATH 无 busted。",
  }, "\n") .. "\n"
end

function spec_lane_args.parse(args)
  -- #107:默认恢复分片并行(#73 迁移期安全网曾默认 serial;基线实测
  -- behavior 45.8s 串行 → 20.2s 分片)。--serial 是显式逃生舱。
  local options = { verbose = false, serial = false }
  local i = 1
  while i <= #(args or {}) do
    local token = args[i]
    if token == "--profile" then
      options.profile = args[i + 1]
      i = i + 2
    elseif token == "--serial" then
      options.serial = true
      i = i + 1
    elseif token == "--verbose" then
      options.verbose = true
      i = i + 1
    elseif token == "--evidence-dir" or token:match("^%-%-evidence%-dir=") then
      local value = token:match("^%-%-evidence%-dir=(.*)$")
      if value == nil then
        value = args[i + 1]
        i = i + 1
      end
      if value == nil or value == "" then return nil, "missing --evidence-dir value" end
      options.evidence_dir = value
      i = i + 1
    elseif token == "--recount" or token:match("^%-%-recount=") then
      local value = token:match("^%-%-recount=(.*)$")
      if value == nil then
        value = args[i + 1]
        i = i + 1
      end
      if value == nil or value == "" then return nil, "missing --recount value" end
      options.recount = value
      i = i + 1
    elseif token == "--help" or token == "-h" then
      options.help = true
      i = i + 1
    else
      return nil, "unknown option: " .. tostring(token)
    end
  end
  if not options.help and options.recount == nil and (not options.profile or options.profile == "") then
    return nil, "missing --profile"
  end
  return options
end

return spec_lane_args
