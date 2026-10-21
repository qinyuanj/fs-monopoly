#!/usr/bin/env bash
# CI 入口(#191 / ADR 0073):跑 `lua5.4 tools/cli.lua verify @args`,按退出码出 annotation。
# 0 通过;3 = 平台或工具不可用(status=unavailable),先查环境再重跑;
# 其余(1 真实失败 / 2 用法错误)为真实红灯。退出码原样透传,job 结论与 verify 一致。
set -uo pipefail

label="verify $*"
lua5.4 tools/cli.lua verify "$@"
rc=$?

case "$rc" in
  0) line="${label}:通过" ;;
  3)
    echo "::error title=${label} UNAVAILABLE (exit 3)::平台或工具不可用(status=unavailable),不是测试回归;请检查环境后重跑 job。"
    line="${label}:**UNAVAILABLE**(exit 3)— 平台或工具不可用,请检查环境后重跑 job,不要当测试回归排查。"
    ;;
  *)
    echo "::error title=${label} FAILED (exit ${rc})::真实失败;按日志里的 [verify] FAIL <lane> 行下钻。"
    line="${label}:**FAILED**(exit ${rc})— 真实失败,按 \`[verify] FAIL <lane>\` 行下钻。"
    ;;
esac
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n' "$line" >> "$GITHUB_STEP_SUMMARY"; fi
exit "$rc"
