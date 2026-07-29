#!/usr/bin/env bash

set -u
set -o pipefail

readonly BOOTSTRAP_VERSION="2.0.0"
readonly BOOTSTRAP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_HOME="${HOME}/.config/mac-dev-bootstrap"
readonly MANAGED_ZSH_CONFIG="${CONFIG_HOME}/zshrc.zsh"
readonly MANAGED_PROMPT_CONFIG="${CONFIG_HOME}/prompt.zsh"
readonly ZSH_SOURCE_LINE='[[ -f "$HOME/.config/mac-dev-bootstrap/zshrc.zsh" ]] && source "$HOME/.config/mac-dev-bootstrap/zshrc.zsh"'
readonly PROMPT_SOURCE_LINE='[[ -f "$HOME/.config/mac-dev-bootstrap/prompt.zsh" ]] && source "$HOME/.config/mac-dev-bootstrap/prompt.zsh"'
readonly HOMEBREW_BREW_GIT_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
readonly HOMEBREW_CORE_GIT_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
readonly HOMEBREW_API_MIRROR="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
readonly HOMEBREW_BOTTLE_MIRROR="https://mirrors.ustc.edu.cn/homebrew-bottles"
readonly HOMEBREW_BREW_GIT_OFFICIAL="https://github.com/Homebrew/brew"
readonly HOMEBREW_CORE_GIT_OFFICIAL="https://github.com/Homebrew/homebrew-core"
readonly LOCALSEND_ARTIFACT_MIRROR_DEFAULT="https://gh-proxy.com"

DRY_RUN=0
INSTALL_PROFILE=""
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

valid_homebrew_mirror() {
  [[ "$1" == "china" || "$1" == "official" ]]
}

valid_https_url() {
  [[ "$1" =~ ^https:/{2}[^[:space:]]+$ ]]
}

valid_install_profile() {
  [[ "$1" == "basic" || "$1" == "standard" || "$1" == "full" ]]
}

profile_from_selection() {
  case "$1" in
    1) printf 'basic\n' ;;
    2) printf 'standard\n' ;;
    3) printf 'full\n' ;;
    *) return 1 ;;
  esac
}

profile_label() {
  case "${1:-${INSTALL_PROFILE:-basic}}" in
    basic) printf '基础\n' ;;
    standard) printf '适中\n' ;;
    full) printf '完整\n' ;;
    *) return 1 ;;
  esac
}

prompt_install_profile() {
  local selection
  local selected_profile

  while true; do
    printf '\n请选择安装档位：\n'
    printf '  1) 基础：当前通用开发环境\n'
    printf '  2) 适中：基础 + 云平台、容器、Clash Verge 与 Codex MCP\n'
    printf '  3) 完整：适中 + 原生工具链、桌面应用、插件与 Skills\n'
    printf '请输入 1、2 或 3（默认 1）：'

    if ! IFS= read -r selection; then
      selection=""
    fi
    selection="${selection:-1}"
    selected_profile="$(profile_from_selection "$selection" 2>/dev/null || true)"
    if [[ -n "$selected_profile" ]]; then
      INSTALL_PROFILE="$selected_profile"
      success "已选择$(profile_label "$INSTALL_PROFILE")安装档位"
      return 0
    fi
    warn "无效选择：${selection}，请输入 1、2 或 3"
  done
}

resolve_install_profile() {
  if [[ -z "$INSTALL_PROFILE" && -n "${MAC_DEV_PROFILE:-}" ]]; then
    INSTALL_PROFILE="$MAC_DEV_PROFILE"
  fi

  if [[ -n "$INSTALL_PROFILE" ]]; then
    if valid_install_profile "$INSTALL_PROFILE"; then
      return 0
    fi
    error "安装档位仅支持 basic、standard 或 full"
    return 1
  fi

  if [[ -t 0 ]]; then
    prompt_install_profile
  else
    INSTALL_PROFILE="basic"
  fi
}

profile_includes_standard() {
  [[ "${INSTALL_PROFILE:-basic}" == "standard" || \
     "${INSTALL_PROFILE:-basic}" == "full" ]]
}

profile_includes_full() {
  [[ "${INSTALL_PROFILE:-basic}" == "full" ]]
}

homebrew_mirror_mode() {
  printf '%s\n' "${MAC_DEV_HOMEBREW_MIRROR:-china}"
}

localsend_artifact_mirror() {
  printf '%s\n' "${MAC_DEV_LOCALSEND_MIRROR:-$LOCALSEND_ARTIFACT_MIRROR_DEFAULT}"
}

configure_homebrew_mirror() {
  local mode="${1:-$(homebrew_mirror_mode)}"

  case "$mode" in
    china)
      export HOMEBREW_BREW_GIT_REMOTE="$HOMEBREW_BREW_GIT_MIRROR"
      export HOMEBREW_CORE_GIT_REMOTE="$HOMEBREW_CORE_GIT_MIRROR"
      export HOMEBREW_API_DOMAIN="$HOMEBREW_API_MIRROR"
      export HOMEBREW_BOTTLE_DOMAIN="$HOMEBREW_BOTTLE_MIRROR"
      unset HOMEBREW_NO_INSTALL_FROM_API
      ;;
    official)
      export HOMEBREW_BREW_GIT_REMOTE="$HOMEBREW_BREW_GIT_OFFICIAL"
      export HOMEBREW_CORE_GIT_REMOTE="$HOMEBREW_CORE_GIT_OFFICIAL"
      unset HOMEBREW_API_DOMAIN HOMEBREW_BOTTLE_DOMAIN
      ;;
    *)
      error "MAC_DEV_HOMEBREW_MIRROR 仅支持 china 或 official"
      return 1
      ;;
  esac
}

basic_formulae() {
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
    starship \
    gemini-cli \
    ansible
}

standard_formulae() {
  printf '%s\n' \
    azure-cli \
    awscli \
    kubernetes-cli \
    docker \
    glab \
    supabase \
    go \
    cloudflared
}

full_formulae() {
  printf '%s\n' \
    aliyun-cli \
    libpq \
    rustup
}

formulae() {
  basic_formulae
  if profile_includes_standard; then
    standard_formulae
  fi
  if profile_includes_full; then
    full_formulae
  fi
}

basic_casks() {
  printf '%s\n' \
    google-chrome \
    feishu \
    chatgpt \
    ghostty \
    visual-studio-code \
    cc-switch \
    localsend \
    font-hack-nerd-font \
    font-jetbrains-mono-nerd-font \
    font-maple-mono-nf-cn
}

standard_casks() {
  printf '%s\n' \
    orbstack \
    clash-verge-rev
}

full_casks() {
  printf '%s\n' \
    android-commandlinetools \
    android-studio \
    arc \
    thebrowsercompany-dia \
    hapigo \
    betterandbetter \
    typeless \
    vibe-island \
    neteasemusic \
    wechat
}

casks() {
  basic_casks
  if profile_includes_standard; then
    standard_casks
  fi
  if profile_includes_full; then
    full_casks
  fi
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

basic_vscode_extensions() {
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
    vscode-icons-team.vscode-icons \
    editorconfig.editorconfig
}

full_vscode_extensions() {
  printf '%s\n' \
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
    vadimcn.vscode-lldb
}

vscode_extensions() {
  basic_vscode_extensions
  if profile_includes_full; then
    full_vscode_extensions
  fi
}

codex_mcp_servers() {
  printf '%s\n' \
    chrome-devtools \
    postgres \
    clickhouse
}

codex_plugins() {
  printf '%s\n' \
    documents@openai-primary-runtime \
    pdf@openai-primary-runtime \
    spreadsheets@openai-primary-runtime \
    presentations@openai-primary-runtime \
    template-creator@openai-primary-runtime \
    sites@openai-bundled \
    browser@openai-bundled \
    computer-use@openai-bundled \
    visualize@openai-bundled
}

skill_packages() {
  printf '%s\n' \
    larksuite/cli \
    vercel-labs/skills \
    titanwings/colleague-skill \
    mvanhorn/last30days-skill
}

manual_app_store_apps() {
  printf '%s\n' \
    "/Applications/Xcode.app" \
    "/Applications/iShot Pro.app"
}

manual_app_store_instructions() {
  printf '%s\t%s\t%s\n' \
    "Xcode" \
    "/Applications/Xcode.app" \
    "https://apps.apple.com/app/xcode/id497799835" \
    "iShot Pro" \
    "/Applications/iShot Pro.app" \
    "https://apps.apple.com/app/ishot-pro/id1611347086"
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
  printf '[模拟执行] 安装档位：%s\n' "$(profile_label)"
  case "$(homebrew_mirror_mode)" in
    china) printf '[模拟执行] Homebrew 镜像：国内（清华 TUNA 仓库 + 中科大 USTC API/Bottle）\n' ;;
    official) printf '[模拟执行] Homebrew 镜像：官方源\n' ;;
    *)
      error "MAC_DEV_HOMEBREW_MIRROR 仅支持 china 或 official"
      return 1
      ;;
  esac
  printf '[模拟执行] Homebrew Formula：\n'
  formulae | sed 's/^/  - /'
  printf '[模拟执行] Homebrew Cask：\n'
  casks | sed 's/^/  - /'
  if ! valid_https_url "$(localsend_artifact_mirror)"; then
    error "MAC_DEV_LOCALSEND_MIRROR 必须是 HTTPS URL"
    return 1
  fi
  printf '[模拟执行] LocalSend 官方源失败后使用镜像：%s\n' \
    "$(localsend_artifact_mirror)"
  printf '[模拟执行] npm 全局包：\n'
  npm_global_packages | sed 's/^/  - /'
  printf '[模拟执行] 其他工具：Oh My Zsh、Bun、Claude Code、Grok Build、mcp-clickhouse\n'
  if profile_includes_standard; then
    printf '[模拟执行] Codex MCP 注册：\n'
    codex_mcp_servers | sed 's/^/  - /'
  fi
  if profile_includes_full; then
    printf '[模拟执行] Codex 插件：\n'
    codex_plugins | sed 's/^/  - /'
    printf '[模拟执行] 可重装 Skill 来源：\n'
    skill_packages | sed 's/^/  - /'
    printf '[模拟执行] 需要从 App Store 人工安装：\n'
    manual_app_store_instructions | while IFS=$'\t' read -r label _ url; do
      printf '  - %s：%s\n' "$label" "$url"
    done
  fi
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
  if ! valid_homebrew_mirror "$(homebrew_mirror_mode)"; then
    error "MAC_DEV_HOMEBREW_MIRROR 仅支持 china 或 official"
    return 1
  fi
  if ! valid_https_url "$(localsend_artifact_mirror)"; then
    error "MAC_DEV_LOCALSEND_MIRROR 必须是 HTTPS URL"
    return 1
  fi
  success "平台检查通过：${os_name}/${architecture}"
}

find_homebrew_binary() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    printf '/opt/homebrew/bin/brew\n'
  elif command_exists brew; then
    command -v brew
  else
    return 1
  fi
}

load_homebrew() {
  local brew_binary
  local shell_environment

  brew_binary="$(find_homebrew_binary)" || return 1
  shell_environment="$("$brew_binary" shellenv)" || return 1

  eval "$shell_environment"
}

homebrew_available() {
  find_homebrew_binary >/dev/null
}

install_homebrew() {
  if homebrew_available; then
    if ! load_homebrew; then
      error "Homebrew 已存在但环境初始化失败"
      return 1
    fi
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
    elif [[ "$formula" == "rustup" ]] && command_exists rustup; then
      success "Rustup 已通过其他官方方式安装"
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
    localsend) printf '%s\n' "/Applications/LocalSend.app" ;;
    orbstack) printf '%s\n' "/Applications/OrbStack.app" ;;
    clash-verge-rev) printf '%s\n' "/Applications/Clash Verge.app" ;;
    android-studio) printf '%s\n' "/Applications/Android Studio.app" ;;
    arc) printf '%s\n' "/Applications/Arc.app" ;;
    thebrowsercompany-dia) printf '%s\n' "/Applications/Dia.app" ;;
    hapigo) printf '%s\n' "/Applications/HapiGo.app" ;;
    betterandbetter) printf '%s\n' "/Applications/BetterAndBetter.app" ;;
    typeless) printf '%s\n' "/Applications/Typeless.app" ;;
    vibe-island) printf '%s\n' "/Applications/Vibe Island.app" ;;
    neteasemusic) printf '%s\n' "/Applications/NeteaseMusic.app" ;;
    wechat) printf '%s\n' "/Applications/WeChat.app" ;;
    *) return 1 ;;
  esac
}

install_cask_package() {
  local cask="$1"
  local mirror

  if run_command brew install --cask "$cask"; then
    return 0
  fi
  if [[ "$cask" != "localsend" ]]; then
    return 1
  fi

  mirror="$(localsend_artifact_mirror)"
  if ! valid_https_url "$mirror"; then
    error "MAC_DEV_LOCALSEND_MIRROR 必须是 HTTPS URL"
    return 1
  fi

  warn "LocalSend 官方源安装失败，尝试 GitHub Release 镜像"
  run_command env \
    HOMEBREW_ARTIFACT_DOMAIN="$mirror" \
    HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK=1 \
    brew install --cask --require-sha localsend
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
    elif install_cask_package "$cask"; then
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

write_managed_shell_config() {
  local destination="$1"

  cat > "$destination" <<'EOF_ZSH'
# 由 mac-dev-bootstrap 管理；此文件不存放任何密钥。
case "${MAC_DEV_HOMEBREW_MIRROR:-china}" in
  china)
    export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
    export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
    export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
    export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
    unset HOMEBREW_NO_INSTALL_FROM_API
    ;;
  official)
    export HOMEBREW_BREW_GIT_REMOTE="https://github.com/Homebrew/brew"
    export HOMEBREW_CORE_GIT_REMOTE="https://github.com/Homebrew/homebrew-core"
    unset HOMEBREW_API_DOMAIN HOMEBREW_BOTTLE_DOMAIN
    ;;
  *)
    unset HOMEBREW_BREW_GIT_REMOTE HOMEBREW_CORE_GIT_REMOTE
    unset HOMEBREW_API_DOMAIN HOMEBREW_BOTTLE_DOMAIN
    ;;
esac

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

export BUN_INSTALL="$HOME/.bun"
export PATH="$HOME/.config/mac-dev-bootstrap/bin:$HOME/.local/bin:$BUN_INSTALL/bin:$PATH"

if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init - zsh)"
fi

if [[ -d /opt/homebrew/opt/libpq/bin ]]; then
  export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
fi

if [[ -d /opt/homebrew/opt/rustup/bin ]]; then
  export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
fi

if [[ -f "$HOME/.cargo/env" ]]; then
  source "$HOME/.cargo/env"
fi

if [[ -d "$HOME/Library/Android/sdk" ]]; then
  export ANDROID_HOME="$HOME/Library/Android/sdk"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  if [[ -d "$ANDROID_HOME/platform-tools" ]]; then
    export PATH="$ANDROID_HOME/platform-tools:$PATH"
  fi
  if [[ -d "$ANDROID_HOME/emulator" ]]; then
    export PATH="$ANDROID_HOME/emulator:$PATH"
  fi
fi

android_studio_jbr="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
if [[ -x "$android_studio_jbr/bin/java" ]]; then
  export JAVA_HOME="$android_studio_jbr"
  export PATH="$JAVA_HOME/bin:$PATH"
fi
unset android_studio_jbr
EOF_ZSH
}

write_managed_prompt_config() {
  local destination="$1"

  cat > "$destination" <<'EOF_ZSH'
# 由 mac-dev-bootstrap 管理；Oh My Zsh 仅提供插件，Starship 负责提示符。
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
plugins=(git z zsh-autosuggestions zsh-syntax-highlighting zsh-completions)

if [[ -s "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
fi

if [[ -x /opt/homebrew/bin/starship ]]; then
  eval "$(/opt/homebrew/bin/starship init zsh)"
fi
EOF_ZSH
}

write_starship_config() {
  local destination="$1"
  local bundled_template="${BOOTSTRAP_ROOT}/config/starship.toml"
  if [[ -f "$bundled_template" ]]; then
    /bin/cp "$bundled_template" "$destination"
    return
  fi
  if ! command_exists starship; then
    return 1
  fi
  starship preset gruvbox-rainbow -o "$destination"
}

write_default_ghostty_config() {
  local destination="$1"
  local bundled_template="${BOOTSTRAP_ROOT}/config/ghostty/config"

  if [[ -f "$bundled_template" ]]; then
    /bin/cp "$bundled_template" "$destination"
    return
  fi

  cat > "$destination" <<'EOF_GHOSTTY'
# 由 mac-dev-bootstrap 管理的 Ghostty 首次安装模板。

# 字体
window-title-font-family = Maple Mono NF CN
font-family = Maple Mono NF CN
font-size = 14
adjust-cell-height = 25%
font-feature = calt, cv01, cv03, ss01, ss02, ss03
font-thicken = true
font-thicken-strength = 255
link-url = true
link-previews = true

# 主题与窗口
theme = Adventure
window-width = 90
window-height = 24
window-save-state = always
window-decoration = true
macos-titlebar-style = tabs
background-opacity = 0.98
quick-terminal-position = center
window-padding-x = 10
resize-overlay-duration = 4s 200ms
window-padding-balance = true

# 分割线与光标
split-divider-color = #e6c5b4
unfocused-split-opacity = 0.92
unfocused-split-fill = #000000
cursor-color = #f5e0dc

# 终端行为
scrollback-limit = 400000000
copy-on-select = clipboard
mouse-hide-while-typing = true
shell-integration = zsh

# 快捷键
keybind = global:super+'=toggle_quick_terminal
keybind = super+r=reload_config
EOF_GHOSTTY
}

write_shell_config() {
  local zshrc="${HOME}/.zshrc"
  local starship_config="${HOME}/.config/starship.toml"

  if ! run_command mkdir -p "$CONFIG_HOME"; then
    record_failure "终端配置目录创建失败"
    return
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[模拟执行] 写入 %s、%s 并连接到 %s\n' \
      "$MANAGED_ZSH_CONFIG" "$MANAGED_PROMPT_CONFIG" "$zshrc"
    printf '[模拟执行] 首次创建 Starship gruvbox-rainbow 配置：%s\n' \
      "$starship_config"
    return 0
  fi

  if ! write_managed_shell_config "$MANAGED_ZSH_CONFIG"; then
    record_failure "终端配置写入失败"
    return
  fi

  if ! write_managed_prompt_config "$MANAGED_PROMPT_CONFIG"; then
    record_failure "提示符配置写入失败"
    return
  fi

  if [[ ! -e "$starship_config" ]]; then
    if write_starship_config "$starship_config"; then
      success "Starship gruvbox-rainbow 配置已创建"
    else
      record_failure "Starship 配置写入失败"
      return
    fi
  else
    success "保留现有 Starship 配置"
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
  if ! grep -Fq 'starship init zsh' "$zshrc" && \
    ! grep -Fqx "$PROMPT_SOURCE_LINE" "$zshrc"; then
    if ! printf '%s\n' "$PROMPT_SOURCE_LINE" >> "$zshrc"; then
      record_failure "无法更新 $zshrc 的提示符加载配置"
      return
    fi
  fi
  success "终端配置已写入：$MANAGED_ZSH_CONFIG、$MANAGED_PROMPT_CONFIG"
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

claude_code_available() {
  command_exists claude && claude --version >/dev/null 2>&1
}

run_claude_native_installer() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[模拟执行] curl -fsSL https://claude.ai/install.sh | bash\n'
    return 0
  fi

  curl -fsSL https://claude.ai/install.sh | bash
}

install_claude_code() {
  if claude_code_available; then
    success "Claude Code 已安装"
    return 0
  fi

  info "使用 Anthropic 官方原生安装器安装 Claude Code"
  if run_claude_native_installer; then
    hash -r 2>/dev/null || true
    if claude_code_available; then
      success "Claude Code 原生安装完成"
      return 0
    fi
    warn "Claude Code 原生安装器已结束，但 claude --version 验证失败"
  else
    warn "Claude Code 原生安装失败，尝试官方 Homebrew Cask"
  fi

  info "使用 Homebrew Cask 兜底安装 Claude Code"
  if run_command brew install --cask claude-code; then
    hash -r 2>/dev/null || true
    if claude_code_available; then
      success "Claude Code 通过 Homebrew Cask 安装完成"
      return 0
    fi
  fi

  record_failure "Claude Code 安装失败"
  return 1
}

install_native_ai_tools() {
  export PATH="${HOME}/.local/bin:${PATH}"

  install_claude_code

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

install_rust_toolchain() {
  local rustup_binary
  if ! profile_includes_full; then
    return
  fi
  if command_exists rustup; then
    rustup_binary="$(command -v rustup)"
  elif [[ -x /opt/homebrew/opt/rustup/bin/rustup ]]; then
    rustup_binary="/opt/homebrew/opt/rustup/bin/rustup"
  else
    record_failure "Rustup 不可用"
    return
  fi
  if run_command "$rustup_binary" default stable; then
    success "Rust stable 工具链已就绪"
  else
    record_failure "Rust stable 工具链安装失败"
  fi
}

android_java_home() {
  local bundled_jbr="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  if [[ -x "$bundled_jbr/bin/java" ]]; then
    printf '%s\n' "$bundled_jbr"
  elif /usr/libexec/java_home -v 21 >/dev/null 2>&1; then
    /usr/libexec/java_home -v 21
  else
    return 1
  fi
}

install_android_sdk() {
  local sdk_root="${HOME}/Library/Android/sdk"
  local java_home_path
  local sdk_components=(
    "platform-tools"
    "emulator"
    "platforms;android-29"
    "platforms;android-36"
    "build-tools;36.0.0"
    "system-images;android-29;google_apis;arm64-v8a"
  )

  if ! profile_includes_full; then
    return
  fi
  if ! command_exists sdkmanager; then
    record_failure "sdkmanager 不可用"
    return
  fi
  java_home_path="$(android_java_home 2>/dev/null || true)"
  if [[ -z "$java_home_path" ]]; then
    record_failure "Android Studio JBR 或 JDK 21 不可用"
    return
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[模拟执行] 接受 Android SDK 许可并安装：'
    printf ' %q' "${sdk_components[@]}"
    printf '\n'
    return
  fi

  if ! mkdir -p "$sdk_root"; then
    record_failure "Android SDK 目录创建失败"
    return
  fi
  if ! printf 'y\n%.0s' {1..30} | env \
    JAVA_HOME="$java_home_path" \
    ANDROID_HOME="$sdk_root" \
    ANDROID_SDK_ROOT="$sdk_root" \
    sdkmanager --sdk_root="$sdk_root" --licenses >/dev/null; then
    record_failure "Android SDK 许可接受失败"
    return
  fi
  if env \
    JAVA_HOME="$java_home_path" \
    ANDROID_HOME="$sdk_root" \
    ANDROID_SDK_ROOT="$sdk_root" \
    sdkmanager --sdk_root="$sdk_root" "${sdk_components[@]}"; then
    success "Android SDK 组件安装完成"
  else
    record_failure "Android SDK 组件安装失败"
  fi
}

write_mcp_helper_scripts() {
  local bin_dir="${1:-${CONFIG_HOME}/bin}"
  if ! run_command mkdir -p "$bin_dir"; then
    return 1
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[模拟执行] 写入无密钥 MCP 与 Chrome 调试启动脚本：%s\n' "$bin_dir"
    return 0
  fi

  cat > "${bin_dir}/chrome-debug" <<'EOF_CHROME'
#!/usr/bin/env bash
set -u
profile_dir="${HOME}/.config/mac-dev-bootstrap/chrome-debug-profile"
mkdir -p "$profile_dir"
exec /usr/bin/open -na "Google Chrome" --args \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port=9222 \
  --user-data-dir="$profile_dir"
EOF_CHROME

  cat > "${bin_dir}/mcp-postgres" <<'EOF_POSTGRES'
#!/usr/bin/env bash
set -u
for env_file in \
  "${HOME}/.config/private-env/postgres.zsh" \
  "${HOME}/.codex/.env"; do
  if [[ -r "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi
done
connection_string="${POSTGRES_CONNECTION_STRING:-${DATABASE_URL:-${POSTGRES_URL:-}}}"
if [[ -z "$connection_string" ]]; then
  printf '缺少 POSTGRES_CONNECTION_STRING、DATABASE_URL 或 POSTGRES_URL\n' >&2
  exit 1
fi
exec mcp-server-postgres "$connection_string"
EOF_POSTGRES

  cat > "${bin_dir}/mcp-clickhouse" <<'EOF_CLICKHOUSE'
#!/usr/bin/env bash
set -u
for env_file in \
  "${HOME}/.config/private-env/clickhouse.zsh" \
  "${HOME}/.codex/.env"; do
  if [[ -r "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi
done
exec mcp-clickhouse
EOF_CLICKHOUSE

  chmod 700 \
    "${bin_dir}/chrome-debug" \
    "${bin_dir}/mcp-postgres" \
    "${bin_dir}/mcp-clickhouse"
}

codex_mcp_registered() {
  codex mcp get "$1" >/dev/null 2>&1
}

register_codex_mcp_server() {
  local server_name="$1"
  if codex_mcp_registered "$server_name"; then
    success "Codex MCP 已注册：$server_name"
    return
  fi

  case "$server_name" in
    chrome-devtools)
      run_command codex mcp add chrome-devtools -- \
        chrome-devtools-mcp \
        --browser-url=http://127.0.0.1:9222
      ;;
    postgres)
      run_command codex mcp add postgres -- \
        "${CONFIG_HOME}/bin/mcp-postgres"
      ;;
    clickhouse)
      run_command codex mcp add clickhouse -- \
        "${CONFIG_HOME}/bin/mcp-clickhouse"
      ;;
    *)
      return 1
      ;;
  esac
}

configure_codex_mcp() {
  local server_name
  if ! profile_includes_standard; then
    return
  fi
  if ! command_exists codex; then
    record_failure "Codex CLI 不可用，无法注册 MCP"
    return
  fi
  if ! write_mcp_helper_scripts; then
    record_failure "MCP 辅助脚本写入失败"
    return
  fi
  while IFS= read -r server_name; do
    [[ -n "$server_name" ]] || continue
    if register_codex_mcp_server "$server_name"; then
      success "Codex MCP 注册完成：$server_name"
    else
      record_failure "Codex MCP 注册失败：$server_name"
    fi
  done < <(codex_mcp_servers)
}

codex_plugin_installed() {
  local selector="$1"
  codex plugin list 2>/dev/null | awk -v selector="$selector" \
    '$1 == selector && $0 ~ /installed, enabled/ { found=1 } END { exit !found }'
}

codex_plugin_marketplaces_ready() {
  local marketplaces
  marketplaces="$(codex plugin marketplace list 2>/dev/null || true)"
  printf '%s\n' "$marketplaces" | awk '$1 == "openai-bundled" { found=1 } END { exit !found }' && \
    printf '%s\n' "$marketplaces" | awk '$1 == "openai-primary-runtime" { found=1 } END { exit !found }'
}

install_codex_plugins() {
  local plugin
  if ! profile_includes_full; then
    return
  fi
  if ! command_exists codex; then
    record_failure "Codex CLI 不可用，无法安装插件"
    return
  fi
  if ! codex_plugin_marketplaces_ready; then
    warn "Codex 官方插件市场尚未初始化；请首次启动并登录 Codex Desktop 后重新运行 Full 档"
    return
  fi
  while IFS= read -r plugin; do
    [[ -n "$plugin" ]] || continue
    if codex_plugin_installed "$plugin"; then
      success "Codex 插件已安装：$plugin"
    elif run_command codex plugin add --json "$plugin"; then
      success "Codex 插件安装完成：$plugin"
    else
      record_failure "Codex 插件安装失败：$plugin"
    fi
  done < <(codex_plugins)
}

install_skill_packages() {
  if ! profile_includes_full; then
    return
  fi
  if ! command_exists npx; then
    record_failure "npx 不可用，无法安装 Skills"
    return
  fi

  if ! run_command npx -y skills add larksuite/cli -g -y; then
    record_failure "Lark Skills 安装失败"
  fi
  if ! run_command npx -y skills add vercel-labs/skills \
    -g -y --skill find-skills --agent '*'; then
    record_failure "find-skills 安装失败"
  fi
  if ! run_command npx -y skills add titanwings/colleague-skill \
    -g -y --agent codex; then
    record_failure "create-colleague Skill 安装失败"
  fi
  if ! run_command npx -y skills add mvanhorn/last30days-skill \
    -g -y --agent codex; then
    record_failure "last30days Skill 安装失败"
  fi
}

print_manual_app_store_steps() {
  local label
  local app_path
  local url
  if ! profile_includes_full; then
    return
  fi
  while IFS=$'\t' read -r label app_path url; do
    [[ -n "$label" ]] || continue
    if [[ -d "$app_path" ]]; then
      success "App Store 应用已安装：$label"
    else
      warn "请从 App Store 人工安装 ${label}：${url}"
    fi
  done < <(manual_app_store_instructions)
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
    if ! write_default_ghostty_config "$ghostty_config"; then
      record_failure "Ghostty 配置写入失败"
      return
    fi
    success "Ghostty 通用配置已创建"
  else
    success "保留现有 Ghostty 配置"
  fi
}

basic_doctor_commands() {
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
    starship \
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

standard_doctor_commands() {
  printf '%s\n' \
    az \
    aws \
    kubectl \
    docker \
    orb \
    glab \
    supabase \
    go \
    cloudflared \
    chrome-debug
}

full_doctor_commands() {
  printf '%s\n' \
    aliyun \
    psql \
    rustup \
    rustc \
    cargo \
    adb \
    sdkmanager \
    java \
    xcodebuild \
    swift
}

doctor_commands() {
  basic_doctor_commands
  if profile_includes_standard; then
    standard_doctor_commands
  fi
  if profile_includes_full; then
    full_doctor_commands
  fi
}

basic_doctor_apps() {
  printf '%s\n' \
    "/Applications/Google Chrome.app" \
    "/Applications/Feishu.app" \
    "/Applications/ChatGPT.app" \
    "/Applications/Ghostty.app" \
    "/Applications/Visual Studio Code.app" \
    "/Applications/CC Switch.app" \
    "/Applications/LocalSend.app"
}

standard_doctor_apps() {
  printf '%s\n' \
    "/Applications/OrbStack.app" \
    "/Applications/Clash Verge.app"
}

full_doctor_apps() {
  printf '%s\n' \
    "/Applications/Android Studio.app" \
    "/Applications/Arc.app" \
    "/Applications/Dia.app" \
    "/Applications/HapiGo.app" \
    "/Applications/BetterAndBetter.app" \
    "/Applications/Typeless.app" \
    "/Applications/Vibe Island.app" \
    "/Applications/NeteaseMusic.app" \
    "/Applications/WeChat.app"
  manual_app_store_apps
}

doctor_apps() {
  basic_doctor_apps
  if profile_includes_standard; then
    standard_doctor_apps
  fi
  if profile_includes_full; then
    full_doctor_apps
  fi
}

setup_runtime_paths() {
  local android_sdk="${HOME}/Library/Android/sdk"
  local android_jbr="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  load_homebrew >/dev/null 2>&1 || true
  export BUN_INSTALL="${HOME}/.bun"
  export PYENV_ROOT="${HOME}/.pyenv"
  export PATH="${CONFIG_HOME}/bin:${HOME}/.local/bin:${BUN_INSTALL}/bin:${PYENV_ROOT}/bin:${PYENV_ROOT}/shims:${PATH}"
  if [[ -d /opt/homebrew/opt/libpq/bin ]]; then
    export PATH="/opt/homebrew/opt/libpq/bin:${PATH}"
  fi
  if [[ -d /opt/homebrew/opt/rustup/bin ]]; then
    export PATH="/opt/homebrew/opt/rustup/bin:${PATH}"
  fi
  if [[ -d "${HOME}/.cargo/bin" ]]; then
    export PATH="${HOME}/.cargo/bin:${PATH}"
  fi
  export ANDROID_HOME="$android_sdk"
  export ANDROID_SDK_ROOT="$android_sdk"
  if [[ -d "${android_sdk}/platform-tools" ]]; then
    export PATH="${android_sdk}/platform-tools:${PATH}"
  fi
  if [[ -d "${android_sdk}/emulator" ]]; then
    export PATH="${android_sdk}/emulator:${PATH}"
  fi
  if [[ -x "${android_jbr}/bin/java" ]]; then
    export JAVA_HOME="$android_jbr"
    export PATH="${android_jbr}/bin:${PATH}"
  fi
}

skill_installed() {
  local skill_name="$1"
  [[ -d "${HOME}/.agents/skills/${skill_name}" || \
     -d "${HOME}/.codex/skills/${skill_name}" || \
     -d "${HOME}/.claude/skills/${skill_name}" ]]
}

doctor() {
  local failures=0
  local item
  setup_runtime_paths

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

  if profile_includes_standard; then
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      if codex_mcp_registered "$item"; then
        success "Codex MCP 已注册：$item"
      else
        error "Codex MCP 未注册：$item"
        failures=$((failures + 1))
      fi
    done < <(codex_mcp_servers)
  fi

  if profile_includes_full; then
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      if codex_plugin_installed "$item"; then
        success "Codex 插件可用：$item"
      else
        error "Codex 插件缺失：$item"
        failures=$((failures + 1))
      fi
    done < <(codex_plugins)

    for item in lark-base find-skills create-colleague last30days; do
      if skill_installed "$item"; then
        success "Skill 可用：$item"
      else
        error "Skill 缺失：$item"
        failures=$((failures + 1))
      fi
    done
  fi

  return "$failures"
}

usage() {
  cat <<'EOF_USAGE'
用法：install.sh [选项]

  --dry-run   仅打印安装计划，不修改电脑
  --doctor    仅检查环境是否安装完整
  --profile PROFILE  安装档位：basic、standard 或 full
  --help      显示帮助

可选环境变量：
  MAC_DEV_PYTHON_VERSION  指定 pyenv 安装的 Python 版本，默认 3.12.2
  MAC_DEV_HOMEBREW_MIRROR  Homebrew 下载源：china（默认）或 official
  MAC_DEV_LOCALSEND_MIRROR  LocalSend 官方源失败后的 HTTPS 镜像
  MAC_DEV_PROFILE         安装档位：basic、standard 或 full
  NO_COLOR                禁用彩色输出
EOF_USAGE
}

parse_args() {
  local requested_action="install"

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --doctor) requested_action="doctor" ;;
      --profile)
        if [[ "$#" -lt 2 ]]; then
          error "--profile 需要 basic、standard 或 full"
          return 2
        fi
        INSTALL_PROFILE="$2"
        shift
        ;;
      --profile=*) INSTALL_PROFILE="${1#*=}" ;;
      --help|-h) requested_action="help" ;;
      *)
        error "未知参数：$1"
        return 2
        ;;
    esac
    shift
  done

  if [[ -n "$INSTALL_PROFILE" ]] && ! valid_install_profile "$INSTALL_PROFILE"; then
    error "安装档位仅支持 basic、standard 或 full"
    return 2
  fi

  case "$requested_action" in
    install) return 0 ;;
    doctor) return 10 ;;
    help) return 11 ;;
  esac
}

main() {
  local parse_status=0
  parse_args "$@" || parse_status=$?
  case "$parse_status" in
    0|10) ;;
    11)
      usage
      return 0
      ;;
    *)
      usage
      return "$parse_status"
      ;;
  esac

  if ! resolve_install_profile; then
    usage
    return 2
  fi

  if [[ "$parse_status" -eq 10 ]]; then
    doctor
    return $?
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    print_plan
    return $?
  fi

  printf '\nmac-dev-bootstrap %s\n' "$BOOTSTRAP_VERSION"
  printf '开始配置 Apple Silicon Mac 开发环境。\n\n'
  success "安装档位：$(profile_label)"

  preflight || return 1
  configure_homebrew_mirror || return 1
  if [[ "$(homebrew_mirror_mode)" == "china" ]]; then
    success "Homebrew 已启用国内镜像：清华 TUNA + 中科大 USTC"
  fi
  install_homebrew || {
    error "Homebrew 安装失败，无法继续"
    return 1
  }

  install_formulae
  install_casks
  install_rust_toolchain
  install_android_sdk
  install_oh_my_zsh
  write_shell_config
  install_bun
  setup_runtime_paths
  install_npm_packages
  setup_python
  install_native_ai_tools
  install_clickhouse_mcp
  configure_codex_mcp
  install_codex_plugins
  install_skill_packages
  install_vscode_extensions
  write_editor_configs
  print_manual_app_store_steps

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
