#!/usr/bin/env bash

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

fail() {
  printf '安全检查失败：%s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

pass() {
  printf '安全检查通过：%s\n' "$1"
}

if grep -REn \
  --exclude='security_test.sh' \
  --exclude-dir='.git' \
  '(gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY)' \
  "$ROOT_DIR" >/dev/null 2>&1; then
  fail "仓库疑似包含密钥或私钥"
else
  pass "未发现常见密钥模式"
fi

if /bin/bash "$ROOT_DIR/tests/check_remote_shell_pipelines.sh" \
  "$ROOT_DIR/install.sh" >/dev/null; then
  pass "仅允许 Anthropic 官方 Claude 安装管道"
else
  fail "远程 Shell 管道策略不符合要求"
fi

if grep -En 'sudo[[:space:]]+npm|rm[[:space:]]+-rf' "$ROOT_DIR/install.sh" >/dev/null 2>&1; then
  fail "安装脚本包含高风险命令"
else
  pass "未发现 sudo npm 或 rm -rf"
fi

URLS="$(grep -Eo 'https://[^"[:space:]]+' "$ROOT_DIR/install.sh" | LC_ALL=C sort -u)"
while IFS= read -r url; do
  [[ -n "$url" ]] || continue
  case "$url" in
    https://raw.githubusercontent.com/Homebrew/install/*|\
    https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git|\
    https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git|\
    https://mirrors.ustc.edu.cn/homebrew-bottles|\
    https://mirrors.ustc.edu.cn/homebrew-bottles/api|\
    https://github.com/Homebrew/brew|\
    https://github.com/Homebrew/homebrew-core|\
    https://github.com/ohmyzsh/*|\
    https://github.com/zsh-users/*|\
    https://bun.com/*|\
    https://claude.ai/*|\
    https://x.ai/*)
      ;;
    *)
      fail "发现未批准的远程脚本来源：$url"
      ;;
  esac
done <<< "$URLS"

if [[ "$FAILURES" -eq 0 ]]; then
  pass "远程来源白名单"
else
  exit 1
fi
