#!/usr/bin/env bash

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION_SCRIPT="$ROOT_DIR/scripts/codex-migrate.sh"
PASS_COUNT=0
FAIL_COUNT=0
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-migrate-test.XXXXXX")"
trap 'command rm -rf "$TEST_ROOT"' EXIT

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '通过：%s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '失败：%s\n' "$1" >&2
}

assert_file_contains() {
  local name="$1"
  local file="$2"
  local expected="$3"
  if [[ -f "$file" ]] && grep -Fq "$expected" "$file"; then
    pass "$name"
  else
    fail "$name"
  fi
}

help_output="$(/bin/bash "$MIGRATION_SCRIPT" --help 2>&1)"
if [[ $? -eq 0 && "$help_output" != *"unbound variable"* ]]; then
  pass "帮助命令成功退出且清理函数兼容空数组"
else
  fail "帮助命令成功退出且清理函数兼容空数组"
fi

source_home="$TEST_ROOT/source-codex"
destination_home="$TEST_ROOT/destination-codex"
backup_directory="$TEST_ROOT/backups"
archive_path="$TEST_ROOT/codex-migration.tar.gz"

for directory_name in \
  sessions archived_sessions memories automations attachments generated_images \
  visualizations about_user agents rules; do
  mkdir -p "$source_home/$directory_name"
done

printf '{"thread":"source"}\n' > "$source_home/sessions/source.jsonl"
printf '{"thread":"archived"}\n' > "$source_home/archived_sessions/archived.jsonl"
printf 'memory source\n' > "$source_home/memories/MEMORY.md"
printf 'nested checksum-named content\n' > "$source_home/memories/SHA256SUMS"
mkdir -p "$source_home/automations/daily"
printf 'name = "daily"\n' > "$source_home/automations/daily/automation.toml"
printf 'automation memory\n' > "$source_home/automations/daily/memory.md"
printf 'attachment\n' > "$source_home/attachments/example.txt"
printf 'image\n' > "$source_home/generated_images/example.txt"
printf 'visualization\n' > "$source_home/visualizations/example.txt"
printf 'about user\n' > "$source_home/about_user/profile.md"
printf 'agent\n' > "$source_home/agents/example.md"
printf 'rule\n' > "$source_home/rules/example.rules"
printf 'global guidance\n' > "$source_home/AGENTS.md"
printf '{"history":"source"}\n' > "$source_home/history.jsonl"
printf '{"index":"source"}\n' > "$source_home/session_index.jsonl"

sqlite3 "$source_home/state_5.sqlite" <<'SQL'
CREATE TABLE threads (
  id TEXT PRIMARY KEY,
  rollout_path TEXT NOT NULL,
  model_provider TEXT NOT NULL DEFAULT 'openai'
);
INSERT INTO threads(id, rollout_path, model_provider)
VALUES('source-thread', '/Users/old-user/.codex/sessions/source.jsonl', 'openai');
SQL
sqlite3 "$source_home/memories_1.sqlite" \
  'CREATE TABLE memories(id TEXT PRIMARY KEY); INSERT INTO memories VALUES("source-memory");'
sqlite3 "$source_home/goals_1.sqlite" \
  'CREATE TABLE goals(id TEXT PRIMARY KEY); INSERT INTO goals VALUES("source-goal");'

printf 'SOURCE_AUTH_SECRET\n' > "$source_home/auth.json"
printf 'mcp_secret = "SOURCE_CONFIG_SECRET"\n' > "$source_home/config.toml"
printf 'SOURCE_LOG_SECRET\n' > "$source_home/logs_2.sqlite"
mkdir -p "$source_home/cache" "$source_home/plugins" "$source_home/skills"
printf 'cache secret\n' > "$source_home/cache/secret.txt"
printf 'plugin secret\n' > "$source_home/plugins/secret.txt"
printf 'skill omitted\n' > "$source_home/skills/omitted.txt"

linked_source_home="$TEST_ROOT/linked-source-codex"
linked_external="$TEST_ROOT/linked-source-external"
mkdir -p "$linked_source_home" "$linked_external"
printf 'must not leak\n' > "$linked_external/secret.jsonl"
ln -s "$linked_external" "$linked_source_home/sessions"
linked_source_archive="$TEST_ROOT/linked-source.tar.gz"
if /bin/bash "$MIGRATION_SCRIPT" export --allow-running \
  --codex-home "$linked_source_home" \
  --output "$linked_source_archive" >/dev/null 2>&1; then
  fail "拒绝导出顶层符号链接目录"
else
  pass "拒绝导出顶层符号链接目录"
fi
if [[ -e "$linked_source_archive" ]]; then
  fail "符号链接源不会生成泄漏归档"
else
  pass "符号链接源不会生成泄漏归档"
fi

unverifiable_source_home="$TEST_ROOT/unverifiable-source-codex"
mkdir -p "$unverifiable_source_home/sessions"
printf '{"thread":"unverifiable"}\n' > \
  "$unverifiable_source_home/sessions/unverifiable.jsonl"
if /bin/bash "$MIGRATION_SCRIPT" export \
  --codex-home "$unverifiable_source_home" \
  --output "$TEST_ROOT/unverifiable.tar.gz" >/dev/null 2>&1; then
  fail "无法确认 Codex 退出状态时默认中止"
else
  pass "无法确认 Codex 退出状态时默认中止"
fi

failing_bin="$TEST_ROOT/failing-bin"
mkdir -p "$failing_bin"
printf '#!/usr/bin/env bash\nexit 23\n' > "$failing_bin/rsync"
chmod +x "$failing_bin/rsync"
failed_archive="$TEST_ROOT/should-not-exist.tar.gz"
if PATH="$failing_bin:$PATH" /bin/bash "$MIGRATION_SCRIPT" export \
  --codex-home "$source_home" \
  --output "$failed_archive" >/dev/null 2>&1; then
  fail "目录复制失败时导出立即失败"
else
  pass "目录复制失败时导出立即失败"
fi

lsof_bin="$TEST_ROOT/lsof-bin"
mkdir -p "$lsof_bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "$#" -gt 2 ]]; then' \
  "  printf '12345\\n'" \
  '  exit 1' \
  'fi' \
  "printf '12345\\n'" \
  'exit 0' > "$lsof_bin/lsof"
chmod +x "$lsof_bin/lsof"
busy_archive="$TEST_ROOT/busy-database.tar.gz"
busy_output="$(PATH="$lsof_bin:$PATH" /bin/bash "$MIGRATION_SCRIPT" export \
  --codex-home "$source_home" \
  --output "$busy_archive" 2>&1)"
busy_status=$?
if [[ "$busy_status" -ne 0 && \
  "$busy_output" == *"Codex 正在写入"* && \
  "$busy_output" != *"unbound variable"* ]]; then
  pass "逐个检查数据库文件并拒绝 lsof 部分失败绕过"
else
  fail "逐个检查数据库文件并拒绝 lsof 部分失败绕过"
fi
if [[ -e "$failed_archive" || -e "$failed_archive.sha256" ]]; then
  fail "复制失败时不生成不完整迁移包"
else
  pass "复制失败时不生成不完整迁移包"
fi

if /bin/bash "$MIGRATION_SCRIPT" export \
  --codex-home "$source_home" \
  --output "$archive_path" >/dev/null 2>&1; then
  pass "导出迁移归档"
else
  fail "导出迁移归档"
fi

if [[ -f "$archive_path" && -f "$archive_path.sha256" ]]; then
  pass "导出归档和外部校验和"
else
  fail "导出归档和外部校验和"
fi

archive_listing="$(tar -tzf "$archive_path" 2>/dev/null || true)"
for expected_path in \
  codex-migration/data/sessions/source.jsonl \
  codex-migration/data/archived_sessions/archived.jsonl \
  codex-migration/data/memories/MEMORY.md \
  codex-migration/data/automations/daily/automation.toml \
  codex-migration/data/attachments/example.txt \
  codex-migration/data/generated_images/example.txt \
  codex-migration/data/visualizations/example.txt \
  codex-migration/data/about_user/profile.md \
  codex-migration/data/agents/example.md \
  codex-migration/data/rules/example.rules \
  codex-migration/data/AGENTS.md \
  codex-migration/data/history.jsonl \
  codex-migration/data/session_index.jsonl \
  codex-migration/data/state_5.sqlite \
  codex-migration/data/memories_1.sqlite \
  codex-migration/data/goals_1.sqlite \
  codex-migration/manifest.txt \
  codex-migration/SHA256SUMS; do
  if printf '%s\n' "$archive_listing" | grep -Fqx "$expected_path"; then
    pass "归档包含：$expected_path"
  else
    fail "归档包含：$expected_path"
  fi
done

for excluded_name in auth.json config.toml logs_2.sqlite cache/ plugins/ skills/; do
  if printf '%s\n' "$archive_listing" | grep -Fq "$excluded_name"; then
    fail "归档排除敏感或可重建内容：$excluded_name"
  else
    pass "归档排除敏感或可重建内容：$excluded_name"
  fi
done

inspect_output="$(/bin/bash "$MIGRATION_SCRIPT" inspect "$archive_path" 2>&1 || true)"
for expected_text in \
  '格式版本：1' \
  '会话文件：1' \
  '归档会话文件：1' \
  '自动化任务：1' \
  '记忆文件：2'; do
  if printf '%s\n' "$inspect_output" | grep -Fq "$expected_text"; then
    pass "检查归档显示：$expected_text"
  else
    fail "检查归档显示：$expected_text"
  fi
done
if printf '%s\n' "$inspect_output" | grep -Fq \
  '未包含 Codex 登录状态；内容仍可能包含敏感信息或用户粘贴的凭证'; then
  pass "检查结果准确说明凭证与内容风险"
else
  fail "检查结果准确说明凭证与内容风险"
fi

mkdir -p "$destination_home/sessions"
printf 'DESTINATION_AUTH_MUST_SURVIVE\n' > "$destination_home/auth.json"
printf 'destination_config = true\n' > "$destination_home/config.toml"
printf '{"thread":"destination"}\n' > "$destination_home/sessions/destination.jsonl"
sqlite3 "$destination_home/state_5.sqlite" \
  "CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    rollout_path TEXT NOT NULL,
    model_provider TEXT NOT NULL DEFAULT 'openai'
  );
  INSERT INTO threads(id, rollout_path, model_provider)
  VALUES('destination-thread', '$destination_home/sessions/destination.jsonl', 'openai');"

if /bin/bash "$MIGRATION_SCRIPT" import "$archive_path" \
  --codex-home "$destination_home" \
  --backup-dir "$backup_directory" >/dev/null 2>&1; then
  fail "默认拒绝覆盖新电脑已有历史索引"
else
  pass "默认拒绝覆盖新电脑已有历史索引"
fi
assert_file_contains "拒绝覆盖时保留新电脑已有会话" \
  "$destination_home/sessions/destination.jsonl" '"thread":"destination"'

if /bin/bash "$MIGRATION_SCRIPT" import "$archive_path" \
  --codex-home "$destination_home" \
  --backup-dir "$backup_directory" \
  --replace-existing-indexes >/dev/null 2>&1; then
  pass "导入迁移归档"
else
  fail "导入迁移归档"
fi

assert_file_contains "导入保留新电脑登录凭证" \
  "$destination_home/auth.json" "DESTINATION_AUTH_MUST_SURVIVE"
assert_file_contains "导入保留新电脑配置" \
  "$destination_home/config.toml" "destination_config = true"
assert_file_contains "导入恢复历史会话" \
  "$destination_home/sessions/source.jsonl" '"thread":"source"'
assert_file_contains "导入保留新电脑已有会话文件" \
  "$destination_home/sessions/destination.jsonl" '"thread":"destination"'
assert_file_contains "导入恢复自动化任务" \
  "$destination_home/automations/daily/automation.toml" 'name = "daily"'
assert_file_contains "导入恢复记忆" \
  "$destination_home/memories/MEMORY.md" "memory source"

if [[ "$(sqlite3 "$destination_home/state_5.sqlite" \
  'SELECT id FROM threads LIMIT 1;')" == "source-thread" ]]; then
  pass "导入恢复线程索引数据库"
else
  fail "导入恢复线程索引数据库"
fi
if [[ "$(sqlite3 "$destination_home/state_5.sqlite" \
  'SELECT rollout_path FROM threads WHERE id = "source-thread";')" == \
  "$destination_home/sessions/source.jsonl" ]]; then
  pass "导入重写线程索引中的旧电脑绝对路径"
else
  fail "导入重写线程索引中的旧电脑绝对路径"
fi

recovery_archive="$(find "$backup_directory" -maxdepth 1 \
  -name 'current-before-import-*.tar.gz' -type f | head -n 1)"
if [[ -n "$recovery_archive" ]] && \
  tar -tzf "$recovery_archive" | grep -Fq \
    'codex-migration/data/sessions/destination.jsonl' && \
  ! tar -tzf "$recovery_archive" | grep -Fq 'auth.json'; then
  pass "导入前自动创建无凭证恢复包"
else
  fail "导入前自动创建无凭证恢复包"
fi

tamper_root="$TEST_ROOT/tamper"
mkdir -p "$tamper_root"
tar -xzf "$archive_path" -C "$tamper_root"
printf 'tampered\n' >> "$tamper_root/codex-migration/data/history.jsonl"
tampered_archive="$TEST_ROOT/tampered.tar.gz"
tar -czf "$tampered_archive" -C "$tamper_root" codex-migration

tamper_destination="$TEST_ROOT/tamper-destination"
mkdir -p "$tamper_destination"
printf 'untouched\n' > "$tamper_destination/marker.txt"
if /bin/bash "$MIGRATION_SCRIPT" import "$tampered_archive" \
  --codex-home "$tamper_destination" \
  --backup-dir "$backup_directory" >/dev/null 2>&1; then
  fail "导入拒绝校验和不匹配的归档"
else
  pass "导入拒绝校验和不匹配的归档"
fi
assert_file_contains "校验失败不会修改目标目录" \
  "$tamper_destination/marker.txt" "untouched"

duplicate_checksum_root="$TEST_ROOT/duplicate-checksum"
mkdir -p "$duplicate_checksum_root"
tar -xzf "$archive_path" -C "$duplicate_checksum_root"
duplicate_checksum_file="$duplicate_checksum_root/codex-migration/SHA256SUMS"
first_checksum_line="$(head -n 1 "$duplicate_checksum_file")"
grep -v 'data/history.jsonl$' "$duplicate_checksum_file" > \
  "$duplicate_checksum_file.tmp"
printf '%s\n' "$first_checksum_line" >> "$duplicate_checksum_file.tmp"
mv "$duplicate_checksum_file.tmp" "$duplicate_checksum_file"
duplicate_checksum_archive="$TEST_ROOT/duplicate-checksum.tar.gz"
tar -czf "$duplicate_checksum_archive" -C "$duplicate_checksum_root" codex-migration
if /bin/bash "$MIGRATION_SCRIPT" inspect \
  "$duplicate_checksum_archive" >/dev/null 2>&1; then
  fail "拒绝重复路径掩盖遗漏文件的校验清单"
else
  pass "拒绝重复路径掩盖遗漏文件的校验清单"
fi

nested_checksum_root="$TEST_ROOT/nested-checksum-name"
mkdir -p "$nested_checksum_root"
tar -xzf "$archive_path" -C "$nested_checksum_root"
printf 'tampered nested checksum-named content\n' > \
  "$nested_checksum_root/codex-migration/data/memories/SHA256SUMS"
nested_checksum_archive="$TEST_ROOT/nested-checksum-name.tar.gz"
tar -czf "$nested_checksum_archive" -C "$nested_checksum_root" codex-migration
if /bin/bash "$MIGRATION_SCRIPT" inspect \
  "$nested_checksum_archive" >/dev/null 2>&1; then
  fail "嵌套同名 SHA256SUMS 文件也必须受校验"
else
  pass "嵌套同名 SHA256SUMS 文件也必须受校验"
fi

invalid_database_root="$TEST_ROOT/invalid-database"
mkdir -p "$invalid_database_root"
tar -xzf "$archive_path" -C "$invalid_database_root"
printf 'not a sqlite database\n' > \
  "$invalid_database_root/codex-migration/data/state_5.sqlite"
(
  cd "$invalid_database_root/codex-migration" || exit 1
  find . -type f ! -path './SHA256SUMS' -exec shasum -a 256 {} \; | \
    LC_ALL=C sort -k 2 > SHA256SUMS
)
invalid_database_archive="$TEST_ROOT/invalid-database.tar.gz"
tar -czf "$invalid_database_archive" -C "$invalid_database_root" codex-migration
invalid_database_destination="$TEST_ROOT/invalid-database-destination"
mkdir -p "$invalid_database_destination/sessions"
printf '{"thread":"must-survive"}\n' > \
  "$invalid_database_destination/sessions/must-survive.jsonl"
sqlite3 "$invalid_database_destination/state_5.sqlite" \
  'CREATE TABLE threads(id TEXT PRIMARY KEY); INSERT INTO threads VALUES("must-survive");'
if /bin/bash "$MIGRATION_SCRIPT" import "$invalid_database_archive" \
  --codex-home "$invalid_database_destination" \
  --backup-dir "$backup_directory" \
  --replace-existing-indexes >/dev/null 2>&1; then
  fail "拒绝校验和正确但内容损坏的 SQLite"
else
  pass "拒绝校验和正确但内容损坏的 SQLite"
fi
if [[ "$(sqlite3 "$invalid_database_destination/state_5.sqlite" \
  'SELECT id FROM threads LIMIT 1;' 2>/dev/null)" == "must-survive" ]]; then
  pass "损坏数据库不会覆盖新电脑现有数据库"
else
  fail "损坏数据库不会覆盖新电脑现有数据库"
fi

linked_target_home="$TEST_ROOT/linked-target-codex"
linked_target_external="$TEST_ROOT/linked-target-external"
mkdir -p "$linked_target_home" "$linked_target_external"
ln -s "$linked_target_external" "$linked_target_home/sessions"
sqlite3 "$linked_target_home/state_5.sqlite" \
  'CREATE TABLE threads(id TEXT PRIMARY KEY);'
if /bin/bash "$MIGRATION_SCRIPT" import "$archive_path" \
  --codex-home "$linked_target_home" \
  --backup-dir "$backup_directory" \
  --replace-existing-indexes >/dev/null 2>&1; then
  fail "拒绝向目标符号链接目录导入"
else
  pass "拒绝向目标符号链接目录导入"
fi
if [[ -e "$linked_target_external/source.jsonl" ]]; then
  fail "目标符号链接不会导致越界写入"
else
  pass "目标符号链接不会导致越界写入"
fi

linked_file_target_home="$TEST_ROOT/linked-file-target-codex"
linked_file_external="$TEST_ROOT/linked-file-target-external.txt"
mkdir -p "$linked_file_target_home"
printf 'must remain unchanged\n' > "$linked_file_external"
ln -s "$linked_file_external" "$linked_file_target_home/AGENTS.md"
sqlite3 "$linked_file_target_home/state_5.sqlite" \
  'CREATE TABLE threads(id TEXT PRIMARY KEY);'
if /bin/bash "$MIGRATION_SCRIPT" import "$archive_path" \
  --codex-home "$linked_file_target_home" \
  --backup-dir "$backup_directory" \
  --replace-existing-indexes >/dev/null 2>&1; then
  fail "拒绝覆盖目标符号链接文件"
else
  pass "拒绝覆盖目标符号链接文件"
fi
assert_file_contains "目标文件符号链接不会导致越界覆盖" \
  "$linked_file_external" "must remain unchanged"

unsafe_source="$TEST_ROOT/unsafe-source"
mkdir -p "$unsafe_source"
printf 'unsafe\n' > "$unsafe_source/payload.txt"
unsafe_archive="$TEST_ROOT/unsafe.tar.gz"
python3 - "$unsafe_archive" "$unsafe_source/payload.txt" <<'PYTHON'
import sys
import tarfile

with tarfile.open(sys.argv[1], "w:gz") as archive:
    archive.add(sys.argv[2], arcname="../escape.txt")
PYTHON

if /bin/bash "$MIGRATION_SCRIPT" inspect "$unsafe_archive" >/dev/null 2>&1; then
  fail "拒绝包含路径穿越的归档"
else
  pass "拒绝包含路径穿越的归档"
fi

printf '\n测试汇总：%d 通过，%d 失败\n' "$PASS_COUNT" "$FAIL_COUNT"
if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
