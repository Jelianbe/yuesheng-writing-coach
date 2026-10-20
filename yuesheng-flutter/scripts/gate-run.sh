#!/usr/bin/env bash
# ============================================================
# 月笙 Flutter 端 — 门禁统一入口 (gate-run)
#
# 【本文件刻意不做的事】
#   **不含任何门禁判据**。它只做三件不相干的事：选路 / 透传参数 / 记一笔运行流水。
#   任何「顺手在这里加一道检查」的想法都必须拒绝 —— 那会立刻造出第三份判据副本，
#   与 gate.sh / gate-fast.sh 必然漂移（本项目已因「同一事实多处表述」吃过多次亏）。
#
# 【为什么需要一个入口】
#   在此之前，人要在脑子里记住：收尾是 gate.sh、迭代是 gate-fast.sh、
#   快道还有 --all / --no-test / 显式路径 / --dry-run 四种形态，
#   而命中率报告是第三个脚本。**记不住 ⇒ 只用最简单那一个 ⇒ 收尾道被跳过**。
#   wrapper 把「该跑哪条道」变成一次选择。
#
# 用法:
#   bash scripts/gate-run.sh                # = 收尾道（19 道全量），默认即此项
#   bash scripts/gate-run.sh full           # 同上（显式）
#   bash scripts/gate-run.sh fast           # = 快道 + 全量测试（gate-fast.sh --all）
#   bash scripts/gate-run.sh quick          # = 快道 + 跳过测试（约 20s，只跑静态门禁）
#   bash scripts/gate-run.sh fast test/a_test.dart test/b/    # 透传给快道
#   bash scripts/gate-run.sh hits           # 命中率报告（透传给 gate_hits_report.py）
#   bash scripts/gate-run.sh hits --days 30
#
# 约定:
#   · 参数里出现 full / fast / quick / hits 视为**选路**；其余一律视为**快道的透传参数**
#     （即 `gate-run.sh test/xxx_test.dart` 等价于 `gate-fast.sh test/xxx_test.dart`）。
#   · 退出码 = 被调用脚本的退出码，**不做任何改写**。
#   · 每次运行追加一行到 outputs/gate/runs.jsonl（本机累积、换机清零，同 hits.jsonl）。
# ============================================================
set -u

_SELF="${BASH_SOURCE[0]}"
case "$_SELF" in
  */*) _DIR="${_SELF%/*}" ;;
  *)   _DIR="." ;;
esac
ROOT="$(cd "$_DIR/.." && pwd)"
cd "$ROOT" || exit 1

OUT_DIR="$ROOT/outputs/gate"
mkdir -p "$OUT_DIR"
RUNS_LOG="$OUT_DIR/runs.jsonl"

# ---- 选路 ----
PROFILE="full"
if [ "$#" -gt 0 ]; then
  case "$1" in
    full|fast|quick|hits) PROFILE="$1"; shift ;;
    *) PROFILE="fast" ;;   # 裸路径/裸参数 ⇒ 意图是快道
  esac
fi

case "$PROFILE" in
  full)
    CMD=(bash "$ROOT/scripts/gate.sh")
    ;;
  fast)
    # ★ 显式给了测试路径 ⇒ 不传 --all。原因：gate-fast.sh 的参数解析里
    #   `TEST_PATHS` 非空会**覆盖** MODE（见其 58-75 行）⇒ 传 `--all test/x` 时
    #   --all 会被静默吞掉，跑的是 x 而不是全量。此处不制造这个假象。
    if [ "$#" -gt 0 ]; then
      CMD=(bash "$ROOT/scripts/gate-fast.sh" "$@")
    else
      CMD=(bash "$ROOT/scripts/gate-fast.sh" --all)
    fi
    ;;
  quick)
    # ★ 同上反向：--no-test 会被 TEST_PATHS 覆盖 ⇒ 带了参数就等于「不做 quick」。
    #   与其静默变成另一件事，不如直接拒绝。
    if [ "$#" -gt 0 ]; then
      echo "[FAIL] quick 模式不接受额外参数（--no-test 会被静默覆盖成 paths 模式）：$*" >&2
      echo "       要指定测试文件请用: bash scripts/gate-run.sh fast <路径...>" >&2
      exit 2
    fi
    CMD=(bash "$ROOT/scripts/gate-fast.sh" --no-test)
    ;;
  hits)
    PY_BIN=""
    if command -v python3 >/dev/null 2>&1; then PY_BIN=python3
    elif command -v python >/dev/null 2>&1; then PY_BIN=python
    fi
    if [ -z "$PY_BIN" ]; then
      echo "[FAIL] 需要 python3/python 才能出命中率报告" >&2
      exit 2
    fi
    exec "$PY_BIN" "$ROOT/scripts/gate_hits_report.py" "$@"
    ;;
esac

# ---- 跑，并记流水 ----
HITS_LOG="$OUT_DIR/hits.jsonl"
HITS_BEFORE=0
[ -f "$HITS_LOG" ] && HITS_BEFORE=$(wc -l < "$HITS_LOG" 2>/dev/null || echo 0)

# 把实际档位透传给被调用脚本，使 hits.jsonl 的 profile 与 runs.jsonl 一致
# （否则 quick 在 runs 里叫 quick、在 hits 里却叫 fast，两份账对不上）。
export GATE_PROFILE_OVERRIDE="$PROFILE"

T0=$(date +%s)
"${CMD[@]}"
RC=$?
T1=$(date +%s)
DUR=$((T1 - T0))

HITS_AFTER=$HITS_BEFORE
[ -f "$HITS_LOG" ] && HITS_AFTER=$(wc -l < "$HITS_LOG" 2>/dev/null || echo 0)
HITS_ADDED=$((HITS_AFTER - HITS_BEFORE))

HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
printf '{"ts":"%s","profile":"%s","rc":%d,"dur_s":%d,"head":"%s","hits_added":%d}\n' \
  "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$PROFILE" "$RC" "$DUR" "$HEAD" "$HITS_ADDED" \
  >> "$RUNS_LOG" 2>/dev/null || true

echo "--------------------------------------------------"
if [ "$HITS_ADDED" -gt 0 ]; then
  echo "命中率流水: +${HITS_ADDED} 条 → bash scripts/gate-run.sh hits 查看累计命中率"
else
  echo "⚠️  命中率流水本次 0 条新增 —— 记录装置可能没生效，别当成「全部通过」"
fi
echo "本次: profile=${PROFILE} / rc=${RC} / ${DUR}s"
exit "$RC"
