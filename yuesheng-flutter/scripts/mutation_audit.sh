#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# mutation_audit.sh — 按需变异审计（**刻意不做成门禁**）
#
# 【为什么不做成门禁】量化依据（2026-09-17 实测，详 .ai/CHECKS.md §9.7）：
#   · 三模块合计 **309 变异点**（character_identity 10 / focus_resolver 117 /
#     training_evaluator 182）—— 远超「单模块试点」时的想象
#   · mutation_test 1.8.1 **无并行选项**（--help 全 14 项里只有 -c 覆盖率加速）
#   · 存在**等价变异体**（character_identity 实测 1/10 杀不死，如并查集 union
#     参数互换）⇒「检不出」不等于「测试差」，做成卡阈值的门禁会产生**恒定假红灯**
#
# 【它该什么时候跑】三种触发（收尾节奏的一部分，非每次提交）：
#   ① 改动了 mutation-test.xml 列出的护栏模块 ⇒ 默认模式自动只审计该模块
#   ② 新写了一批测试 ⇒ 用 --module 验证「测试是否真有牙齿」
#   ③ 怀疑某模块测试变空壳 ⇒ 同上
#
# 【★★★ 必读风险：mutation_test 会**就地改写源文件】★★★（2026-09-17 实测取证）
#   它按变异点逐个「写入源文件 → 跑测试 → 还原」，**不创建副本**（报告目录里
#   只有 HTML，没有源码快照）。由此带来两个必须防的坑：
#     · 运行期间**源码处于变异态** ⇒ 此刻读源文件/跑其他测试都会得到假象。
#       实测踩坑：审计中读 focus_resolver.dart 看到 `if (!(problems.isEmpty))`，
#       差点据此断言「fallback 表永不可达」——那其实是当前生效的变异体。
#       ⇒ **审计期间禁止读源码下结论、禁止跑其他门禁**。
#     · 进程被中断（Ctrl-C / 超时 / 崩溃）时，**当前变异体不会还原** ⇒
#       残留会混进提交。本脚本因此加了跑前/跑后双向校验（见下方断言）。
#
# 【report 目录的坑】HTML 是在 run **开始时**初始化为「Detected: 0 / 全部未检出」
#   的快照，run 结束后才写最终结果。⇒ 运行中途读报告会看到「全部未检出」的假象。
#
# 用法：
#   bash scripts/mutation_audit.sh                 # 自动：只审计 git diff 触及的模块
#   bash scripts/mutation_audit.sh --module focus_resolver
#   bash scripts/mutation_audit.sh --all           # 全量三模块（耗时最长）
#   bash scripts/mutation_audit.sh --list          # 只看模块清单与映射
#   bash scripts/mutation_audit.sh --all --dry-run # 只数变异点、不跑测试（估规模用，亚秒级）
# ─────────────────────────────────────────────────────────────
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP_XML="mutation-test.audit.tmp.xml"

# 模块 → 源文件 / 测试文件 映射。
# ★ 新增模块时**必须同时**更新这里与 mutation-test.xml（两处不一致会导致审计漏跑）
declare -A SRC=(
  [character_identity]="lib/services/character_identity.dart"
  [focus_resolver]="lib/services/focus_resolver.dart"
  [training_evaluator]="lib/services/training_evaluator.dart"
)
declare -A TST=(
  [character_identity]="test/services/character_identity_test.dart"
  [focus_resolver]="test/services/focus_resolver_coverage_test.dart test/services/focus_resolver_discrimination_test.dart"
  [training_evaluator]="test/services/training_evaluator_test.dart"
)
ALL_MODULES=(character_identity focus_resolver training_evaluator)

print_list() {
  echo "模块清单（mutation_audit.sh 与 mutation-test.xml 必须一致）："
  for m in "${ALL_MODULES[@]}"; do
    printf '  %-22s %s\n' "$m" "${SRC[$m]}"
    printf '  %-22s   ↳ %s\n' '' "${TST[$m]}"
  done
}

# ── 参数解析 ──
MODE="auto"
TARGET=""
DRY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list) print_list; exit 0 ;;
    --all)  MODE="all" ;;
    --module) MODE="one"; TARGET="${2:-}"; shift ;;
    --dry-run) DRY="-d" ;;   # 传给 mutation_test：只数变异点，不跑测试
    -h|--help) sed -n '1,30p' "$0"; exit 0 ;;
    *) echo "未知参数：$1（用 --help 看用法）"; exit 2 ;;
  esac
  shift
done

# ── 决定要审计的模块 ──
SELECTED=()
case "$MODE" in
  all)
    SELECTED=("${ALL_MODULES[@]}")
    ;;
  one)
    if [ -z "${SRC[$TARGET]:-}" ]; then
      echo "[FAIL] 未知模块 '$TARGET'。可用："
      print_list
      exit 2
    fi
    SELECTED=("$TARGET")
    ;;
  auto)
    # 只取**本次改动**触及的护栏模块（工作区 vs HEAD，含已暂存）
    CHANGED="$(git diff --name-only HEAD 2>/dev/null || true)"
    if [ -z "$CHANGED" ]; then
      echo "[SKIP] 工作区无改动 ⇒ 无需变异审计"
      exit 0
    fi
    for m in "${ALL_MODULES[@]}"; do
      if printf '%s\n' "$CHANGED" | grep -qxF "${SRC[$m]}"; then
        SELECTED+=("$m")
      fi
    done
    if [ ${#SELECTED[@]} -eq 0 ]; then
      echo "[SKIP] 本次改动未触及护栏模块 ⇒ 无需变异审计"
      echo "       （改动文件：$(printf '%s\n' "$CHANGED" | wc -l) 个，均不在 mutation-test.xml 清单内）"
      exit 0
    fi
    echo "[INFO] 本次改动触及：${SELECTED[*]}"
    ;;
esac

# ── 跑前断言：目标模块必须干净（否则无法区分「残留变异」与「你的正常改动」）──
DIRTY=()
for m in "${SELECTED[@]}"; do
  if ! git diff --quiet -- "${SRC[$m]}"; then DIRTY+=("${SRC[$m]}"); fi
done
if [ ${#DIRTY[@]} -gt 0 ]; then
  echo "[ABORT] 以下**待审计模块**有未提交改动："
  printf '          %s\n' "${DIRTY[@]}"
  echo "        mutation_test 就地改写源文件、跑完还原；基线不干净时无法判别"
  echo "        「运行残留」与「你的改动」。请先提交或 stash 后再跑。"
  exit 3
fi

# ── 生成临时 XML（只含选中模块 + 对应测试命令）──
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<!-- 由 scripts/mutation_audit.sh 生成，跑完即删 -->'
  echo '<mutations version="1.2">'
  echo '  <files>'
  for m in "${SELECTED[@]}"; do
    echo "    <file>${SRC[$m]}</file>"
  done
  echo '  </files>'
  echo '  <commands>'
  CMDS=""
  for m in "${SELECTED[@]}"; do
    CMDS="$CMDS ${TST[$m]}"
  done
  echo "    <command group=\"test\" expected-return=\"0\" working-directory=\".\" timeout=\"1800\">flutter test$CMDS</command>"
  echo '  </commands>'
  echo '</mutations>'
} > "$TMP_XML"

cleanup() { rm -f "$TMP_XML"; }
trap cleanup EXIT

echo "--> 变异审计：${SELECTED[*]}"
echo "    （临时配置 $TMP_XML，退出时自动删除）"
if [ -n "$DRY" ]; then
  echo "    （--dry-run：只数变异点，不跑测试）"
fi
echo

# shellcheck disable=SC2086  # $DRY 为空时必须不传参，故刻意不加引号
dart run mutation_test $DRY "$TMP_XML"
RC=$?

echo
# ── 跑后断言：源码必须已还原（就地改写 ⇒ 中断会留残留）──
RESIDUE=()
for m in "${SELECTED[@]}"; do
  if ! git diff --quiet -- "${SRC[$m]}"; then RESIDUE+=("${SRC[$m]}"); fi
done
if [ ${#RESIDUE[@]} -gt 0 ]; then
  echo "  ╔════════════════════════════════════════════════════════════════════╗"
  echo "  ║  [★ 危险] 变异残留：以下文件跑完后与 HEAD 不一致                    ║"
  echo "  ╚════════════════════════════════════════════════════════════════════╝"
  printf '      %s\n' "${RESIDUE[@]}"
  echo "  mutation_test 就地改写源文件；进程若被中断，当前变异体不会还原。"
  echo "  **切勿提交**。先核对 diff 确认是变异体（而非你的正常改动），然后执行："
  printf '      git checkout -- %s\n' "${RESIDUE[@]}"
  exit 4
fi
echo "[OK] 源码完整性：${#SELECTED[@]} 个待审计模块均已还原（与 HEAD 一致）"

# ★ --dry-run 的退出码**不是失败信号**（2026-09-17 实测 rc=127）：
#   没跑测试 ⇒ 全部变异点必然报「未检出」、rating F、非零退出码，属预期行为。
if [ -n "$DRY" ]; then
  echo "[OK] --dry-run 完成：已统计变异点（**未执行测试**，故不判定检出率）。"
  exit 0
fi
if [ $RC -eq 0 ]; then
  echo "[注意] 退出码 0 **不代表变异全部被检测**。判定一律看上面的 Undetected"
  echo "       计数与 Quality rating，并**逐条区分「真盲区」与「等价变异体」**"
  echo "       （等价变异体杀不死，不是缺陷）。"
else
  echo "[注意] mutation_test 退出码 $RC —— **这不是「审计失败」**。"
  echo "       2026-09-17 实测：工具在**存在未检出变异**时即返回非 0"
  echo "       （79/309 未检出 ⇒ rc=127），与 dry-run 同码。"
  echo "       判定一律看上面的 Undetected 计数与 Quality rating。"
fi
echo "       报告目录：mutation-test-report/（已 gitignore）"
echo "       未检出清单（结构化提取：行号 / 变异类型 / 真实改动点）："
echo "         python .ai/tools/_parse_mutation_report.py \\"
echo "             mutation-test-report/lib/services/<模块>.dart.html --stats"
exit $RC
