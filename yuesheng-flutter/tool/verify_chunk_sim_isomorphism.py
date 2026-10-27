#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""H7 同构校验：采样器喂给子代理的 prompt 必须等于**生产当前值**（T-20261027-01）。

三条判据（与卡面逐条对应，全部可红）
--------------------------------------
  J1 同构：`chunk_system_prompt_prod.txt` 与「现场重新导出的生产常量」**逐字节相同**。
     差异 ⇒ 报红并给首个差异行号（不同构时的典型原因：改了生产 prompt 忘了重导出）。
  J2 去写死：采样器源码里**偏向措辞**零命中（旧版的「宁缺勿滥」/「命中例外条款形态的
     **不判**」/「判据例外条款命中的判 miss」——它们系统性把子代理推向「不报」）。
  J3 可红性（★ 防 J1/J2 恒真）：把导出副本改**一个字符**后走**同一条**比较逻辑 ⇒
    必须报红。若 J3 也绿，说明 J1 的判据根本没在看内容。

★ 为什么 J3 必须存在
  本仓已多次踩「判据恒真」：比较函数若因路径错/读空串而恒等，J1 会永远绿，
  而它本要防的「采样器与生产不同构」会照旧发生。J3 是这条判据的负向探针。

用法
----
    python tool/verify_chunk_sim_isomorphism.py           # 跑三条判据
    python tool/verify_chunk_sim_isomorphism.py --no-refresh
        （跳过 flutter test 重导出，直接拿现有文件比 —— 仅用于离线排查）

退出码：0 = 三条全 PASS；1 = 任一 FAIL；2 = 环境错误（导出失败/文件缺失）。
"""

from __future__ import annotations

import argparse
import ast
import os
import shutil
import subprocess
import sys
import tempfile

BASE = "D:/ai-teacher/.ai/research/cross-validation/data/chunk_sim"
PROMPT_REF = BASE + "/chunk_system_prompt_prod.txt"
FLUTTER_ROOT = "D:/ai-teacher/yuesheng-flutter"
DUMP_RUNNER = "tool/dump_chunk_prompt_runner.dart"
SAMPLER = os.path.join(FLUTTER_ROOT, "tool", "build_chunk_sim_tasks.py")

# 旧版写死的偏向措辞（判据 2 的检索词）。**只许减不许加**：
# 加词会把「中性的新表述」误判成偏向；减词会让已清掉的措辞悄悄回来。
BIAS_TERMS = (
    "宁缺勿滥",
    "命中例外条款形态的",
    "判据例外条款命中的判 miss",
)


def _flat(p: str) -> str:
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def _first_diff_line(a: str, b: str):
    """返回首个差异行号（1-based）与两侧内容；无差异返回 None。"""
    la, lb = a.split("\n"), b.split("\n")
    for i in range(max(len(la), len(lb))):
        x = la[i] if i < len(la) else "<EOF>"
        y = lb[i] if i < len(lb) else "<EOF>"
        if x != y:
            return i + 1, x[:80], y[:80]
    return None


def refresh(tmp_path: str) -> int:
    env = dict(os.environ)
    env["DUMP_OUT"] = tmp_path
    exe = os.environ.get("FLUTTER_BIN") or shutil.which("flutter") or "flutter"
    cmd = f'"{exe}" test {DUMP_RUNNER}'
    proc = subprocess.run(cmd, shell=True, cwd=FLUTTER_ROOT, env=env,
                          capture_output=True, text=True, encoding="utf-8",
                          errors="replace")
    if proc.returncode != 0:
        sys.stderr.write(f"ERROR: 生产 prompt 导出失败（rc={proc.returncode}）\n"
                         f"{(proc.stdout or '')[-600:]}\n")
        return 2
    if not os.path.isfile(tmp_path):
        sys.stderr.write(f"ERROR: 导出返回 0 但文件不存在：{tmp_path}\n")
        return 2
    return 0


def _string_literals(path: str) -> str:
    """取出源码里**会被拼进提示词**的字符串字面量（排除注释与 docstring）。

    ★ 口径为什么必须这样切（2026-10-27 实测）：直接 `grep` 源码会把
    「旧版写了什么」的**注释与 docstring** 也算命中 —— 而本文件正是靠
    「记下旧措辞」来防复发的（见 `build_chunk_sim_tasks.py` 头部说明）。
    用裸 grep 当判据 ⇒ **要么删掉这段防复发说明，要么永远红**，两条都坏。
    真正的判据是「喂给子代理的话术里有没有偏向措辞」⇒ 只看字符串字面量。
    """
    with open(path, encoding="utf-8") as fh:
        tree = ast.parse(fh.read())
    doc_nodes = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.FunctionDef,
                             ast.AsyncFunctionDef, ast.ClassDef)):
            body = getattr(node, "body", [])
            if body and isinstance(body[0], ast.Expr) \
                    and isinstance(body[0].value, ast.Constant) \
                    and isinstance(body[0].value.value, str):
                doc_nodes.add(id(body[0].value))
    parts = [n.value for n in ast.walk(tree)
             if isinstance(n, ast.Constant) and isinstance(n.value, str)
             and id(n) not in doc_nodes]
    return "\n".join(parts)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-refresh", action="store_true",
                    help="跳过 flutter test 重导出（离线排查用）")
    args = ap.parse_args()

    if not os.path.isfile(PROMPT_REF):
        sys.stderr.write(f"ERROR: 采样器的 prompt 文件不存在：{PROMPT_REF}\n"
                         f"       先跑 `python tool/build_chunk_sim_tasks.py --dry-run`\n")
        return 2

    tmpdir = tempfile.mkdtemp(prefix="h7_iso_")
    try:
        prod = os.path.join(tmpdir, "prod.txt")
        if args.no_refresh:
            shutil.copyfile(PROMPT_REF, prod)
            print("[J1] --no-refresh：用现有文件与自身比（**不证明同构**，仅供离线排查）")
        else:
            rc = refresh(prod)
            if rc != 0:
                return rc

        a = _flat(PROMPT_REF)
        b = _flat(prod)
        d = _first_diff_line(a, b)
        j1_ok = d is None and a == b
        print(f"[J1] 同构（采样器文件 vs 生产导出）：{'PASS' if j1_ok else 'FAIL'} "
              f"| 字符数 {len(a)} vs {len(b)}")
        if d:
            print(f"     首个差异行 {d[0]}:")
            print(f"       采样器: {d[1]}")
            print(f"       生产  : {d[2]}")

        src = _string_literals(SAMPLER)
        hits = [(t, src.count(t)) for t in BIAS_TERMS if t in src]
        j2_ok = not hits
        print(f"[J2] 偏向措辞零命中：{'PASS' if j2_ok else 'FAIL'} "
              f"| 检索词 {len(BIAS_TERMS)} 个")
        for term, cnt in hits:
            print(f"     命中 {cnt} 次：{term}")

        # J3：把副本改一个字符，走**同一条**比较逻辑，必须报红
        mutated = b[:-1] + ("X" if b[-1:] != "X" else "Y")
        d3 = _first_diff_line(a, mutated)
        j3_ok = d3 is not None
        print(f"[J3] 可红性（生产 prompt 改一字符 ⇒ 必须报红）：{'PASS' if j3_ok else 'FAIL'}")
        if not j3_ok:
            print("     ★ 改了一字符仍判相同 ⇒ J1 的判据没在看内容（恒真）")

        print("-" * 60)
        ok = j1_ok and j2_ok and j3_ok
        print(f"结论：{'3/3 PASS' if ok else '未通过'}")
        return 0 if ok else 1
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
