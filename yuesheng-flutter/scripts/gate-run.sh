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

# ---- P5：本轮**起跑时**的工作树脏度（文件计数，`git status --porcelain -uall`）----
# 【为什么记这个】runs.jsonl 已有的字段能回答「什么时候 / 多久 / 哪个提交 / 新增几条命中」，
#   但回答不了「**这条失败对应的树长什么样**」。同一个 head + 同一个 rc，
#   可能出自一棵干净的树，也可能出自一棵改了 12 个文件的树 —— 后者不可复现。
#
# 【为什么在起跑前测】要描述的是「我们基于什么树跑的」。跑完之后测试可能改文件/生成快照，
#   那时再测，记下的就不是起跑时的状态了。
#
# 【为什么是计数不是布尔】布尔脏度「几乎恒为 1」，信息量近零 —— 这个判断本身没错。
#   但**计数不是布尔**：0 / 3 / 27 能区分「干净树上的失败」与「改到一半的树上的失败」。
#   这也是字段名必须是 `dirty_count` 而不能缩成 `dirty` 的原因：改名等于把计数偷偷降回布尔。
#
# 【为什么落在这里（每轮一行）而不是 hits.jsonl（每道一行）】
#   hits.jsonl 是 19 行/轮，各跑一次 `git status`（本机实测约 111 ms）合计约 2 s，
#   而同一轮内这 19 个值**完全相同** ⇒ 重复 19 份，零信息增量。
#
# 【读不到写 `-1`】`git status` 失败时 `wc -l` 仍会输出 0，那样「读不到」会被写成
#   「干净」—— 正是本卡要治的假绿形态。用 -1 做哨兵，
#   **保持该列始终是整数**（`jq '.dirty_count > 0'` 这类查询不会因类型混用而炸），
#   同时 0 与 -1 永不混淆。
#   ⚠️ 2026-10-25 更正：本条原先举例「index.lock 被占」，**那个例子是错的**。
#   实测（独立复核 §3.2 + 本笔复现）：`touch .git/index.lock` 之后 `git status`
#   仍 **rc=0** —— `git status` 是只读操作，不抢写锁。真实可触发的路径是
#   ① `git` 不在 PATH；② cwd 不在任何 git 仓内（`fatal: not a git repository`，rc=128）。
#   两者都已实测写出 -1。删掉错误举例不是为了好看：留着一个**跑不到的例子**，
#   下一个人会照着它去构造判据，然后发现「构造不出来 ⇒ 这条判据是假的」。
#
# ★ 配套约束（主理人 2026-10-25 裁定，**用 `-1` 的必要条件**）：
#   **任何对 `dirty_count` 的聚合（均值 / 趋势 / 分布 / 排名）必须先过滤 `>= 0`。**
#   否则那个 -1 会被当成真实脏度算进去，把「读不到」稀释成「平均脏度略高」——
#   一个不报错、不出现在任何一行上的静默偏差。看到 `dirty_count < 0` 的行，
#   正确处置是**把它从统计里剔除并单独计数**，不是让它参与计算。
#   ⇒ 与 P4b 的 `cov_flag: "UNKNOWN"` 同一条原则：**「读不到」是一等结论，
#     不许被任何下游当成一个数值用掉。**
DIRTY_COUNT=-1
if DIRTY_STATUS="$(git status --porcelain -uall 2>/dev/null)"; then
  if [ -z "$DIRTY_STATUS" ]; then
    DIRTY_COUNT=0
  else
    DIRTY_COUNT=0
    while IFS= read -r _dirty_line; do
      DIRTY_COUNT=$((DIRTY_COUNT + 1))
    done <<< "$DIRTY_STATUS"
  fi
fi

# ---- P6：判据脚本的内容指纹（T-20261025-11 件3 · 2026-10-31）----
# 【回答什么】`head` + `dirty_count` 仍回答不了「这一轮的判据脚本是哪一份」——
#   同一个路径可以在 20 分钟内被改 4 次（已实证），同一个 head 的两轮可能跑的
#   不是同一份脚本。
# 【为什么在**起跑前**算】要回答「这一轮**实际启动**的是哪一份内容」。跑完再算，
#   若中途有人改了脚本，记下的是**改后**的字节，而执行的是改前 —— 正是本件要防的错。
# 【算法】唯一表达式 `b.replace(b'\r\n', b'\n')`（PRACTICES A3b 第 22 条，逐字照抄）。
#   工作区是 CRLF、索引是 LF ⇒ 归一后两侧同串，跨 checkout 可复核。
#   **不得**用 `tr -d '\r'` 之类「删所有 CR」的等价变体（对含孤立 CR 的文件会分叉）。
# 【读不到写 `null`】不写 `0`：0 是合法摘要值，「没算」与「算出来是零」必须可区分。
#   向后兼容：旧行没有这三个键 ⇒ JSON 消费方读到 `null`/`absent`，不会崩。
# 【覆盖】判据真源 `gate.sh` + 测试执行器 `_run_flutter_test.sh` + **记录器自身**
#   `gate-run.sh`（否则「记录装置自己变了」仍在盲区）。
# 【不影响结论】写失败一律吞掉（与 dirty_count 同），记录装置永不让门禁变红或变绿。
_PY_SHA=""
if command -v python3 >/dev/null 2>&1; then _PY_SHA=python3
elif command -v python >/dev/null 2>&1; then _PY_SHA=python
fi
_sha256_lf_json() {
  if [ -z "$_PY_SHA" ] || [ ! -f "$1" ]; then printf 'null'; return; fi
  _h="$("$_PY_SHA" -c 'import sys,hashlib;b=open(sys.argv[1],"rb").read();print(hashlib.sha256(b.replace(b"\r\n",b"\n")).hexdigest())' "$1" 2>/dev/null)" || _h=""
  if [ -n "$_h" ]; then printf '"%s"' "$_h"; else printf 'null'; fi
}
SCRIPT_SHA_LF_JSON="$(_sha256_lf_json "$ROOT/scripts/_run_flutter_test.sh")"
GATE_SHA_LF_JSON="$(_sha256_lf_json "$ROOT/scripts/gate.sh")"
RUNNER_SHA_LF_JSON="$(_sha256_lf_json "$ROOT/scripts/gate-run.sh")"

"${CMD[@]}"
RC=$?
T1=$(date +%s)
DUR=$((T1 - T0))

HITS_AFTER=$HITS_BEFORE
[ -f "$HITS_LOG" ] && HITS_AFTER=$(wc -l < "$HITS_LOG" 2>/dev/null || echo 0)
HITS_ADDED=$((HITS_AFTER - HITS_BEFORE))

HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

printf '{"ts":"%s","profile":"%s","rc":%d,"dur_s":%d,"head":"%s","hits_added":%d,"dirty_count":%d,"script_sha256_lf":%s,"gate_sha256_lf":%s,"runner_sha256_lf":%s}\n' \
  "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$PROFILE" "$RC" "$DUR" "$HEAD" "$HITS_ADDED" "$DIRTY_COUNT" \
  "$SCRIPT_SHA_LF_JSON" "$GATE_SHA_LF_JSON" "$RUNNER_SHA_LF_JSON" \
  >> "$RUNS_LOG" 2>/dev/null || true

echo "--------------------------------------------------"
if [ "$HITS_ADDED" -gt 0 ]; then
  echo "命中率流水: +${HITS_ADDED} 条 → bash scripts/gate-run.sh hits 查看累计命中率"
else
  echo "⚠️  命中率流水本次 0 条新增 —— 记录装置可能没生效，别当成「全部通过」"
fi
echo "本次: profile=${PROFILE} / rc=${RC} / ${DUR}s"
exit "$RC"
