# mac-dev-bootstrap

面向 Apple Silicon 新 Mac 的开发环境一键安装脚本。启动时可选择基础、适中或完整档位，按需安装团队需要的桌面应用、终端环境、语言运行时、AI 编程 CLI、云平台工具、MCP 服务和 VS Code 扩展。

## 一行安装

在新 Mac 的终端中执行：

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Snychng/mac-dev-bootstrap/main/install.sh)"

安装开始时会显示三个档位供选择，直接回车默认使用基础档位。安装过程中可能要求输入 macOS 管理员密码。

Homebrew 默认直接使用国内镜像：Brew 与 Core 仓库走清华 TUNA，Formula/Cask 元数据和预编译 Bottle 走中科大 USTC。首次引导仍使用 Homebrew 官方的小型安装脚本，以兼容尚未具备可用 Git 的全新 Mac；后续主要下载均由国内镜像承接。配置会写入项目管理的 zsh 配置，重新打开终端后仍然生效。

建议执行远程脚本前先查看源码：

    curl -fsSL https://raw.githubusercontent.com/Snychng/mac-dev-bootstrap/main/install.sh | less

## 安装档位

三个档位采用逐级包含关系：

- **基础（basic）**：当前通用开发环境，包含下面列出的全部原有工具。
- **适中（standard）**：基础 + Azure CLI、AWS CLI、kubectl、Docker CLI、OrbStack、GitLab CLI、Supabase CLI、Go 和 cloudflared。
- **完整（full）**：当前继承适中档位，并预留后续完整工具集扩展入口。

交互安装时输入 `1`、`2` 或 `3`。自动化环境可直接指定档位：

    /bin/bash install.sh --profile standard

非交互环境未指定档位时默认使用 `basic`，避免自动扩大安装范围。

直接使用 Homebrew Bundle 时，`Brewfile` 对应基础档位，`Brewfile.standard` 是适中/完整档位的增量清单。

## 基础档位内容

- Homebrew
- Chrome、飞书、Codex Desktop、Ghostty、VS Code、CC Switch
- Git、Git LFS、GitHub CLI
- Oh My Zsh 及 autosuggestions、syntax-highlighting、completions
- Hack、JetBrains Mono、Maple Mono Nerd Font
- Node.js、npm、Corepack、pnpm、Bun
- pyenv、Python 3.12、uv
- curl、wget、jq、ripgrep、fzf、fd、tree、coreutils
- Ansible、ansible-playbook
- Claude Code、Codex CLI、Gemini CLI、Grok Build
- lark-cli、awb-cli、lj-awb-cli
- Chrome DevTools MCP、PostgreSQL MCP、ClickHouse MCP
- 团队通用 VS Code 扩展

## 其他用法

只查看安装计划：

    /bin/bash install.sh --dry-run

查看适中档位安装计划：

    /bin/bash install.sh --profile standard --dry-run

检查当前电脑是否完整：

    /bin/bash scripts/doctor.sh --profile basic

检查适中档位是否完整：

    /bin/bash scripts/doctor.sh --profile standard

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

Claude Code 优先执行 Anthropic 官方原生安装命令 `curl -fsSL https://claude.ai/install.sh | bash`。若安装 URL 返回 403、下载中断，或安装后 `claude --version` 验证失败，脚本会自动使用官方 Homebrew Cask `brew install --cask claude-code` 兜底，并再次验证命令可用性。

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
- 不覆盖已有 VS Code 和 Ghostty 配置。
- 除 Anthropic 官方 Claude 安装管道外，其他远程安装器先下载到临时文件，再交给 Bash 执行。
- 单项失败后继续安装其他项目，并在结尾统一报告。

## 安装后登录

安装完成后，请分别登录 GitHub、飞书、Codex、Claude、Gemini、Grok Build 和 CC Switch。适中档位还需要按实际使用情况完成 Azure、AWS、GitLab、Supabase 与 Cloudflare 登录，并首次启动 OrbStack。PostgreSQL 与 ClickHouse 的连接信息由使用者在各自的本地环境中配置。

## 测试

    bash -n install.sh scripts/doctor.sh scripts/codex-migrate.sh tests/run.sh tests/security_test.sh tests/check_remote_shell_pipelines.sh tests/codex_migrate_test.sh
    bash tests/run.sh
    bash tests/security_test.sh
    bash tests/codex_migrate_test.sh

仓库使用 MIT License。
