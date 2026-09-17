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
  [focus_resolver]="test/services/focus_resolver_coverage_test.dart"
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
if [ $RC -eq 0 ]; then
  echo "[注意] 退出码 0 **不代表变异全部被检测** —— mutation_test 在「有未检出变异」时"
  echo "       也可能返回 0。判定必须看报告里的 Quality rating 与 Undetected 计数，"
  echo "       并**逐条区分「真盲区」与「等价变异体」**（等价变异体杀不死，不是缺陷）。"
  echo "       报告目录：mutation-test-report/（已 gitignore）"
else
  echo "[FAIL] mutation_test 退出码 $RC"
fi
exit $RC
