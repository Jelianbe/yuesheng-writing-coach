#!/usr/bin/env bash
# 序 3 · 第二次 web 构建（`flutter build web --wasm`）读数采集脚本
# 用法：bash scripts/run_web_build_once.sh
#
# 纪律（来自本轮踩坑与 §4-459 硬约束）：
#  1. **rc 必须真取**：`flutter build ... > log 2>&1; rc=$?` —— 绝不 `cmd | tee log; echo $?`
#     （管道 $? 是 tee 的 rc，不是 flutter 的。本轮已踩坑三次：tail rc 冒充 / cwd 重置致 rc=2 假读数）
#  2. **cwd 显式指定**：sandbox cwd 会在调用间重置回 D:/ai-teacher
#  3. **命令逐字**：`flutter build web --wasm`（§4-457 授权形态）。**不加 --csp**
#     （2026-11-10 13:2x 舰长已裁「不带」—— 带 --csp 属命令形态变更，且会让序 4
#      「A 点终值 CSP 策略串」在更受限的产物上实测；若序 4 判定需要 ⇒ 走**新的一次
#      构建授权**，不在序 3 额度内）
#  4. **构建次数**：这是累计第 2 次、**再无第三次**。rc=1 ⇒ 落唯一错误清单即止，不重试（§4-459 裁 3 + 附加门 ⑶）
#  5. 产物落 `outputs/web-build/`（不与 `outputs/gate/` 混）
#  6. **pathspec 必须相对仓根**：git 仓根 = D:/ai-teacher（`yuesheng-flutter/` 是其内目录）。
#     在 $ROOT 内跑 `git status -- yuesheng-flutter/` 会因路径不存在而**静默返回空** ⇒ dirty_count 恒 0
#     ⇒ 「干净树读数」判据失效（`.ai/PRACTICES.md §B10` 已登记此坑）。故本脚本改用 `git -C <仓根>`。

set -u
REPO="/d/ai-teacher"          # git 仓根（`yuesheng-flutter/` 是其内目录）
ROOT="$REPO/yuesheng-flutter" # Flutter 工程根
OUT="$ROOT/outputs/web-build"
mkdir -p "$OUT"
cd "$ROOT" || exit 9

STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$OUT/build-$STAMP.log"
META="$OUT/build-$STAMP.meta"

echo "=== 序 3 · 第二次 web 构建 ==="
echo "时刻(起)   : $(date '+%Y-%m-%d %H:%M:%S %z')"
echo "命令       : flutter build web --wasm"
echo "cwd        : $(pwd)"
echo "repo_root  : $REPO"
echo "HEAD       : $(git -C "$REPO" rev-parse --short HEAD)"
echo "log        : $LOG"

# ── 构建前预检（预检不过 ⇒ 不消耗构建额度）────────────────────
# ⚠ 本脚本是**唯一一次**额度消耗器（累计第 2 次、再无第三次）⇒ 预检必须拦掉
#   「注定白耗」的情形：flutter 不可用 / 工作树不净 / web/ 脚手架缺失。
PRECHECK_FAIL=0

if ! command -v flutter > /dev/null 2>&1; then
  echo "[PRECHECK FAIL] flutter 不在 PATH ⇒ 预检拦下，不消耗构建额度"
  PRECHECK_FAIL=1
fi

DIRTY=$(git -C "$REPO" status --porcelain -- yuesheng-flutter/ | wc -l | tr -d ' ')
if [ "$DIRTY" != "0" ]; then
  echo "[PRECHECK FAIL] 主仓工作树不净（dirty_count=$DIRTY）⇒ 读数不可归因（§七第9条），预检拦下"
  git -C "$REPO" status --porcelain -- yuesheng-flutter/
  PRECHECK_FAIL=1
fi

if [ ! -d "$ROOT/web" ]; then
  echo "[PRECHECK FAIL] web/ 脚手架不存在 ⇒ flutter build web 必然失败，预检拦下"
  PRECHECK_FAIL=1
fi

if [ "$PRECHECK_FAIL" != "0" ]; then
  echo "ts_end=$(date '+%Y-%m-%d %H:%M:%S %z')" > "$META"
  echo "rc=PRECHECK_FAIL" >> "$META"
  echo "dirty_count=$DIRTY" >> "$META"
  exit 8
fi

echo "预检        : PASS（flutter 可用 / dirty_count=0 / web/ 存在）"

# ── 构建前旁证快照（零构建口径留痕）──────────────────────────
# ⚠ `dirty_count` 必须用 `git -C <仓根> -- yuesheng-flutter/`：
#   在 $ROOT 内写 `-- yuesheng-flutter/` ⇒ 路径不存在 ⇒ git **静默返回空** ⇒ 恒 0（假绿）。
# ⚠ `find | grep -vc`：零命中时 grep rc=1 ⇒ 不能直接用 `|| echo 0` 兜（会串成两行输出）。
#   改用 `grep -vc ... || true` 后仍需过滤空行，故这里改用 `find ... -print | wc -l` 的显式计数。
web_products_before=$(find "$ROOT/outputs" -iname '*web*' -not -path "$OUT/*" 2>/dev/null | wc -l | tr -d ' ')
{
  echo "ts_start=$(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "command=flutter build web --wasm"
  echo "head=$(git -C "$REPO" rev-parse HEAD)"
  echo "dirty_count=$(git -C "$REPO" status --porcelain -- yuesheng-flutter/ | wc -l | tr -d ' ')"
  echo "web_dir_exists=$([ -d "$ROOT/web" ] && echo yes || echo no)"
  echo "outputs_web_products_before=$web_products_before"
  echo "build_dir_exists=$([ -d "$ROOT/build/web" ] && echo yes || echo no)"
} > "$META"

# ── 真跑构建（rc 真实取，不经管道）────────────────────────────
flutter build web --wasm > "$LOG" 2>&1
RC=$?

# ── 构建后旁证（rc 真实取）──────────────────────────────────
web_products_after=$(find "$ROOT/outputs" -iname '*web*' -not -path "$OUT/*" 2>/dev/null | wc -l | tr -d ' ')
{
  echo "ts_end=$(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "rc=$RC"
  echo "log_bytes=$(wc -c < "$LOG")"
  echo "log_lines=$(wc -l < "$LOG")"
  echo "build_web_dir=$([ -d "$ROOT/build/web" ] && echo yes || echo no)"
  echo "outputs_web_products_after=$web_products_after"
  echo "dirty_count_after=$(git -C "$REPO" status --porcelain -- yuesheng-flutter/ | wc -l | tr -d ' ')"
} >> "$META"

echo "rc         : $RC"
echo "时刻(毕)   : $(date '+%Y-%m-%d %H:%M:%S %z')"
echo "log        : $LOG"
echo "meta       : $META"

# ── 读数抽取：唯一错误清单（rc=1 时落盘即止）──────────────────
if [ "$RC" -ne 0 ]; then
  LIST="$OUT/error-list-$STAMP.txt"
  {
    echo "# 序 3 第二次构建唯一错误清单（rc=$RC）"
    echo "# 时刻: $(date '+%Y-%m-%d %H:%M:%S %z')   HEAD: $(git -C "$REPO" rev-parse --short HEAD)"
    echo "# 逐条归属（哪个包/哪个文件）—— 本清单直接成为 23-04 U8 / 存储层后续批输入（§4-459 裁 3）"
    echo
    echo "## 按错误类型计数"
    grep -oE "dart:(ffi|html|js|js_util)|Error:|error:" "$LOG" 2>/dev/null | sort | uniq -c | sort -rn
    echo
    echo "## 原始错误行（去重）"
    grep -E "^(Error|.*\.dart:[0-9]+:[0-9]+|.*Error:)" "$LOG" 2>/dev/null | sed 's/[[:space:]]*$//' | sort -u | head -200
    echo
    echo "## 涉及的包/文件"
    grep -oE "[a-z_0-9-]+\.dart|[a-z_0-9-]+-[0-9]+\.[0-9]+\.[0-9]+" "$LOG" 2>/dev/null | sort | uniq -c | sort -rn | head -40
  } > "$LIST"
  echo "错误清单    : $LIST"
  echo "★ rc≠0 ⇒ 按附加门 ⑶ 即止，不重试（没有第三次）"
fi

exit "$RC"
