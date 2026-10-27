#!/usr/bin/env bash
# ============================================================
# scripts/_run_flutter_test.sh — sandbox-aware flutter test wrapper
#
# 目的：调用 flutter test 前注入沙箱会话缺失的环境变量，其他环境原值优先。
#
# 触发场景（V4.22，2026-09-04 批次 I 实证）：
#   AI 沙箱会话缺 `PROGRAMFILES(X86)`，flutter.bat 内部调用
#   update_engine_version.ps1 触发 `%PROGRAMFILES(X86)% environment variable
#   not found.` 报错退出；表现「测试零输出 / 假绿」，且 `| tail` 取 $? 时
#   拿到的是 tail 的退出码（V4.5 陷阱），掩盖真实失败。
#
# 原值优先：仅缺时注入 Windows 标准值；已有原值时**不动**（避免污染其他环境）。
# 代理清空：复用 gate.sh V4.18 的兜底（HTTP_PROXY / HTTPS_PROXY 设为空）。
#
# 用法：bash scripts/_run_flutter_test.sh [flutter test args...]
#   固定附加：--exclude-tags live,external（可覆盖：再传同参数由 flutter 取后者）
#   覆盖率：默认 --coverage；快道置 RUN_FLUTTER_TEST_COVERAGE=0 关闭
# 退出码：透传 flutter test 自身退出码（0 通过 / 1 失败）。
#   例外：锁护栏 abort 返回 **75**（`EX_TEMPFAIL`：暂时无法执行，重试即可）。
#   为什么不是 1：1 表示「测试真的红了」，75 表示「压根没跑」。二者混同会误导归因。
#   为什么 75 不是「跳过」：门禁只判 rc 是否为 0（gate.sh:261）⇒ 75 记 FAIL，不得归 SKIP。
# ============================================================
set -u

# 0. 并发护栏：绝不与另一个 flutter test --coverage 同时跑
#    V4.28（QA 实测 2026-09-12）：两个 flutter test --coverage 并发时，
#    各自收尾都会重写 coverage/ 目录，先跑完的那个会把 lcov 抽走 ——
#    门禁 2 全绿、门禁 6 却拿不到文件。更糟的是两者互相覆盖，
#    可能留下**不属于本次运行**的 lcov（查错代码）。
#    这里用锁串行化：拿不到锁就明确拒绝出结论，而不是静默降级。
#
# ★ T-20261025-08（2026-10-25）：锁由「文件锁」改为「目录锁」，为堵住
#   「进程在跑却没登记为持锁者」（实测：pid 29620 在跑 flutter test，
#   锁里却仍是 5805 ⇒ 另一轮看到 5805 已死 ⇒ rm -f + 继续 ⇒ 两个
#   --coverage 并发）。五条护栏（缺一不算）：
#     判据 1 锁写入失败必须 abort —— 继续跑等于断言「无人并发」，与事实相反。
#     判据 2 **写后回读**：owner 内容必须等于自己的 pid，不符即 abort。
#            本环境实测过 `rc=0 ≠ 落盘`；只有回读比对能区分「写了 / 没写 / 写了一半」。
#     判据 3 判「被占用」要 pid 存活 **且** 命令行匹配 `_run_flutter_test.sh`。
#            本机短命进程多、pid 复用真实存在，只看存活会把复用误判成真冲突。
#     判据 4 「锁内 pid 不存活 ⇒ 自愈」这条路必须保留并走通（只测「不该自愈」= 漏一半）。
#     判据 5 自愈必须留痕：打旧 pid / 新 pid / 判定依据 —— 否则「自愈」与
#            「真的拿到锁」在日志上完全同形，事后无法归因。
#   为什么用 `mkdir` 而不是 `rm -f` + `echo >`：`mkdir` 在 POSIX 上**原子**，
#   已存在即失败（EEXIST）—— 这正是锁需要的语义，且少一个「rm 与 write 之间」的竞态窗。
#    ⚠️ 必须 `mkdir` **不带 `-p`**：`mkdir -p` 把「已存在」当成功（rc=0）⇒ 锁静默失效。
#    ⚠️ 不许换 `mktemp -d`：锁的全部意义是「所有人看同一个位置」，
#       每次给唯一目录 = 永不冲突 = 根本没有锁。
#    ⚠️ 不许换 `flock`（跨平台不可用，且本卡边界明令禁止）。
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# 锁落在 outputs/gate/（该目录已被 .gitignore 忽略）：不再污染 git status。
LOCK="$ROOT/outputs/gate/.lock.d"
LOCK_OWNER="$LOCK/owner"
LOCK_STARTED="$(date '+%Y-%m-%dT%H:%M:%S')"

# 退出码 75 = EX_TEMPFAIL（暂时无法执行，重试即可），区别于测试断言失败（1）。
#   ⚠️ 门禁侧**不得**把 75 归为 SKIP / 环境跳过 —— 那会新开一条假绿通路
#   （脚本 abort 了，门禁却显示「这道跳过」，十九道少一道而汇总仍可能全绿）。
#   现状核对（gate.sh:261）：`if bash scripts/_run_flutter_test.sh > log 2>&1`
#   只判 rc 是否为 0 ⇒ 75 落 else 分支 ⇒ RC_TEST=1 ⇒ 记 FAIL。**这是必须保持的**。

# 读锁内 pid（首字段）；owner 不可读 / 不存在 ⇒ 输出空串，**不要**猜一个值。
lock_owner_pid() {
  local line
  line="$(head -n 1 "$LOCK_OWNER" 2>/dev/null)"
  printf '%s' "${line%% *}"
}

# 统一 abort 出口：75 + 可照抄的清理命令。
lock_abort() {
  echo "[ABORT] $1"
  echo "        锁：$LOCK（owner 记录「pid 启动时刻」）"
  echo "        确认全机无 flutter test 在跑后清理：rm -rf '$LOCK'"
  exit 75
}

acquire_lock() {
  mkdir -p "$ROOT/outputs/gate" 2>/dev/null \
    || lock_abort "锁的父目录建不起来（$ROOT/outputs/gate）"

  # 判据 1 的前半：锁**建不起来**（非「被占用」）也必须 abort。
  if mkdir "$LOCK" 2>/dev/null; then
    return 0
  fi
  if [ ! -d "$LOCK" ]; then
    lock_abort "锁无法建立，且不是「被占用」（$LOCK 存在但不是目录，或父目录不可写）"
  fi

  # 锁存在 ⇒ 判定持有者。读不出 pid 时**不许**假设无人并发。
  OLD_LINE="$(head -n 1 "$LOCK_OWNER" 2>/dev/null)"
  OLD_PID="$(lock_owner_pid)"
  if [ -z "$OLD_PID" ]; then
    lock_abort "锁已存在但 owner 不可解析（判定依据：$LOCK_OWNER 缺失或首字段为空）"
  fi
  OLD_STARTED="${OLD_LINE#* }"
  if [ "$OLD_STARTED" = "$OLD_LINE" ]; then OLD_STARTED="未知"; fi

  WHY=""
  if ! kill -0 "$OLD_PID" 2>/dev/null; then
    WHY="判据 4：锁内 pid=$OLD_PID 已不存活"
  else
    OLD_CMD="$(tr '\0' ' ' < "/proc/$OLD_PID/cmdline" 2>/dev/null)"
    if [ -z "$OLD_CMD" ]; then
      lock_abort "pid=$OLD_PID 存活但读不到命令行（/proc 不可用）⇒ 无法区分 pid 复用与真持锁者，拒绝假设无人并发"
    fi
    case "$OLD_CMD" in
      *_run_flutter_test.sh*)
        echo "[ABORT] 已有 flutter test 在跑（pid=$OLD_PID，启动于 $OLD_STARTED，锁 $LOCK）。"
        echo "        并发跑 --coverage 会互相抽走 coverage/lcov.info，故拒绝并发。"
        echo "        判据 3：该 pid 存活**且**命令行匹配 _run_flutter_test.sh ⇒ 判为真持锁者。"
        echo "        若确认该进程已死，清理锁后重试：rm -rf '$LOCK'"
        exit 75
        ;;
      *)
        WHY="判据 3：pid=$OLD_PID 存活但命令行不是本脚本（pid 复用）→ $OLD_CMD"
        ;;
    esac
  fi

  # 判据 5：自愈必须留痕（旧 pid / 判定依据 / 新 pid 三样齐全）。
  echo "[WARN] 陈旧锁自愈：旧 pid=$OLD_PID（启动于 $OLD_STARTED）"
  echo "       判定依据：$WHY"
  rm -rf "$LOCK"
  if mkdir "$LOCK" 2>/dev/null; then
    echo "[INFO] 自愈后重新持锁：新 pid=$$（旧 pid=$OLD_PID 已清理）"
    return 0
  fi
  if [ ! -d "$LOCK" ]; then
    lock_abort "自愈后仍然建不起锁（非「被占用」）"
  fi
  lock_abort "自愈后重新抢锁失败：另一进程已抢先持锁"
}

# ★ T-20261025-14（2026-10-25）：旧路径锁（$ROOT/.flutter_test.lock）一次性兼容告警。
#   锁已在 T-20261025-08 迁到 $LOCK（目录锁），但历史**文件锁**可能仍留在盘上。
#   三条边界（缺一不算）：
#     边界 1 **只告警、不 abort**：历史文件存在与否**不参与**「本次能否持锁」的判定。
#     边界 2 **不删**：旧进程可能仍在跑并继续写它 —— 本脚本无权替他人判死活。
#     边界 3 读不到 / 空内容 / 首字段非数字 ⇒ 退化为「内容无法解析」，**不承载判定**。
#             `[ -e ]` 与 `head` 之间有 TOCTOU（文件可能在这一瞬被删）：**已知且可接受** ——
#             本段不产出判定，最坏结果只是少打一行告警。
#   为什么放**顶层**而不是 acquire_lock 函数体内：函数内的告警在 abort 路径上会被跳过
#   ⇒ 又退回「无声」。放这里 ⇒ 拿锁成功 / 自愈 / abort 三条路径都会先告警一次。
LEGACY_LOCK="$ROOT/.flutter_test.lock"
if [ -e "$LEGACY_LOCK" ]; then
  LEGACY_PID="$(head -n 1 "$LEGACY_LOCK" 2>/dev/null)"
  LEGACY_PID="${LEGACY_PID%% *}"
  case "$LEGACY_PID" in
    ''|*[!0-9]*)
      echo "[WARN] 发现旧路径锁 $LEGACY_LOCK，但内容无法解析（首字段为空或非数字）⇒ 忽略，不影响本次持锁判定。"
      ;;
    *)
      if kill -0 "$LEGACY_PID" 2>/dev/null; then
        echo "[WARN] 发现旧路径锁 $LEGACY_LOCK（pid 存活：pid=$LEGACY_PID）⇒ 可能有旧版脚本仍在跑。"
      else
        echo "[WARN] 发现旧路径锁 $LEGACY_LOCK（pid=$LEGACY_PID 已不存活）⇒ 属历史残留。"
      fi
      ;;
  esac
  echo "        锁已迁至 $LOCK；本段只告警：不改变持锁判定、不删除该文件。确认无旧进程后可手工删：rm -f '$LEGACY_LOCK'"
fi

acquire_lock

cleanup_lock() {
  # 只删**自己**拿到的锁：pid 已被新进程接管时不要误删对方的锁。
  if [ -d "$LOCK" ] && [ "$(lock_owner_pid)" = "$$" ]; then
    rm -rf "$LOCK"
  fi
}
# ★ 2026-09-17 起**不再用 exec** 启动 flutter（理由见文件末尾注释），
# EXIT trap 因此恢复正常工作；下面这行 trap 保留作兜底，
# 覆盖「flutter 尚未启动就失败」以及「owner 写一半被 Ctrl+C」的路径。
trap cleanup_lock EXIT INT TERM

# 判据 1：锁内容写入失败必须 abort（锁目录建好了 ≠ 已登记为持锁者）。
if ! printf '%s %s\n' "$$" "$LOCK_STARTED" > "$LOCK_OWNER" 2>/dev/null; then
  rm -rf "$LOCK"
  lock_abort "锁内容写入失败（锁目录已建立，owner 写不进去）"
fi
# 判据 2：写后回读。`rc=0` 只说明系统调用被受理，不说明字节到了盘上。
READBACK_PID="$(lock_owner_pid)"
if [ "$READBACK_PID" != "$$" ]; then
  rm -rf "$LOCK"
  lock_abort "写后回读不符：期望 pid=$$，实读 '$READBACK_PID'（写入 rc=0 但落盘不是本进程）"
fi

# ★ T-20261027-04 乙（2026-10-27 舰长裁「先乙后甲」）：日志截断必须发生在**持锁之后**。
#   旧写法由调用方 `> "$TEST_LOG"` 在脚本启动前截断 ⇒ 两轮并发时后一轮先清空、
#   前一轮仍按旧偏移写 ⇒ 稀疏文件（曾见 14.2 MB 带 NUL）⇒ 汇总行可能落在 NUL 之后不被 grep 命中。
#   `exec >` 只截断一次，且此刻已持锁 ⇒ 截断与写入进同一临界区。
#   未设 TEST_LOG_PATH 时行为与改前完全一致（stdout 照旧交给调用方）。
if [ -n "${TEST_LOG_PATH:-}" ]; then
  exec > "$TEST_LOG_PATH" 2>&1
fi

# 1. 注入 Windows 标准环境变量（仅缺时）
#    bash 变量名解析限制：PROGRAMFILES(X86) 含括号无法作变量名 → 用 env 命令传。
export PROGRAMFILES="${PROGRAMFILES:-C:\\Program Files}"
export PROGRAMW6432="${PROGRAMW6432:-C:\\Program Files}"
PROG_FILES_X86="${PROGRAMFILES_X86:-C:\\Program Files (x86)}"

# 2. 清代理（V4.18）+ 注入 PROGRAMFILES(X86) + 透传所有 flutter test 参数
#    V4.27：必须写 /usr/bin/env 绝对路径——uv 遗留 shim（~/.local/bin/env）
#    会遮蔽裸 env（只 export PATH 不 exec），导致 flutter 静默不执行、假绿。
#
#    --coverage：默认开启（门禁 6 依赖门禁 2 产出的 lcov；锁文件保证同一时刻
#      只有一个 --coverage 写入者）。**快道**（gate-fast.sh）会置
#      RUN_FLUTTER_TEST_COVERAGE=0 关掉它 —— 窄范围测试若写 lcov，会把只含
#      几个文件的覆盖率文件留在 coverage/lcov.info 上，之后收尾门禁 6 读到它
#      必然 T1 假红（实测：单文件 lcov 的 T1 仅 0.83%）。
#
#    --exclude-tags live,external：**固定开启**（2026-09-17 口径收口）。
#      此前只有 CI 加了标签排除、本地门禁 2 不加 ⇒ 本地与 CI 口径分叉。
#      CI 注释写明它是「双保险：即使某条 live 测试的 markTestSkipped 位置没提前
#      到 LlmClient() 构造之前，也不会触发出站网络调用」。本地同样需要。
#      ⇒ **单一真源在此**，调用方不要再重复传 --exclude-tags。
COV_FLAG="--coverage"
if [ "${RUN_FLUTTER_TEST_COVERAGE:-1}" = "0" ]; then
  COV_FLAG=""
fi

# ★ T-20261025-04 P4b：把**本次实际生效的 COV_FLAG** 落盘，供 gate.sh 记进 hits.jsonl。
#
# 【为什么由 wrapper 写，而不是 gate.sh 自己记 env】
#   gate.sh 只能看到它自己导出的 RUN_FLUTTER_TEST_COVERAGE；真正决定命令行的是这里。
#   「记一个看起来对、实则记的是另一件事的字段」正是本卡要治的病。
#
# 【为什么空值也必须写文件】写空文件 ≠ 不写文件：
#   文件存在且为空 = wrapper 确实跑了、且明确没开覆盖率；
#   文件不存在   = 不知道 wrapper 跑没跑 / 是哪一版 wrapper（旧版不写这个文件）。
#   把这两态压成同一态，就是又造一个不可证伪的 PASS。
#
# 【为什么写在这一行（跑之前），而不是跑完之后】
#   这个值在**决策时**就已确定，与 flutter 跑成什么样无关。先落盘 ⇒ 后续进程被杀、
#   磁盘写满、flutter 崩掉，都不会让「当时开的什么档」这件事灭失（P4b 与 P5 同理）。
#
# 【为什么 `printf '%s'` 不带换行】空值时 `%s\n` 会写出 1 字节（一个 LF），
#   而判据要的是「文件存在且 **0 字节**」；不带换行才真的是 0 字节。
#   非空时文件内容是 `--coverage`（无尾换行），门禁用内建 `read` 读，不依赖换行存在。
#
# 【写失败不 abort】这是证据记录，不是判定前提：写不进去会退化成 UNKNOWN（WARN），
#   让门禁红在「证据缺失」上，而不是让测试根本跑不起来。
mkdir -p "$ROOT/outputs/gate" 2>/dev/null || true
printf '%s' "$COV_FLAG" > "$ROOT/outputs/gate/cov_flag.txt" 2>/dev/null || true
# ★ 这里**故意不用 `exec`**（2026-09-17 实测修正）：
#   旧实现 `exec ... flutter test` 会让 bash 被 flutter 替换进程映像，
#   于是 EXIT trap 永不触发 ⇒ **每次跑完都在工作区留下一个 .flutter_test.lock**
#   （T-20261025-08 起锁已迁到 outputs/gate/.lock.d，同一弊病对目录锁成立）。
#   它靠「下次发现 pid 已死就自愈」才没阻塞，但每次都会：①污染 git status；
#   ②若该 pid 被系统复用给别的进程，会误报「已有 flutter test 在跑」而拒绝执行
#     （exit 75），看起来像门禁故障。
#   实测：快道首跑结束后锁仍在，内容 pid 已不存在、且全机无 dart/flutter 进程。
#   代价：多一个常驻 bash 等子进程（可忽略）；Ctrl+C 仍经进程组送达 flutter。
# ★ 2026-10-06 显式清 UPDATE_SNAPSHOTS（实测常态风险，非窗口期）：
#   本文件全文原先**没有任何 unset UPDATE_SNAPSHOTS** ⇒ 该变量原样传给
#   `flutter test`；而 `test/services/skill_prompt_anchor_test.dart:329` /
#   `l3_entry_anchor_test.dart:109` / `chat_service_message_sequence_anchor_test.dart:316`
#   （实测共 5 份测试共用该开关）在 `updating == true` 时走
#   `if (updating) { …写基线…; return; }` ⇒ **跳过全部 diff 断言并返回通过**。
#   又因 `tool/check_prompt_volume.py` 的数据源正是这些测试写出的快照，
#   残留该变量会让体积门禁报出一组「全新且全绿的余量 +0」= 假绿已发生。
#   ⇒ 收尾门禁必须**永远**在无该变量下运行；重冻快照请用**独立命令**
#     （`UPDATE_SNAPSHOTS=true flutter test test/services/<anchor>_test.dart`），
#     绝不与收尾门禁同一条命令。
unset UPDATE_SNAPSHOTS
/usr/bin/env "PROGRAMFILES(X86)=${PROG_FILES_X86}" \
  HTTP_PROXY= HTTPS_PROXY= http_proxy= https_proxy= \
  NO_PROXY=localhost,127.0.0.1 \
  flutter test $COV_FLAG --exclude-tags live,external "$@"
RC=$?
cleanup_lock
exit $RC