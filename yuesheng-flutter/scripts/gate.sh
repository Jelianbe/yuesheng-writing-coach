#!/usr/bin/env bash
# ============================================================
# 月笙写作教练 Flutter 端 — 六道门禁 (R-027 + 宪法 §二)
#
# 门禁 0: 代码格式 (dart format --set-exit-if-changed lib) — 宪法 §二.2
# 门禁 1: 静态分析 (dart analyze lib) — 类型检查 + Lint
# 门禁 2: 单元测试 (flutter test)
# 门禁 3: 循环依赖扫描 (scripts/check_circular.py) — 宪法 §二.4 / R-020
#         止血模式：以 tool/circular_baseline.json 为基线（存量 3 环），只卡新增
#         ⚠️ 本门禁曾长期假绿（路径不可解析 + lib 缺失时 return 0 放行、
#            裸相对导入不进图），2026-09-03 修复，详见下方门禁 3 注释
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
  RC_FORMAT=0
else
  RC_FORMAT=1
  tail -n 40 "$FORMAT_LOG"
fi
log_result "格式校验 (dart format)" "$RC_FORMAT"

# ---------- 门禁 1: 静态分析 ----------
echo "--> 门禁 1/6: 静态分析 (dart analyze lib)"
if dart analyze lib > "$TYPECHECK_LOG" 2>&1; then
  RC_ANALYZE=0
else
  RC_ANALYZE=1
  tail -n 30 "$TYPECHECK_LOG"
fi
log_result "静态分析 (analyze lib)" "$RC_ANALYZE"

# ---------- 门禁 2: 测试 ----------
echo "--> 门禁 2/6: 单元测试 (flutter test)"
if flutter test > "$TEST_LOG" 2>&1; then
  RC_TEST=0
else
  RC_TEST=1
  tail -n 40 "$TEST_LOG"
fi
log_result "单元测试 (flutter test)" "$RC_TEST"

# ---------- 门禁 3: 循环依赖（调用独立脚本 scripts/check_circular.py）----------
#
# ⚠️ 传参必须能被 Windows 原生 python 解析（2026-09-03 实证）：
#    旧写法传 "$ROOT"（Git Bash 的 `/d/ai-teacher/...`），python 侧拼出
#    `lib not found`，而 check_circular.py 当时 **return 0 静默放行**，
#    结果门禁 3 长期假绿、一次都没真正扫过。现两处都已修：
#    传 "."（gate.sh 已 cd 至 ROOT）+ 脚本侧 lib 缺失时失败关闭（退出码 2）。
#
# ⚠️ 修好后的第二层问题：建图时**裸相对导入**（`import 'x.dart';`）不进图，
#    而本项目有 177 条这样的边（占内部边 21.7%）——等于在缺了五分之一边的
#    图上做环检测。修复后立刻暴露出 3 个真实存量环（Dart 允许循环 import，
#    故此前从未出过问题）。它们位于核心模块，需先写 ADR 才能动，
#    故先走止血模式：存量登记进 tool/circular_baseline.json，只卡新增。
echo "--> 门禁 3/6: 循环依赖扫描 (lib import 图)"
if [ -n "$PY_BIN" ]; then
  if "$PY_BIN" scripts/check_circular.py . \
      --baseline tool/circular_baseline.json > "$CIRCULAR_LOG" 2>&1; then
    RC_CIRCULAR=0
  else
    RC_CIRCULAR=1
    cat "$CIRCULAR_LOG"
  fi
else
  echo "  [WARN] 未找到 python3 / python，跳过循环依赖扫描（建议本地装 Python 3.10+）"
  echo "OK: (SKIPPED) python not available" > "$CIRCULAR_LOG"
  RC_CIRCULAR=SKIP
  log_result "循环依赖扫描(跳过)" 0
fi
# 跳过分支（python 不可用）已单独记为 PASS，此处只在真正执行过时记录
if [ "$RC_CIRCULAR" != "SKIP" ]; then
  log_result "循环依赖扫描" "$RC_CIRCULAR"
fi

# ---------- 门禁 4: 安全 / 密钥（调用独立脚本 scripts/check_secrets.sh）----------
echo "--> 门禁 4/6: 安全/密钥扫描"
if bash scripts/check_secrets.sh "$ROOT" > "$SECURITY_LOG" 2>&1; then
  RC_SECRETS=0
else
  RC_SECRETS=1
  cat "$SECURITY_LOG"
fi
log_result "安全/密钥扫描" "$RC_SECRETS"

# ---------- 门禁 5: R-019 函数行数（止血模式：存量豁免，只卡新增）----------
#
# 背景：R-019 规定「函数 ≤ 50 行（硬上限）」，但此前四道门禁**没有一道检查它**，
# 债务已累积到 264 个（手写 237 个）却无人察觉。本门禁不追溯存量——
# 以 tool/r019_baseline.json 为基线，只阻止**新增**超限，避免一次性阻塞所有提交。
# 待债务按期清偿后，可去掉 --baseline 改为全量卡口。
echo "--> 门禁 5/6: R-019 函数行数（基线豁免，只卡新增）"
if [ -n "$PY_BIN" ] && [ -f "$ROOT/tool/r019_baseline.json" ]; then
  if "$PY_BIN" tool/check_r019.py --baseline tool/r019_baseline.json > "$R019_LOG" 2>&1; then
    RC_R019=0
  else
    RC_R019=1
    tail -n 30 "$R019_LOG"
  fi
else
  echo "  [WARN] python 不可用或基线缺失（tool/r019_baseline.json），跳过 R-019 扫描"
  echo "OK: (SKIPPED)" > "$R019_LOG"
  RC_R019=SKIP
  log_result "R-019 函数行数(跳过)" 0
fi
if [ "$RC_R019" != "SKIP" ]; then
  log_result "R-019 函数行数" "$RC_R019"
fi

# ---------- 汇总报告 ----------
#
# 判定一律以**退出码**为准（2026-09-03 实证）：旧版对循环依赖用
# `grep -q 'OK:'` 判定，而脚本在 lib 找不到时打印的是 `SKIP:`，
# 于是同一份日志里「汇总 6 通过 / 0 失败」却显示「循环依赖 FAIL」——
# 报告自相矛盾，且掩盖了门禁其实没跑的事实。
# 口诀：**报告里的一切判定都要回到退出码，别二次解读日志文本。**
verdict() {
  case "$1" in
    0) printf 'PASS' ;;
    SKIP) printf 'SKIP' ;;
    *) printf 'FAIL' ;;
  esac
}

cat > "$REPORT" <<EOF
# 六道门禁报告

- 时间: $(date '+%Y-%m-%d %H:%M:%S')
- 项目: yuesheng-flutter

| 门禁 | 结果 |
|------|------|
| 格式校验 (dart format) | $(verdict "${RC_FORMAT:-SKIP}") |
| 静态分析 (dart analyze lib) | $(verdict "${RC_ANALYZE:-SKIP}") |
| 单元测试 (flutter test) | $(verdict "${RC_TEST:-SKIP}") |
| 循环依赖扫描 | $(verdict "${RC_CIRCULAR:-SKIP}") |
| 安全/密钥扫描 | $(verdict "${RC_SECRETS:-SKIP}") |
| R-019 函数行数（只卡新增） | $(verdict "${RC_R019:-SKIP}") |

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
