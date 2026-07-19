#!/usr/bin/env bash

set -u
set -o pipefail

readonly BOOTSTRAP_VERSION="1.0.0"
readonly CONFIG_HOME="${HOME}/.config/mac-dev-bootstrap"
readonly MANAGED_ZSH_CONFIG="${CONFIG_HOME}/zshrc.zsh"
readonly ZSH_SOURCE_LINE='[[ -f "$HOME/.config/mac-dev-bootstrap/zshrc.zsh" ]] && source "$HOME/.config/mac-dev-bootstrap/zshrc.zsh"'

DRY_RUN=0
FAILED_STEPS=()

color_enabled() {
  [[ -t 1 && -z "${NO_COLOR:-}" ]]
}

print_color() {
  local color="$1"
  shift
  if color_enabled; then
    printf '\033[%sm%s\033[0m\n' "$color" "$*"
  else
    printf '%s\n' "$*"
  fi
}

info() {
  print_color "1;34" "→ $*"
}

success() {
  print_color "1;32" "✓ $*"
}

warn() {
  print_color "1;33" "⚠ $*" >&2
}

error() {
  print_color "1;31" "✗ $*" >&2
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

platform_supported() {
  [[ "$1" == "Darwin" && "$2" == "arm64" ]]
}

valid_python_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

valid_wait_seconds() {
  [[ "$1" =~ ^[0-9]+$ ]] &&
    [[ "${#1}" -le 5 ]] &&
    [[ "$1" -ge 20 ]] &&
    [[ "$1" -le 86400 ]]
}

formulae() {
  printf '%s\n' \
    git \
    git-lfs \
    gh \
    node \
    pyenv \
    python@3.12 \
    uv \
    curl \
    wget \
    jq \
    ripgrep \
    fzf \
    fd \
    tree \
    coreutils \
    gemini-cli \
    ansible
}

casks() {
  printf '%s\n' \
    google-chrome \
    feishu \
    chatgpt \
    ghostty \
    visual-studio-code \
    cc-switch \
    font-hack-nerd-font \
    font-jetbrains-mono-nerd-font \
    font-maple-mono-nf-cn
}

npm_global_packages() {
  printf '%s\n' \
    corepack \
    @openai/codex \
    @larksuite/cli \
    @lingjingai/awb-cli \
    @lingjingai/lj-awb-cli \
    chrome-devtools-mcp \
    @modelcontextprotocol/server-postgres
}

vscode_extensions() {
  printf '%s\n' \
    anthropic.claude-code \
    openai.chatgpt \
    continue.continue \
    ms-python.python \
    ms-python.vscode-pylance \
    ms-python.debugpy \
    ms-python.vscode-python-envs \
    ms-toolsai.jupyter \
    ms-toolsai.jupyter-keymap \
    ms-toolsai.jupyter-renderers \
    ms-toolsai.vscode-jupyter-cell-tags \
    ms-toolsai.vscode-jupyter-slideshow \
    ms-vscode-remote.remote-ssh \
    ms-vscode-remote.remote-ssh-edit \
    ms-vscode.remote-explorer \
    vue.volar \
    ritwickdey.liveserver \
    davidanson.vscode-markdownlint \
    yzhang.markdown-all-in-one \
    bierner.markdown-mermaid \
    mechatroner.rainbow-csv \
    jock.svg \
    tomoki1207.pdf \
    ms-ceintl.vscode-language-pack-zh-hans \
    vscode-icons-team.vscode-icons
}

record_failure() {
  FAILED_STEPS[${#FAILED_STEPS[@]}]="$1"
  error "$1"
}

run_command() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[模拟执行]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

download_and_run() {
  local label="$1"
  local url="$2"
  local temporary_script

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[模拟执行] 下载并执行 %s：%s\n' "$label" "$url"
    return 0
  fi

  temporary_script="$(mktemp "${TMPDIR:-/tmp}/mac-dev-bootstrap.XXXXXX")" || return 1
  if ! /usr/bin/curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location "$url" --output "$temporary_script"; then
    command rm -f "$temporary_script"
    return 1
  fi
  /bin/bash "$temporary_script"
  local status=$?
  command rm -f "$temporary_script"
  return "$status"
}

print_plan() {
  printf 'mac-dev-bootstrap %s\n\n' "$BOOTSTRAP_VERSION"
  printf '[模拟执行] 目标平台：Apple Silicon macOS\n'
  printf '[模拟执行] 安装或验证 Xcode Command Line Tools\n'
  printf '[模拟执行] Homebrew Formula：\n'
  formulae | sed 's/^/  - /'
  printf '[模拟执行] Homebrew Cask：\n'
  casks | sed 's/^/  - /'
  printf '[模拟执行] npm 全局包：\n'
  npm_global_packages | sed 's/^/  - /'
  printf '[模拟执行] 其他工具：Oh My Zsh、Bun、Claude Code、Grok Build、mcp-clickhouse\n'
  printf '[模拟执行] VS Code 扩展：\n'
  vscode_extensions | sed 's/^/  - /'
}

preflight() {
  local os_name
  local architecture
  os_name="$(uname -s)"
  architecture="$(uname -m)"

  if ! platform_supported "$os_name" "$architecture"; then
    error "仅支持 Apple Silicon macOS，当前环境为 ${os_name}/${architecture}"
    return 1
  fi
  if ! valid_python_version "${MAC_DEV_PYTHON_VERSION:-3.12.2}"; then
    error "MAC_DEV_PYTHON_VERSION 必须是形如 3.12.2 的版本号"
    return 1
  fi
  if ! valid_wait_seconds "${MAC_DEV_CLT_WAIT_SECONDS:-1800}"; then
    error "MAC_DEV_CLT_WAIT_SECONDS 必须是 20 到 86400 的整数"
    return 1
  fi
  success "平台检查通过：${os_name}/${architecture}"
}

ensure_xcode_clt() {
  local waited=0
  local wait_limit="${MAC_DEV_CLT_WAIT_SECONDS:-1800}"

  if /usr/bin/xcode-select -p >/dev/null 2>&1; then
    success "Xcode Command Line Tools 已安装"
    return 0
  fi

  info "请求安装 Xcode Command Line Tools，请在系统弹窗中确认"
  /usr/bin/xcode-select --install >/dev/null 2>&1 || true
  while ! /usr/bin/xcode-select -p >/dev/null 2>&1 && [[ "$waited" -lt "$wait_limit" ]]; do
    if [[ "$waited" -eq 0 ]]; then
      printf '脚本将等待安装完成，最长等待 %s 秒。\n' "$wait_limit"
    fi
    sleep 20
    waited=$((waited + 20))
  done

  if /usr/bin/xcode-select -p >/dev/null 2>&1; then
    success "Xcode Command Line Tools 安装完成"
    return 0
  fi

  error "Xcode Command Line Tools 未在等待时间内完成安装"
  return 1
}

load_homebrew() {
  local brew_binary=""
  if [[ -x /opt/homebrew/bin/brew ]]; then
    brew_binary="/opt/homebrew/bin/brew"
  elif command_exists brew; then
    brew_binary="$(command -v brew)"
  fi

  if [[ -z "$brew_binary" ]]; then
    return 1
  fi

  eval "$("$brew_binary" shellenv)"
}

install_homebrew() {
  if command_exists brew || [[ -x /opt/homebrew/bin/brew ]]; then
    load_homebrew
    success "Homebrew 已安装"
    return 0
  fi

  info "安装 Homebrew；首次安装可能要求输入管理员密码"
  if ! download_and_run "Homebrew" "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"; then
    return 1
  fi
  load_homebrew
}

install_formulae() {
  local formula
  while IFS= read -r formula; do
    [[ -n "$formula" ]] || continue
    if brew list --formula "$formula" >/dev/null 2>&1; then
      success "Formula 已安装：$formula"
    elif run_command brew install "$formula"; then
      success "Formula 安装完成：$formula"
    else
      record_failure "Formula 安装失败：$formula"
    fi
  done < <(formulae)
}

cask_app_path() {
  case "$1" in
    google-chrome) printf '%s\n' "/Applications/Google Chrome.app" ;;
    feishu) printf '%s\n' "/Applications/Feishu.app" ;;
    chatgpt) printf '%s\n' "/Applications/ChatGPT.app" ;;
    ghostty) printf '%s\n' "/Applications/Ghostty.app" ;;
    visual-studio-code) printf '%s\n' "/Applications/Visual Studio Code.app" ;;
    cc-switch) printf '%s\n' "/Applications/CC Switch.app" ;;
    *) return 1 ;;
  esac
}

install_casks() {
  local cask
  local app_path
  while IFS= read -r cask; do
    [[ -n "$cask" ]] || continue
    app_path="$(cask_app_path "$cask" 2>/dev/null || true)"
    if brew list --cask "$cask" >/dev/null 2>&1; then
      success "Cask 已安装：$cask"
    elif [[ -n "$app_path" && -d "$app_path" ]]; then
      success "应用已存在：$app_path"
    elif run_command brew install --cask "$cask"; then
      success "Cask 安装完成：$cask"
    else
      record_failure "Cask 安装失败：$cask"
    fi
  done < <(casks)
}

install_oh_my_zsh() {
  local custom_plugins="${HOME}/.oh-my-zsh/custom/plugins"

  if [[ ! -d "${HOME}/.oh-my-zsh/.git" ]]; then
    info "安装 Oh My Zsh"
    if ! run_command git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "${HOME}/.oh-my-zsh"; then
      record_failure "Oh My Zsh 安装失败"
      return
    fi
  else
    success "Oh My Zsh 已安装"
  fi

  if ! run_command mkdir -p "$custom_plugins"; then
    record_failure "Oh My Zsh 插件目录创建失败"
    return
  fi
  install_zsh_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions.git"
  install_zsh_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git"
  install_zsh_plugin "zsh-completions" "https://github.com/zsh-users/zsh-completions.git"
}

install_zsh_plugin() {
  local name="$1"
  local repository="$2"
  local target="${HOME}/.oh-my-zsh/custom/plugins/${name}"

  if [[ -d "$target/.git" ]]; then
    success "zsh 插件已安装：$name"
  elif run_command git clone --depth=1 "$repository" "$target"; then
    success "zsh 插件安装完成：$name"
  else
    record_failure "zsh 插件安装失败：$name"
  fi
}

write_shell_config() {
  local zshrc="${HOME}/.zshrc"

  if ! run_command mkdir -p "$CONFIG_HOME"; then
    record_failure "终端配置目录创建失败"
    return
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[模拟执行] 写入 %s 并连接到 %s\n' "$MANAGED_ZSH_CONFIG" "$zshrc"
    return 0
  fi

  if ! cat > "$MANAGED_ZSH_CONFIG" <<'EOF_ZSH'
# 由 mac-dev-bootstrap 管理；此文件不存放任何密钥。
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="agnoster"
plugins=(git z zsh-autosuggestions zsh-syntax-highlighting zsh-completions)

if [[ -s "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
fi

export BUN_INSTALL="$HOME/.bun"
export PATH="$HOME/.local/bin:$BUN_INSTALL/bin:$PATH"

if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init - zsh)"
fi
EOF_ZSH
  then
    record_failure "终端配置写入失败"
    return
  fi

  if ! touch "$zshrc"; then
    record_failure "无法创建 $zshrc"
    return
  fi
  if ! grep -Fqx "$ZSH_SOURCE_LINE" "$zshrc"; then
    if ! printf '\n%s\n' "$ZSH_SOURCE_LINE" >> "$zshrc"; then
      record_failure "无法更新 $zshrc"
      return
    fi
  fi
  success "终端配置已写入：$MANAGED_ZSH_CONFIG"
}

install_bun() {
  export BUN_INSTALL="${HOME}/.bun"
  export PATH="${BUN_INSTALL}/bin:${PATH}"
  if command_exists bun; then
    success "Bun 已安装"
  elif download_and_run "Bun" "https://bun.com/install"; then
    success "Bun 安装完成"
  else
    record_failure "Bun 安装失败"
  fi
}

install_npm_packages() {
  local packages=()
  local package
  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    packages[${#packages[@]}]="$package"
  done < <(npm_global_packages)

  if run_command npm install --global "${packages[@]}"; then
    success "npm 全局工具安装完成"
  else
    record_failure "npm 全局工具安装失败"
    return
  fi

  if command_exists corepack; then
    if run_command corepack enable && run_command corepack prepare pnpm@latest --activate; then
      success "Corepack 与 pnpm 已启用"
    else
      record_failure "Corepack 或 pnpm 启用失败"
    fi
  fi
}

setup_python() {
  local python_version="${MAC_DEV_PYTHON_VERSION:-3.12.2}"
  if ! command_exists pyenv; then
    record_failure "pyenv 不可用"
    return
  fi

  export PYENV_ROOT="${HOME}/.pyenv"
  export PATH="${PYENV_ROOT}/bin:${PATH}"
  eval "$(pyenv init -)"

  if pyenv versions --bare | grep -Fqx "$python_version"; then
    success "Python $python_version 已安装"
  elif run_command pyenv install "$python_version"; then
    success "Python $python_version 安装完成"
  else
    record_failure "Python $python_version 安装失败"
    return
  fi

  if run_command pyenv global "$python_version"; then
    success "Python 全局版本已设为 $python_version"
  else
    record_failure "Python 全局版本设置失败"
  fi
}

install_native_ai_tools() {
  export PATH="${HOME}/.local/bin:${PATH}"

  if command_exists claude; then
    success "Claude Code 已安装"
  elif download_and_run "Claude Code" "https://claude.ai/install.sh"; then
    success "Claude Code 安装完成"
  else
    record_failure "Claude Code 安装失败"
  fi

  if command_exists grok; then
    success "Grok Build 已安装"
  elif download_and_run "Grok Build" "https://x.ai/cli/install.sh"; then
    success "Grok Build 安装完成"
  else
    record_failure "Grok Build 安装失败"
  fi
}

install_clickhouse_mcp() {
  if ! command_exists uv; then
    record_failure "uv 不可用，无法安装 mcp-clickhouse"
    return
  fi

  if uv tool list 2>/dev/null | grep -q '^mcp-clickhouse '; then
    success "mcp-clickhouse 已安装"
  elif run_command uv tool install mcp-clickhouse; then
    success "mcp-clickhouse 安装完成"
  else
    record_failure "mcp-clickhouse 安装失败"
  fi
}

code_command() {
  if command_exists code; then
    command -v code
  elif [[ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
    printf '%s\n' "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  else
    return 1
  fi
}

install_vscode_extensions() {
  local code_binary
  local extension
  code_binary="$(code_command 2>/dev/null || true)"
  if [[ -z "$code_binary" ]]; then
    record_failure "VS Code 命令行工具不可用"
    return
  fi

  while IFS= read -r extension; do
    [[ -n "$extension" ]] || continue
    if "$code_binary" --list-extensions 2>/dev/null | grep -Fqi "$extension"; then
      success "VS Code 扩展已安装：$extension"
    elif run_command "$code_binary" --install-extension "$extension"; then
      success "VS Code 扩展安装完成：$extension"
    else
      record_failure "VS Code 扩展安装失败：$extension"
    fi
  done < <(vscode_extensions)
}

write_editor_configs() {
  local vscode_dir="${HOME}/Library/Application Support/Code/User"
  local vscode_settings="${vscode_dir}/settings.json"
  local ghostty_dir="${HOME}/Library/Application Support/com.mitchellh.ghostty"
  local ghostty_config="${ghostty_dir}/config"

  if ! run_command mkdir -p "$vscode_dir" "$ghostty_dir"; then
    record_failure "编辑器配置目录创建失败"
    return
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[模拟执行] 首次创建 VS Code 与 Ghostty 通用配置\n'
    return 0
  fi

  if [[ ! -e "$vscode_settings" ]]; then
    if ! cat > "$vscode_settings" <<'EOF_VSCODE'
{
  "editor.formatOnSave": true,
  "files.insertFinalNewline": true,
  "files.trimTrailingWhitespace": true,
  "git.autofetch": true,
  "terminal.integrated.defaultProfile.osx": "zsh",
  "terminal.integrated.fontFamily": "JetBrainsMono Nerd Font",
  "workbench.iconTheme": "vscode-icons"
}
EOF_VSCODE
    then
      record_failure "VS Code 配置写入失败"
      return
    fi
    success "VS Code 通用配置已创建"
  else
    success "保留现有 VS Code 配置"
  fi

  if [[ ! -e "$ghostty_config" ]]; then
    if ! cat > "$ghostty_config" <<'EOF_GHOSTTY'
font-family = JetBrainsMono Nerd Font
font-size = 14
macos-titlebar-style = tabs
EOF_GHOSTTY
    then
      record_failure "Ghostty 配置写入失败"
      return
    fi
    success "Ghostty 通用配置已创建"
  else
    success "保留现有 Ghostty 配置"
  fi
}

doctor_commands() {
  printf '%s\n' \
    brew \
    git \
    git-lfs \
    gh \
    node \
    npm \
    corepack \
    pnpm \
    bun \
    pyenv \
    python3 \
    uv \
    curl \
    wget \
    jq \
    rg \
    fzf \
    fd \
    tree \
    claude \
    codex \
    gemini \
    grok \
    lark-cli \
    awb \
    lj-awb \
    chrome-devtools-mcp \
    mcp-server-postgres \
    mcp-clickhouse \
    ansible \
    ansible-playbook \
    code
}

doctor_apps() {
  printf '%s\n' \
    "/Applications/Google Chrome.app" \
    "/Applications/Feishu.app" \
    "/Applications/ChatGPT.app" \
    "/Applications/Ghostty.app" \
    "/Applications/Visual Studio Code.app" \
    "/Applications/CC Switch.app"
}

setup_runtime_paths() {
  load_homebrew >/dev/null 2>&1 || true
  export BUN_INSTALL="${HOME}/.bun"
  export PYENV_ROOT="${HOME}/.pyenv"
  export PATH="${HOME}/.local/bin:${BUN_INSTALL}/bin:${PYENV_ROOT}/bin:${PYENV_ROOT}/shims:${PATH}"
}

doctor() {
  local failures=0
  local item
  setup_runtime_paths

  if /usr/bin/xcode-select -p >/dev/null 2>&1; then
    success "Xcode Command Line Tools 可用"
  else
    error "Xcode Command Line Tools 缺失"
    failures=$((failures + 1))
  fi

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    if command_exists "$item"; then
      success "命令可用：$item"
    else
      error "命令缺失：$item"
      failures=$((failures + 1))
    fi
  done < <(doctor_commands)

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    if [[ -d "$item" ]]; then
      success "应用可用：$item"
    else
      error "应用缺失：$item"
      failures=$((failures + 1))
    fi
  done < <(doctor_apps)

  return "$failures"
}

usage() {
  cat <<'EOF_USAGE'
用法：install.sh [选项]

  --dry-run   仅打印安装计划，不修改电脑
  --doctor    仅检查环境是否安装完整
  --help      显示帮助

可选环境变量：
  MAC_DEV_PYTHON_VERSION  指定 pyenv 安装的 Python 版本，默认 3.12.2
  MAC_DEV_CLT_WAIT_SECONDS  等待 Xcode Command Line Tools 的秒数，默认 1800
  NO_COLOR                禁用彩色输出
EOF_USAGE
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --doctor) return 10 ;;
      --help|-h) return 11 ;;
      *)
        error "未知参数：$1"
        return 2
        ;;
    esac
    shift
  done
  return 0
}

main() {
  local parse_status=0
  parse_args "$@" || parse_status=$?
  case "$parse_status" in
    0) ;;
    10)
      doctor
      return $?
      ;;
    11)
      usage
      return 0
      ;;
    *)
      usage
      return "$parse_status"
      ;;
  esac

  if [[ "$DRY_RUN" -eq 1 ]]; then
    print_plan
    return 0
  fi

  printf '\nmac-dev-bootstrap %s\n' "$BOOTSTRAP_VERSION"
  printf '开始配置 Apple Silicon Mac 开发环境。\n\n'

  preflight || return 1
  ensure_xcode_clt || return 1
  install_homebrew || {
    error "Homebrew 安装失败，无法继续"
    return 1
  }

  install_formulae
  install_casks
  install_oh_my_zsh
  write_shell_config
  install_bun
  setup_runtime_paths
  install_npm_packages
  setup_python
  install_native_ai_tools
  install_clickhouse_mcp
  install_vscode_extensions
  write_editor_configs

  printf '\n'
  if [[ "${#FAILED_STEPS[@]}" -gt 0 ]]; then
    error "安装完成，但有 ${#FAILED_STEPS[@]} 个步骤失败："
    printf '  - %s\n' "${FAILED_STEPS[@]}" >&2
    printf '\n修复网络或权限问题后，可直接重新运行同一条安装命令。\n'
    return 1
  fi

  if doctor; then
    printf '\n'
    success "开发环境安装并验证完成"
    printf '请重新打开 Ghostty，然后分别登录 GitHub、飞书、Codex、Claude、Gemini、Grok Build 和 CC Switch。\n'
    return 0
  fi

  warn "安装步骤已完成，但最终检查仍有缺失；可运行 install.sh --doctor 再次检查。"
  return 1
}

if [[ "${MAC_DEV_BOOTSTRAP_TEST:-0}" != "1" ]]; then
  main "$@"
fi
