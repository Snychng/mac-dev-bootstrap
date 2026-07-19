#!/usr/bin/env bash

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_DEV_BOOTSTRAP_TEST=1
export MAC_DEV_BOOTSTRAP_TEST
# shellcheck source=../install.sh
source "$ROOT_DIR/install.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '通过：%s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '失败：%s\n' "$1" >&2
}

assert_true() {
  local name="$1"
  shift
  if "$@"; then
    pass "$name"
  else
    fail "$name"
  fi
}

assert_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"
  if printf '%s\n' "$haystack" | grep -Fqx "$needle"; then
    pass "$name"
  else
    fail "${name}（缺少 ${needle}）"
  fi
}

assert_not_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"
  if printf '%s\n' "$haystack" | grep -Fqx "$needle"; then
    fail "${name}（不应包含 ${needle}）"
  else
    pass "$name"
  fi
}

test_platform_contract() {
  assert_true "支持 Apple Silicon macOS" platform_supported Darwin arm64
  if platform_supported Darwin x86_64; then
    fail "拒绝非 Apple Silicon 环境"
  else
    pass "拒绝非 Apple Silicon 环境"
  fi
}

test_input_validation() {
  assert_true "接受标准 Python 版本" valid_python_version "3.12.2"
  if valid_python_version '3.12.2;echo unsafe'; then
    fail "拒绝异常 Python 版本"
  else
    pass "拒绝异常 Python 版本"
  fi
  assert_true "接受数字等待时长" valid_wait_seconds "1800"
  if valid_wait_seconds '20;echo unsafe'; then
    fail "拒绝异常等待时长"
  else
    pass "拒绝异常等待时长"
  fi
}

test_formula_manifest() {
  local list
  list="$(formulae)"
  local item
  for item in git git-lfs gh node pyenv python@3.12 uv curl wget jq ripgrep fzf fd tree coreutils gemini-cli; do
    assert_contains "Formula 清单" "$list" "$item"
  done
  assert_not_contains "Formula 清单排除 CMake" "$list" "cmake"
  assert_not_contains "Formula 清单排除 Ninja" "$list" "ninja"
}

test_cask_manifest() {
  local list
  list="$(casks)"
  local item
  for item in google-chrome feishu chatgpt ghostty visual-studio-code cc-switch font-hack-nerd-font font-jetbrains-mono-nerd-font font-maple-mono-nf-cn; do
    assert_contains "Cask 清单" "$list" "$item"
  done
}

test_npm_manifest() {
  local list
  list="$(npm_global_packages)"
  local item
  for item in corepack @openai/codex @larksuite/cli @lingjingai/awb-cli @lingjingai/lj-awb-cli chrome-devtools-mcp @modelcontextprotocol/server-postgres; do
    assert_contains "npm 全局清单" "$list" "$item"
  done
}

test_vscode_manifest() {
  local list
  list="$(vscode_extensions)"
  local item
  for item in anthropic.claude-code openai.chatgpt continue.continue ms-python.python ms-python.vscode-pylance ms-vscode-remote.remote-ssh vue.volar ritwickdey.liveserver davidanson.vscode-markdownlint ms-ceintl.vscode-language-pack-zh-hans; do
    assert_contains "VS Code 扩展清单" "$list" "$item"
  done
  assert_not_contains "VS Code 清单不含 Docker 扩展" "$list" "docker.docker"
}

test_dry_run_contract() {
  local output
  if output="$(MAC_DEV_BOOTSTRAP_TEST=0 bash "$ROOT_DIR/install.sh" --dry-run 2>&1)"; then
    if printf '%s\n' "$output" | grep -Fq '[模拟执行]'; then
      pass "dry-run 可执行且不落盘"
    else
      fail "dry-run 输出缺少模拟标记"
    fi
    if printf '%s\n' "$output" | grep -Fq 'Xcode Command Line Tools'; then
      pass "安装计划包含 Xcode Command Line Tools"
    else
      fail "安装计划缺少 Xcode Command Line Tools"
    fi
  else
    fail "dry-run 应成功退出"
  fi
}

test_platform_contract
test_input_validation
test_formula_manifest
test_cask_manifest
test_npm_manifest
test_vscode_manifest
test_dry_run_contract

printf '\n测试汇总：%d 通过，%d 失败\n' "$PASS_COUNT" "$FAIL_COUNT"
if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
