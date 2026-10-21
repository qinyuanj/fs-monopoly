#!/usr/bin/env bash
# Ubuntu CI 工具链(#191 / ADR 0073):apt 装 Lua 5.4 + LuaRocks,再按 ADR 0072
# 把五个钉定 rock 装进用户 tree ~/.luarocks(--local,与开发机同一 tree;runner
# 用户无权写 /usr/local)。失败分类沿用退 3 口径:apt / luarocks 的网络
# 或清单不可达退 3(重跑可恢复),其余(编译、版本)退 1。
set -euo pipefail

fail() {
  local code=$1
  shift
  local title
  if [ "$code" -eq 3 ]; then title="setup UNAVAILABLE (exit 3)"; else title="setup FAILED (exit $code)"; fi
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::error title=$title::$*"; fi
  echo "setup-lua: $*" >&2
  exit "$code"
}

# 网络不可达退 3(重跑可恢复);拿到 HTTP 响应的错(404 等)重跑无用,按真实失败退 1。
run_step() {
  local out
  if ! out=$("$@" 2>&1); then
    if printf '%s' "$out" | grep -Eq 'Failed downloading|Failed searching manifest|timed out|Could not connect|Temporary failure resolving'; then
      fail 3 "$* 失败: $out"
    fi
    fail 1 "$* 退非零: $out"
  fi
}

run_step sudo apt-get update
run_step sudo apt-get install -y --no-install-recommends \
  lua5.4 liblua5.4-dev luarocks build-essential python3-venv git

lua5.4 -v
luarocks --lua-version 5.4 --version

rock_pins=(
  "busted 2.3.0-1"
  "luassert 1.9.0-1"
  "luacov 0.17.0-1"
  "luacov-reporter-lcov 0.2-0"
  "luacheck 1.2.0-1"
)
for pin in "${rock_pins[@]}"; do
  read -r name ver <<< "$pin"
  run_step luarocks --lua-version 5.4 install --local "$name" "$ver"
done

exit 0
