#!/usr/bin/env bash
# 部署目录 log.txt 事后取证(#191 / ADR 0073):WSL 中运行,按严重度给命中行与上下文。
#
# 用法:
#   .agents/skills/device-debug/scripts/analyze_log.sh [-t 部署根] [-l log.txt 路径]
#        [-n 尾部行数] [-c 上下行数] [-m 最多命中数]
#
# 部署目录由 `lua5.4 tools/cli.lua deploy` 纯拷贝生成,不是 git clone;log.txt 在根部。
# 目标解析顺序:-l > -t > <家目录>/Desktop/dev/eggy/LuaSource_大富翁;家目录取
# $MONOPOLY_DEPLOY_HOME,否则经 cmd.exe + wslpath 解析 %USERPROFILE%(与 deploy 同一口径)。
set -euo pipefail

target_path=""
log_path=""
tail_lines=120
context_lines=4
max_matches=8

while getopts ":t:l:n:c:m:" option; do
  case "$option" in
    t) target_path=$OPTARG ;;
    l) log_path=$OPTARG ;;
    n) tail_lines=$OPTARG ;;
    c) context_lines=$OPTARG ;;
    m) max_matches=$OPTARG ;;
    *) echo "用法: analyze_log.sh [-t 部署根] [-l log.txt路径] [-n 尾部行数] [-c 上下文行数] [-m 命中数]" >&2; exit 2 ;;
  esac
done

expand_path() {
  local text=$1
  case "$text" in
    "~/"*) text="${HOME}/${text#\~/}" ;;
  esac
  if [[ "$text" != /* ]]; then
    text="${PWD}/${text}"
  fi
  # 折叠 . 与 .. 段。
  python3 -I -c 'import os,sys; print(os.path.normpath(sys.argv[1]))' "$text"
}

windows_home() {
  local profile
  profile=$(cd /mnt/c 2>/dev/null && cmd.exe /d /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r' || true)
  if [[ -z "$profile" || "$profile" != [A-Za-z]:* ]]; then
    return 1
  fi
  wslpath -u "$profile" 2>/dev/null
}

default_target() {
  local home
  if [[ -n "${MONOPOLY_DEPLOY_HOME:-}" ]]; then
    home=$(expand_path "$MONOPOLY_DEPLOY_HOME")
  elif ! home=$(windows_home); then
    echo "无法解析 Windows 家目录:cmd.exe 或 wslpath 不可用(在 WSL 中运行)。" >&2
    exit 3
  fi
  printf '%s/Desktop/dev/eggy/LuaSource_大富翁\n' "$home"
}

if [[ -n "$log_path" ]]; then
  log_file=$(expand_path "$log_path")
else
  target_dir=${target_path:+$(expand_path "$target_path")}
  target_dir=${target_dir:-$(default_target)}
  log_file="${target_dir}/log.txt"
fi

if [[ ! -f "$log_file" ]]; then
  hint="确认已运行 \`lua5.4 tools/cli.lua deploy\` 部署,或用 -t/-l 指向正确的部署目录。"
  if [[ -n "${target_dir:-}" && ! -d "$target_dir" ]]; then
    hint="${hint} 目标目录不存在: ${target_dir}"
  fi
  echo "log.txt not found: ${log_file}. ${hint}" >&2
  exit 1
fi

python3 -I - "$log_file" "$tail_lines" "$context_lines" "$max_matches" <<'PY'
import datetime
import os
import re
import sys

path, tail_lines, context_lines, max_matches = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
rules = [
    ("stack_traceback", re.compile(r"stack traceback|traceback"), 100),
    ("error", re.compile(r"\[error\]|\berror\b"), 90),
    ("attempt", re.compile(r"attempt to"), 85),
    ("nil_value", re.compile(r"nil value"), 80),
    ("exception", re.compile(r"exception"), 75),
    ("failed", re.compile(r"\bfailed\b|\bfailure\b"), 70),
    ("panic", re.compile(r"\bpanic\b"), 65),
    ("warn", re.compile(r"\[warn\]|\bwarning\b|\bwarn\b"), 40),
]

with open(path, "r", encoding="utf-8", errors="replace") as handle:
    lines = handle.read().splitlines()
total = len(lines)

matches, seen = [], set()
for index, text in enumerate(lines, start=1):
    rule = next(((name, rank) for name, pattern, rank in rules if pattern.search(text)), None)
    if rule is None:
        continue
    key = re.sub(r'^\[[^\]]+\]\s+\[[^\]]+\]\s*', "", text)
    key = key.replace('"', "")
    key = re.sub(r"\d{2}:\d{2}:\d{2}", "<time>", key).strip()
    if key in seen:
        continue
    seen.add(key)
    matches.append((rule[1], index, rule[0], text))

top = sorted(matches, key=lambda item: (-item[0], -item[1]))[:max_matches]
stat = os.stat(path)
stamp = datetime.datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S")

print(f"LOG_PATH: {os.path.abspath(path)}")
print(f"LAST_WRITE_TIME: {stamp}")
print(f"SIZE_BYTES: {stat.st_size}")
print(f"TOTAL_LINES: {total}")
print(f"MATCH_COUNT: {len(top)}")
print()
print("TOP_MATCHES:")
if not top:
    print("- none")
    print()
else:
    for _rank, number, kind, text in top:
        print(f"- line={number} kind={kind} text={text}")
    print()
    for order, (_rank, number, kind, _text) in enumerate(top, start=1):
        print(f"CONTEXT {order}: line={number} kind={kind}")
        start = max(1, number - context_lines)
        end = min(total, number + context_lines)
        for current in range(start, end + 1):
            prefix = ">" if current == number else " "
            print(f"{prefix} {current:5d} | {lines[current - 1]}")
        print()

tail_start = max(1, total - tail_lines + 1)
print(f"TAIL: start_line={tail_start}")
for current in range(tail_start, total + 1):
    print(f"  {current:5d} | {lines[current - 1]}")
PY
