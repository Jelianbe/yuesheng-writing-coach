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
# 退出码：透传 flutter test 自身退出码。
# ============================================================
set -u

# 1. 注入 Windows 标准环境变量（仅缺时）
#    bash 变量名解析限制：PROGRAMFILES(X86) 含括号无法作变量名 → 用 env 命令传。
export PROGRAMFILES="${PROGRAMFILES:-C:\\Program Files}"
export PROGRAMW6432="${PROGRAMW6432:-C:\\Program Files}"
PROG_FILES_X86="${PROGRAMFILES_X86:-C:\\Program Files (x86)}"

# 2. 清代理（V4.18）+ 注入 PROGRAMFILES(X86) + 透传所有 flutter test 参数
#    V4.27：必须写 /usr/bin/env 绝对路径——uv 遗留 shim（~/.local/bin/env）
#    会遮蔽裸 env（只 export PATH 不 exec），导致 flutter 静默不执行、假绿。
exec /usr/bin/env "PROGRAMFILES(X86)=${PROG_FILES_X86}" \
  HTTP_PROXY= HTTPS_PROXY= http_proxy= https_proxy= \
  NO_PROXY=localhost,127.0.0.1 \
  flutter test "$@"