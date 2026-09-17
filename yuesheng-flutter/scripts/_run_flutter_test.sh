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
# 退出码：透传 flutter test 自身退出码。
# ============================================================
set -u

# 0. 并发护栏：绝不与另一个 flutter test --coverage 同时跑
#    V4.28（QA 实测 2026-09-12）：两个 flutter test --coverage 并发时，
#    各自收尾都会重写 coverage/ 目录，先跑完的那个会把 lcov 抽走 ——
#    门禁 2 全绿、门禁 6 却拿不到文件。更糟的是两者互相覆盖，
#    可能留下**不属于本次运行**的 lcov（查错代码）。
#    这里用锁文件串行化：拿不到锁就明确拒绝出结论，而不是静默降级。
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/.flutter_test.lock"

if [ -f "$LOCK" ]; then
  LOCK_PID="$(cat "$LOCK" 2>/dev/null || echo '')"
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "[ABORT] 已有 flutter test 在跑（pid=$LOCK_PID，锁 $LOCK）。"
    echo "        并发跑 --coverage 会互相抽走 coverage/lcov.info，故拒绝并发。"
    echo "        若确认该进程已死，删掉锁文件后重试：rm -f '$LOCK'"
    exit 75   # EX_TEMPFAIL：暂时失败，重试即可，区别于测试断言失败
  fi
  echo "[WARN] 发现陈旧锁文件（pid=$LOCK_PID 已不存在），自动清理"
  rm -f "$LOCK"
fi

cleanup_lock() {
  # 只删**自己**拿到的锁：pid 已被新进程接管时不要误删对方的锁。
  if [ -f "$LOCK" ] && [ "$(cat "$LOCK" 2>/dev/null || echo '')" = "$$" ]; then
    rm -f "$LOCK"
  fi
}
# ★ 2026-09-17 起**不再用 exec** 启动 flutter（理由见文件末尾注释），
EXIT trap 因此恢复正常工作；下面这行 trap 保留作兜底，
覆盖「flutter 尚未启动就失败」的路径。
trap cleanup_lock EXIT INT TERM
echo "$$" > "$LOCK"

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
# ★ 这里**故意不用 `exec`**（2026-09-17 实测修正）：
#   旧实现 `exec ... flutter test` 会让 bash 被 flutter 替换进程映像，
#   于是 EXIT trap 永不触发 ⇒ **每次跑完都在工作区留下一个 .flutter_test.lock**。
#   它靠「下次发现 pid 已死就自愈」才没阻塞，但每次都会：①污染 git status；
#   ②若该 pid 被系统复用给别的进程，会误报「已有 flutter test 在跑」而拒绝执行
#     （exit 75），看起来像门禁故障。
#   实测：快道首跑结束后锁仍在，内容 pid 已不存在、且全机无 dart/flutter 进程。
#   代价：多一个常驻 bash 等子进程（可忽略）；Ctrl+C 仍经进程组送达 flutter。
/usr/bin/env "PROGRAMFILES(X86)=${PROG_FILES_X86}" \
  HTTP_PROXY= HTTPS_PROXY= http_proxy= https_proxy= \
  NO_PROXY=localhost,127.0.0.1 \
  flutter test $COV_FLAG --exclude-tags live,external "$@"
RC=$?
cleanup_lock
exit $RC