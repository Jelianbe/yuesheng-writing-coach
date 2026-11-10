#!/usr/bin/env bash
# 序 3 · 第二次 web 构建（`flutter build web --wasm`）读数采集脚本
# 用法：bash tools/run_web_build_once.sh
#
# 纪律（来自本轮踩坑与 §4-459 硬约束）：
#  1. **rc 必须真取**：`flutter build ... > log 2>&1; rc=$?` —— 绝不 `cmd | tee log; echo $?`
#     （管道 $? 是 tee 的 rc，不是 flutter 的。本轮已踩坑三次：tail rc 冒充 / cwd 重置致 rc=2 假读数）
#  2. **cwd 显式指定**：sandbox cwd 会在调用间重置回 D:/ai-teacher
#  3. **命令逐字**：`flutter build web --wasm`（§4-457 授权形态）。**不加 --csp**（待裁点，主理人另行决定）
#  4. **构建次数**：这是累计第 2 次、**再无第三次**。rc=1 ⇒ 落唯一错误清单即止，不重试（§4-459 裁 3 + 附加门 ⑶）
#  5. 产物落 `outputs/web-build/`（不与 `outputs/gate/` 混）

set -u
ROOT="/d/ai-teacher/yuesheng-flutter"
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
echo "HEAD       : $(git rev-parse --short HEAD)"
echo "log        : $LOG"

# ── 构建前旁证快照（零构建口径留痕）──────────────────────────
{
  echo "ts_start=$(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "command=flutter build web --wasm"
  echo "head=$(git rev-parse HEAD)"
  echo "dirty_count=$(git status --porcelain -- yuesheng-flutter/ | wc -l)"
  echo "web_dir_exists=$([ -d "$ROOT/web" ] && echo yes || echo no)"
  echo "outputs_web_products_before=$(find "$ROOT/outputs" -iname '*web*' 2>/dev/null | grep -vc web-build || echo 0)"
} > "$META"

# ── 真跑构建（rc 真实取，不经管道）────────────────────────────
flutter build web --wasm > "$LOG" 2>&1
RC=$?

# ── 构建后旁证（rc 真实取）──────────────────────────────────
{
  echo "ts_end=$(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "rc=$RC"
  echo "log_bytes=$(wc -c < "$LOG")"
  echo "log_lines=$(wc -l < "$LOG")"
  echo "build_web_dir=$([ -d "$ROOT/build/web" ] && echo yes || echo no)"
  echo "outputs_web_products_after=$(find "$ROOT/outputs" -iname '*web*' 2>/dev/null | grep -vc web-build || echo 0)"
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
    echo "# 时刻: $(date '+%Y-%m-%d %H:%M:%S %z')   HEAD: $(git rev-parse --short HEAD)"
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
