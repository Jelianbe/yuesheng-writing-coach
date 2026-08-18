#!/usr/bin/env bash
# ============================================================
# 月笙写作教练 Flutter 端 — 四道门禁 (R-027 四道代码质量门禁)
#
# 门禁 1: 静态分析 (dart analyze lib) — 类型检查 + Lint
# 门禁 2: 单元测试 (flutter test)
# 门禁 3: 循环依赖扫描 (lib 内 import 图 DFS 检测环)
# 门禁 4: 安全/可达性扫描 (R-029 密钥零硬编码 / 基础可达性)
#
# 用法:  bash scripts/gate.sh
# 退出码: 任一门禁 FAIL 则非 0 (可接入 CI / 提交前自检)
# ============================================================
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

OUT_DIR="$ROOT/outputs/gate"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/gate-report.md"

# 日志落盘（保留历史产物，类似旧机制 _typecheck.txt/_test.txt/_circular.txt/_a11y.txt）
TYPECHECK_LOG="$OUT_DIR/typecheck.txt"
TEST_LOG="$OUT_DIR/test.txt"
CIRCULAR_LOG="$OUT_DIR/circular.txt"
SECURITY_LOG="$OUT_DIR/security.txt"

pass=0
fail=0

emit() { printf '%s\n' "$1"; }
log_result() {
  local name="$1"; local ok="$2"
  if [ "$ok" = "0" ]; then
    emit "[PASS] $name"
    pass=$((pass + 1))
  else
    emit "[FAIL] $name"
    fail=$((fail + 1))
  fi
}

echo "=================================================="
echo "月笙 Flutter 四道门禁 @ $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="

# ---------- 门禁 1: 静态分析 ----------
echo "--> 门禁 1/4: 静态分析 (dart analyze lib)"
if dart analyze lib > "$TYPECHECK_LOG" 2>&1; then
  log_result "静态分析 (analyze lib)" 0
else
  log_result "静态分析 (analyze lib)" 1
  tail -n 30 "$TYPECHECK_LOG"
fi

# ---------- 门禁 2: 测试 ----------
echo "--> 门禁 2/ 4: 单元测试 (flutter test)"
if flutter test > "$TEST_LOG" 2>&1; then
  log_result "单元测试 (flutter test)" 0
else
  log_result "单元测试 (flutter test)" 1
  tail -n 40 "$TEST_LOG"
fi

# ---------- 门禁 3: 循环依赖 ----------
echo "--> 门禁 3/4: 循环依赖扫描 (lib import 图)"
python3 - "$ROOT" > "$CIRCULAR_LOG" 2>&1 <<'PY'
import os, re, sys
root = sys.argv[1]
lib = os.path.join(root, 'lib')
if not os.path.isdir(lib):
    print('SKIP: lib not found'); sys.exit(0)

# 收集所有 dart 文件，建立 package:writingcoach 与相对 import 的模块映射
files = []
for dirpath, _, fnames in os.walk(lib):
    for f in fnames:
        if f.endswith('.dart'):
            files.append(os.path.join(dirpath, f))

def mod_of(path):
    rel = os.path.relpath(path, lib).replace(os.sep, '/')
    rel = rel[:-5]  # strip .dart
    return 'package:writingcoach/' + rel

import_re = re.compile(r"^import\s+'([^']+)'", re.M)
graph = {}
for path in files:
    src = mod_of(path)
    deps = []
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            m = import_re.match(line.strip())
            if not m:
                continue
            dep = m.group(1)
            if dep.startswith('package:writingcoach/'):
                deps.append(dep)
            elif dep.startswith('./') or dep.startswith('../'):
                # 相对导入 -> 解析到绝对 package 模块
                base = os.path.dirname(path)
                resolved = os.path.normpath(os.path.join(base, dep)).replace(os.sep, '/')
                rel = os.path.relpath(resolved, lib).replace(os.sep, '/')
                rel = rel[:-5] if rel.endswith('.dart') else rel
                deps.append('package:writingcoach/' + rel)
    graph[src] = deps

WHITE, GRAY, BLACK = 0, 1, 2
color = {k: WHITE for k in graph}
cycles = []
def dfs(node, stack):
    color[node] = GRAY
    for dep in graph.get(node, []):
        if dep not in graph:
            continue
        if color[dep] == GRAY:
            # 找到环
            idx = stack.index(dep) if dep in stack else 0
            cycles.append(stack[idx:] + [dep])
        elif color[dep] == WHITE:
            dfs(dep, stack + [dep])
    color[node] = BLACK

for node in sorted(graph):
    if color[node] == WHITE:
        dfs(node, [node])

if cycles:
    print('FAIL: 检测到 %d 个循环依赖:' % len(cycles))
    for c in cycles[:20]:
        print('  -> ' + ' -> '.join(c))
    sys.exit(1)
print('OK: 未检测到 lib 内循环依赖 (共 %d 模块)' % len(graph))
sys.exit(0)
PY
if [ $? -eq 0 ]; then
  log_result "循环依赖扫描" 0
else
  log_result "循环依赖扫描" 1
  cat "$CIRCULAR_LOG"
fi

# ---------- 门禁 4: 安全 / 可达性 ----------
echo "--> 门禁 4/4: 安全/可达性扫描"
{
  issues=0
  # R-029: 密钥零硬编码 — 扫描疑似明文密钥/令牌
  matches=$(grep -rnE "(apiKey|api_key|secret|token|password|accessKey|sk-)[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9+/_.-]{12,}" lib --include='*.dart' 2>/dev/null | grep -vE "(test|_test|example|sample|mock|dummy|placeholder|your_|xxx|TODO)" || true)
  if [ -n "$matches" ]; then
    echo "  [WARN] 疑似硬编码密钥/令牌:"
    echo "$matches" | sed 's/^/    /'
    issues=$((issues + 1))
  fi
  # 可达性基础: 是否存在非空 Semantics / 文本对比度提示（轻量、仅统计缺失）
  missing_semantics=$(grep -rnE "Tooltip\(" lib --include='*.dart' 2>/dev/null | wc -l)
  echo "  [info] Tooltip 使用计数: $missing_semantics (可达性正向信号，非阻断)"
  if [ "$issues" -gt 0 ]; then
    echo "FAIL: 安全扫描发现疑似密钥硬编码"
    exit 1
  fi
  echo "OK: 安全扫描通过 (未发现疑似硬编码密钥)"
  exit 0
} > "$SECURITY_LOG" 2>&1
if [ $? -eq 0 ]; then
  log_result "安全/可达性扫描" 0
else
  log_result "安全/可达性扫描" 1
  cat "$SECURITY_LOG"
fi

# ---------- 汇总报告 ----------
cat > "$REPORT" <<EOF
# 四道门禁报告

- 时间: $(date '+%Y-%m-%d %H:%M:%S')
- 项目: yuesheng-flutter

| 门禁 | 结果 |
|------|------|
| 静态分析 (dart analyze lib) | $([ -s "$TYPECHECK_LOG" ] && grep -q ' error ' "$TYPECHECK_LOG" && echo FAIL || echo PASS) |
| 单元测试 (flutter test) | $([ -s "$TEST_LOG" ] && grep -qE 'Some tests failed|FAIL' "$TEST_LOG" && echo FAIL || echo PASS) |
| 循环依赖扫描 | $(grep -q 'OK:' "$CIRCULAR_LOG" && echo PASS || echo FAIL) |
| 安全/可达性扫描 | $(grep -q 'OK:' "$SECURITY_LOG" && echo PASS || echo FAIL) |

汇总: ${pass} 通过 / ${fail} 失败

## 详细日志
- 静态分析: outputs/gate/typecheck.txt
- 测试: outputs/gate/test.txt
- 循环依赖: outputs/gate/circular.txt
- 安全扫描: outputs/gate/security.txt
EOF

echo "=================================================="
echo "汇总: $pass 通过 / $fail 失败"
echo "报告: $REPORT"
echo "=================================================="

[ "$fail" -eq 0 ]
