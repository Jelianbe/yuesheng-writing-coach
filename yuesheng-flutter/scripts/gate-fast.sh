#!/usr/bin/env bash
# ============================================================
# 月笙写作教练 Flutter 端 — 快道门禁 (gate-fast)
#
# 【定位：这不是收尾门禁】收尾一律 `bash scripts/gate.sh`（十二道全量）。
# 本脚本只服务**编码迭代**：把「改一行代码等 4~6 分钟」压到约 40 秒。
#
# 与 gate.sh 的唯一差别（其余口径逐条复制，不得独立演化）：
#   - 门禁 2：只跑**本次改动推导出的测试文件**（gate.sh 跑全量 3435 例）
#   - 门禁 2：**不加 `--coverage`**（避免用窄范围 lcov 覆盖 coverage/lcov.info）
#   - 门禁 6：**不执行**（其输入 lcov 依赖门禁 2 全量产出，快道必然没有）
#   其余 0/1/3/4/5/7/8/9/10/11 十道与 gate.sh **完全相同**。
#
# 为什么不加 --coverage 反而必须强调：
#   仓库里的 coverage/lcov.info 是**收尾门禁 6 的唯一输入**。若快道用窄范围测试
#   写了一份只含几个文件的 lcov，随后某人跑收尾门禁 6 会读到它 ⇒ T1 跌到 1% 级
#   ⇒ **假红**。反之若读到陈旧 lcov ⇒ **假绿**。两种都是事故，故快道一律不碰它。
#
# 用法:
#   bash scripts/gate-fast.sh                 # 自动推导受影响的测试文件
#   bash scripts/gate-fast.sh --all           # 门禁 2 也跑全量（仍不含 --coverage / 门禁 6）
#   bash scripts/gate-fast.sh test/a_test.dart test/b/   # 显式指定要跑的测试
#   bash scripts/gate-fast.sh --no-test       # 完全跳过门禁 2（只跑十道静态门禁，约 20s）
#   bash scripts/gate-fast.sh --dry-run       # 只打印将执行什么，不真跑
#
# 日志: outputs/gate-fast/  报告: outputs/gate-fast/gate-report.md
#       —— **刻意与 gate.sh 的 outputs/gate/ 分开**，避免覆盖官方全量日志。
# 退出码: 任一门禁 FAIL 或任一门禁未真正执行 (SKIP) 则非 0。
#         门禁 6「按设计未执行」**不计入** degraded（快道本就不含它），
#         但在报告顶部显著标注，防止被误读为「全绿」。
# ============================================================
set -u

# 定位仓库根：用参数展开而非 `dirname`。
# 会话沙箱的 MSYS bash 缺 dirname（PATH 被重写），`$(dirname "$0")` 会算出空 ROOT，
# 之后所有门禁行为不可信。参数展开零外部命令依赖。
_SELF="${BASH_SOURCE[0]}"
case "$_SELF" in
  */*) _DIR="${_SELF%/*}" ;;
  *)   _DIR="." ;;
esac
ROOT="$(cd "$_DIR/.." && pwd)"
cd "$ROOT" || exit 1

# ---------- 参数解析 ----------
MODE="auto"          # auto | all | none | paths
TEST_PATHS=()
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --all)     MODE="all" ;;
    --no-test) MODE="none" ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,32p' "$_SELF" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) TEST_PATHS+=("$arg") ;;
  esac
done
if [ "${#TEST_PATHS[@]}" -gt 0 ]; then
  MODE="paths"
fi

OUT_DIR="$ROOT/outputs/gate-fast"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/gate-report.md"
FORMAT_LOG="$OUT_DIR/format.txt"
TYPECHECK_LOG="$OUT_DIR/typecheck.txt"
TEST_LOG="$OUT_DIR/test.txt"
CIRCULAR_LOG="$OUT_DIR/circular.txt"
SECURITY_LOG="$OUT_DIR/security.txt"
R019_LOG="$OUT_DIR/r019.txt"
PROMPT_LINT_LOG="$OUT_DIR/prompt_lint.txt"
META_LOG="$OUT_DIR/content_metadata.txt"
INTERACTION_LOG="$OUT_DIR/interaction.txt"
SPLIT_LOG="$OUT_DIR/split_shape.txt"
A_CLASS_LOG="$OUT_DIR/a_class_exemption.txt"
COVERAGE_LOG="$OUT_DIR/coverage.txt"

pass=0
fail=0
degraded=0

emit() { printf '%s\n' "$1"; }
log_result() {
  local name="$1"; local ok="$2"
  if [ "$ok" = "0" ]; then
    emit "[PASS] $name"
    pass=$((pass + 1))
  elif [ "$ok" = "SKIP" ]; then
    emit "[SKIP] $name（未真正执行 → 计入 DEGRADED，退出码非 0）"
    degraded=$((degraded + 1))
  else
    emit "[FAIL] $name"
    fail=$((fail + 1))
  fi
}

echo "=================================================="
echo "月笙 Flutter 快道门禁 @ $(date '+%Y-%m-%d %H:%M:%S')"
echo "（非收尾！收尾请跑 bash scripts/gate.sh 的十二道全量）"
echo "=================================================="

# ---------- 公共：定位 python（门禁 3 / 5 共用）----------
PY_BIN=""
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
  PY_BIN=python3
elif command -v python >/dev/null 2>&1 && python -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
  PY_BIN=python
else
  echo "  [WARN] 未找到可用的 python3 / python —— 门禁 3（循环依赖）与门禁 5（R-019）将跳过"
fi

# ---------- 推导本次受影响的测试文件 ----------
# 判据两条（并集，宁多勿少）：
#   a) test/ 下**自己**被改动的 .dart（新写的测试、改过的测试）
#   b) lib/**.dart 改动 ⇒ 在 test/ 下按**同名约定**找 `<basename>_test.dart`
# `core.quotepath=false` 必须有：否则含中文的路径会被 git 转义成 \"\\346...\" 形式，
# 后续 [ -f ] / find 全部失配（静默少跑测试 = 快道最危险的失效形态）。
derive_tests() {
  local changed base
  changed="$(git -c core.quotepath=false status --porcelain -uall 2>/dev/null \
    | awk '{ $1=""; sub(/^ /,""); print }')"
  for f in $changed; do
    case "$f" in
      test/*.dart) [ -f "$f" ] && printf '%s\n' "$f" ;;
    esac
  done
  for f in $changed; do
    case "$f" in
      lib/*.dart)
        base="$(basename "$f" .dart)"
        find test -type f -name "${base}_test.dart" 2>/dev/null
        ;;
    esac
  done | sort -u
}

TEST_SCOPE=""
case "$MODE" in
  all)  TEST_SCOPE="__ALL__" ;;
  none) TEST_SCOPE="" ;;
  paths) TEST_SCOPE="$(printf '%s\n' "${TEST_PATHS[@]}")" ;;
  auto) TEST_SCOPE="$(derive_tests)" ;;
esac

TEST_COUNT=0
if [ -n "$TEST_SCOPE" ] && [ "$TEST_SCOPE" != "__ALL__" ]; then
  TEST_COUNT="$(printf '%s\n' "$TEST_SCOPE" | sed '/^$/d' | wc -l | tr -d ' ')"
fi

echo "门禁 2 范围: ${MODE}（${TEST_COUNT} 个测试文件${TEST_SCOPE:+；__ALL__ 表示全量}）"
if [ "$MODE" = "auto" ] && [ "$TEST_COUNT" = "0" ]; then
  echo "  [WARN] 未能从改动推导出任何测试文件 —— 门禁 2 将记为 NOTRUN（不是通过！）"
  echo "         如需强制全量：bash scripts/gate-fast.sh --all"
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "---- --dry-run 将执行 ----"
  echo "门禁 0: dart format --set-exit-if-changed -o none lib test integration_test tool"
  echo "门禁 1: dart analyze lib integration_test tool test"
  if [ "$TEST_SCOPE" = "__ALL__" ]; then
    echo "门禁 2: flutter test --exclude-tags live,external   （全量）"
  elif [ -n "$TEST_SCOPE" ]; then
    echo "门禁 2: flutter test --exclude-tags live,external \\"
    printf '           %s\n' $TEST_SCOPE
  else
    echo "门禁 2: （不执行）"
  fi
  echo "门禁 3: python scripts/check_circular.py ."
  echo "门禁 4: bash scripts/check_secrets.sh"
  echo "门禁 5: python tool/check_r019.py --baseline tool/r019_baseline.json"
  echo "门禁 6: （按设计不执行——快道不产 lcov）"
  echo "门禁 7: python scripts/check_prompt_antipattern.py --diff-baseline --expect-rule-count 4"
  echo "门禁 8: python scripts/check_content_metadata.py --strict"
  echo "门禁 9: python scripts/check_interaction_regression.py"
  echo "门禁 10: python scripts/check_split_shape.py --baseline tool/split_shape_baseline.json --expect-rule-count 3"
  echo "门禁 11: python scripts/check_a_class_exemption.py --baseline tool/a_class_exemption_baseline.json --expect-rule-count 4"
  exit 0
fi

# ---------- 门禁 0: 格式 ----------
echo "--> 快道 门禁 0: 格式校验 (dart format lib test integration_test tool)"
if dart format --set-exit-if-changed -o none lib test integration_test tool > "$FORMAT_LOG" 2>&1; then
  RC_FORMAT=0
else
  RC_FORMAT=1
  tail -n 40 "$FORMAT_LOG"
fi
log_result "格式校验 (dart format)" "$RC_FORMAT"

# ---------- 门禁 1: 静态分析 ----------
echo "--> 快道 门禁 1: 静态分析 (dart analyze lib integration_test tool test)"
if dart analyze lib integration_test tool test > "$TYPECHECK_LOG" 2>&1; then
  RC_ANALYZE=0
else
  RC_ANALYZE=1
  tail -n 30 "$TYPECHECK_LOG"
fi
log_result "静态分析 (analyze lib+integration_test+tool+test)" "$RC_ANALYZE"

# ---------- 门禁 2: 窄范围测试 ----------
echo "--> 快道 门禁 2: 单元测试（窄范围，不加 --coverage）"
if [ "$TEST_SCOPE" = "__ALL__" ]; then
  if bash scripts/_run_flutter_test.sh > "$TEST_LOG" 2>&1; then
    RC_TEST=0
  else
    RC_TEST=1
    tail -n 40 "$TEST_LOG"
  fi
  log_result "单元测试 (flutter test，本轮强制全量)" "$RC_TEST"
elif [ -n "$TEST_SCOPE" ]; then
  # --exclude-tags live,external 由 _run_flutter_test.sh 固定加，此处不重复传
  RUN_FLUTTER_TEST_COVERAGE=0 bash scripts/_run_flutter_test.sh $TEST_SCOPE > "$TEST_LOG" 2>&1
  RC_TEST=$?
  if [ "$RC_TEST" != "0" ]; then
    tail -n 40 "$TEST_LOG"
  fi
  log_result "单元测试 (flutter test，窄范围 ${TEST_COUNT} 文件)" "$RC_TEST"
else
  echo "  [NOTRUN] 门禁 2 未执行（未推导出受影响测试 / --no-test）—— 这不是通过"
  echo "NOTRUN: gate 2 not executed (no affected test derived, or --no-test)" > "$TEST_LOG"
  RC_TEST="NOTRUN"
fi

# ---------- 门禁 3: 循环依赖（全量卡口）----------
echo "--> 快道 门禁 3: 循环依赖扫描（全量卡口）"
if [ -n "$PY_BIN" ]; then
  if "$PY_BIN" scripts/check_circular.py . > "$CIRCULAR_LOG" 2>&1; then
    RC_CIRCULAR=0
  else
    RC_CIRCULAR=1
    cat "$CIRCULAR_LOG"
  fi
else
  echo "  [WARN] 未找到 python3 / python，跳过循环依赖扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$CIRCULAR_LOG"
  RC_CIRCULAR=SKIP
fi
log_result "循环依赖扫描" "$RC_CIRCULAR"

# ---------- 门禁 4: 安全 / 密钥 ----------
echo "--> 快道 门禁 4: 安全/密钥扫描"
if bash scripts/check_secrets.sh "$ROOT" > "$SECURITY_LOG" 2>&1; then
  RC_SECRETS=0
else
  RC_SECRETS=1
  cat "$SECURITY_LOG"
fi
log_result "安全/密钥扫描" "$RC_SECRETS"

# ---------- 门禁 5: R-019 函数行数（止血模式）----------
echo "--> 快道 门禁 5: R-019 函数行数（基线豁免，只卡新增）"
if [ -n "$PY_BIN" ] && [ -f "$ROOT/tool/r019_baseline.json" ]; then
  if "$PY_BIN" tool/check_r019.py --baseline tool/r019_baseline.json > "$R019_LOG" 2>&1; then
    RC_R019=0
  else
    RC_R019=1
    tail -n 30 "$R019_LOG"
  fi
else
  echo "  [WARN] python 不可用或基线缺失，跳过 R-019 扫描"
  echo "SKIP: (NOT EXECUTED)" > "$R019_LOG"
  RC_R019=SKIP
fi
log_result "R-019 函数行数" "$RC_R019"

# ---------- 门禁 6: 覆盖率 —— 按设计不执行 ----------
# 快道不产 lcov，因此**不能**跑门禁 6。此处刻意留一条显式的 NOTRUN 记录，
# 而不是静默省略——静默省略会让下一个人以为「快道全绿 = 覆盖率也过了」。
echo "--> 快道 门禁 6: 覆盖率 —— 按设计不执行（快道不产 lcov；收尾由 gate.sh 负责）"
echo "NOTRUN: gate 6 is intentionally not executed by gate-fast (no lcov produced)." > "$COVERAGE_LOG"
RC_COVERAGE="NOTRUN"

# ---------- 门禁 7: Prompt 反模式 ----------
echo "--> 快道 门禁 7: Prompt 反模式（diff-baseline，只卡新增）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过 prompt 反模式扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$PROMPT_LINT_LOG"
  RC_PROMPT=SKIP
elif [ ! -d "$ROOT/lib/services" ]; then
  echo "  [WARN] lib/services 不存在，跳过 prompt 反模式扫描"
  echo "SKIP: (NOT EXECUTED) lib/services missing" > "$PROMPT_LINT_LOG"
  RC_PROMPT=SKIP
else
  if "$PY_BIN" scripts/check_prompt_antipattern.py \
    --diff-baseline --expect-rule-count 4 > "$PROMPT_LINT_LOG" 2>&1; then
    RC_PROMPT=0
  else
    RC_PROMPT=1
    cat "$PROMPT_LINT_LOG"
  fi
fi
log_result "Prompt 反模式" "$RC_PROMPT"

# ---------- 门禁 8: 内容元数据 ----------
echo "--> 快道 门禁 8: 内容元数据（--strict，只卡新增缺失）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过内容元数据检查"
  echo "SKIP: (NOT EXECUTED) python not available" > "$META_LOG"
  RC_META=SKIP
else
  if "$PY_BIN" scripts/check_content_metadata.py --strict > "$META_LOG" 2>&1; then
    RC_META=0
  else
    RC_META=1
    cat "$META_LOG"
  fi
fi
log_result "内容元数据" "$RC_META"

# ---------- 门禁 9: 交互回归 ----------
echo "--> 快道 门禁 9: 交互回归（仅 P0 阻断，P1 报告）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过交互回归扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$INTERACTION_LOG"
  RC_INTERACTION=SKIP
elif ! ls "$ROOT"/lib/**/*.dart >/dev/null 2>&1 && ! find "$ROOT/lib" -name '*.dart' -print -quit 2>/dev/null | grep -q .; then
  echo "  [WARN] lib 下未找到 .dart 文件，跳过交互回归扫描（空扫会假绿）"
  echo "SKIP: (NOT EXECUTED) no .dart under lib" > "$INTERACTION_LOG"
  RC_INTERACTION=SKIP
else
  if "$PY_BIN" scripts/check_interaction_regression.py > "$INTERACTION_LOG" 2>&1; then
    RC_INTERACTION=0
  else
    RC_INTERACTION=1
    cat "$INTERACTION_LOG"
  fi
fi
log_result "交互回归" "$RC_INTERACTION"

# ---------- 门禁 10: 伪拆分形态 ----------
echo "--> 快道 门禁 10: 伪拆分形态（基线豁免，只卡新增）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过伪拆分扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$SPLIT_LOG"
  RC_SPLIT=SKIP
elif [ ! -f "$ROOT/tool/split_shape_baseline.json" ]; then
  echo "  [WARN] 伪拆分基线缺失，跳过"
  echo "SKIP: (NOT EXECUTED) baseline missing" > "$SPLIT_LOG"
  RC_SPLIT=SKIP
else
  if "$PY_BIN" scripts/check_split_shape.py \
    --baseline tool/split_shape_baseline.json \
    --expect-rule-count 3 > "$SPLIT_LOG" 2>&1; then
    RC_SPLIT=0
  else
    RC_SPLIT=1
    cat "$SPLIT_LOG"
  fi
fi
log_result "伪拆分形态" "$RC_SPLIT"

# ---------- 门禁 11: A 类豁免准入 ----------
echo "--> 快道 门禁 11: A 类豁免准入守卫（基线豁免，只卡新增）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过 A 类豁免准入扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$A_CLASS_LOG"
  RC_ACLASS=SKIP
elif [ ! -f "$ROOT/tool/a_class_exemption_baseline.json" ]; then
  echo "  [WARN] A 类豁免基线缺失，跳过"
  echo "SKIP: (NOT EXECUTED) baseline missing" > "$A_CLASS_LOG"
  RC_ACLASS=SKIP
elif [ ! -f "$ROOT/scripts/check_split_shape.py" ]; then
  echo "  [WARN] 豁免模式真源缺失，跳过"
  echo "SKIP: (NOT EXECUTED) exemption source missing" > "$A_CLASS_LOG"
  RC_ACLASS=SKIP
else
  if "$PY_BIN" scripts/check_a_class_exemption.py \
    --baseline tool/a_class_exemption_baseline.json \
    --expect-rule-count 4 > "$A_CLASS_LOG" 2>&1; then
    RC_ACLASS=0
  else
    RC_ACLASS=1
    cat "$A_CLASS_LOG"
  fi
fi
log_result "A 类豁免准入" "$RC_ACLASS"

# ---------- 汇总报告 ----------
verdict() {
  case "$1" in
    0) printf 'PASS' ;;
    SKIP) printf 'SKIP' ;;
    NOTRUN) printf '未执行（设计）' ;;
    *) printf 'FAIL' ;;
  esac
}

DEGRADED_BANNER=""
if [ "$degraded" -gt 0 ]; then
  DEGRADED_BANNER="> ⚠️ **DEGRADED: ${degraded} 门未真正执行**（见下表 SKIP 项）——\
报告**不可**视为通过；请补齐环境后重跑。

"
fi

# 测试范围描述（写进报告，保证「过了」这句话有范围）
if [ "$TEST_SCOPE" = "__ALL__" ]; then
  TEST_SCOPE_DESC="全量（--all）"
elif [ -n "$TEST_SCOPE" ]; then
  TEST_SCOPE_DESC="${TEST_COUNT} 个文件：$(printf '%s ' $TEST_SCOPE)"
else
  TEST_SCOPE_DESC="**未执行**"
fi

cat > "$REPORT" <<EOF
# 快道门禁报告（**非收尾**）

> 🚦 这是**迭代快道**，不是十二道收尾门禁。它**不执行门禁 6（覆盖率）**。
> 声称「完成」前必须跑 \`bash scripts/gate.sh\` 并全绿。

${DEGRADED_BANNER}- 时间: $(date '+%Y-%m-%d %H:%M:%S')
- 项目: yuesheng-flutter
- 门禁 2 范围: ${TEST_SCOPE_DESC}

| 门禁 | 结果 |
|------|------|
| 0 格式校验 | $(verdict "${RC_FORMAT:-SKIP}") |
| 1 静态分析 | $(verdict "${RC_ANALYZE:-SKIP}") |
| 2 单元测试（窄范围） | $(verdict "${RC_TEST:-SKIP}") |
| 3 循环依赖扫描 | $(verdict "${RC_CIRCULAR:-SKIP}") |
| 4 安全/密钥扫描 | $(verdict "${RC_SECRETS:-SKIP}") |
| 5 R-019 函数行数 | $(verdict "${RC_R019:-SKIP}") |
| 6 覆盖率 | $(verdict "${RC_COVERAGE:-SKIP}") |
| 7 Prompt 反模式 | $(verdict "${RC_PROMPT:-SKIP}") |
| 8 内容元数据 | $(verdict "${RC_META:-SKIP}") |
| 9 交互回归 | $(verdict "${RC_INTERACTION:-SKIP}") |
| 10 伪拆分形态 | $(verdict "${RC_SPLIT:-SKIP}") |
| 11 A 类豁免准入 | $(verdict "${RC_ACLASS:-SKIP}") |

汇总: ${pass} 通过 / ${fail} 失败 / ${degraded} 未执行（SKIP） / 门禁 6 按设计未跑

## 详细日志
- 格式: outputs/gate-fast/format.txt
- 静态分析: outputs/gate-fast/typecheck.txt
- 测试: outputs/gate-fast/test.txt
- 循环依赖: outputs/gate-fast/circular.txt
- 安全扫描: outputs/gate-fast/security.txt
- R-019 函数行数: outputs/gate-fast/r019.txt
- 覆盖率: outputs/gate-fast/coverage.txt（NOTRUN 说明）
- Prompt 反模式: outputs/gate-fast/prompt_lint.txt
- 内容元数据: outputs/gate-fast/content_metadata.txt
- 交互回归: outputs/gate-fast/interaction.txt
- 伪拆分形态: outputs/gate-fast/split_shape.txt
- A 类豁免准入: outputs/gate-fast/a_class_exemption.txt
EOF

echo "=================================================="
if [ "$degraded" -gt 0 ]; then
  echo "⚠️  DEGRADED: ${degraded} 门未真正执行（SKIP）——不计入通过"
fi
echo "汇总: $pass 通过 / $fail 失败 / $degraded 未执行（门禁 6 按设计未跑）"
echo "报告: $REPORT"
echo "⚠️  这不是收尾门禁 —— 收尾请跑 bash scripts/gate.sh"
echo "=================================================="

[ "$fail" -eq 0 ] && [ "$degraded" -eq 0 ]
