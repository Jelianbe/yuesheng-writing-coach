#!/usr/bin/env bash
#
# 月笙 Flutter 端 — 密钥硬编码扫描（R-029 / §六 / AGENTS.md 四闸 闸4）。
#
# 独立出原 gate.sh 内嵌的 grep 逻辑，供 CI / 本地 pre-commit 单独调用。
#
# 用法:  bash scripts/check_secrets.sh           # 扫描 ../lib (相对于脚本位置)
#        bash scripts/check_secrets.sh ROOT_DIR  # 指定 Flutter 工程根目录
# 退出码:
#   0 = 未命中疑似硬编码
#   1 = 命中疑似硬编码（命中内容输出到 stdout）
#
set -u

if [ "$#" -ge 1 ]; then
  ROOT="$1"
else
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi
LIB="$ROOT/lib"

if [ ! -d "$LIB" ]; then
  echo "SKIP: lib not found at $LIB"
  exit 0
fi

issues=0

# R-029: 密钥零硬编码 — 疑似明文密钥/令牌正则。
# 白名单: llm_config_storage.dart 只存 SecureStorage 用的"键名常量"，不是真实密钥值；
#        测试/example/mock/占位符相关文件跳过。
matches=$(grep -rnE "(apiKey|api_key|secret|token|password|accessKey|sk-)[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9+/_.-]{12,}" \
  "$LIB" --include='*.dart' 2>/dev/null \
  | grep -vE "(test|_test|example|sample|mock|dummy|placeholder|your_|xxx|TODO|llm_config_storage\.dart)" || true)

if [ -n "$matches" ]; then
  echo "FAIL: suspected hardcoded secrets:"
  echo "$matches" | sed 's/^/    /'
  issues=$((issues + 1))
fi

# 可达性轻量信号（统计，不阻断）
tooltip_count=$(grep -rnE "Tooltip\(" "$LIB" --include='*.dart' 2>/dev/null | wc -l)
echo "info: Tooltip usage count: $tooltip_count (positive accessibility signal, non-blocking)"

if [ "$issues" -gt 0 ]; then
  exit 1
fi
echo "OK: no suspected hardcoded secrets in lib"
exit 0
