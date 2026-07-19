#!/usr/bin/env bash

set -u
set -o pipefail

readonly MIGRATION_FORMAT_VERSION="1"
readonly MIGRATION_BUNDLE_NAME="codex-migration"

MODE=""
ARCHIVE_PATH=""
OUTPUT_PATH=""
CODEX_HOME_PATH="${CODEX_HOME:-$HOME/.codex}"
BACKUP_DIRECTORY="${HOME}/codex-backups"
ALLOW_RUNNING=0
REPLACE_EXISTING_INDEXES=0
# Bash 3.2 在 set -u 下展开真正的空数组会报 unbound variable，保留空哨兵兼容 macOS。
CREATED_TEMP_DIRECTORIES=("")
VALIDATED_BUNDLE=""
PREPARED_DATABASE_DIRECTORY=""
TARGET_STAGE_DIRECTORY=""

info() {
  printf '→ %s\n' "$*"
}

success() {
  printf '✓ %s\n' "$*"
}

warn() {
  printf '⚠ %s\n' "$*" >&2
}

die() {
  printf '✗ %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local temporary_directory
  for temporary_directory in "${CREATED_TEMP_DIRECTORIES[@]}"; do
    [[ -n "$temporary_directory" ]] || continue
    case "$temporary_directory" in
      "${TMPDIR:-/tmp}"/codex-migrate.*|/private/tmp/codex-migrate.*|/tmp/codex-migrate.*|"$CODEX_HOME_PATH"/.codex-migrate-stage.*)
        command rm -rf -- "$temporary_directory"
        ;;
    esac
  done
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
  cat <<'EOF_USAGE'
Codex 本地数据迁移工具

用法：
  codex-migrate.sh export [--output 归档路径] [选项]
  codex-migrate.sh inspect <归档路径>
  codex-migrate.sh import <归档路径> [选项]

选项：
  --codex-home 路径   指定 Codex 数据目录，默认 ${CODEX_HOME:-~/.codex}
  --output 路径       export 输出路径，默认桌面上的时间戳归档
  --backup-dir 路径   import 前恢复包目录，默认 ~/codex-backups
  --allow-running     明知 Codex 正在写入仍继续，不推荐
  --replace-existing-indexes
                      允许替换新电脑已有索引；仅在已备份现有历史后使用
  --help              显示帮助

迁移内容：历史会话、归档会话、线程索引、历史输入、记忆、自动化任务、
附件、生成图片、可视化产物、用户画像、Agent/规则和全局 AGENTS.md。

始终排除：auth.json、系统钥匙串凭证、config.toml、hooks.json、日志、
缓存、插件缓存、skills、浏览器数据和其他可能包含凭证或可重新下载的内容。
迁移内容本身仍可能含有个人信息或用户曾粘贴的密钥，请安全传输。
EOF_USAGE
}

create_temp_directory() {
  local temporary_directory
  temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/codex-migrate.XXXXXX")" || \
    die "无法创建临时目录"
  chmod 700 "$temporary_directory" || die "无法保护临时目录：$temporary_directory"
  CREATED_TEMP_DIRECTORIES[${#CREATED_TEMP_DIRECTORIES[@]}]="$temporary_directory"
  CREATED_TEMP_DIRECTORY="$temporary_directory"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "缺少必需命令：$1"
}

require_dependencies() {
  local command_name
  for command_name in tar rsync shasum sqlite3 find mktemp cmp; do
    require_command "$command_name"
  done
}

migration_directories() {
  printf '%s\n' \
    sessions \
    archived_sessions \
    memories \
    automations \
    attachments \
    generated_images \
    visualizations \
    about_user \
    agents \
    rules
}

migration_files() {
  printf '%s\n' \
    AGENTS.md \
    history.jsonl \
    session_index.jsonl
}

migration_databases() {
  printf '%s\n' \
    state_5.sqlite \
    memories_1.sqlite \
    goals_1.sqlite
}

validate_codex_home_root() {
  [[ -n "$CODEX_HOME_PATH" && "$CODEX_HOME_PATH" != "/" ]] || \
    die "拒绝使用过宽的 Codex 数据目录：$CODEX_HOME_PATH"
  [[ "$CODEX_HOME_PATH" != *$'\n'* && "$CODEX_HOME_PATH" != *$'\r'* ]] || \
    die "Codex 数据目录不能包含换行符"
  [[ ! -L "$CODEX_HOME_PATH" ]] || \
    die "Codex 数据目录不能是符号链接：$CODEX_HOME_PATH"
}

validate_source_paths() {
  local item_name

  validate_codex_home_root
  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    [[ ! -L "$CODEX_HOME_PATH/$item_name" ]] || \
      die "拒绝导出顶层符号链接：$CODEX_HOME_PATH/$item_name"
  done < <(migration_directories)
  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    [[ ! -L "$CODEX_HOME_PATH/$item_name" ]] || \
      die "拒绝导出符号链接文件：$CODEX_HOME_PATH/$item_name"
  done < <(migration_files)
  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    [[ ! -L "$CODEX_HOME_PATH/$item_name" ]] || \
      die "拒绝导出符号链接数据库：$CODEX_HOME_PATH/$item_name"
  done < <(migration_databases)
}

validate_target_paths() {
  local item_name
  local linked_path

  validate_codex_home_root
  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    [[ ! -L "$CODEX_HOME_PATH/$item_name" ]] || \
      die "拒绝向符号链接目标写入：$CODEX_HOME_PATH/$item_name"
    if [[ -e "$CODEX_HOME_PATH/$item_name" && \
      ! -d "$CODEX_HOME_PATH/$item_name" ]]; then
      die "目标路径类型不是目录：$CODEX_HOME_PATH/$item_name"
    fi
    if [[ -d "$CODEX_HOME_PATH/$item_name" ]]; then
      linked_path="$(find "$CODEX_HOME_PATH/$item_name" -type l -print -quit 2>/dev/null)" || \
        die "无法安全检查目标目录：$CODEX_HOME_PATH/$item_name"
      [[ -z "$linked_path" ]] || die "目标目录包含符号链接，拒绝导入：$linked_path"
    fi
  done < <(migration_directories)

  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    [[ ! -L "$CODEX_HOME_PATH/$item_name" ]] || \
      die "拒绝覆盖符号链接文件：$CODEX_HOME_PATH/$item_name"
    if [[ -e "$CODEX_HOME_PATH/$item_name" && \
      ! -f "$CODEX_HOME_PATH/$item_name" ]]; then
      die "目标路径类型不是普通文件：$CODEX_HOME_PATH/$item_name"
    fi
  done < <(migration_files)

  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    [[ ! -L "$CODEX_HOME_PATH/$item_name" ]] || \
      die "拒绝覆盖符号链接数据库：$CODEX_HOME_PATH/$item_name"
    if [[ -e "$CODEX_HOME_PATH/$item_name" && \
      ! -f "$CODEX_HOME_PATH/$item_name" ]]; then
      die "目标数据库路径类型无效：$CODEX_HOME_PATH/$item_name"
    fi
  done < <(migration_databases)
}

ensure_codex_is_quiet() {
  local database_name
  local database_path
  local database_candidate
  local checked_database_count=0

  if [[ "$ALLOW_RUNNING" -eq 1 ]]; then
    warn "已跳过 Codex 运行状态检查；归档可能缺少最后一段写入"
    return 0
  fi

  command -v lsof >/dev/null 2>&1 || \
    die "缺少 lsof，无法确认 Codex 已退出；仅在了解风险时使用 --allow-running"
  while IFS= read -r database_name; do
    [[ -n "$database_name" ]] || continue
    database_path="$CODEX_HOME_PATH/$database_name"
    [[ -e "$database_path" ]] || continue
    checked_database_count=$((checked_database_count + 1))
    for database_candidate in \
      "$database_path" "$database_path-wal" "$database_path-shm"; do
      [[ -e "$database_candidate" ]] || continue
      if lsof -t "$database_candidate" >/dev/null 2>&1; then
        die "Codex 正在写入 ${CODEX_HOME_PATH}。请退出 Codex App 和 CLI 后重试；仅在了解风险时使用 --allow-running"
      fi
    done
  done < <(migration_databases)

  [[ "$checked_database_count" -gt 0 ]] || \
    die "未找到 Codex 状态数据库，无法确认应用已退出；仅在了解风险时使用 --allow-running"
}

copy_directory_without_links() {
  local source_directory="$1"
  local destination_directory="$2"
  local symlink_count

  mkdir -p "$destination_directory" || die "无法创建目录：$destination_directory"
  symlink_count="$(find "$source_directory" -type l 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${symlink_count:-0}" -gt 0 ]]; then
    warn "跳过 $source_directory 中的 ${symlink_count} 个符号链接"
  fi
  rsync -a --no-links "$source_directory/" "$destination_directory/" || \
    die "复制目录失败：$source_directory"
}

snapshot_sqlite_database() {
  local source_database="$1"
  local destination_database="$2"

  case "$destination_database" in
    *"'"*) die "SQLite 快照路径不能包含单引号：$destination_database" ;;
  esac
  sqlite3 "$source_database" ".backup '$destination_database'" || \
    die "SQLite 快照失败：$source_database"
  chmod 600 "$destination_database" || die "无法保护数据库快照：$destination_database"
}

count_matching_files() {
  local directory_path="$1"
  local file_name_pattern="$2"
  if [[ ! -d "$directory_path" ]]; then
    printf '0\n'
    return
  fi
  find "$directory_path" -type f -name "$file_name_pattern" | wc -l | tr -d ' '
}

count_all_files() {
  local directory_path="$1"
  if [[ ! -d "$directory_path" ]]; then
    printf '0\n'
    return
  fi
  find "$directory_path" -type f | wc -l | tr -d ' '
}

write_manifest() {
  local bundle_path="$1"
  local data_path="$bundle_path/data"
  local codex_version="unknown"

  if command -v codex >/dev/null 2>&1; then
    codex_version="$(codex --version 2>/dev/null | head -n 1 || true)"
    codex_version="${codex_version:-unknown}"
  fi

  cat > "$bundle_path/manifest.txt" <<EOF_MANIFEST
format_version=$MIGRATION_FORMAT_VERSION
created_at_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
codex_version=$codex_version
sessions_count=$(count_matching_files "$data_path/sessions" '*.jsonl')
archived_sessions_count=$(count_matching_files "$data_path/archived_sessions" '*.jsonl')
automations_count=$(count_matching_files "$data_path/automations" 'automation.toml')
memories_count=$(count_all_files "$data_path/memories")
contains_auth_state=false
EOF_MANIFEST
  chmod 600 "$bundle_path/manifest.txt" || die "无法保护迁移清单"
}

generate_embedded_checksums() {
  local bundle_path="$1"
  (
    cd "$bundle_path" || exit 1
    find . -type f ! -path './SHA256SUMS' -exec shasum -a 256 {} \; | \
      LC_ALL=C sort -k 2 > SHA256SUMS
  ) || die "生成归档内部校验和失败"
  chmod 600 "$bundle_path/SHA256SUMS" || die "无法保护内部校验和"
}

build_bundle() {
  local source_home="$1"
  local bundle_parent="$2"
  local bundle_path="$bundle_parent/$MIGRATION_BUNDLE_NAME"
  local data_path="$bundle_path/data"
  local item_name

  mkdir -p "$data_path" || die "无法创建迁移包目录：$data_path"
  chmod 700 "$bundle_path" "$data_path" || die "无法保护迁移包目录"

  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    if [[ -d "$source_home/$item_name" ]]; then
      copy_directory_without_links "$source_home/$item_name" "$data_path/$item_name"
    fi
  done < <(migration_directories)

  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    if [[ -f "$source_home/$item_name" && ! -L "$source_home/$item_name" ]]; then
      cp -p "$source_home/$item_name" "$data_path/$item_name" || \
        die "复制文件失败：$source_home/$item_name"
    fi
  done < <(migration_files)

  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    if [[ -f "$source_home/$item_name" && ! -L "$source_home/$item_name" ]]; then
      snapshot_sqlite_database "$source_home/$item_name" "$data_path/$item_name"
    fi
  done < <(migration_databases)

  if find "$bundle_path" -type l | grep -q .; then
    die "迁移包中出现符号链接，已中止"
  fi

  write_manifest "$bundle_path"
  generate_embedded_checksums "$bundle_path"
  BUILT_BUNDLE="$bundle_path"
}

default_output_path() {
  local output_directory="$PWD"
  if [[ -d "$HOME/Desktop" ]]; then
    output_directory="$HOME/Desktop"
  fi
  printf '%s/codex-migration-%s.tar.gz\n' \
    "$output_directory" "$(date '+%Y%m%d-%H%M%S')"
}

create_archive_from_bundle() {
  local bundle_path="$1"
  local archive_path="$2"
  local archive_directory
  local archive_name
  local partial_archive
  local archive_hash

  archive_directory="$(dirname "$archive_path")"
  archive_name="$(basename "$archive_path")"
  mkdir -p "$archive_directory" || die "无法创建归档目录：$archive_directory"

  [[ ! -e "$archive_path" ]] || die "输出归档已存在：$archive_path"
  [[ ! -e "$archive_path.sha256" ]] || die "校验和文件已存在：$archive_path.sha256"

  partial_archive="$archive_path.partial.$$"
  tar -czf "$partial_archive" -C "$(dirname "$bundle_path")" \
    "$(basename "$bundle_path")" || {
      command rm -f -- "$partial_archive"
      die "创建归档失败"
    }
  chmod 600 "$partial_archive" || die "无法保护临时归档"
  mv "$partial_archive" "$archive_path" || die "无法写入归档：$archive_path"

  archive_hash="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
  [[ "$archive_hash" =~ ^[0-9a-fA-F]{64}$ ]] || die "生成归档校验和失败"
  printf '%s  %s\n' "$archive_hash" "$archive_name" > "$archive_path.sha256" || \
    die "写入归档校验和失败"
  chmod 600 "$archive_path.sha256" || die "无法保护校验和文件"
}

verify_external_checksum_if_present() {
  local archive_path="$1"
  local checksum_path="$archive_path.sha256"
  local expected_hash
  local actual_hash

  [[ -f "$checksum_path" ]] || return 0
  expected_hash="$(awk 'NR == 1 { print $1 }' "$checksum_path")"
  actual_hash="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
  [[ "$expected_hash" =~ ^[0-9a-fA-F]{64}$ ]] || \
    die "外部校验和格式无效：$checksum_path"
  [[ "$expected_hash" == "$actual_hash" ]] || \
    die "外部校验和不匹配，归档可能损坏"
}

validate_archive_listing() {
  local archive_path="$1"
  local entry_name
  local entry_type

  while IFS= read -r entry_name; do
    [[ -n "$entry_name" ]] || continue
    case "$entry_name" in
      "$MIGRATION_BUNDLE_NAME"|"$MIGRATION_BUNDLE_NAME/"|"$MIGRATION_BUNDLE_NAME/"*) ;;
      *) die "归档包含越界路径：$entry_name" ;;
    esac
    case "/$entry_name/" in
      */../*|*/./*) die "归档包含不安全路径：$entry_name" ;;
    esac
  done < <(tar -tzf "$archive_path")

  while IFS= read -r entry_type; do
    case "$entry_type" in
      -|d) ;;
      *) die "归档包含链接或特殊文件，已拒绝" ;;
    esac
  done < <(tar -tvzf "$archive_path" | awk '{print substr($0, 1, 1)}')
}

manifest_value() {
  local manifest_path="$1"
  local key="$2"
  sed -n "s/^${key}=//p" "$manifest_path" | head -n 1
}

extract_and_validate_archive() {
  local archive_path="$1"
  local extraction_root
  local bundle_path
  local manifest_path
  local actual_checksum_paths
  local listed_checksum_paths

  [[ -f "$archive_path" ]] || die "归档不存在：$archive_path"
  verify_external_checksum_if_present "$archive_path"
  validate_archive_listing "$archive_path"

  create_temp_directory
  extraction_root="$CREATED_TEMP_DIRECTORY"
  tar -xzf "$archive_path" -C "$extraction_root" || die "解压归档失败"
  bundle_path="$extraction_root/$MIGRATION_BUNDLE_NAME"
  manifest_path="$bundle_path/manifest.txt"

  [[ -f "$manifest_path" ]] || die "归档缺少 manifest.txt"
  [[ -f "$bundle_path/SHA256SUMS" ]] || die "归档缺少 SHA256SUMS"
  [[ "$(manifest_value "$manifest_path" format_version)" == \
    "$MIGRATION_FORMAT_VERSION" ]] || die "不支持的迁移包格式"
  [[ "$(manifest_value "$manifest_path" contains_auth_state)" == "false" ]] || \
    die "归档包含或未正确声明 Codex 登录状态，已拒绝"

  if find "$bundle_path" -type l | grep -q .; then
    die "归档包含符号链接，已拒绝"
  fi

  if grep -Eqv '^[0-9a-fA-F]{64}  \./[^[:cntrl:]]+$' \
    "$bundle_path/SHA256SUMS"; then
    die "内部校验和格式或路径无效"
  fi
  if cut -c 67- "$bundle_path/SHA256SUMS" | \
    grep -Eq '(^|/)\.\.(/|$)|^/|/\./'; then
    die "内部校验和包含不安全路径"
  fi

  actual_checksum_paths="$extraction_root/actual-checksum-paths.txt"
  listed_checksum_paths="$extraction_root/listed-checksum-paths.txt"
  (
    cd "$bundle_path" || exit 1
    find . -type f ! -path './SHA256SUMS' | LC_ALL=C sort > "$actual_checksum_paths"
    cut -c 67- SHA256SUMS | LC_ALL=C sort > "$listed_checksum_paths"
  ) || die "无法核对内部校验和路径"
  cmp -s "$actual_checksum_paths" "$listed_checksum_paths" || \
    die "内部校验和未与归档文件一一对应"

  (
    cd "$bundle_path" || exit 1
    shasum -a 256 -c SHA256SUMS >/dev/null
  ) || die "内部校验和不匹配，归档可能被修改"

  VALIDATED_BUNDLE="$bundle_path"
}

print_archive_summary() {
  local manifest_path="$1"
  printf '格式版本：%s\n' "$(manifest_value "$manifest_path" format_version)"
  printf '创建时间：%s\n' "$(manifest_value "$manifest_path" created_at_utc)"
  printf 'Codex 版本：%s\n' "$(manifest_value "$manifest_path" codex_version)"
  printf '会话文件：%s\n' "$(manifest_value "$manifest_path" sessions_count)"
  printf '归档会话文件：%s\n' \
    "$(manifest_value "$manifest_path" archived_sessions_count)"
  printf '自动化任务：%s\n' "$(manifest_value "$manifest_path" automations_count)"
  printf '记忆文件：%s\n' "$(manifest_value "$manifest_path" memories_count)"
  printf '未包含 Codex 登录状态；内容仍可能包含敏感信息或用户粘贴的凭证\n'
}

target_has_existing_history() {
  local directory_name
  local thread_count

  for directory_name in sessions archived_sessions; do
    if [[ -d "$CODEX_HOME_PATH/$directory_name" ]] && \
      find "$CODEX_HOME_PATH/$directory_name" -type f -print -quit | grep -q .; then
      return 0
    fi
  done
  [[ ! -s "$CODEX_HOME_PATH/history.jsonl" ]] || return 0
  [[ ! -s "$CODEX_HOME_PATH/session_index.jsonl" ]] || return 0

  if [[ -f "$CODEX_HOME_PATH/state_5.sqlite" ]]; then
    thread_count="$(sqlite3 "$CODEX_HOME_PATH/state_5.sqlite" \
      'SELECT count(*) FROM threads;' 2>/dev/null)" || return 0
    [[ "${thread_count:-0}" -eq 0 ]] || return 0
  fi
  return 1
}

quick_check_database() {
  local database_path="$1"
  local database_name="$2"
  local check_result

  check_result="$(sqlite3 "$database_path" 'PRAGMA quick_check;' 2>/dev/null)" || \
    die "SQLite 文件无法读取：$database_name"
  [[ "$check_result" == "ok" ]] || die "SQLite 完整性检查失败：$database_name"
}

rewrite_state_rollout_paths() {
  local database_path="$1"
  local escaped_codex_home
  local invalid_path_count
  local table_count
  local column_count

  table_count="$(sqlite3 "$database_path" \
    "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='threads';")" || \
    die "无法读取 state_5.sqlite schema"
  [[ "$table_count" -eq 1 ]] || die "state_5.sqlite 缺少 threads 表"
  column_count="$(sqlite3 "$database_path" \
    "SELECT count(*) FROM pragma_table_info('threads') WHERE name='rollout_path';")" || \
    die "无法读取 threads.rollout_path schema"
  [[ "$column_count" -eq 1 ]] || die "state_5.sqlite 缺少 threads.rollout_path 字段"

  invalid_path_count="$(sqlite3 "$database_path" \
    "SELECT count(*) FROM threads
     WHERE instr(rollout_path, '/sessions/') = 0
       AND instr(rollout_path, '/archived_sessions/') = 0
        OR instr(rollout_path, '/../') > 0
        OR instr(rollout_path, '/./') > 0
        OR instr(rollout_path, char(10)) > 0
        OR instr(rollout_path, char(13)) > 0;")" || \
    die "无法检查线程索引路径"
  [[ "$invalid_path_count" -eq 0 ]] || \
    die "state_5.sqlite 包含无法安全重写的会话路径"

  escaped_codex_home="$(printf '%s' "$CODEX_HOME_PATH" | sed "s/'/''/g")"
  sqlite3 "$database_path" <<EOF_SQL || die "重写线程索引路径失败"
BEGIN IMMEDIATE;
UPDATE threads
SET rollout_path = CASE
  WHEN instr(rollout_path, '/archived_sessions/') > 0
    THEN '$escaped_codex_home' || substr(
      rollout_path, instr(rollout_path, '/archived_sessions/'))
  ELSE '$escaped_codex_home' || substr(
    rollout_path, instr(rollout_path, '/sessions/'))
END;
COMMIT;
EOF_SQL
}

prepare_incoming_databases() {
  local data_path="$1"
  local database_name

  create_temp_directory
  PREPARED_DATABASE_DIRECTORY="$CREATED_TEMP_DIRECTORY/prepared-databases"
  mkdir -p "$PREPARED_DATABASE_DIRECTORY" || die "无法创建数据库暂存目录"
  chmod 700 "$PREPARED_DATABASE_DIRECTORY" || die "无法保护数据库暂存目录"

  while IFS= read -r database_name; do
    [[ -n "$database_name" ]] || continue
    [[ -f "$data_path/$database_name" ]] || continue
    cp -p "$data_path/$database_name" \
      "$PREPARED_DATABASE_DIRECTORY/$database_name" || \
      die "暂存数据库失败：$database_name"
    quick_check_database "$PREPARED_DATABASE_DIRECTORY/$database_name" "$database_name"
    if [[ "$database_name" == "state_5.sqlite" ]]; then
      rewrite_state_rollout_paths "$PREPARED_DATABASE_DIRECTORY/$database_name"
      quick_check_database "$PREPARED_DATABASE_DIRECTORY/$database_name" "$database_name"
    fi
    chmod 600 "$PREPARED_DATABASE_DIRECTORY/$database_name" || \
      die "无法保护暂存数据库：$database_name"
  done < <(migration_databases)
}

prepare_target_stage() {
  local data_path="$1"
  local item_name

  mkdir -p "$CODEX_HOME_PATH" || die "无法创建 Codex 数据目录：$CODEX_HOME_PATH"
  chmod 700 "$CODEX_HOME_PATH" || die "无法保护 Codex 数据目录：$CODEX_HOME_PATH"
  TARGET_STAGE_DIRECTORY="$CODEX_HOME_PATH/.codex-migrate-stage.$$"
  [[ ! -e "$TARGET_STAGE_DIRECTORY" ]] || die "目标暂存目录已存在"
  mkdir "$TARGET_STAGE_DIRECTORY" || die "无法创建目标暂存目录"
  chmod 700 "$TARGET_STAGE_DIRECTORY" || die "无法保护目标暂存目录"
  CREATED_TEMP_DIRECTORIES[${#CREATED_TEMP_DIRECTORIES[@]}]="$TARGET_STAGE_DIRECTORY"

  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    if [[ -f "$data_path/$item_name" ]]; then
      cp -p "$data_path/$item_name" "$TARGET_STAGE_DIRECTORY/$item_name" || \
        die "暂存待恢复文件失败：$item_name"
    fi
  done < <(migration_files)

  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    if [[ -f "$PREPARED_DATABASE_DIRECTORY/$item_name" ]]; then
      cp -p "$PREPARED_DATABASE_DIRECTORY/$item_name" \
        "$TARGET_STAGE_DIRECTORY/$item_name" || \
        die "暂存待恢复数据库失败：$item_name"
      quick_check_database "$TARGET_STAGE_DIRECTORY/$item_name" "$item_name"
    fi
  done < <(migration_databases)
}

has_migratable_data() {
  local item_name
  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    [[ -d "$CODEX_HOME_PATH/$item_name" ]] && return 0
  done < <(migration_directories)
  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    [[ -f "$CODEX_HOME_PATH/$item_name" ]] && return 0
  done < <(migration_files)
  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    [[ -f "$CODEX_HOME_PATH/$item_name" ]] && return 0
  done < <(migration_databases)
  return 1
}

create_recovery_archive() {
  local backup_path

  has_migratable_data || return 0
  mkdir -p "$BACKUP_DIRECTORY" || die "无法创建恢复包目录：$BACKUP_DIRECTORY"
  chmod 700 "$BACKUP_DIRECTORY" || die "无法保护恢复包目录：$BACKUP_DIRECTORY"
  backup_path="$BACKUP_DIRECTORY/current-before-import-$(date '+%Y%m%d-%H%M%S').tar.gz"

  create_temp_directory
  build_bundle "$CODEX_HOME_PATH" "$CREATED_TEMP_DIRECTORY"
  create_archive_from_bundle "$BUILT_BUNDLE" "$backup_path"
  success "导入前恢复包：$backup_path"
}

restore_bundle_data() {
  local data_path="$1"
  local item_name

  mkdir -p "$CODEX_HOME_PATH" || die "无法创建 Codex 数据目录：$CODEX_HOME_PATH"
  chmod 700 "$CODEX_HOME_PATH" || die "无法保护 Codex 数据目录：$CODEX_HOME_PATH"

  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    if [[ -d "$data_path/$item_name" ]]; then
      copy_directory_without_links "$data_path/$item_name" "$CODEX_HOME_PATH/$item_name"
    fi
  done < <(migration_directories)

  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    if [[ -f "$TARGET_STAGE_DIRECTORY/$item_name" ]]; then
      mv -f "$TARGET_STAGE_DIRECTORY/$item_name" "$CODEX_HOME_PATH/$item_name" || \
        die "原子恢复文件失败：$item_name"
    fi
  done < <(migration_files)

  while IFS= read -r item_name; do
    [[ -n "$item_name" ]] || continue
    if [[ -f "$TARGET_STAGE_DIRECTORY/$item_name" ]]; then
      command rm -f -- \
        "$CODEX_HOME_PATH/$item_name-wal" \
        "$CODEX_HOME_PATH/$item_name-shm" || \
        die "清理旧数据库 WAL/SHM 失败：$item_name"
      mv -f "$TARGET_STAGE_DIRECTORY/$item_name" \
        "$CODEX_HOME_PATH/$item_name" || die "原子恢复数据库失败：$item_name"
      chmod 600 "$CODEX_HOME_PATH/$item_name" || die "无法保护数据库：$item_name"
      quick_check_database "$CODEX_HOME_PATH/$item_name" "$item_name"
    fi
  done < <(migration_databases)
}

run_export() {
  local output_path="$OUTPUT_PATH"

  [[ -d "$CODEX_HOME_PATH" ]] || die "Codex 数据目录不存在：$CODEX_HOME_PATH"
  validate_source_paths
  ensure_codex_is_quiet
  [[ -n "$output_path" ]] || output_path="$(default_output_path)"

  create_temp_directory
  build_bundle "$CODEX_HOME_PATH" "$CREATED_TEMP_DIRECTORY"
  create_archive_from_bundle "$BUILT_BUNDLE" "$output_path"

  success "Codex 迁移包已创建：$output_path"
  success "校验和文件已创建：$output_path.sha256"
  warn "迁移包包含私人对话、记忆与自动化内容，请仅通过可信方式传输"
  print_archive_summary "$BUILT_BUNDLE/manifest.txt"
}

run_inspect() {
  extract_and_validate_archive "$ARCHIVE_PATH"
  success "迁移包结构与校验和有效"
  print_archive_summary "$VALIDATED_BUNDLE/manifest.txt"
}

run_import() {
  extract_and_validate_archive "$ARCHIVE_PATH"
  validate_target_paths
  ensure_codex_is_quiet
  if target_has_existing_history && [[ "$REPLACE_EXISTING_INDEXES" -ne 1 ]]; then
    die "新电脑已有历史或索引；请先单独导出备份，确认后使用 --replace-existing-indexes"
  fi
  prepare_incoming_databases "$VALIDATED_BUNDLE/data"
  create_recovery_archive
  prepare_target_stage "$VALIDATED_BUNDLE/data"
  restore_bundle_data "$VALIDATED_BUNDLE/data"

  success "Codex 历史、记忆和自动化任务已导入：$CODEX_HOME_PATH"
  warn "auth.json、系统钥匙串和 config.toml 未被导入；请在新电脑重新登录并重新配置需要凭证的 MCP"
  warn "请重新启动 Codex。若旧会话未立即出现，先等待本地索引完成"
  print_archive_summary "$VALIDATED_BUNDLE/manifest.txt"
}

parse_args() {
  [[ "$#" -gt 0 ]] || {
    usage
    exit 2
  }

  case "$1" in
    export|inspect|import)
      MODE="$1"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      die "未知操作：$1"
      ;;
  esac

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --codex-home)
        [[ "$#" -ge 2 ]] || die "--codex-home 缺少路径"
        CODEX_HOME_PATH="$2"
        shift
        ;;
      --output)
        [[ "$#" -ge 2 ]] || die "--output 缺少路径"
        OUTPUT_PATH="$2"
        shift
        ;;
      --backup-dir)
        [[ "$#" -ge 2 ]] || die "--backup-dir 缺少路径"
        BACKUP_DIRECTORY="$2"
        shift
        ;;
      --allow-running)
        ALLOW_RUNNING=1
        ;;
      --replace-existing-indexes)
        REPLACE_EXISTING_INDEXES=1
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --*)
        die "未知参数：$1"
        ;;
      *)
        if [[ "$MODE" == "export" && -z "$OUTPUT_PATH" ]]; then
          OUTPUT_PATH="$1"
        elif [[ "$MODE" != "export" && -z "$ARCHIVE_PATH" ]]; then
          ARCHIVE_PATH="$1"
        else
          die "多余参数：$1"
        fi
        ;;
    esac
    shift
  done

  if [[ "$MODE" == "inspect" || "$MODE" == "import" ]]; then
    [[ -n "$ARCHIVE_PATH" ]] || die "$MODE 需要迁移归档路径"
  fi
}

main() {
  parse_args "$@"
  require_dependencies

  case "$MODE" in
    export) run_export ;;
    inspect) run_inspect ;;
    import) run_import ;;
  esac
}

main "$@"
