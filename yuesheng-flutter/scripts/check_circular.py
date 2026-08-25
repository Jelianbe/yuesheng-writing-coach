#!/usr/bin/env python3
"""
月笙 Flutter 端 — 循环依赖扫描（§二.4 / AGENTS.md 四闸 闸3）。

独立出原 gate.sh 内嵌的 Python DFS 代码，供 CI / 本地 pre-commit 单独调用。

用法:
    python3 scripts/check_circular.py            # 默认扫描 ../lib (相对于脚本位置)
    python3 scripts/check_circular.py ROOT_DIR   # 指定 Flutter 工程根目录
退出码:
    0 = 未检测到循环依赖
    1 = 检测到循环依赖（详细打印环路径）
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
                    elif dep.startswith('./') or dep.startswith('../'):
                        base = os.path.dirname(path)
                        resolved = os.path.normpath(os.path.join(base, dep)).replace(os.sep, '/')
                        rel2 = os.path.relpath(resolved, lib_dir).replace(os.sep, '/')
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


def main() -> int:
    if len(sys.argv) >= 2:
        root = sys.argv[1]
    else:
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    lib = os.path.join(root, 'lib')
    if not os.path.isdir(lib):
        print(f'SKIP: lib not found at {lib}')
        return 0

    graph = build_graph(lib)
    cycles = find_cycles(graph)

    if cycles:
        print(f'FAIL: detected {len(cycles)} circular import cycle(s):')
        for c in cycles[:20]:
            print('  -> ' + ' -> '.join(c))
        return 1
    print(f'OK: no circular imports in lib ({len(graph)} modules)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
