#!/usr/bin/env python3
"""把三条新守卫接入 gate.sh / gate-fast.sh（门禁 14/15/16），并同步道数口径14→17。

带断言：每个替换点必须命中预期次数，不符即 exit 1 且**不写文件**。
"""
from __future__ import annotations

import io
import sys

GATE_SH = r"d:\ai-teacher\yuesheng-flutter\scripts\gate.sh"
FAST_SH = r"d:\ai-teacher\yuesheng-flutter\scripts\gate-fast.sh"
HOOK = r"d:\ai-teacher\yuesheng-flutter\scripts\git-hooks\pre-commit"
INSTALL_PS = r"d:\ai-teacher\yuesheng-flutter\scripts\install-git-hooks.ps1"

edits: dict[str, list[tuple[str, str, int]]] = {}


def add(path: str, old: str, new: str, expect: int) -> None:
    edits.setdefault(path, []).append((old, new, expect))


# ---------- gate.sh ----------
NEW_BLOCK = '''
# ---------- 门禁 14: flag 契约同步（scripts/check_flag_contract.py）----------
# 背景（2026-10-07 P0 事故 7d245a75）：该提交把 kBlockEditorEnabled 由 false 翻为
# true，提交信息自述「+ 同步测试契约」，实际只同步了 block_readonly_view_test.dart、
# **漏了 writing_page_test.dart** ⇒ 收尾门禁 54 例红，且事故当时零台账登记。
# 根因不是「忘了」，而是「自述已同步 ≠ 已同步」**没有机器执行点**。
# 判据（守卫内建）：G1 空扫 fail-closed / G2 登记完整性 / G3 值变更时受影响测试
#   必须**同批**改动。基线 tool/flag_contract_baseline.json。
# 退出码：0 通过 / 1 有未同步或登记缺失 / 2 环境不可判定（rc=2 判 FAIL 不当 SKIP）。
echo "--> 门禁 14/17: flag 变更须同步测试契约（ADR-0002 事故 7d245a75 遗留）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3/ python，跳过 flag 契约扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$FLAG_CONTRACT_LOG"
  RC_FLAG_CONTRACT=SKIP
elif [ ! -f "$ROOT/tool/flag_contract_baseline.json" ]; then
  echo "  [WARN] flag 基线缺失（tool/flag_contract_baseline.json），跳过"
  echo "SKIP: (NOT EXECUTED) baseline missing" > "$FLAG_CONTRACT_LOG"
  RC_FLAG_CONTRACT=SKIP
else
  if "$PY_BIN" scripts/check_flag_contract.py > "$FLAG_CONTRACT_LOG" 2>&1; then
    RC_FLAG_CONTRACT=0
  else
    RC_FLAG_CONTRACT=1
    cat "$FLAG_CONTRACT_LOG"
  fi
fi
log_result "flag 契约同步" "$RC_FLAG_CONTRACT"

# ---------- 门禁 15: ADR 悬空引用 ----------
# 背景：.ai/adr/ 的编号↔实体对应关系此前**只靠人记**，无机器执行点。实测
# ADR-0001 被 .ai 文档引 9 处（代码侧零引用）而 .ai/adr/ 下无 0001 实体文件。
# 判据：G1 空扫 fail-closed / G2 悬空引用须补实体或**显式登记豁免**（EXEMPT 表
#   只认裸 4 位数字键）/ G3 索引陈旧提醒（排除已豁免）。
# ⚠️ 跨仓判据：它读仓库根的 .ai/ 与 yuesheng-flutter/（本仓是 monorepo 子目录，
#   git 仓库根是 D:/ai-teacher 而非 yuesheng-flutter/）—— 路径错配会静默零扫描，
#   故守卫内建 G1 空扫 fail-closed。
echo "--> 门禁 15/17: ADR 悬空引用（编号↔实体必须有实文件）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过 ADR 悬空扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$ADR_DANGLING_LOG"
  RC_ADR_DANGLING=SKIP
elif [ ! -d "$ROOT/../.ai/adr" ]; then
  echo "  [WARN] 未找到 ADR 目录（$ROOT/../.ai/adr），跳过"
  echo "SKIP: (NOT EXECUTED) adr dir missing" > "$ADR_DANGLING_LOG"
  RC_ADR_DANGLING=SKIP
else
  if "$PY_BIN" scripts/check_adr_dangling.py > "$ADR_DANGLING_LOG" 2>&1; then
    RC_ADR_DANGLING=0
  else
    RC_ADR_DANGLING=1
    cat "$ADR_DANGLING_LOG"
  fi
fi
log_result "ADR 悬空引用" "$RC_ADR_DANGLING"

# ---------- 门禁 16: git hook 副本同步 ----------
# 背景（2026-10-07 实踩）：scripts/git-hooks/pre-commit 是**源文件**（受版本控制），
# 而 git 实际执行的是 <git-dir>/hooks/pre-commit（**安装副本**，不受版本控制）。
# 二者只靠手工跑 install-git-hooks.ps1 同步 —— 改了源文件提交后**不生效**，而
# 一切检查都绿（源文件本身没问题）⇒ 静默失效。
# 判据：git rev-parse --absolute-git-dir 取生效目录 → 比 md5；不一致报红并给出
#   修复命令。副本未安装判 SKIP/0（首次 clone 常见，非漂移）。
echo "--> 门禁 16/17: hook 副本↔源文件同步（防改了不生效）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过 hook 同步扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$HOOK_SYNC_LOG"
  RC_HOOK_SYNC=SKIP
else
  if "$PY_BIN" scripts/check_hook_sync.py > "$HOOK_SYNC_LOG" 2>&1; then
    RC_HOOK_SYNC=0
  else
    RC_HOOK_SYNC=1
    cat "$HOOK_SYNC_LOG"
  fi
fi
log_result "hook 副本同步" "$RC_HOOK_SYNC"

# ---------- 汇总报告 ----------'''

add(GATE_SH, "\n# ---------- 汇总报告 ----------", NEW_BLOCK, 1)
add(GATE_SH,
    'EXT_SHAPE_LOG="$OUT_DIR/extension_shape.txt"',
    'EXT_SHAPE_LOG="$OUT_DIR/extension_shape.txt"\n'
    'FLAG_CONTRACT_LOG="$OUT_DIR/flag_contract.txt"\n'
    'ADR_DANGLING_LOG="$OUT_DIR/adr_dangling.txt"\n'
    'HOOK_SYNC_LOG="$OUT_DIR/hook_sync.txt"', 1)
add(GATE_SH,
    '| extension 单块行数（只卡新增） | $(verdict "${RC_EXTENSION_SHAPE:-SKIP}") |',
    '| extension 单块行数（只卡新增） | $(verdict "${RC_EXTENSION_SHAPE:-SKIP}") |\n'
    '| flag 契约同步 | $(verdict "${RC_FLAG_CONTRACT:-SKIP}") |\n'
    '| ADR 悬空引用 | $(verdict "${RC_ADR_DANGLING:-SKIP}") |\n'
    '| hook 副本同步 | $(verdict "${RC_HOOK_SYNC:-SKIP}") |', 1)
add(GATE_SH,
    '- extension 单块行数: outputs/gate/extension_shape.txt',
    '- extension 单块行数: outputs/gate/extension_shape.txt\n'
    '- flag 契约同步: outputs/gate/flag_contract.txt\n'
    '- ADR 悬空引用: outputs/gate/adr_dangling.txt\n'
    '- hook 副本同步: outputs/gate/hook_sync.txt', 1)
# 道数口径 14→17（全文件统一；历史 bug 复盘叙述处的「十四道」按纪律不动，
# 但 gate.sh 的 7 处全是当前口径声明，故统一替换）
add(GATE_SH, "十四道", "十七道", 7)
add(GATE_SH, "门禁 13/14", "门禁 13/17", 1)


def main() -> int:
    # 先做断言式校验
    loaded = {}
    for path in edits:
        with io.open(path, encoding="utf-8") as fh:
            loaded[path] = fh.read()
    bad = []
    for path, items in edits.items():
        for old, new, expect in items:
            n = loaded[path].count(old)
            if n != expect:
                bad.append(f"{path}: 期望 {expect} 实得 {n} :: {old[:70]!r}")
    if bad:
        print("[ABORT] 断言不符，未写任何文件：")
        for b in bad:
            print("  " + b)
        return 1

    for path, items in edits.items():
        text = loaded[path]
        for old, new, _ in items:
            text = text.replace(old, new)
        with io.open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        print(f"[WROTE] {path} ({len(items)} 处)")
    return 0


if __name__ == "__main__":
    sys.exit(main())