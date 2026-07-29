# mac-dev-bootstrap

面向 Apple Silicon 新 Mac 的开发环境一键安装脚本。启动时可选择基础、适中或完整档位，按需安装团队需要的桌面应用、终端环境、语言运行时、AI 编程 CLI、云平台工具、MCP 服务、Codex 插件/Skills 和 VS Code 扩展。

## 一行安装

在新 Mac 的终端中执行：

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Snychng/mac-dev-bootstrap/main/install.sh)"

安装开始时会显示三个档位供选择，直接回车默认使用基础档位。安装过程中可能要求输入 macOS 管理员密码。

Homebrew 默认直接使用国内镜像：Brew 与 Core 仓库走清华 TUNA，Formula/Cask 元数据和预编译 Bottle 走中科大 USTC。首次引导仍使用 Homebrew 官方的小型安装脚本，以兼容尚未具备可用 Git 的全新 Mac；后续主要下载均由国内镜像承接。配置会写入项目管理的 zsh 配置，重新打开终端后仍然生效。

建议执行远程脚本前先查看源码：

    curl -fsSL https://raw.githubusercontent.com/Snychng/mac-dev-bootstrap/main/install.sh | less

## 轻量 TUI

在交互式终端中，安装脚本会自动启用纯 Bash TUI，无需提前安装 Node.js、Python、Go、Rust 或额外界面库：

- 开始安装前按命令、应用、Codex MCP、插件和 Skill 列出“已安装 / 未安装”状态。
- 安装期间显示当前阶段、总阶段数和 `0%` 到 `100%` 的进度条。
- 每个具体工具仍会输出“已安装、安装完成、缺失或失败”，不会隐藏 Homebrew 等安装器的重要日志和密码提示。
- 某个工具失败时继续处理其他项目，阶段标记为“部分失败”，最终再次检查并汇总缺失项。

百分比按已完成安装阶段计算，用来反映流程完成度；由于 Homebrew Formula、桌面应用等阶段耗时不同，它不是剩余时间估算。

脚本输出被重定向或运行在 CI 中时会自动退回普通日志。也可以手动切换：

    /bin/bash install.sh --tui
    /bin/bash install.sh --no-tui

环境变量方式：

    MAC_DEV_TUI=always /bin/bash install.sh
    MAC_DEV_TUI=never /bin/bash install.sh

`MAC_DEV_TUI=auto` 是默认值；`NO_COLOR=1` 只关闭颜色，不关闭进度界面。

## 安装档位

三个档位采用逐级包含关系：

- **基础（basic）**：通用开发环境、Starship 终端体验和常用 AI 编程工具。
- **适中（standard）**：完整继承基础档位，再加入云平台、容器、部署工具、Clash Verge 与 Codex MCP 注册。
- **完整（full）**：完整继承适中档位，再加入移动端/原生工具链、完整开发扩展、桌面应用、Codex 插件和可重装 Skills。

交互安装时输入 `1`、`2` 或 `3`。自动化环境可直接指定档位：

    /bin/bash install.sh --profile standard

非交互环境未指定档位时默认使用 `basic`，避免自动扩大安装范围。

直接使用 Homebrew Bundle 时，三个清单同样采用逐级叠加：

    brew bundle --file Brewfile
    brew bundle --file Brewfile.standard
    brew bundle --file Brewfile.full

安装适中档位需依次执行前两个文件；安装完整档位需依次执行三个文件。

## 基础档位内容

- Homebrew
- Chrome、飞书、Codex Desktop、Ghostty、VS Code、CC Switch、LocalSend
- Git、Git LFS、GitHub CLI
- Oh My Zsh 及 autosuggestions、syntax-highlighting、completions
- Starship 与 `gruvbox-rainbow` 主题
- Ghostty 的 Maple Mono NF CN、Adventure 主题和常用窗口/快捷键配置
- Hack、JetBrains Mono、Maple Mono Nerd Font
- Node.js、npm、Corepack、pnpm、Bun
- pyenv、Python 3.12、uv
- curl、wget、jq、ripgrep、fzf、fd、tree、coreutils
- Ansible、ansible-playbook
- Claude Code、Codex CLI、Gemini CLI、Grok Build
- lark-cli、awb-cli、lj-awb-cli
- Chrome DevTools MCP、PostgreSQL MCP、ClickHouse MCP
- 团队通用 VS Code 扩展，包括 EditorConfig

## 适中档位增量

- Azure CLI、AWS CLI、kubectl、Docker CLI
- OrbStack、GitLab CLI、Supabase CLI、Go、cloudflared
- Clash Verge Rev
- 独立 Chrome 调试配置与 `chrome-debug` 命令
- 为 Codex 注册 Chrome DevTools、PostgreSQL、ClickHouse MCP
- MCP 注册不写入数据库连接串、密码或 Token

## 完整档位增量

- Aliyun CLI、`libpq`/`psql`
- Rustup、Rust stable、Cargo
- Android Studio、Android Command-line Tools
- Android SDK Platform 29/36、Build Tools 36、Platform Tools、Emulator 和 API 29 ARM64 系统镜像
- Arc、Dia、HapiGo、BetterAndBetter、Typeless、Vibe Island、网易云音乐、微信
- Go、Docker、Containers、YAML、C/C++、CMake、Clangd、LLDB、Rust、Swift VS Code 扩展
- Codex Documents、PDF、Spreadsheets、Presentations、Template Creator、Sites、Browser、Computer Use、Visualize 插件
- 从公开来源重装 Lark Skills、find-skills、create-colleague 和 last30days
- Xcode 与 iShot Pro：不引入 `mas`，安装计划会显示官方 App Store 链接，需人工安装

Full 档不会迁移本机私有或无公开安装源的 Skills，也不会复制 Codex 插件缓存。它只使用公开、可重装的来源。

按当前清单，OpenCLI、Anitime Admin CLI 和 `mas` 不属于任何档位。

## 其他用法

只查看安装计划：

    /bin/bash install.sh --dry-run

查看适中档位安装计划：

    /bin/bash install.sh --profile standard --dry-run

查看完整档位安装计划：

    /bin/bash install.sh --profile full --dry-run

检查当前电脑是否完整：

    /bin/bash scripts/doctor.sh --profile basic

检查适中档位是否完整：

    /bin/bash scripts/doctor.sh --profile standard

检查完整档位是否完整：

    /bin/bash scripts/doctor.sh --profile full

指定 pyenv 安装的 Python 版本：

    MAC_DEV_PYTHON_VERSION=3.12.2 /bin/bash install.sh

也可以通过环境变量指定安装档位：

    MAC_DEV_PROFILE=standard /bin/bash install.sh

临时切回 Homebrew 官方源运行安装：

    MAC_DEV_HOMEBREW_MIRROR=official /bin/bash install.sh

在当前终端切回官方源：

    export MAC_DEV_HOMEBREW_MIRROR=official
    source ~/.config/mac-dev-bootstrap/zshrc.zsh
    brew update

恢复国内镜像：

    unset MAC_DEV_HOMEBREW_MIRROR
    source ~/.config/mac-dev-bootstrap/zshrc.zsh
    brew update

说明：Homebrew Cask 中部分应用的安装包由软件厂商自行托管，这些下载仍可能访问厂商的官方地址。

LocalSend 会先通过官方 Homebrew Cask 安装。若 GitHub Releases 下载失败，脚本会临时通过 `https://gh-proxy.com` 镜像重试，并要求 Homebrew 使用 Cask 中的 SHA-256 校验下载文件；该镜像仅作用于本次 LocalSend 重试。可用 `MAC_DEV_LOCALSEND_MIRROR=https://你的镜像地址 /bin/bash install.sh` 替换默认镜像。

Claude Code 优先执行 Anthropic 官方原生安装命令 `curl -fsSL https://claude.ai/install.sh | bash`。若安装 URL 返回 403、下载中断，或安装后 `claude --version` 验证失败，脚本会自动使用官方 Homebrew Cask `brew install --cask claude-code` 兜底，并再次验证命令可用性。

## MCP、插件与 Skills

适中档位会创建无密钥辅助命令并注册三个 Codex MCP：

- `chrome-debug` 使用独立浏览器目录启动 Chrome 9222 调试端口，不复制日常浏览器资料。
- PostgreSQL MCP 从 `POSTGRES_CONNECTION_STRING`、`DATABASE_URL` 或 `POSTGRES_URL` 读取连接串。
- ClickHouse MCP 从环境变量读取连接信息。

敏感变量可放入 `~/.config/private-env/postgres.zsh`、`~/.config/private-env/clickhouse.zsh` 或现有的 `~/.codex/.env`。文件应由使用者自行创建并设置为 `600`；仓库不会创建、读取、上传或打印其中的值。

完整档位通过 `codex plugin add` 安装公开 Codex 插件，并通过以下公开来源重装 Skills：

- `larksuite/cli`
- `vercel-labs/skills` 中的 `find-skills`
- `titanwings/colleague-skill`
- `mvanhorn/last30days-skill`

全新电脑需要先首次启动并登录 Codex Desktop，让官方 `openai-bundled` 与 `openai-primary-runtime` 插件市场完成初始化。若 Full 档运行时市场尚未出现，脚本会安全延后插件安装；完成首次启动后重新运行 Full 档即可，doctor 在此之前会如实报告插件缺失。

本机自定义 Skills、账号状态、插件缓存和项目专用浏览器任务不属于可重装清单。

## Full 档人工 App Store 项

Xcode 与 iShot Pro 没有对应的 Homebrew Cask。按照“不引入 `mas`”的选择，Full 档会输出下面两个官方入口，并由 doctor 检查应用是否已经存在：

- [Xcode](https://apps.apple.com/app/xcode/id497799835)
- [iShot Pro](https://apps.apple.com/app/ishot-pro/id1611347086)

未完成人工安装时，Full 档最终 doctor 会如实报告缺失；完成 App Store 安装后重新运行 `scripts/doctor.sh --profile full` 即可。

## 迁移 Codex 到新电脑

仓库提供 `scripts/codex-migrate.sh`，用于迁移 Codex 历史会话、归档会话、记忆、自动化任务、线程索引、历史输入、附件、生成图片、可视化产物、用户画像以及 Agent/规则。

迁移前请先完全退出 Codex App 和正在运行的 Codex CLI，避免复制过程中继续写入。

在旧电脑导出：

    /bin/bash scripts/codex-migrate.sh export \
      --output ~/Desktop/codex-migration.tar.gz

导出后会得到两个文件，请一起传到新电脑：

- `codex-migration.tar.gz`
- `codex-migration.tar.gz.sha256`

迁移包包含私人对话和记忆，未加密；即使排除了 Codex 登录状态，内容里仍可能存在你曾粘贴的密钥或其他敏感信息。应通过隔空投送、加密磁盘或其他可信方式传输，不要上传到公开仓库或公共网盘。

在新电脑先安装并登录 Codex，然后完全退出 Codex，再检查并导入：

    /bin/bash scripts/codex-migrate.sh inspect \
      ~/Desktop/codex-migration.tar.gz

    /bin/bash scripts/codex-migrate.sh import \
      ~/Desktop/codex-migration.tar.gz

导入前会在 `~/codex-backups/current-before-import-时间戳.tar.gz` 自动创建恢复包。导入完成后重新打开 Codex，等待本地索引完成。

如果新电脑已经产生过对话，脚本默认拒绝替换其索引。先把新电脑也单独导出备份，确认允许用旧电脑索引替换后再执行：

    /bin/bash scripts/codex-migrate.sh import \
      ~/Desktop/codex-migration.tar.gz \
      --replace-existing-indexes

安全边界：

- 永远不迁移或覆盖 `auth.json` 和系统钥匙串凭证，新电脑保持自己的登录状态。
- 不迁移 `config.toml`、`hooks.json`、日志、缓存、插件缓存、`skills` 和浏览器数据；需要凭证的 MCP 与技能应在新电脑重新安装或配置。
- 会话与内容目录采用合并恢复；线程、记忆和目标 SQLite 索引使用旧电脑的一致性快照替换，线程中的旧电脑绝对路径会重写为新电脑的 `CODEX_HOME`。
- 所有导入数据库都会先在暂存目录完成 SQLite 完整性检查，再以同文件系统原子替换；校验失败不会触碰现有数据库。
- 如果新电脑已经产生重要对话，建议先单独导出新电脑，再执行导入；自动恢复包可用于回滚。
- `.sha256` 与归档内部校验和用于发现传输损坏，不是数字签名，不能证明归档来自可信来源。

## 设计原则

- 脚本可重复运行，已经存在的软件会跳过。
- 不保存或上传账号、Token、数据库密码和 SSH 私钥。
- 不覆盖已有 VS Code、Ghostty 和 Starship 配置；仅在文件不存在时创建模板。
- 除 Anthropic 官方 Claude 安装管道外，其他远程安装器先下载到临时文件，再交给 Bash 执行。
- 单项失败后继续安装其他项目，并在结尾统一报告。

## 安装后登录

安装完成后，请分别登录 GitHub、飞书、Codex、Claude、Gemini、Grok Build 和 CC Switch。适中档位还需要按实际使用情况完成 Azure、AWS、GitLab、Supabase 与 Cloudflare 登录，并首次启动 OrbStack、Clash Verge；使用 Chrome DevTools MCP 前先运行 `chrome-debug`。完整档位还需要完成 Aliyun 登录、Android SDK 首次确认，以及 Xcode、iShot Pro 的 App Store 安装。PostgreSQL 与 ClickHouse 的连接信息由使用者在各自的私有环境文件中配置。

## 测试

    bash -n install.sh scripts/doctor.sh scripts/codex-migrate.sh tests/run.sh tests/security_test.sh tests/check_remote_shell_pipelines.sh tests/codex_migrate_test.sh
    bash tests/run.sh
    bash tests/security_test.sh
    bash tests/codex_migrate_test.sh

仓库使用 MIT License。
