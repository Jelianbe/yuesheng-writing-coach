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

# 单次扫描：一遍 awk 同时产出 P1/P2 要的汇总行、P3 要的命中数 + 首条。
#
# 【为什么必须共用一次】不只是省时间。同一份输入被解析两次就**有两次解释机会**，
#   两处口径早晚漂移 —— 那时会出现「P1 判绿、P2 却说解析不出 +N」这种自相矛盾的读数，
#   比单条判据写错更难查（因为两条看起来各自都对）。⇒ 解析只发生在这一处；
#   三条判据只消费事实，不碰文件。
#
# 【正则怎么传】必须走 ENVIRON。实测：awk 对 `-v` 与命令行 `var=value` 都会**解释
#   反斜杠转义**（`\+` 被降级成 `+` 并打 `warning: escape sequence \`\+' treated as plain \`+'`）
#   ⇒ 正则在传递途中被悄悄改写，而改写后的正则**仍然看起来能跑**。
#   ENVIRON 原样透传：实测 `\+`、`\.` 均逐字节保留。
#
# 【二进制安全】原来用 `grep -a` 是因为日志含控制字符时 grep 会判二进制、只回一句
#   "Binary file matches"（此时 `-c` 也变成 1，内容取不到）。awk 没有这层探测，按字节读。
#   实测：14 MB 真日志、掺 NUL 的样本，两者都正常出结果（第 2 笔报告里有读数）。
#
# 【缓存语义】按路径缓存，同一文件第二次调用不再扫。
#   ⚠️ 缓存是**shell 变量**，所以必须在**同一个 shell** 里连续调用才能命中。
#   `msg="$(ev_p1_summary f)"` 这种写法每条各起一个子 shell ⇒ 缓存全废、日志被扫 3 遍
#   （实测 1632 ms vs 单遍 290 ms）。⇒ gate.sh **只调 ev_check_p123 这一个入口**，
#   由它在同一个 shell 里串起三条判据。这是「共用一次解析」的落地形态，
#   不是靠调用方自觉 —— 调用方自觉的东西早晚会被下一个人写回三遍。
#   自测每条探针是独立 bash 进程 ⇒ 缓存冷启，测到的仍是真实解析路径。
#
# 【首条诊断为什么不在 awk 里截断】`substr` 在 UTF-8 locale 下按字符、在 C locale 下按
#   字节，同一个表达式两种语义。截断交给 bash 的 `cut -c1-160`（跟随 locale）更稳。
_ev_facts() { # $1=log ; 副作用：设 EV_F_SRC / EV_F_SUMMARY / EV_F_P3_HITS / EV_F_P3_FIRST / EV_F_N1
  local f="${1:-}" out
  if [ "${EV_F_SRC:-}" = "$f" ] && [ "${EV_F_READY:-0}" = "1" ]; then
    return 0
  fi
  EV_F_SRC="$f"; EV_F_READY=1
  EV_F_SUMMARY=""; EV_F_P3_HITS=0; EV_F_P3_FIRST=""; EV_F_N1=""
  [ -f "$f" ] || return 0
  out="$(EV_RE1="$EV_RE_P1" EV_RE3="$EV_RE_P3" awk '
    BEGIN { re1 = ENVIRON["EV_RE1"]; re3 = ENVIRON["EV_RE3"]; hits = 0; n1 = 0 }
    $0 ~ re1 { summary = $0; n1++ }
    $0 ~ re3 { hits++; if (hits == 1) first = $0 }
    END { printf "%d\n%s\n%s\n%d\n", hits, summary, first, n1 }
  ' "$f" 2>/dev/null)"
  EV_F_P3_HITS=""; EV_F_SUMMARY=""; EV_F_P3_FIRST=""
  # 用内建 `read` 拆四行，不用 `printf | sed`：本机（MSYS/Git Bash）每 fork 一次约 60-100 ms，
  # 三次 sed 就是三次 fork。实测这一处占掉约 200 ms（第 2 笔报告里有前后读数）。
  { IFS= read -r EV_F_P3_HITS; IFS= read -r EV_F_SUMMARY; IFS= read -r EV_F_P3_FIRST; IFS= read -r EV_F_N1; } <<< "$out"
  [ -n "$EV_F_P3_HITS" ] || EV_F_P3_HITS=0
  [ -n "$EV_F_N1" ] || EV_F_N1=0
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
# 用内建读 + case 匹配，不用 4 次 `grep -q`：本机每 fork 约 75-90 ms，文件只有 130 B
# 也一样要付。实测 4 次 grep = 120-133 ms → 内建读 43-49 ms。
_ev_base_provenance_ok() {
  local f="${1:-}" k body
  [ -f "$f" ] || return 1
  body="$(< "$f")" 2>/dev/null || return 1
  for k in count head generated_at reason; do
    case "$body" in
      *"\"$k\""*) ;;
      *) return 1 ;;
    esac
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
    echo "[FAIL] P1 汇总行：日志文件不存在（$f）⇒ 无证据"
    return 1
  fi
  # 不用 `line="$(...)"`：那会起子 shell，把 _ev_facts 的缓存丢掉 ⇒ 同一份日志被重复扫。
  _ev_facts "$f"; line="$EV_F_SUMMARY"
  if [ -z "$line" ]; then
    echo "[FAIL] P1 汇总行：未找到 All tests passed! 汇总行 ⇒ PASS 无例数证据"
    return 1
  fi
  # ★ 唯一性：混写日志（并发两轮写同一份 test.txt）里，summary 取的是**最后一条**。
  #   只看「找到了一条」等于放弃判断「这条属于哪一轮」—— 实测代价是 P2 拿窄道的
  #   `+34` 去比全量基线，报出「例数下降 5261」，理由看起来完全正当。
  if [ "${EV_F_N1:-0}" -gt 1 ]; then
    echo "[FAIL] P1 汇总行：命中 $EV_F_N1 条汇总行（日志混写/并发）⇒ 无法确认本条结论对应哪一轮"
    return 1
  fi
  echo "[PASS] P1 汇总行：命中「$line」"
  return 0
}

# ---------- P2 例数下限 ----------
# 判据（§4-295① 裁定）：N **低于**基线 ⇒ FAIL；**高于** ⇒ WARN（该刷基线了）；相等 ⇒ PASS。
# 取不到 N ⇒ **不判**（返回 0，归因 P1）：否则「破坏 P1」会连带 P2 变红，单点归因失效。
ev_p2_count() { # $1=test_log $2=baseline_json
  local f="${1:-}" base_json="${2:-}" line n base reason
  # 日志缺失时 _ev_facts 留空 ⇒ 下面落到 [N/A]。不在这里提前 return 0：
  # 静默返回会让 gate.sh 少打一行，看起来像「P2 通过了」，实际上是「P2 没说话」。
  _ev_facts "$f"; line="$EV_F_SUMMARY"
  # ★ 汇总行不唯一 ⇒ 本条**不判**（归因 P1）。必须放在解析 +N **之前**：
  #   放在 -z "$n" 之后，任何形态偏差都会被报成「无法解析 +N」，
  #   而真因是日志混写 —— 两个不同病因报同一句话，归因就废了。
  if [ "${EV_F_N1:-0}" -gt 1 ]; then
    echo "[N/A] P2 例数下限：汇总行不唯一（$EV_F_N1 条）⇒ 本条不判（归因 P1）"
    return 0
  fi
  n="$(_ev_field "$line" passed)"
  if [ -z "$n" ]; then
    echo "[N/A] P2 例数下限：无法从日志解析 +N ⇒ 本条不判（归因 P1）"
    return 0
  fi

  reason="flutter test 全绿轮次的 +N（基线只卡下降，不卡等号）"

  if [ ! -f "$base_json" ]; then
    _ev_write_baseline "$base_json" "$n" "$reason"
    echo "[WARN] P2 例数下限：基线不存在 ⇒ 已首建（count=$n，含 provenance 四字段），本轮不判定"
    return 0
  fi

  if ! _ev_base_provenance_ok "$base_json"; then
    echo "[WARN] P2 例数下限：基线 provenance 不齐（需 count/head/generated_at/reason 四键）⇒ 判为无效基线，不采用"
    return 0
  fi

  base="$(_ev_base_count "$base_json")"
  if [ -z "$base" ]; then
    echo "[WARN] P2 例数下限：基线里解析不出 count ⇒ 判为无效基线，不采用"
    return 0
  fi

  if [ "${UPDATE_TEST_BASELINE:-0}" = "1" ]; then
    _ev_write_baseline "$base_json" "$n" "$reason"
    echo "[WARN] P2 例数下限：UPDATE_TEST_BASELINE=1 ⇒ 基线已刷新 $base → $n（显式入口）"
    return 0
  fi

  if [ "$n" -lt "$base" ]; then
    echo "[FAIL] P2 例数下限：+N=$n < 基线 $base ⇒ 例数下降（Δ=$((n - base))）"
    return 1
  fi
  if [ "$n" -gt "$base" ]; then
    echo "[WARN] P2 例数下限：+N=$n > 基线 $base（Δ=+$((n - base))）⇒ 用例增长，提示刷新基线"
    return 0
  fi
  echo "[PASS] P2 例数下限：+N=$n = 基线 $base"
  return 0
}

# ---------- P3 日志可信性 ----------
ev_p3_log_integrity() { # $1=test_log
  local f="${1:-}" first
  if [ ! -f "$f" ]; then
    echo "[FAIL] P3 日志可信性：日志文件不存在（$f）⇒ 结论不可信"
    return 1
  fi
  _ev_facts "$f"
  if [ "$EV_F_P3_HITS" -gt 0 ]; then
    first="$(printf '%s' "$EV_F_P3_FIRST" | cut -c1-160)"
    echo "[FAIL] P3 日志可信性：命中 $EV_F_P3_HITS 条写失败诊断（首条：$first）⇒ 日志写不全，结论不可信"
    return 1
  fi
  echo "[PASS] P3 日志可信性：0 命中（锚定形态）"
  return 0
}

# ---------- P1/P2/P3 单一入口（gate.sh 只调这一个）----------
# 【为什么要有它】缓存是 shell 变量。gate.sh 若写成
#   msg="$(ev_p1_summary …)"; msg="$(ev_p2_count …)"; msg="$(ev_p3_log_integrity …)"
# 每条命令替换各起一个子 shell ⇒ 缓存全废 ⇒ 14 MB 日志被扫 3 遍。
# 实测：三处各调 = 1632 ms；本函数一次调 = 单遍扫描。**指令要防的正是这个形态。**
#
# 【P1 与 P3 在混写日志上的**有意不对称**】
#   P1 = 覆盖取**最后**一条汇总行 / P3 = 计**全部**命中、诊断取**首条**。
#   ⇒ 同一份混写日志上，二者可能指向**不同的 run**。这是保守方向：P1 靠「唯一性」
#     判据兜底（命中 >1 就判红），P3 宁可错杀（日志确实混了 ⇒ 结论确实不可信）。
#   ⚠️ 不要把它「修」成一致：能让 P3 只统计最后一个 run 的前提是先能切分 run 边界，
#     而 P1 的唯一性判据已在做同一件事 —— 那是重复投入，不是修复。
#
# 【输出契约】
#   stdout = 恰好三行，每行以 `[PASS]/[WARN]/[N/A]/[FAIL] P<n>` 开头（供单点归因 grep）
#   return 0 = 三条无一 FAIL；return 1 = 至少一条 FAIL
#   ⇒ 三行**始终都打**，不因前一条 FAIL 就短路：归因要看的是「哪几条红」，
#     少打一行会把「没判」伪装成「通过」（S9d 就是钉这条）。
ev_check_p123() { # $1=test_log $2=baseline_json
  local f="${1:-}" base="${2:-}" rc=0
  if [ ! -f "$f" ]; then
    echo "[FAIL] P1 汇总行：日志文件不存在（$f）⇒ 无证据"
    echo "[N/A] P2 例数下限：无日志 ⇒ 本条不判（归因 P1）"
    echo "[FAIL] P3 日志可信性：日志文件不存在（$f）⇒ 结论不可信"
    return 1
  fi
  _ev_facts "$f"   # ← 全流程唯一一次读日志
  # 三个 `if !` 都**在同一个 shell 里**执行（不是 `msg="$(…)"`）：
  #   ① 缓存命中，日志不再被读；② 输出直接进 stdout，顺序不会乱；③ 不额外 fork。
  # 每条都判、不短路 —— 归因要看「哪几条红」，短路会让后面几条根本不说话。
  if ! ev_p1_summary "$f";               then rc=1; fi
  if ! ev_p2_count "$f" "$base";         then rc=1; fi
  if ! ev_p3_log_integrity "$f";         then rc=1; fi
  return "$rc"
}

# ---------- P4a 覆盖率新鲜度 ----------
# 判据：mtime(lcov) **>=** run_start（秒级）。
#   ⚠️ 必须 `>=` 而非 `>`：`stat -c %Y` 与 run_start 同为秒级，
#      同一秒内起跑并写完 lcov 时二者相等 ⇒ 用 `>` 会**间歇假红**（§4-295④）。
#   ⚠️ 必须先判 `-f`：文件不存在时 `stat` 会往 stderr 喷错，那会被误读成环境故障。
ev_p4a_fresh() { # $1=lcov $2=run_start_ts
  local lcov="${1:-}" start="${2:-}" mtime
  if [ ! -f "$lcov" ]; then
    echo "[FAIL] P4a 覆盖率新鲜度：lcov 不存在（$lcov）⇒ 无新鲜度可验"
    return 1
  fi
  if ! mtime="$(stat -c %Y "$lcov" 2>/dev/null)"; then
    echo "[FAIL] P4a 覆盖率新鲜度：本环境不支持 stat -c %Y ⇒ 无法验证（fail-closed）"
    return 1
  fi
  if [ -z "$mtime" ]; then
    echo "[FAIL] P4a 覆盖率新鲜度：mtime 读不出 ⇒ 无法验证（fail-closed）"
    return 1
  fi
  if [ "$mtime" -ge "$start" ]; then
    echo "[PASS] P4a 覆盖率新鲜度：mtime=$mtime >= run_start=$start（差 $((mtime - start))s）"
    return 0
  fi
  echo "[FAIL] P4a 覆盖率新鲜度：mtime=$mtime < run_start=$start（陈旧 $((start - mtime))s）⇒ 消费了上一轮的 lcov"
  return 1
}

# ---------- P4b 实际 COV_FLAG ----------
# 「文件存在且为空」与「文件不存在」**必须可区分**：
#   空串 = wrapper 确实跑了、且明确未开覆盖率；
#   UNKNOWN = 不知道 wrapper 跑没跑 / 哪一版 wrapper。
# 压成同一态 = 又造一个不可证伪的 PASS（T-20261025-04 §四-P4b 要求 1）。
#
# 【为什么拆成「读进变量」+「打印」两层】
#   gate.sh 的 record_hit 每道门禁都要记这个字段（19 次）。若每次都
#   `x="$(ev_p4b_cov_flag …)"`，就是 19 次子 shell —— 本机每 fork 75-90 ms，
#   白送 1.5 s。所以主读法用内建 `read` + 重定向（零 fork），把结果放变量；
#   `ev_p4b_cov_flag` 只是给自测用的打印壳，契约（stdout/rc）与第 1 笔一致。
#
# 【为什么用 `read` 而不是 `$(cat)` / `$(<f)`】
#   `read` 是内建，重定向是内建 ⇒ 不 fork。`$(<f)` 虽然 bash 有优化，但仍是命令替换，
#   在 set -u 下还要额外操心退出码。`read` 读不到行（空文件）返回非 0，正好把
#   「文件在但为空」与「文件缺失」分成两条不同的路径。
EV_P4B_VALUE=""
EV_P4B_MISSING=0
_ev_p4b_read() { # $1=cov_flag_file ; 设 EV_P4B_VALUE / EV_P4B_MISSING（0=在,1=缺失）
  local f="${1:-}"
  EV_P4B_VALUE=""
  if [ ! -f "$f" ]; then
    EV_P4B_MISSING=1
    EV_P4B_VALUE="UNKNOWN"
    return 0
  fi
  EV_P4B_MISSING=0
  # 空文件 ⇒ read 失败、EV_P4B_VALUE 保持空串（**不是** UNKNOWN，这是设计）
  IFS= read -r EV_P4B_VALUE < "$f" 2>/dev/null || true
  # 防御 CRLF：万一 wrapper 在 Windows 上被改成用非 LF 写，值里会多一个 \r，
  # 那样 `= "--coverage"` 的比较永远不成立 ⇒ 覆盖率开着却被判「没开」。
  EV_P4B_VALUE="${EV_P4B_VALUE%$'\r'}"
  return 0
}

ev_p4b_cov_flag() { # $1=cov_flag_file ; stdout=值或 UNKNOWN ; return 0=文件在, 2=缺失
  _ev_p4b_read "${1:-}"
  printf '%s' "$EV_P4B_VALUE"
  [ "$EV_P4B_MISSING" = "0" ] && return 0
  return 2
}

# ---------- P5 工作树脏度：**本节已删除**（2026-10-25，T-20261025-04 第6笔）----------
# 【这一节原来是 `ev_p5_dirty_count`，现在没有 —— 不是漏写，是删掉的。】
# 删它的理由（主理人裁定，依据独立复核 t04-batch3-independent-verify.md §4.1）：
#   `dirty_count` **不判红**。本文件的定位是「**能变红的判据**」纯函数层；
#   一个永不变红的计数器放在判据库里，是**放错层**。
#   而它当时还是三份互斥实现里最坏的一份：
#     `git status --porcelain -uall 2>/dev/null | wc -l`
#     在 `git` 失败时 `wc -l` 对空输入照样输出 0 ⇒「读不到」被记成「干净」，
#     正是本卡（P5）要治的那个假绿形态；而上线版同环境下写 `-1`。
#   更关键：**唯一调用它的是自测**，`gate-run.sh` 从来没调过 ⇒ 自测测的不是上线那份代码。
# 【上线的实现只有一个】`scripts/gate-run.sh` 里 `DIRTY_COUNT=-1` 那段内联块
#   （`git` 失败 ⇒ `-1`；空树 ⇒ `0`，靠 `if [ -z "$DIRTY_STATUS" ]` 分叉）。
#   要改它去改那里。**不要在这里补一个函数再让 gate-run 调过去** ——
#   那会把「`-1` 哨兵」这条语义拆成两份，两份必然漂移。
# 【后来者】这不是待办，是一个**作过的决定**。要推翻请先推翻上面两条：
#   ① `dirty_count` 不判红；② 判据库只放能变红的判据。
