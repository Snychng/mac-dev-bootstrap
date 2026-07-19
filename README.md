# mac-dev-bootstrap

面向 Apple Silicon 新 Mac 的开发环境一键安装脚本。它会安装团队需要的桌面应用、终端环境、语言运行时、AI 编程 CLI、MCP 服务和 VS Code 扩展。

## 一行安装

在新 Mac 的终端中执行：

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Snychng/mac-dev-bootstrap/main/install.sh)"

安装过程中可能要求输入 macOS 管理员密码，并在首次安装 Xcode Command Line Tools 时弹出系统确认窗口。

建议执行远程脚本前先查看源码：

    curl -fsSL https://raw.githubusercontent.com/Snychng/mac-dev-bootstrap/main/install.sh | less

## 安装内容

- Xcode Command Line Tools、Homebrew
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

检查当前电脑是否完整：

    /bin/bash scripts/doctor.sh

指定 pyenv 安装的 Python 版本：

    MAC_DEV_PYTHON_VERSION=3.12.2 /bin/bash install.sh

## 设计原则

- 脚本可重复运行，已经存在的软件会跳过。
- 不保存或上传账号、Token、数据库密码和 SSH 私钥。
- 不覆盖已有 VS Code 和 Ghostty 配置。
- 远程安装器先下载到临时文件，再交给 Bash 执行。
- 单项失败后继续安装其他项目，并在结尾统一报告。

## 安装后登录

安装完成后，请分别登录 GitHub、飞书、Codex、Claude、Gemini、Grok Build 和 CC Switch。PostgreSQL 与 ClickHouse 的连接信息由使用者在各自的本地环境中配置。

## 测试

    bash -n install.sh scripts/doctor.sh tests/run.sh tests/security_test.sh
    bash tests/run.sh
    bash tests/security_test.sh

仓库使用 MIT License。
