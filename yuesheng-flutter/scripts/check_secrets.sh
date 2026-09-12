#!/usr/bin/env bash
#
# 月笙 Flutter 端 — 密钥硬编码扫描（R-029 / §六 / AGENTS.md 四闸 闸4）。
#
# 独立出原 gate.sh 内嵌的 grep 逻辑，供 CI / 本地 pre-commit 单独调用。
#
# ⚠️ 覆盖边界（务必知悉，勿过度解读结论）：本脚本**只扫 `lib/**/*.dart`**
#    （见下方 grep 的 "$LIB" --include='*.dart'）。`test/`、`tool/`、`scripts/`、
#    仓库根配置等**均不在扫描范围内**——故"通过"仅代表 lib 范围内未命中，
#    不等于全项目无密钥。扩大范围是独立议题，本脚本不擅自扩权。
#
# 用法:  bash scripts/check_secrets.sh           # 扫描 ../lib (相对于脚本位置)
#        bash scripts/check_secrets.sh ROOT_DIR  # 指定 Flutter 工程根目录
# 退出码:
#   0 = 未命中疑似硬编码（**仅 lib 范围内**）
#   1 = 命中疑似硬编码（命中内容输出到 stdout）
#   2 = 环境错误：lib 目录不存在（**失败关闭**，绝不静默放行）
#
# ⚠️ 失败关闭约定 (2026-09-12 实证)：此处原本在 lib 缺失时打印 SKIP 并
#    `exit 0`——与 check_circular.py 的 `return 2`、gate.sh 的记 PASS 三种
#    策略互相矛盾。护栏的缺省必须是「拦下」而非「放行」：无法检查 ≠ 通过。
#    现三脚本统一 fail-closed，本脚本改为非 0 退出。
#
set -u

if [ "$#" -ge 1 ]; then
  ROOT="$1"
else
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi
LIB="$ROOT/lib"

if [ ! -d "$LIB" ]; then
  # 失败关闭：lib 找不到 = 调用方式或环境有问题，绝不放行。
  # 旧行为 `exit 0` 会让本门禁在「根本没扫过任何文件」时假绿。
  echo "ERROR: lib not found at $LIB"
  echo "  → 若由 CI / 脚本调用，请传入 Flutter 工程根目录（其中须含 lib/）。"
  echo "  → 拒绝以「通过」收尾：无法检查 ≠ 通过（fail-closed）。"
  exit 2
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
echo "OK: no suspected hardcoded secrets in lib (lib only)"
exit 0
