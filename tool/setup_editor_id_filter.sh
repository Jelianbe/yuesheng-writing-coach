#!/usr/bin/env bash
#
# setup_editor_id_filter.sh — 注册「剥除编辑器节点 ID」的 git clean filter。
#
# 【为什么需要一个脚本，而不是只改 .gitattributes】
# `.gitattributes` 只能**声明**某个 pattern 用哪个 filter（它随仓走，能跨机同步）；
# filter 的**实现**（clean = 跑哪个命令）必须写进 `.git/config`，而 `.git/config`
# **不随仓走**。⇒ 新克隆 / 新机器上，`.gitattributes` 的声明会指向一个未定义的
# filter。此时 git 的行为取决于 `required`：
#   · `required = true`  → `git add` **报错停下**（fail-closed，我们要的）
#   · `required` 缺省/false → git **静默放行原内容**（噪声照进库，且不报错）
# ⇒ 本脚本的第一个动作就是**先写 required=true**，再写 clean，避免中途失败留下
#   「声明了但未定义」的静默放行窗口。
#
# 【幂等】反复跑无副作用；已存在则覆盖为当前口径。
# 【失败关闭】任何一步失败立即 exit 非零，不吞错。
#
# 用法：
#   bash tool/setup_editor_id_filter.sh          # 注册
#   bash tool/setup_editor_id_filter.sh --check  # 只检查，不改动（rc=0 表示已就绪）

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

PY=""
if command -v python3 >/dev/null 2>&1; then
  PY=python3
elif command -v python >/dev/null 2>&1; then
  PY=python
else
  echo "[FAIL] 找不到 python3 / python —— clean filter 无法运行" >&2
  exit 2
fi

CLEAN_CMD="$PY tool/strip_editor_ids.py"

check_only=0
if [ "${1:-}" = "--check" ]; then
  check_only=1
fi

if [ "$check_only" -eq 1 ]; then
  rc=0
  cur_clean="$(git config --get filter.stripEditorIds.clean || true)"
  cur_req="$(git config --get filter.stripEditorIds.required || true)"
  if [ "$cur_clean" != "$CLEAN_CMD" ]; then
    echo "[MISS] filter.stripEditorIds.clean = '${cur_clean}'（期望 '$CLEAN_CMD'）"
    rc=1
  fi
  if [ "$cur_req" != "true" ]; then
    echo "[MISS] filter.stripEditorIds.required = '${cur_req}'（期望 'true'）"
    rc=1
  fi
  if [ -f tool/strip_editor_ids.py ]; then
    echo "[ OK ] tool/strip_editor_ids.py 存在"
  else
    echo "[FAIL] tool/strip_editor_ids.py 不存在"
    rc=1
  fi
  if [ "$rc" -eq 0 ]; then
    echo "[ OK ] filter 已就绪"
  fi
  exit "$rc"
fi

# ★ 顺序关键：先 required，再 clean。
git config filter.stripEditorIds.required true
git config filter.stripEditorIds.clean "$CLEAN_CMD"
git config filter.stripEditorIds.smudge cat

echo "[ OK ] filter.stripEditorIds.clean    = $CLEAN_CMD"
echo "[ OK ] filter.stripEditorIds.required = true"
echo "[ OK ] filter.stripEditorIds.smudge   = cat"

# 注册后立刻自检：一个已知含注入的样例必须被剥除。
#
# ★ 口径纪律（本脚本首版这里就写错过，留痕防复发）：
#   `grep -c` 数的是**命中的行数**，`grep -o | wc -l` 数的是**命中的处数**。
#   同一文件实测 **167 行 / 203 处** —— 一行可含多处。两者不同义，不可互换。
#   本项目一律以「处」为准（属性是逐标签注入的，行数没有语义）。
if [ -f .ai/tmp/_dirty_index_backup.html ]; then
  before="$("$PY" tool/strip_editor_ids.py < .ai/tmp/_dirty_index_backup.html 2>&1 >/dev/null | sed -n 's/.*剥除 \([0-9]*\) 处.*/\1/p')"
  after="$(grep -o 'data-page-node-id' .ai/tmp/_dirty_index_backup.html | wc -l || true)"
  echo "[SELF] 样例注入 $after 处 → 剥除 $before 处（期望两者相等且剩 0）"
  if [ -n "$before" ] && [ "$before" -ne "$after" ]; then
    echo "[FAIL] 剥除数 $before ≠ 注入处数 $after" >&2
    exit 1
  fi
fi

echo "[ OK ] setup 完成"