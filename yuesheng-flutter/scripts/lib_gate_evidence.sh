#!/usr/bin/env bash
# ============================================================
# scripts/lib_gate_evidence.sh — 门禁证据链判据（纯函数层）
#
# 【这是谁的卡】T-20261025-04（证据链完整性：门禁 2/6 的 PASS 不可证伪）
#
# 【为什么单独成库，而不是直接写进 gate.sh】
#   判据必须**可被自测直接调用**。若逻辑写在 gate.sh 里，自测只能
#   `sed` 抽取函数体或另写一份 —— 前者脆、后者等于测另一份实现（假绿）。
#   ⇒ 单一定义、两处调用：`gate.sh` 用它的判定，`_selftest_gate_evidence.py`
#     用同一份定义跑正/负探针。**测的就是上线的那份逻辑。**
#
# 【本文件不许有副作用】
#   除 `ev_p2_count` 的显式建基线分支（仅当 `UPDATE_TEST_BASELINE=1` 或基线不存在）
#   之外，任何函数都**不写盘**。被 gate.sh `source` 时不得打印任何东西。
#
# 【返回值契约】每个判据函数：
#   stdout = 一行人类可读结论（gate.sh 原样转述，供单点归因）
#   return 0 = 非 FAIL（PASS / WARN / 不判）
#   return 1 = FAIL
#   ⇒ 必须区分「这条判据红了」与「这条判据没有输入」：后者**不得**返回 1，
#     否则「破坏 P1」会连带把 P2 也判红，单点归因失效（T-20261025-04 §四之二 的验收判据）。
# ============================================================

# P1/P2 的汇总行正则（flutter test 末尾：`05:04 +5295 ~3: All tests passed!`）
#   ⚠️ `~N` 段必须可选：跳过用例的轮次会带它，漏了就是**每天假红**。
#   ⚠️ 匹配用「任意行」而非「末行」：bash 的 fd 写失败诊断会落在汇总行**之后**
#      （`<脚本>: line N: <命令>: write error: ...`）⇒ 末行口径在**真出故障那一轮**假红，
#      正好与 P3 要抓的场景冲突。实测见 T-20261025-04 校准记录（H 段）。
EV_RE_P1='^[0-9]{2}:[0-9]{2} \+[0-9]+( ~[0-9]+)?: All tests passed!$'

# P3 的日志可信性正则。**必须带 bash 诊断锚**：
#   bash 的写失败格式固定为 `<脚本>: line N: <命令>: <errno 文案>`，
#   业务文案打印不出 `line N: …: write error` 这一形态。
#   ⇒ 裸词面会把测试自己断言的错误文案误判成「日志写坏了」（实测：假阳性样本 1 命中，锚定后 0）。
EV_RE_P3='^(scripts/_run_flutter_test\.sh|bash): line [0-9]+: .*: (write error|Broken pipe|Permission denied|No space left on device)'

# ---------- 内部工具 ----------

# 取汇总行（可能为空）。`-a`：14 MB 日志含控制字符时 grep 可能判二进制而只回一句
# "Binary file matches"，那样 `-c` 计数会变成 1 但内容取不到。
_ev_summary_line() {
  local f="${1:-}"
  [ -f "$f" ] || return 0
  grep -aE "$EV_RE_P1" "$f" 2>/dev/null | tail -n 1
}

# 从汇总行取 +N / ~N（取不到 ⇒ 空串，**不要**猜 0）
_ev_field() { # $1=行 $2=passed|skipped
  local line="${1:-}"
  case "$2" in
    passed)  printf '%s' "$line" | sed -nE 's/^[0-9]{2}:[0-9]{2} \+([0-9]+)( ~[0-9]+)?: All tests passed!$/\1/p' ;;
    skipped) printf '%s' "$line" | sed -nE 's/^[0-9]{2}:[0-9]{2} \+[0-9]+ ~([0-9]+): All tests passed!$/\1/p' ;;
  esac
}

# 基线 provenance 是否齐全（四键缺一 ⇒ 视为**无效基线**，不许静默采用）
_ev_base_provenance_ok() {
  local f="${1:-}" k
  [ -f "$f" ] || return 1
  for k in count head generated_at reason; do
    grep -q "\"$k\"" "$f" 2>/dev/null || return 1
  done
  return 0
}

_ev_base_count() { # 取不到 ⇒ 空串
  local f="${1:-}"
  [ -f "$f" ] || return 0
  sed -nE 's/.*"count"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$f" 2>/dev/null | head -n 1
}

# 写基线（**唯一**写盘入口）。只允许两处调用：基线不存在时的首建、或 UPDATE_TEST_BASELINE=1。
_ev_write_baseline() { # $1=path $2=count $3=reason
  local path="$1" count="$2" reason="$3" head
  head="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  printf '{"count": %s, "head": "%s", "generated_at": "%s", "reason": "%s"}\n' \
    "$count" "$head" "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$reason" > "$path" 2>/dev/null
}

# ---------- P1 汇总行 ----------
# 判据：test.txt 里存在 `^\d\d:\d\d \+\d+( ~\d+)?: All tests passed!$` 的行；缺失 ⇒ FAIL。
ev_p1_summary() { # $1=test_log
  local f="${1:-}" line
  if [ ! -f "$f" ]; then
    echo "P1 汇总行：日志文件不存在（$f）⇒ 无证据"
    return 1
  fi
  line="$(_ev_summary_line "$f")"
  if [ -z "$line" ]; then
    echo "P1 汇总行：未找到 All tests passed! 汇总行 ⇒ PASS 无例数证据"
    return 1
  fi
  echo "P1 汇总行：命中「$line」"
  return 0
}

# ---------- P2 例数下限 ----------
# 判据（§4-295① 裁定）：N **低于**基线 ⇒ FAIL；**高于** ⇒ WARN（该刷基线了）；相等 ⇒ PASS。
# 取不到 N ⇒ **不判**（返回 0，归因 P1）：否则「破坏 P1」会连带 P2 变红，单点归因失效。
ev_p2_count() { # $1=test_log $2=baseline_json
  local f="${1:-}" base_json="${2:-}" line n base reason
  line="$(_ev_summary_line "$f")"
  n="$(_ev_field "$line" passed)"
  if [ -z "$n" ]; then
    echo "P2 例数下限：无法从日志解析 +N ⇒ 本条不判（归因 P1）"
    return 0
  fi

  reason="flutter test 全绿轮次的 +N（基线只卡下降，不卡等号）"

  if [ ! -f "$base_json" ]; then
    _ev_write_baseline "$base_json" "$n" "$reason"
    echo "P2 例数下限：基线不存在 ⇒ 已首建（count=$n，含 provenance 四字段），本轮不判定（WARN）"
    return 0
  fi

  if ! _ev_base_provenance_ok "$base_json"; then
    echo "P2 例数下限：基线 provenance 不齐（需 count/head/generated_at/reason 四键）⇒ 判为无效基线，不采用（WARN）"
    return 0
  fi

  base="$(_ev_base_count "$base_json")"
  if [ -z "$base" ]; then
    echo "P2 例数下限：基线里解析不出 count ⇒ 判为无效基线，不采用（WARN）"
    return 0
  fi

  if [ "${UPDATE_TEST_BASELINE:-0}" = "1" ]; then
    _ev_write_baseline "$base_json" "$n" "$reason"
    echo "P2 例数下限：UPDATE_TEST_BASELINE=1 ⇒ 基线已刷新 $base → $n（显式入口）"
    return 0
  fi

  if [ "$n" -lt "$base" ]; then
    echo "P2 例数下限：+N=$n < 基线 $base ⇒ 例数下降（Δ=$((n - base))）"
    return 1
  fi
  if [ "$n" -gt "$base" ]; then
    echo "P2 例数下限：+N=$n > 基线 $base（Δ=+$((n - base))）⇒ 用例增长，提示刷新基线（WARN）"
    return 0
  fi
  echo "P2 例数下限：+N=$n = 基线 $base"
  return 0
}

# ---------- P3 日志可信性 ----------
ev_p3_log_integrity() { # $1=test_log
  local f="${1:-}" hits first
  if [ ! -f "$f" ]; then
    echo "P3 日志可信性：日志文件不存在（$f）⇒ 结论不可信"
    return 1
  fi
  hits="$(grep -acE "$EV_RE_P3" "$f" 2>/dev/null)"
  [ -n "$hits" ] || hits=0
  if [ "$hits" -gt 0 ]; then
    first="$(grep -aE "$EV_RE_P3" "$f" 2>/dev/null | head -n 1 | cut -c1-160)"
    echo "P3 日志可信性：命中 $hits 条写失败诊断（首条：$first）⇒ 日志写不全，结论不可信"
    return 1
  fi
  echo "P3 日志可信性：0 命中（锚定形态）"
  return 0
}

# ---------- P4a 覆盖率新鲜度 ----------
# 判据：mtime(lcov) **>=** run_start（秒级）。
#   ⚠️ 必须 `>=` 而非 `>`：`stat -c %Y` 与 run_start 同为秒级，
#      同一秒内起跑并写完 lcov 时二者相等 ⇒ 用 `>` 会**间歇假红**（§4-295④）。
#   ⚠️ 必须先判 `-f`：文件不存在时 `stat` 会往 stderr 喷错，那会被误读成环境故障。
ev_p4a_fresh() { # $1=lcov $2=run_start_ts
  local lcov="${1:-}" start="${2:-}" mtime
  if [ ! -f "$lcov" ]; then
    echo "P4a 覆盖率新鲜度：lcov 不存在（$lcov）⇒ 无新鲜度可验"
    return 1
  fi
  if ! mtime="$(stat -c %Y "$lcov" 2>/dev/null)"; then
    echo "P4a 覆盖率新鲜度：本环境不支持 stat -c %Y ⇒ 无法验证（fail-closed）"
    return 1
  fi
  if [ -z "$mtime" ]; then
    echo "P4a 覆盖率新鲜度：mtime 读不出 ⇒ 无法验证（fail-closed）"
    return 1
  fi
  if [ "$mtime" -ge "$start" ]; then
    echo "P4a 覆盖率新鲜度：mtime=$mtime >= run_start=$start（差 $((mtime - start))s）"
    return 0
  fi
  echo "P4a 覆盖率新鲜度：mtime=$mtime < run_start=$start（陈旧 $((start - mtime))s）⇒ 消费了上一轮的 lcov"
  return 1
}

# ---------- P4b 实际 COV_FLAG ----------
# 「文件存在且为空」与「文件不存在」**必须可区分**：
#   空串 = wrapper 确实跑了、且明确未开覆盖率；
#   UNKNOWN = 不知道 wrapper 跑没跑 / 哪一版 wrapper。
# 压成同一态 = 又造一个不可证伪的 PASS（T-20261025-04 §四-P4b 要求 1）。
ev_p4b_cov_flag() { # $1=cov_flag_file ; stdout=值或 UNKNOWN ; return 0=文件在, 2=缺失
  local f="${1:-}" v
  if [ ! -f "$f" ]; then
    printf 'UNKNOWN'
    return 2
  fi
  v="$(head -n 1 "$f" 2>/dev/null)"
  printf '%s' "$v"
  return 0
}

# ---------- P5 工作树脏度 ----------
ev_p5_dirty_count() {
  git status --porcelain -uall 2>/dev/null | wc -l | tr -d '[:space:]'
}
