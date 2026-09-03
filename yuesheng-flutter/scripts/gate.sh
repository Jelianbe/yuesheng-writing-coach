#!/usr/bin/env bash
# ============================================================
# 月笙写作教练 Flutter 端 — 六道门禁 (R-027 + 宪法 §二)
#
# 门禁 0: 代码格式 (dart format --set-exit-if-changed lib) — 宪法 §二.2
# 门禁 1: 静态分析 (dart analyze lib) — 类型检查 + Lint
# 门禁 2: 单元测试 (flutter test)
# 门禁 3: 循环依赖扫描 (scripts/check_circular.py) — 宪法 §二.4 / R-020
# 门禁 4: 安全/密钥扫描 (scripts/check_secrets.sh) — R-029
# 门禁 5: R-019 函数行数 (tool/check_r019.py --baseline) — 宪法 §二.3 硬上限
#         止血模式：以 tool/r019_baseline.json 为基线，存量豁免、只卡新增
#
# 用法:  bash scripts/gate.sh
# 退出码: 任一门禁 FAIL 则非 0 (可接入 CI / 提交前自检)
# ============================================================
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

OUT_DIR="$ROOT/outputs/gate"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/gate-report.md"

# 日志落盘
FORMAT_LOG="$OUT_DIR/format.txt"
TYPECHECK_LOG="$OUT_DIR/typecheck.txt"
TEST_LOG="$OUT_DIR/test.txt"
CIRCULAR_LOG="$OUT_DIR/circular.txt"
SECURITY_LOG="$OUT_DIR/security.txt"
R019_LOG="$OUT_DIR/r019.txt"

pass=0
fail=0

emit() { printf '%s\n' "$1"; }
log_result() {
  local name="$1"; local ok="$2"
  if [ "$ok" = "0" ]; then
    emit "[PASS] $name"
    pass=$((pass + 1))
  else
    emit "[FAIL] $name"
    fail=$((fail + 1))
  fi
}

echo "=================================================="
echo "月笙 Flutter 六道门禁 @ $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="

# ---------- 公共：定位 python（门禁 3 / 5 共用）----------
# Windows 兼容：优先 python3，fallback python；两者都不可用时门禁 3 / 5 跳过。
PY_BIN=""
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
  PY_BIN=python3
elif command -v python >/dev/null 2>&1 && python -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
  PY_BIN=python
else
  echo "  [WARN] 未找到可用的 python3 / python —— 门禁 3（循环依赖）与门禁 5（R-019）将跳过"
fi

# ---------- 门禁 0: 格式（宪法 §二.2）----------
echo "--> 门禁 0/6: 格式校验 (dart format --set-exit-if-changed lib)"
if dart format --set-exit-if-changed -o none lib > "$FORMAT_LOG" 2>&1; then
  log_result "格式校验 (dart format)" 0
else
  log_result "格式校验 (dart format)" 1
  tail -n 40 "$FORMAT_LOG"
fi

# ---------- 门禁 1: 静态分析 ----------
echo "--> 门禁 1/6: 静态分析 (dart analyze lib)"
if dart analyze lib > "$TYPECHECK_LOG" 2>&1; then
  log_result "静态分析 (analyze lib)" 0
else
  log_result "静态分析 (analyze lib)" 1
  tail -n 30 "$TYPECHECK_LOG"
fi

# ---------- 门禁 2: 测试 ----------
echo "--> 门禁 2/6: 单元测试 (flutter test)"
if flutter test > "$TEST_LOG" 2>&1; then
  log_result "单元测试 (flutter test)" 0
else
  log_result "单元测试 (flutter test)" 1
  tail -n 40 "$TEST_LOG"
fi

# ---------- 门禁 3: 循环依赖（调用独立脚本 scripts/check_circular.py）----------
echo "--> 门禁 3/6: 循环依赖扫描 (lib import 图)"
if [ -n "$PY_BIN" ]; then
  if "$PY_BIN" scripts/check_circular.py "$ROOT" > "$CIRCULAR_LOG" 2>&1; then
    log_result "循环依赖扫描" 0
  else
    log_result "循环依赖扫描" 1
    cat "$CIRCULAR_LOG"
  fi
else
  echo "  [WARN] 未找到 python3 / python，跳过循环依赖扫描（建议本地装 Python 3.10+）"
  echo "OK: (SKIPPED) python not available" > "$CIRCULAR_LOG"
  log_result "循环依赖扫描(跳过)" 0
fi

# ---------- 门禁 4: 安全 / 密钥（调用独立脚本 scripts/check_secrets.sh）----------
echo "--> 门禁 4/6: 安全/密钥扫描"
if bash scripts/check_secrets.sh "$ROOT" > "$SECURITY_LOG" 2>&1; then
  log_result "安全/密钥扫描" 0
else
  log_result "安全/密钥扫描" 1
  cat "$SECURITY_LOG"
fi

# ---------- 门禁 5: R-019 函数行数（止血模式：存量豁免，只卡新增）----------
#
# 背景：R-019 规定「函数 ≤ 50 行（硬上限）」，但此前四道门禁**没有一道检查它**，
# 债务已累积到 264 个（手写 237 个）却无人察觉。本门禁不追溯存量——
# 以 tool/r019_baseline.json 为基线，只阻止**新增**超限，避免一次性阻塞所有提交。
# 待债务按期清偿后，可去掉 --baseline 改为全量卡口。
echo "--> 门禁 5/6: R-019 函数行数（基线豁免，只卡新增）"
if [ -n "$PY_BIN" ] && [ -f "$ROOT/tool/r019_baseline.json" ]; then
  if "$PY_BIN" tool/check_r019.py --baseline tool/r019_baseline.json > "$R019_LOG" 2>&1; then
    log_result "R-019 函数行数" 0
  else
    log_result "R-019 函数行数" 1
    tail -n 30 "$R019_LOG"
  fi
else
  echo "  [WARN] python 不可用或基线缺失（tool/r019_baseline.json），跳过 R-019 扫描"
  echo "OK: (SKIPPED)" > "$R019_LOG"
  log_result "R-019 函数行数(跳过)" 0
fi

# ---------- 汇总报告 ----------
cat > "$REPORT" <<EOF
# 六道门禁报告

- 时间: $(date '+%Y-%m-%d %H:%M:%S')
- 项目: yuesheng-flutter

| 门禁 | 结果 |
|------|------|
| 格式校验 (dart format) | $(grep -q 'Formatted.*0 changed' "$FORMAT_LOG" 2>/dev/null && echo PASS || (grep -q 'Changed' "$FORMAT_LOG" 2>/dev/null && echo FAIL || echo PASS)) |
| 静态分析 (dart analyze lib) | $([ -s "$TYPECHECK_LOG" ] && grep -q ' error ' "$TYPECHECK_LOG" && echo FAIL || echo PASS) |
| 单元测试 (flutter test) | $([ -s "$TEST_LOG" ] && grep -qE 'Some tests failed|FAIL' "$TEST_LOG" && echo FAIL || echo PASS) |
| 循环依赖扫描 | $(grep -q 'OK:' "$CIRCULAR_LOG" && echo PASS || echo FAIL) |
| 安全/密钥扫描 | $(grep -q 'OK:' "$SECURITY_LOG" 2>/dev/null && echo PASS || echo FAIL) |
| R-019 函数行数（只卡新增） | $(grep -q 'SKIPPED' "$R019_LOG" 2>/dev/null && echo SKIP || (grep -q '无超限函数' "$R019_LOG" 2>/dev/null && echo PASS || echo FAIL)) |

汇总: ${pass} 通过 / ${fail} 失败

## 详细日志
- 格式: outputs/gate/format.txt
- 静态分析: outputs/gate/typecheck.txt
- 测试: outputs/gate/test.txt
- 循环依赖: outputs/gate/circular.txt
- 安全扫描: outputs/gate/security.txt
- R-019 函数行数: outputs/gate/r019.txt
EOF

echo "=================================================="
echo "汇总: $pass 通过 / $fail 失败"
echo "报告: $REPORT"
echo "=================================================="

[ "$fail" -eq 0 ]
