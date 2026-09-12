#!/usr/bin/env bash
# ============================================================
# 月笙写作教练 Flutter 端 — 十二道门禁 (R-027 + 宪法 §二)
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
# 门禁 7: Prompt 反模式 (scripts/check_prompt_antipattern.py --diff-baseline) — R-025
# 门禁 8: 内容元数据 (scripts/check_content_metadata.py --strict) — R-025
# 门禁 9: 交互回归 (scripts/check_interaction_regression.py) — 仅 P0 阻断
# 门禁 10: 伪拆分形态 (scripts/check_split_shape.py --baseline) — R-019 §2
#          A 类纯常量知识库按文件名豁免（见 R-019:57-60）
# 门禁 11: A 类豁免准入 (scripts/check_a_class_exemption.py --baseline) — R-019:57-60
#          把 A 类豁免的**前提**变成可执行判据（内容级），堵住门禁 10 的 fail-open
#          基线 tool/a_class_exemption_baseline.json，止血模式：只卡新增
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
#    这样「全绿」才真正等价于「十二道都跑过且都通过」。
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
PROMPT_LINT_LOG="$OUT_DIR/prompt_lint.txt"
META_LOG="$OUT_DIR/content_metadata.txt"
INTERACTION_LOG="$OUT_DIR/interaction.txt"
SPLIT_LOG="$OUT_DIR/split_shape.txt"
A_CLASS_LOG="$OUT_DIR/a_class_exemption.txt"

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
echo "月笙 Flutter 十二道门禁 @ $(date '+%Y-%m-%d %H:%M:%S')"
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
echo "--> 门禁 0/12: 格式校验 (dart format --set-exit-if-changed lib)"
if dart format --set-exit-if-changed -o none lib > "$FORMAT_LOG" 2>&1; then
  RC_FORMAT=0
else
  RC_FORMAT=1
  tail -n 40 "$FORMAT_LOG"
fi
log_result "格式校验 (dart format)" "$RC_FORMAT"

# ---------- 门禁 1: 静态分析 ----------
echo "--> 门禁 1/12: 静态分析 (dart analyze lib)"
if dart analyze lib > "$TYPECHECK_LOG" 2>&1; then
  RC_ANALYZE=0
else
  RC_ANALYZE=1
  tail -n 30 "$TYPECHECK_LOG"
fi
log_result "静态分析 (analyze lib)" "$RC_ANALYZE"

# ---------- 门禁 2: 测试 ----------
echo "--> 门禁 2/12: 单元测试 (flutter test)"
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
echo "--> 门禁 3/12: 循环依赖扫描 (lib import 图，全量卡口)"
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
echo "--> 门禁 4/12: 安全/密钥扫描"
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
echo "--> 门禁 5/12: R-019 函数行数（基线豁免，只卡新增）"
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
echo "--> 门禁 6/12: 覆盖率检查 (T1 整体 ≥65%，T2 五个核心文件各 ≥85%)"
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

# ---------- 门禁 7: Prompt 反模式（调用 scripts/check_prompt_antipattern.py）----------
#
# 背景（ADR-C92）：该脚本早已写好、能跑，却**从未接入任何门禁**——它真正能拦到
# 的 prompt 话术反模式（强制触发 / 固定格式 / 断言式下结论）被静默放过。
#
# ⚠️ 接入前必须先修假阳性（2026-09-12 实测）：修复前 12 条命中里 11 条是假阳性
#    （92%）——`report-tone` 把月笙**核心协议字段「诊断置信度」**错当报告腔，
#    `assert-conclude` 把 `❌` 标注的反例说明当断言，`cross-dup` 把**有意的
#    跨文件教学规则一致性**当重复缺陷。带着这些假阳性接门禁，结果是「正常改
#    prompt 就假红」→ 门禁被当噪音绕过。现已修复，并**不能反过来改 prompt 去
#    迎合检查器**（违反 R-009/R-010）。
#
# ⚠️ 用 --diff-baseline 而非全量：存量 1 条真阳性（force-trigger）走基线祖父，
#    只卡**新增**，与门禁 5/6 的先例一致（门禁 5 止血基线 / 门禁 6 T2 守卫）。
#    cross-dup 已降级为信息型，不参与 FAIL 判定。
#
# ⚠️ --expect-rule-count 4 是**静默降级护栏**（类比门禁 6 的 --expect-t2-count）：
#    若将来有人删掉一条 KEYWORD_RULES，剩余规则仍可能全 PASS → 假绿、
#    实际少守一类反模式。加了这条护栏，规则数不符一律 FAIL。
#
# 退出码语义（check_prompt_antipattern.py）：0 = 无新增（diff 模式）；
#    1 = 有新增命中 / 规则数不符护栏。
echo "--> 门禁 7/12: Prompt 反模式（diff-baseline，只卡新增）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过 prompt 反模式扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$PROMPT_LINT_LOG"
  RC_PROMPT=SKIP
elif [ ! -d "$ROOT/lib/services" ]; then
  # 扫描目录不存在 ⇒ 脚本会 return 1（被误当「有反模式」），故在 wrapper 先判，
  # 记 SKIP（环境缺失）而非 FAIL，避免把「找不到目录」误报成「有反模式」。
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

# ---------- 门禁 8: 内容元数据（调用 scripts/check_content_metadata.py）----------
#
# 背景（ADR-C92）：同为「已写未接入」脚本。检查内容增减规范要求的元数据头
# （体积/定位/来源/loadWhen）是否齐备。内置存量豁免，只卡新增头缺失。
#
# ⚠️ 必须用 --strict：非 strict 模式下有 finding 也是 rc=0（advisory），
#    接为门禁会恒绿、零价值。--strict 才有「有 finding → 1」的阻断语义。
echo "--> 门禁 8/12: 内容元数据（--strict，只卡新增缺失）"
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

# ---------- 门禁 9: 交互回归（调用 scripts/check_interaction_regression.py）----------
#
# 背景（ADR-C92）：拦截会导致**运行时崩溃**的交互/导航缺陷（P0 级）。
# 仅 P0 命中才 FAIL；P1 候选只报告不阻断（避免误报海啸淹没门禁）。
#
# ⚠️ 空 lib 扫描会假绿（2026-09-12 规格验证）：若 lib 下无 .dart 文件，
#    脚本会 rc=0「什么都没扫到」——这不是「通过」，是「没检查」。故 wrapper
#    先判 lib 下有 .dart，否则记 SKIP（fail-closed，绝不记 PASS）。
echo "--> 门禁 9/12: 交互回归（仅 P0 阻断，P1 报告）"
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

# ---------- 门禁 10: 伪拆分形态（调用 scripts/check_split_shape.py）----------
#
# 背景（舰长质询 2026-09-12 / docs/audits/pseudo-split-legacy-inventory-2026-09-12.md）：
# **R-019 的「文件 ≤300 行」与「禁止 part/extension 伪拆分」两条从来没有机器
# 执行点**——tool/check_r019.py 只统计**函数**行数（limit=50），基线里没有
# 任何文件行数字段。⇒ 伪拆分是**唯一一种七道门禁全绿也无法察觉**的劣化形态。
# 本门禁补上这个执行点。
#
# 判据（三条，实测 S1=3 / S2=5 / S3=4）：
#   S1 宿主>300 且家族内有 part>300 ⇒ 伪拆分（宿主没变小，还多造一个超限文件）
#   S2 宿主>300（含「拆了没拆动」形态）
#   S3 家族内任一 part>300
#   A 类豁免（R-019:57-60）：skills_*.dart / skill_registry.dart /
#     *_knowledge_base.dart / {syndrome,technique,training}_kb_content*.dart
#     —— 纯常量知识库，part 与内容领域边界一致，不触发伪拆分审查。
#
# ⚠️ 基线止血模式（同门禁 5）：存量 12 条违规走基线祖父，只卡**新增**。
#    否则本门禁一上线就红灯、阻塞所有提交，会被当噪音绕过。
#    基线一旦生成不会自动变严 ⇒ **每清偿一条必须重生成基线**：
#      python scripts/check_split_shape.py --json tool/split_shape_baseline.json
#    **重生成时绝不能带 --baseline**（脚本已内置防护：同传 → exit 2）。
#
# 退出码语义（check_split_shape.py）：0 = 通过/无新增；1 = 有违规/新增；
#    2 = 环境错误（lib 缺失 / 0 个 dart / --json 与 --baseline 同传）。
echo "--> 门禁 10/12: 伪拆分形态（基线豁免，只卡新增）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过伪拆分扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$SPLIT_LOG"
  RC_SPLIT=SKIP
elif [ ! -f "$ROOT/tool/split_shape_baseline.json" ]; then
  echo "  [WARN] 伪拆分基线缺失（tool/split_shape_baseline.json），跳过"
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

# ---------- 门禁 11: A 类豁免准入守卫（调用 scripts/check_a_class_exemption.py）----------
#
# 背景（2026-09-12 侦察，docs/recon-reports/RECON-P3-knowledge-relief-2026-09-12.md）：
# 门禁 10 的 A 类豁免是**纯按文件名**（`_A_CLASS_PATTERNS`）的——它豁免「A 类纯常量
# 知识库」，却**从不校验文件内容是否真的满足豁免前提**。⇒ 豁免是 fail-open 的，
# 存在一条完全绕过门禁 10 的路径（代码直读）：
#     建 `foo.dart` 声明 `part 'skills_data.dart';`，`skills_data.dart` 装 800 行逻辑
#     ⇒ 宿主行数没超（S1/S2 不报），分片 basename 命中豁免（S3 不报）。
# 本门禁把 R-019:57-60 的豁免**前提**变成可执行判据。
#
# 判据（四条，每条锚定 R-019 一处前提）：
#   A1  **分片**不得声明 class/extension/mixin（前提②「纯常量」）
#   A2  **任何 A 类文件**不得含 @override（前提③「无 override 契约」）
#   A3  **分片**顶层函数须逐名登记在基线内（前提②「无逻辑耦合」）
#   A4  **任何 A 类文件**必须是 part 家族成员（守住豁免适用范围，防命名滥用）
#   ⚠️ 宿主不做 A1/A3 断言：宿主按设计保留「检索/渲染逻辑」（批次 96-26/96-27），
#      对其施加「无函数」会与既定分离设计冲突（越权改规则）。宿主仍受 A2/A4 约束。
#
# ⚠️ 基线止血模式（同门禁 5/10）：存量漂移 2 个分片 / 5 个函数（Phase 3 阶段裁剪
#    入口）走基线 `allowedFunctions` **透明登记**，只卡**新增**。
#    基线一旦生成不会自动变严 ⇒ **每清偿一条必须重生成基线**：
#       python scripts/check_a_class_exemption.py --json tool/a_class_exemption_baseline.json
#    **重生成时绝不能带 --baseline**（脚本已内置防护：同传 → exit 2）。
#    另：分片数由 `minPartCount` 守（G1）——把分片改名移出豁免集会触发 FAIL。
#
# 退出码语义（check_a_class_exemption.py）：0 = 通过/无新增；1 = 有违规/新增/守卫失败；
#    2 = 环境错误（lib 缺失 / 0 个 dart / 0 个豁免文件 / 真源缺失或载入失败 /
#    基线结构非法 / --json 与 --baseline 同传）。
echo "--> 门禁 11/12: A 类豁免准入守卫（基线豁免，只卡新增）"
if [ -z "$PY_BIN" ]; then
  echo "  [WARN] 未找到 python3 / python，跳过 A 类豁免准入扫描"
  echo "SKIP: (NOT EXECUTED) python not available" > "$A_CLASS_LOG"
  RC_ACLASS=SKIP
elif [ ! -f "$ROOT/tool/a_class_exemption_baseline.json" ]; then
  echo "  [WARN] A 类豁免基线缺失（tool/a_class_exemption_baseline.json），跳过"
  echo "SKIP: (NOT EXECUTED) baseline missing" > "$A_CLASS_LOG"
  RC_ACLASS=SKIP
elif [ ! -f "$ROOT/scripts/check_split_shape.py" ]; then
  # 豁免模式真源缺失 ⇒ 脚本 exit 2（fail-closed）。在 wrapper 先判并记 SKIP，
  # 避免把「环境缺失」与「真有违规」混为一谈（但仍计入 degraded → 退出码非 0）。
  echo "  [WARN] 豁免模式真源缺失（scripts/check_split_shape.py），跳过"
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
# 十二道门禁报告

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
| Prompt 反模式（只卡新增） | $(verdict "${RC_PROMPT:-SKIP}") |
| 内容元数据（--strict） | $(verdict "${RC_META:-SKIP}") |
| 交互回归（仅 P0） | $(verdict "${RC_INTERACTION:-SKIP}") |
| 伪拆分形态（只卡新增） | $(verdict "${RC_SPLIT:-SKIP}") |
| A 类豁免准入（只卡新增） | $(verdict "${RC_ACLASS:-SKIP}") |

汇总: ${pass} 通过 / ${fail} 失败 / ${degraded} 未执行（SKIP）

## 详细日志
- 格式: outputs/gate/format.txt
- 静态分析: outputs/gate/typecheck.txt
- 测试: outputs/gate/test.txt
- 循环依赖: outputs/gate/circular.txt
- 安全扫描: outputs/gate/security.txt
- R-019 函数行数: outputs/gate/r019.txt
- 覆盖率: outputs/gate/coverage.txt
- Prompt 反模式: outputs/gate/prompt_lint.txt
- 内容元数据: outputs/gate/content_metadata.txt
- 交互回归: outputs/gate/interaction.txt
- 伪拆分形态: outputs/gate/split_shape.txt
- A 类豁免准入: outputs/gate/a_class_exemption.txt
EOF

echo "=================================================="
if [ "$degraded" -gt 0 ]; then
  echo "⚠️  DEGRADED: ${degraded} 门未真正执行（SKIP）——不计入通过"
fi
echo "汇总: $pass 通过 / $fail 失败 / $degraded 未执行"
echo "报告: $REPORT"
echo "=================================================="

# fail-closed：任一 FAIL 或任一 SKIP（未真正执行）都使退出码非 0。
# 「全绿」= fail==0 且 degraded==0，此时才确信十二道都真的跑过。
[ "$fail" -eq 0 ] && [ "$degraded" -eq 0 ]
