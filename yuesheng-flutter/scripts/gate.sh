#!/usr/bin/env bash
# ============================================================
# 月笙写作教练 Flutter 端 — 四道门禁 (R-027 四道代码质量门禁)
#
# 门禁 1: 静态分析 (dart analyze lib) — 类型检查 + Lint
# 门禁 2: 单元测试 (flutter test)
# 门禁 3: 循环依赖扫描 (lib 内 import 图 DFS 检测环)
# 门禁 4: 安全/可达性扫描 (R-029 密钥零硬编码 / 基础可达性)
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

# 日志落盘（保留历史产物，类似旧机制 _typecheck.txt/_test.txt/_circular.txt/_a11y.txt）
TYPECHECK_LOG="$OUT_DIR/typecheck.txt"
TEST_LOG="$OUT_DIR/test.txt"
CIRCULAR_LOG="$OUT_DIR/circular.txt"
SECURITY_LOG="$OUT_DIR/security.txt"

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
echo "月笙 Flutter 四道门禁 @ $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="

# ---------- 门禁 1: 静态分析 ----------
echo "--> 门禁 1/4: 静态分析 (dart analyze lib)"
if dart analyze lib > "$TYPECHECK_LOG" 2>&1; then
  log_result "静态分析 (analyze lib)" 0
else
  log_result "静态分析 (analyze lib)" 1
  tail -n 30 "$TYPECHECK_LOG"
fi

# ---------- 门禁 2: 测试 ----------
echo "--> 门禁 2/ 4: 单元测试 (flutter test)"
if flutter test > "$TEST_LOG" 2>&1; then
  log_result "单元测试 (flutter test)" 0
else
  log_result "单元测试 (flutter test)" 1
  tail -n 40 "$TEST_LOG"
fi

# ---------- 门禁 3: 循环依赖（调用独立脚本 scripts/check_circular.py）----------
echo "--> 门禁 3/4: 循环依赖扫描 (lib import 图)"
# Windows 兼容：优先 python3，fallback python
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
  PY_BIN=python3
elif command -v python >/dev/null 2>&1; then
  PY_BIN=python
else
  echo "  [WARN] 未找到 python3 / python，跳过循环依赖扫描（建议本地装 Python 3.10+）"
  echo "OK: (SKIPPED) python not available" > "$CIRCULAR_LOG"
  log_result "循环依赖扫描(跳过)" 0
  PY_BIN=""
fi
if [ -n "${PY_BIN:-}" ]; then
  if "$PY_BIN" scripts/check_circular.py "$ROOT" > "$CIRCULAR_LOG" 2>&1; then
    log_result "循环依赖扫描" 0
  else
    log_result "循环依赖扫描" 1
    cat "$CIRCULAR_LOG"
  fi
fi

# ---------- 门禁 4: 安全 / 可达性（调用独立脚本 scripts/check_secrets.sh）----------
echo "--> 门禁 4/4: 安全/可达性扫描"
if bash scripts/check_secrets.sh "$ROOT" > "$SECURITY_LOG" 2>&1; then
  log_result "安全/可达性扫描" 0
else
  log_result "安全/可达性扫描" 1
  cat "$SECURITY_LOG"
fi

# ---------- 汇总报告 ----------
cat > "$REPORT" <<EOF
# 四道门禁报告

- 时间: $(date '+%Y-%m-%d %H:%M:%S')
- 项目: yuesheng-flutter

| 门禁 | 结果 |
|------|------|
| 静态分析 (dart analyze lib) | $([ -s "$TYPECHECK_LOG" ] && grep -q ' error ' "$TYPECHECK_LOG" && echo FAIL || echo PASS) |
| 单元测试 (flutter test) | $([ -s "$TEST_LOG" ] && grep -qE 'Some tests failed|FAIL' "$TEST_LOG" && echo FAIL || echo PASS) |
| 循环依赖扫描 | $(grep -q 'OK:' "$CIRCULAR_LOG" && echo PASS || echo FAIL) |
| 安全/可达性扫描 | $(grep -q 'OK:' "$SECURITY_LOG" && echo PASS || echo FAIL) |

汇总: ${pass} 通过 / ${fail} 失败

## 详细日志
- 静态分析: outputs/gate/typecheck.txt
- 测试: outputs/gate/test.txt
- 循环依赖: outputs/gate/circular.txt
- 安全扫描: outputs/gate/security.txt
EOF

echo "=================================================="
echo "汇总: $pass 通过 / $fail 失败"
echo "报告: $REPORT"
echo "=================================================="

[ "$fail" -eq 0 ]
