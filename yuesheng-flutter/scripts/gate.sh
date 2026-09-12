#!/usr/bin/env bash
# ============================================================
# 月笙写作教练 Flutter 端 — 七道门禁 (R-027 + 宪法 §二)
#
# 门禁 0: 代码格式 (dart format --set-exit-if-changed lib) — 宪法 §二.2
# 门禁 1: 静态分析 (dart analyze lib) — 类型检查 + Lint
# 门禁 2: 单元测试 (flutter test --coverage) — 同时产出 coverage/lcov.info
# 门禁 3: 循环依赖扫描 (scripts/check_circular.py) — 宪法 §二.4 / R-020
#         **全量卡口**：2026-09-03 ADR-C70 解开全部 3 个存量环后已撤除豁免基线
#         ⚠️ 本门禁曾长期假绿（路径不可解析 + lib 缺失时 return 0 放行 +
#            裸相对导入不进图），2026-09-03 修复，详见下方门禁 3 注释
# 门禁 4: 安全/密钥扫描 (scripts/check_secrets.sh) — R-029
# 门禁 5: R-019 函数行数 (tool/check_r019.py --baseline) — 宪法 §二.3 硬上限
#         止血模式：以 tool/r019_baseline.json 为基线，存量豁免、只卡新增
# 门禁 6: 覆盖率 (scripts/check_coverage.py) — R-013 口径补全
#         T1 = 整体行覆盖率 ≥ 65%（±2% 容差，< 63% 才 FAIL）
#         T2 = 五个核心文件各自 85% 硬门槛
#         ⚠️ **必须**读取门禁 2 刚产出的 coverage/lcov.info（门禁 2 已带
#            --coverage）。覆盖率不能独立跑测试：陈旧 lcov 会假绿
#            （查的是旧代码），单文件测试产出的 lcov 会假红（T1 仅 0.83%）。
#
# 用法:  bash scripts/gate.sh
# 退出码: 任一门禁 FAIL **或** 任一门禁未真正执行 (SKIP/DEGRADED) 则非 0
#
# ⚠️ 失败关闭约定 (2026-09-12 实证，三脚本统一)：
#    「无法检查 ≠ 通过」。当门禁因环境缺失（python 不可用、lib 不存在等）
#    而**从未真正执行**时，绝不允许记为 PASS。三种此前互相矛盾的策略
#    （check_circular.py return 2 / check_secrets.sh exit 0 / gate.sh 记 PASS）
#    现统一为 fail-closed：一律非 0 退出 + 明确原因。
#    本脚本中 python 缺失使门禁 3 / 5 跳过、或 lcov 缺失使门禁 6 跳过时，
#    记 `SKIP`（独立于 PASS/FAIL），并在报告的**顶部**打出醒目的
#    `⚠️ DEGRADED` 警告，退出码非 0。
#    这样「全绿」才真正等价于「七道都跑过且都通过」。
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
COVERAGE_LOG="$OUT_DIR/coverage.txt"

pass=0
fail=0
degraded=0   # 因环境缺失而**未真正执行**的门禁数（fail-closed：计入退出码）

emit() { printf '%s\n' "$1"; }
# 记录一道门禁的结果。
#   ok=0    → PASS
#   ok=SKIP → SKIP（未真正执行）；不是 PASS，计入 degraded，使退出码非 0
#   其他    → FAIL
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
echo "月笙 Flutter 七道门禁 @ $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="

# ---------- 公共：定位 python（门禁 3 / 5 / 6 共用）----------
# Windows 兼容：优先 python3，fallback python；两者都不可用时门禁 3 / 5 / 6 跳过。
PY_BIN=""
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
  PY_BIN=python3
elif command -v python >/dev/null 2>&1 && python -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
  PY_BIN=python
else
  echo "  [WARN] 未找到可用的 python3 / python —— 门禁 3（循环依赖）、门禁 5（R-019）与门禁 6（覆盖率）将跳过"
fi

# ---------- 门禁 0: 格式（宪法 §二.2）----------
echo "--> 门禁 0/7: 格式校验 (dart format --set-exit-if-changed lib)"
if dart format --set-exit-if-changed -o none lib > "$FORMAT_LOG" 2>&1; then
  RC_FORMAT=0
else
  RC_FORMAT=1
  tail -n 40 "$FORMAT_LOG"
fi
log_result "格式校验 (dart format)" "$RC_FORMAT"

# ---------- 门禁 1: 静态分析 ----------
echo "--> 门禁 1/7: 静态分析 (dart analyze lib)"
if dart analyze lib > "$TYPECHECK_LOG" 2>&1; then
  RC_ANALYZE=0
else
  RC_ANALYZE=1
  tail -n 30 "$TYPECHECK_LOG"
fi
log_result "静态分析 (analyze lib)" "$RC_ANALYZE"

# ---------- 门禁 2: 测试 ----------
echo "--> 门禁 2/7: 单元测试 (flutter test)"
# V4.18：会话注入的 HTTP_PROXY 会劫持 Dart VM ↔ flutter_tester 的
# localhost WebSocket，导致全量测试加载失败（错误行同样带 [E]，
# 看起来每个测试都失败）。门禁脚本必须主动清空代理环境变量，
# 否则整道门禁在某些会话环境下会假红。
#
# V4.22（2026-09-04 批次 I 实证）：AI 沙箱会话缺 PROGRAMFILES(X86)，
# flutter.bat → update_engine_version.ps1 报错退出，表现
# 「%PROGRAMFILES(X86)% environment variable not found.」且被 `| tail`
# 吞掉退出码后**假绿**。注入兜底统一放在 _run_flutter_test.sh：
#   原值优先，仅缺时注入 Windows 标准值；其他环境完全不变。
if bash scripts/_run_flutter_test.sh > "$TEST_LOG" 2>&1; then
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
#    图上做环检测。修复后暴露出 3 个真实存量环（Dart 允许循环 import，
#    故此前从未出过问题）。
#
# ✅ 2026-09-03 ADR-C70：3 个存量环已全部解开，**转为全量卡口**
#    （去掉 --baseline，任何环一律拦截）。这正是 V4.14 设定的终点——
#    豁免基线只是让门禁先落地的过渡手段，债务清零后就必须撤掉，
#    否则门禁会一直停留在「只卡新增」的弱化状态。
#    tool/circular_baseline.json 已重生成空数组并保留在库中，
#    供将来确需临时豁免时按同一格式使用（届时必须同时登记清偿计划）。
echo "--> 门禁 3/7: 循环依赖扫描 (lib import 图，全量卡口)"
if [ -n "$PY_BIN" ]; then
  if "$PY_BIN" scripts/check_circular.py . > "$CIRCULAR_LOG" 2>&1; then
    RC_CIRCULAR=0
  else
    RC_CIRCULAR=1
    cat "$CIRCULAR_LOG"
  fi
else
  echo "  [WARN] 未找到 python3 / python，跳过循环依赖扫描（建议本地装 Python 3.10+）"
  echo "SKIP: (NOT EXECUTED) python not available" > "$CIRCULAR_LOG"
  RC_CIRCULAR=SKIP
fi
# 统一在分支外记录：真正执行过记其退出码，跳过则记 SKIP（fail-closed，非 PASS）
log_result "循环依赖扫描" "$RC_CIRCULAR"

# ---------- 门禁 4: 安全 / 密钥（调用独立脚本 scripts/check_secrets.sh）----------
echo "--> 门禁 4/7: 安全/密钥扫描"
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
echo "--> 门禁 5/7: R-019 函数行数（基线豁免，只卡新增）"
if [ -n "$PY_BIN" ] && [ -f "$ROOT/tool/r019_baseline.json" ]; then
  if "$PY_BIN" tool/check_r019.py --baseline tool/r019_baseline.json > "$R019_LOG" 2>&1; then
    RC_R019=0
  else
    RC_R019=1
    tail -n 30 "$R019_LOG"
  fi
else
  echo "  [WARN] python 不可用或基线缺失（tool/r019_baseline.json），跳过 R-019 扫描"
  echo "SKIP: (NOT EXECUTED)" > "$R019_LOG"
  RC_R019=SKIP
fi
# 统一在分支外记录：跳过记 SKIP（fail-closed，非 PASS）
log_result "R-019 函数行数" "$RC_R019"

# ---------- 门禁 6: 覆盖率（调用独立脚本 scripts/check_coverage.py）----------
#
# 背景（R-013 口径缺口）：门禁 0-5 中**没有**任何覆盖率检查——只有 CI
# （.github/workflows/flutter_ci.yaml:96-104）有。于是本地提交前发现不了
# 覆盖率跌破，只能等 CI 失败，反馈链路过长。本门禁把 CI 的口径原样搬回本地。
#
# ⚠️ 为什么覆盖率**不能**独立成门禁自己跑测试（2026-09 实证）：
#    - 复用仓库里陈旧的 coverage/lcov.info → **假绿**（查的是旧代码；
#      实测仓库内文件停在 2026-08-28，66.37% 已失真）；
#    - 若本门禁自行只跑个别测试文件 → 产出的 lcov 只含那几个文件，
#      整体行覆盖率仅 0.83%，T1 必然 FAIL → **假红**。
#    ⇒ 因此门禁 2 的测试包装器（_run_flutter_test.sh）已固定加 `--coverage`，
#      本门禁只**读取门禁 2 刚产出的新鲜 lcov**，二者构成一条流水线。
#      **顺序依赖**：门禁 6 必须在门禁 2 之后。
#
# ⚠️ lcov 缺失时记 FAIL 而非 SKIP（QA 审计 2026-09-12 裁定）：
#    前置守卫写 `[ -f lcov ]` 曾把脚本自身的 exit 2 保护**架空**——lcov 不在
#    就直接记 SKIP，而 SKIP 只是「不计入通过」，不会像 FAIL 那样把原因钉在
#    报告上。实测中 lcov 会被**并发运行的 flutter test --coverage** 抽走
#    （dart 每次跑完都要重写该文件），于是门禁 6 会在「其实该查」的情况下
#    常态 SKIP（qa 实测：2026-09-12 上午 lcov 两次消失又重生成）。
#    现在改为：门禁 2 通过而 lcov 仍缺失 ⇒ FAIL，并提示查并发。
#    仅当 python 不可用或门禁 2 本身没跑成功时才保留 SKIP。
#
# ⚠️ 传参必须与 CI 完全一致（对齐 flutter_ci.yaml:96-104），
#    否则本地与 CI 口径分叉，又会出现「本地绿、CI 红」的落差。
#    --expect-t2-count 5 是本地额外的**静默降级护栏**：CI 那条命令写死了
#    5 条 --t2，若将来有人删掉一条，剩下 4 条仍可能全 PASS → CI 假绿、
#    实际少守一个文件。加了这条护栏，数量不符一律 FAIL。
#    刻意**不传** --warn-event-file：那是 CI 的跨 run WARN 计数机制，本地无需。
#
# 退出码语义（check_coverage.py）：0 = T1 PASS/WARN 且 T2 全过；
#    1 = T1 FAIL 或任一 T2 FAIL/缺失 或 T2 数量不符护栏；
#    2 = 环境错误（lcov 缺失 / 解析 0 记录 / --t2 语法错）。
echo "--> 门禁 6/7: 覆盖率检查 (T1 整体 ≥65%，T2 五个核心文件各 ≥85%)"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过覆盖率检查"
  echo "SKIP: (NOT EXECUTED) python not available" > "$COVERAGE_LOG"
  RC_COVERAGE=SKIP
elif [ "${RC_TEST:-1}" != "0" ]; then
  # 门禁 2 没通过 ⇒ lcov 可能只写了一半甚至没写，覆盖率无从判定。
  # 此时不该报 FAIL（会把「测试挂了」误报成「覆盖率挂了」），记 SKIP。
  echo "  [WARN] 门禁 2 未通过，未产出可信 lcov，跳过覆盖率检查"
  echo "SKIP: (NOT EXECUTED) gate 2 did not pass" > "$COVERAGE_LOG"
  RC_COVERAGE=SKIP
elif [ ! -f "$ROOT/coverage/lcov.info" ]; then
  # V4.28（QA 实测 2026-09-12）：门禁 2 跑成功却没留下 lcov —— 最常见的
  # 原因是**另一个会话正在并发跑 flutter test --coverage**，dart 收尾时
  # 会重写/删除 coverage/ 目录。这不是「无法检查」，是「本该检查却没东西
  # 可查」，按 fail-closed 记 FAIL，逼出真实原因而不是静默放行。
  echo "  [FAIL] 门禁 2 已通过但 coverage/lcov.info 不存在 —— 疑似并发 flutter test --coverage 将其抽走"
  echo "FAIL: lcov missing although gate 2 passed (concurrent flutter test --coverage?)" > "$COVERAGE_LOG"
  RC_COVERAGE=1
else
  if "$PY_BIN" scripts/check_coverage.py \
    --lcov coverage/lcov.info \
    --t1-target 65.0 --t1-margin 2.0 \
    --t2 "lib/services/training_evaluator.dart:85" \
    --t2 "lib/services/evaluation_service.dart:85" \
    --t2 "lib/data/repositories/diagnosis_repository.dart:85" \
    --t2 "lib/services/chat_service.dart:85" \
    --t2 "lib/services/focus_resolver.dart:85" \
    --expect-t2-count 5 > "$COVERAGE_LOG" 2>&1; then
    RC_COVERAGE=0
  else
    RC_COVERAGE=1
    cat "$COVERAGE_LOG"
  fi
fi
log_result "覆盖率检查" "$RC_COVERAGE"

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

# 顶部 DEGRADED 横幅：任一 SKIP 门禁都必须在报告最显眼处点名，
# 防止「跳过」被埋在表格里、而汇总行仍写着「全绿」。
DEGRADED_BANNER=""
if [ "$degraded" -gt 0 ]; then
  DEGRADED_BANNER="> ⚠️ **DEGRADED: ${degraded} 门未真正执行**（见下表 SKIP 项）——\
报告**不可**视为全绿；请补齐环境后重跑。

"
fi

cat > "$REPORT" <<EOF
# 七道门禁报告

${DEGRADED_BANNER}- 时间: $(date '+%Y-%m-%d %H:%M:%S')
- 项目: yuesheng-flutter

| 门禁 | 结果 |
|------|------|
| 格式校验 (dart format) | $(verdict "${RC_FORMAT:-SKIP}") |
| 静态分析 (dart analyze lib) | $(verdict "${RC_ANALYZE:-SKIP}") |
| 单元测试 (flutter test) | $(verdict "${RC_TEST:-SKIP}") |
| 循环依赖扫描 | $(verdict "${RC_CIRCULAR:-SKIP}") |
| 安全/密钥扫描 | $(verdict "${RC_SECRETS:-SKIP}") |
| R-019 函数行数（只卡新增） | $(verdict "${RC_R019:-SKIP}") |
| 覆盖率检查 | $(verdict "${RC_COVERAGE:-SKIP}") |

汇总: ${pass} 通过 / ${fail} 失败 / ${degraded} 未执行（SKIP）

## 详细日志
- 格式: outputs/gate/format.txt
- 静态分析: outputs/gate/typecheck.txt
- 测试: outputs/gate/test.txt
- 循环依赖: outputs/gate/circular.txt
- 安全扫描: outputs/gate/security.txt
- R-019 函数行数: outputs/gate/r019.txt
- 覆盖率: outputs/gate/coverage.txt
EOF

echo "=================================================="
if [ "$degraded" -gt 0 ]; then
  echo "⚠️  DEGRADED: ${degraded} 门未真正执行（SKIP）——不计入通过"
fi
echo "汇总: $pass 通过 / $fail 失败 / $degraded 未执行"
echo "报告: $REPORT"
echo "=================================================="

# fail-closed：任一 FAIL 或任一 SKIP（未真正执行）都使退出码非 0。
# 「全绿」= fail==0 且 degraded==0，此时才确信七道都真的跑过。
[ "$fail" -eq 0 ] && [ "$degraded" -eq 0 ]
