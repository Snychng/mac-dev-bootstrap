#!/usr/bin/env bash

set -u
set -o pipefail

INSTALL_SCRIPT="${1:-}"

if [[ -z "$INSTALL_SCRIPT" || ! -f "$INSTALL_SCRIPT" ]]; then
  printf '用法：%s <install-script>\n' "$0" >&2
  exit 2
fi

NORMALIZED_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/mac-dev-bootstrap-pipeline-policy.XXXXXX")"
FILTERED_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/mac-dev-bootstrap-pipeline-filtered.XXXXXX")"
trap 'command rm -f "$NORMALIZED_SCRIPT" "$FILTERED_SCRIPT"' EXIT

# 合并反斜杠续行和单管道符续行，同时保留起始行号，避免跨行绕过检查。
awk '
  {
    command_line = $0
    start_line = NR
    while (command_line ~ /\\[[:space:]]*$/ ||
           command_line ~ /(^|[^|])[|][[:space:]]*$/) {
      if (command_line ~ /\\[[:space:]]*$/) {
        sub(/\\[[:space:]]*$/, " ", command_line)
      } else {
        command_line = command_line " "
      }
      if ((getline continuation) <= 0) {
        break
      }
      command_line = command_line continuation
    }
    print start_line ":" command_line
  }
' "$INSTALL_SCRIPT" > "$NORMALIZED_SCRIPT"

APPROVED_PIPELINE='^[0-9]+:[[:space:]]*curl -fsSL https://claude[.]ai/install[.]sh [|] bash[[:space:]]*$'
DRY_RUN_MESSAGE="^[0-9]+:[[:space:]]*printf '\[模拟执行\] curl -fsSL https://claude[.]ai/install[.]sh [|] bash\\\\n'[[:space:]]*$"
PIPE_TO_SHELL='[|][[:space:]]*((/usr/bin/)?env[[:space:]]+)?(/bin/)?(bash|sh|zsh)([[:space:];&]|$)'
PIPE_TO_VARIABLE="(^|[^|])[|][[:space:]]*((/usr/bin/)?env[[:space:]]+)?['\"]?[$]"

APPROVED_COUNT="$(grep -Ec "$APPROVED_PIPELINE" "$NORMALIZED_SCRIPT" || true)"
if [[ "$APPROVED_COUNT" -ne 1 ]]; then
  printf '必须且只能包含一次 Anthropic 官方 Claude 安装管道，当前为 %s 次\n' \
    "$APPROVED_COUNT" >&2
  exit 1
fi

# 仅剔除精确的真实命令和精确的模拟输出，不按关键词宽泛排除整行。
grep -Ev "$APPROVED_PIPELINE|$DRY_RUN_MESSAGE" \
  "$NORMALIZED_SCRIPT" > "$FILTERED_SCRIPT" || true

if grep -En \
  "$PIPE_TO_SHELL|$PIPE_TO_VARIABLE" \
  "$FILTERED_SCRIPT" >&2; then
  printf '发现未批准的 Shell 管道\n' >&2
  exit 1
fi

printf '远程 Shell 管道策略通过\n'
