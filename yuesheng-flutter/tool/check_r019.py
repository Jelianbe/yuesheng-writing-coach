# -*- coding: utf-8 -*-
"""R-019 函数行数扫描（只测不拆）。

背景
----
R-019 规定**函数 ≤ 50 行**（硬上限，比文件 300 行更重要），但四道门禁
（format / analyze / test / circular）**没有一道检查它** —— 这是 R-019 长期
处于「已登记债务」状态却无人门禁的原因之一。本脚本补上这个测量能力。

注意：本脚本**不做任何拆分**。仓库历史上曾有 `tool/r019_split.py`（part 分片
+ 逐字节保真），但该做法已被 X-025-ARCH 定性为**伪拆分**并回退 13 个 commit，
其 .py 已删（仅剩 __pycache__ 产物）。AGENTS.md 现明令：
  真分解 = 独立类 / 显式接口 / 依赖注入 / 职责级重构。

实现要点
--------
括号配平必须**字符串/注释感知**：Dart 函数体里常见
`{'a': 1}`、`'${x}'`、`// }` 等，裸配平会把这些当成块边界。
做法：先把源码逐字符扫描，生成等长「掩码」——字符串与注释区间内的字符
替换为空格（保留换行以维持行号），再在掩码上做配平与签名匹配。

用法
----
    python tool/check_r019.py                 # 扫 lib/，阈值 50
    python tool/check_r019.py --limit 60      # 自定义阈值
    python tool/check_r019.py --dir lib/services
    python tool/check_r019.py --top 30        # 只显示最严重的 N 个
    python tool/check_r019.py --json out.json # 落盘（给台账/ADR 用）
    # 债务止血模式：存量豁免，只卡新增（推荐接门禁的方式）
    python tool/check_r019.py --baseline tool/r019_baseline.json

退出码：无超限 → 0；有超限 → 1（可接入 gate.sh）。

基线文件 `tool/r019_baseline.json` 已入库——注意 `outputs/` 被 .gitignore
（.gitignore:75），基线不能放那里，否则门禁在别人机器上取不到。
"""
import argparse
import collections
import io
import json
import os
import re
import sys

DEFAULT_LIMIT = 50

# 控制流关键字：出现在 `(` 之前的标识符若命中，说明这不是函数签名
CONTROL_KEYWORDS = {
    'if', 'else', 'for', 'while', 'switch', 'try', 'catch', 'finally',
    'do', 'return', 'await', 'assert', 'yield', 'when',
}

# 函数签名（在掩码行上匹配）
#
# 性能陷阱（本脚本首版踩到，扫 507 个文件跑了 15 分钟仍未结束）：
# 掩码把字符串/注释内容替换成**空格**后，原本很长的字符串字面量行会变成
# 超长空白行；若 ret 段写成 `[\w<>?,\s\[\]]+?`，`\s` 会在这些空白上反复
# 回溯 → 灾难性回溯。
# 三重防护：① ret 段限长 {1,60}?；② 调用方跳过超长行；③ 行内必须有 `(`。
SIG_RE = re.compile(
    r'^(?P<indent>[ \t]*)'
    r'(?:(?:static|external|abstract|final|const|late)\s+)*'
    r'(?P<ret>[\w<>?,\s\[\]]{1,60}?)\s+'
    r'(?P<name>[A-Za-z_$][\w$]*)'
    r'(?P<generics><[^>]*>)?\s*'
    r'\('
)

# 掩码行超过此长度直接跳过：函数签名不可能这么长，
# 超长的几乎都是被掩码掏空的长字符串行（灾难性回溯的温床）
MAX_SIG_LINE = 300


def build_mask(src):
    """生成等长掩码：字符串与注释区间置为空格（保留换行以维持行号）。"""
    n = len(src)
    mask = [' '] * n
    i = 0
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ''

        # 行注释
        if c == '/' and nxt == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue
        # 块注释（可嵌套）
        if c == '/' and nxt == '*':
            depth = 1
            i += 2
            while i < n and depth > 0:
                if src[i] == '/' and i + 1 < n and src[i + 1] == '*':
                    depth += 1
                    i += 2
                elif src[i] == '*' and i + 1 < n and src[i + 1] == '/':
                    depth -= 1
                    i += 2
                else:
                    if src[i] != '\n':
                        mask[i] = ' '
                    i += 1
            continue
        # 三引号字符串
        triple = None
        for q in ("'''", '"""'):
            if src.startswith(q, i):
                triple = q
                break
        if triple:
            i += 3
            while i < n and not src.startswith(triple, i):
                if src[i] == '\\':
                    i += 2
                    continue
                if src[i] != '\n':
                    mask[i] = ' '
                i += 1
            i += 3
            continue
        # 单引号 / 双引号字符串（含 Dart raw 前缀 r'...'）
        if c in ('"', "'") or (c == 'r' and nxt in ('"', "'")):
            if c == 'r':
                i += 1
                c = src[i]
            i += 1
            while i < n and src[i] != c:
                if src[i] == '\\':
                    i += 2
                    continue
                if src[i] != '\n':
                    mask[i] = ' '
                i += 1
            i += 1
            continue

        mask[i] = c
        i += 1
    return ''.join(mask)


def match_block(mask, open_idx, o='{', c='}'):
    """从掩码上的开括号位置配平到对应的闭括号，返回闭括号下标；不配对返回 -1。"""
    depth = 0
    i = open_idx
    n = len(mask)
    while i < n:
        if mask[i] == o:
            depth += 1
        elif mask[i] == c:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


# 参数列表配平后允许出现的修饰符（其后必须跟 `{`）
BODY_PREFIX_RE = re.compile(r'^(?:async|sync\*|sync)\s*\{')


def scan_file(path, limit):
    """返回该文件内超过 limit 行的函数清单。"""
    with io.open(path, encoding='utf-8', errors='replace') as f:
        src = f.read()
    mask = build_mask(src)
    lines = mask.split('\n')

    # 行首偏移表，便于 下标 -> (行号, 列号)
    offsets = []
    pos = 0
    for ln in lines:
        offsets.append(pos)
        pos += len(ln) + 1

    def line_of(idx):
        lo, hi = 0, len(offsets) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if offsets[mid] <= idx:
                lo = mid
            else:
                hi = mid - 1
        return lo + 1  # 1-based

    results = []
    for ln_no, line in enumerate(lines, start=1):
        # 预筛（顺序即成本，从最便宜的开始）
        if '(' not in line:
            continue
        if len(line) > MAX_SIG_LINE:
            continue
        if '=>' in line:
            continue
        m = SIG_RE.match(line)
        if not m:
            continue
        name = m.group('name')
        if name in CONTROL_KEYWORDS:
            continue
        # 误报过滤（首版实测踩到）：
        #   `required void Function(String) markStage,` —— 函数**类型参数**被
        #   当成签名（name 落到 `Function` 上）。两条判据：
        #   ① 函数名叫 Function；② 行以 `,` 结尾（签名行不会以逗号收尾）
        if name == 'Function':
            continue
        if line.rstrip().endswith(','):
            continue
        # `(` 之后必须能找到 `{`（签名行或之后几行），且不能以 `;` 或 `=>` 收尾
        open_paren = line.index('(', m.start())
        tail = line[open_paren:]
        if '=>' in tail or tail.rstrip().endswith(';'):
            continue

        # 区分「函数定义」与「函数调用」（最关键的一条判据）:
        #   定义 —— `Future<void> foo(...) async {`，参数列表配平后紧跟 `{`
        #   调用 —— `await customStatement('...');`，配平后紧跟 `;`
        # 首版缺这条，把 onCreate 回调里的 `await customStatement(` 当成定义，
        # 报出「402 行」的假冠军。
        close_paren = match_block(
            mask, offsets[ln_no - 1] + open_paren, o='(', c=')')
        if close_paren == -1:
            continue
        after = mask[close_paren + 1: close_paren + 80].lstrip()
        if after.startswith('{'):
            brace_idx = close_paren + 1 + (
                len(mask[close_paren + 1: close_paren + 80])
                - len(mask[close_paren + 1: close_paren + 80].lstrip()))
        elif BODY_PREFIX_RE.match(after):
            brace_idx = mask.index('{', close_paren)
        else:
            continue  # 不是定义（调用 / 声明 / 类型参数等）
        end_idx = match_block(mask, brace_idx, o='{', c='}')
        if end_idx == -1:
            continue
        end_line = line_of(end_idx)
        n_lines = end_line - ln_no + 1
        if n_lines > limit:
            results.append({
                'file': path.replace('\\', '/'),
                'func': name,
                'start': ln_no,
                'end': end_line,
                'lines': n_lines,
            })
    return results


def main():
    ap = argparse.ArgumentParser(description='R-019 函数行数扫描（只测不拆）')
    ap.add_argument('--dir', default='lib', help='扫描目录（默认 lib）')
    ap.add_argument('--limit', type=int, default=DEFAULT_LIMIT, help='行数阈值（默认 50）')
    ap.add_argument('--top', type=int, default=0, help='只显示最严重的 N 个（0=全部）')
    ap.add_argument('--json', default='', help='结果落盘 JSON 路径')
    ap.add_argument(
        '--baseline', default='',
        help='基线 JSON；给出后**只报基线之外的新增项**（债务止血模式：'
             '不追溯存量，只阻止继续恶化）。key 取 `file:func`，'
             '不取行号，避免无关改动导致行号漂移而误报。')
    args = ap.parse_args()

    all_hits = []
    file_count = 0
    for root, dirs, files in os.walk(args.dir):
        dirs[:] = [d for d in dirs if d not in ('.git', 'build', '.dart_tool')]
        for fn in files:
            if not fn.endswith('.dart'):
                continue
            file_count += 1
            if file_count % 100 == 0:
                # 进度输出：首版跑了 15 分钟无任何输出，看起来像挂死
                print('  ...已扫 %d 个文件，累计命中 %d'
                      % (file_count, len(all_hits)), flush=True)
            all_hits.extend(scan_file(os.path.join(root, fn), args.limit))

    # 债务止血模式：只报基线之外的新增项
    #
    # key 取 `file:func`，**不取行号**（无关改动会让行号漂移而误报）。
    # 但同一文件里可能有同名函数（如一个 .dart 内多个 Widget 的 build），
    # 所以按**计数**比较而非集合去重——首版用集合去重，264 条被并成 216 个 key，
    # 48 个同名函数互相顶掉，新增的同名函数会被误判为「存量」而漏报。
    baseline_total = 0
    if args.baseline:
        with io.open(args.baseline, encoding='utf-8') as f:
            base = json.load(f)
        base_counter = collections.Counter(
            '%s:%s' % (v['file'], v['func']) for v in base['violations'])
        baseline_total = sum(base_counter.values())

        cur_counter = collections.Counter(
            '%s:%s' % (h['file'], h['func']) for h in all_hits)
        # 每个 key 取「超出的条数」里最长的几条作为新增
        extra_needed = {
            k: max(0, cur_counter[k] - base_counter.get(k, 0))
            for k in cur_counter
        }
        kept = []
        by_key = {}
        for h in all_hits:
            by_key.setdefault('%s:%s' % (h['file'], h['func']), []).append(h)
        for k, need in extra_needed.items():
            if need <= 0:
                continue
            kept.extend(
                sorted(by_key[k], key=lambda r: -r['lines'])[:need])
        all_hits = kept

    all_hits.sort(key=lambda r: -r['lines'])
    shown = all_hits[:args.top] if args.top else all_hits

    mode = ('止血模式（基线 %s，存量 %d 个豁免，只报新增）'
            % (args.baseline, baseline_total)) if args.baseline else '全量模式'
    print('=' * 68)
    print('R-019 函数行数扫描：目录=%s  阈值=%d 行  文件数=%d'
          % (args.dir, args.limit, file_count))
    print('模式：%s' % mode)
    print('=' * 68)
    if not all_hits:
        print('无超限函数 ✓')
    else:
        print('超 %d 行的函数：%d 个（按行数降序%s）'
              % (args.limit, len(all_hits),
                 '，显示前 %d' % args.top if args.top else ''))
        print('')
        print('%-8s %-6s %-40s %s' % ('行数', '起行', '函数', '文件'))
        print('-' * 68)
        for r in shown:
            print('%-8d %-6d %-40s %s:%d'
                  % (r['lines'], r['start'], r['func'][:40],
                     r['file'], r['start']))

        # 按文件聚合
        by_file = {}
        for r in all_hits:
            by_file.setdefault(r['file'], []).append(r)
        print('')
        print('按文件聚合（超限函数数 ≥ 2 的）：')
        for f, rs in sorted(by_file.items(), key=lambda kv: -len(kv[1])):
            if len(rs) < 2:
                continue
            print('  %-58s %d 个（最长 %d 行）'
                  % (f, len(rs), max(x['lines'] for x in rs)))

    if args.json:
        with io.open(args.json, 'w', encoding='utf-8') as f:
            f.write(json.dumps({
                'dir': args.dir, 'limit': args.limit,
                'fileCount': file_count, 'violations': all_hits,
            }, ensure_ascii=False, indent=2))
        print('\n已落盘：%s' % args.json)

    return 1 if all_hits else 0


if __name__ == '__main__':
    sys.exit(main())
