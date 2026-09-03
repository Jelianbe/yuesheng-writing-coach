#!/usr/bin/env python3
"""
月笙 Flutter 端 — 循环依赖扫描（R-020 / AGENTS.md 六道门禁 门禁 3）。

独立出原 gate.sh 内嵌的 Python DFS 代码，供 CI / 本地 pre-commit 单独调用。

用法:
    python3 scripts/check_circular.py            # 默认扫描 ../lib (相对于脚本位置)
    python3 scripts/check_circular.py ROOT_DIR   # 指定 Flutter 工程根目录
退出码:
    0 = 未检测到循环依赖
    1 = 检测到循环依赖（详细打印环路径）
    2 = 环境错误：lib 目录不存在（**失败关闭**，绝不静默放行）

⚠️ 关于退出码 2（2026-09-03 实证）：此处原本在 lib 找不到时打印 SKIP 并
**return 0**——而 gate.sh 传的是 Git Bash 风格路径 `/d/ai-teacher/...`，
Windows 原生 python 解析不了，于是**门禁 3 从未真正扫描过任何文件**，
却每次都计入「通过」。这就是典型的**失败开放**：环境一出错，护栏直接
失效且不留痕迹。护栏的缺省必须是「拦下」，不是「放行」。
"""
import os
import re
import sys


def build_graph(lib_dir: str) -> dict[str, list[str]]:
    graph: dict[str, list[str]] = {}
    import_re = re.compile(r"^import\s+'([^']+)'", re.M)

    for dirpath, _, fnames in os.walk(lib_dir):
        for fname in fnames:
            if not fname.endswith('.dart'):
                continue
            path = os.path.join(dirpath, fname)
            rel = os.path.relpath(path, lib_dir).replace(os.sep, '/')[:-5]
            src = 'package:writingcoach/' + rel

            deps: list[str] = []
            with open(path, encoding='utf-8') as fh:
                for line in fh:
                    m = import_re.match(line.strip())
                    if not m:
                        continue
                    dep = m.group(1)
                    if dep.startswith('package:writingcoach/'):
                        deps.append(dep)
                    elif dep.startswith(('package:', 'dart:')):
                        # 外部依赖：与循环依赖无关，忽略
                        continue
                    else:
                        # 相对导入，三种写法都要建图：
                        #   `../x.dart`  `./x.dart`  以及**裸写** `x.dart`
                        # ⚠️ 裸写形式长久以来被漏掉（旧代码只认 `./` 和 `../`），
                        #    而本项目大量使用（`import 'app_theme.dart';` 等）——
                        #    实测 177 条边（占内部边 21.7%）不进图，等于在缺了
                        #    五分之一边的图上做环检测。2026-09-03 实证：两个文件
                        #    互相 `import 'b.dart'` / `import 'a.dart'`，
                        #    脚本仍报 "no circular imports"。
                        base = os.path.dirname(path)
                        resolved = os.path.normpath(
                            os.path.join(base, dep)).replace(os.sep, '/')
                        rel2 = os.path.relpath(resolved, lib_dir).replace(
                            os.sep, '/')
                        if rel2.endswith('.dart'):
                            rel2 = rel2[:-5]
                        deps.append('package:writingcoach/' + rel2)
            graph[src] = deps
    return graph


def find_cycles(graph: dict[str, list[str]]) -> list[list[str]]:
    WHITE, GRAY, BLACK = 0, 1, 2
    color: dict[str, int] = {k: WHITE for k in graph}
    cycles: list[list[str]] = []

    def dfs(node: str, stack: list[str]) -> None:
        color[node] = GRAY
        for dep in graph.get(node, []):
            if dep not in graph:
                continue
            if color[dep] == GRAY:
                idx = stack.index(dep) if dep in stack else 0
                cycles.append(stack[idx:] + [dep])
            elif color[dep] == WHITE:
                dfs(dep, stack + [dep])
        color[node] = BLACK

    for node in sorted(graph):
        if color[node] == WHITE:
            dfs(node, [node])
    return cycles


def cycle_key(cycle: list[str]) -> str:
    """环的稳定标识。

    同一组文件形成的环，DFS 从不同节点出发会得到不同的旋转表示
    （A->B->A 与 B->A->B），直接比列表会误判成两个不同的环。
    取**字典序最小的旋转**作为 key，使同一个环恒有同一标识。
    """
    nodes = cycle[:-1] if len(cycle) > 1 else cycle
    if not nodes:
        return ''
    rots = [tuple(nodes[i:] + nodes[:i]) for i in range(len(nodes))]
    return '|'.join(min(rots))


def _dump(path: str, graph: dict[str, list[str]]) -> None:
    """基线落盘：始终写**全量**环，不受 --baseline 过滤影响。"""
    import json

    all_cycles = find_cycles(graph)
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump({'cycles': [cycle_key(c) for c in all_cycles],
                   'detail': all_cycles}, fh, indent=2, ensure_ascii=False)


def main() -> int:
    import argparse
    import json

    ap = argparse.ArgumentParser(description='循环依赖扫描（R-020）')
    ap.add_argument('root', nargs='?', default='',
                    help='Flutter 工程根目录；省略则用脚本位置的父目录')
    ap.add_argument('--baseline', default='',
                    help='基线 JSON；给出后只报基线之外的新增环（止血模式）。'
                         '与 R-019 的 --baseline 同构：存量豁免、只卡新增。')
    ap.add_argument('--json', default='', help='结果落盘 JSON 路径')
    args = ap.parse_args()

    root = args.root or os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))
    lib = os.path.join(root, 'lib')
    if not os.path.isdir(lib):
        # 失败关闭：lib 找不到 = 调用方式或环境有问题，必须让门禁变红。
        # 旧行为 return 0（静默放行）曾让本门禁长期假绿而无人察觉。
        print(f'ERROR: lib not found at {lib}')
        print('  → 若由脚本调用，请传工程根目录；'
              '在 Git Bash 下不要传 `/d/...` 这类 POSIX 路径'
              '（Windows 原生 python 无法解析），传 "." 即可。')
        return 2

    graph = build_graph(lib)
    cycles = find_cycles(graph)

    # 止血模式：存量环豁免，只报新增（与 R-019 同构）
    #
    # 2026-09-03：修好「裸相对导入不进图」的缺陷后，本门禁立刻暴露出 3 个
    # 真实存在的存量环（Dart 允许循环 import，故此前从未出过任何问题）。
    # 它们都在核心模块（Skill 注入链路 / providers），按 AGENTS.md 须先写
    # ADR 才能动。为了让门禁**立刻生效**又不阻塞日常提交，先走止血模式：
    # 存量 3 个环登记进基线，此后**任何新增环一律拦截**。
    # ⚠️ 同 R-019 的教训：豁免基线不会自己变严，每解开一个环必须重生成基线。
    baseline_keys: set[str] = set()
    if args.baseline and os.path.isfile(args.baseline):
        with open(args.baseline, encoding='utf-8') as fh:
            baseline_keys = set(json.load(fh).get('cycles', []))
        cycles = [c for c in cycles if cycle_key(c) not in baseline_keys]

    if cycles:
        print(f'FAIL: detected {len(cycles)} circular import cycle(s)'
              + ('（基线外新增）' if args.baseline else ''))
        for c in cycles[:20]:
            print('  -> ' + ' -> '.join(c))
        if args.json:
            # ⚠️ 落盘一律**全量**（R-019 V4.14 的教训）：cycles 此时已被基线
            # 过滤过，若直接落它，重生成基线就等于把存量环一笔勾销。
            _dump(args.json, graph)
            print('  （--json 落的是全量结果，非过滤后）')
        return 1
    if args.json:
        _dump(args.json, graph)
    if args.baseline:
        print('OK: no new circular imports in lib '
              f'({len(graph)} modules，基线豁免 {len(baseline_keys)} 个存量环)')
    else:
        print(f'OK: no circular imports in lib ({len(graph)} modules，全量卡口)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
