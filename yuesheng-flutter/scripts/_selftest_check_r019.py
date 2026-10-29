#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""_selftest_check_r019.py —— `tool/check_r019.py` 签名判据的负向验证 + 判据强度自检。

★ 为什么必须有这个（`T-20261029-01`）
=====================================
门禁 5 的头号死法是**静默失明**：签名正则匹配失败时，函数不是「少算行数」，
而是**整条从统计中消失** —— 报出来的数字照样「无超限 ✓」，零告警。

实证：`T-20261027-06` 把 `_streamLlm` 的返回类型从记录类型改成 `Future<StreamOutcome>`，
它才**第一次**被看见（140 行）。⇒ 修之前，「把签名改成记录类型」是一条
**可被无意踩中的逃逸口**。

探针
====
| 探针 | 注入（临时目录，不碰真源） | 期望 |
|:--|:--|:--|
| A1 | `Future<({String a, bool b})> _probeRecord()` + 60 行体 | 报出 |
| A2 | `Future<Map<String, int>> _probeGeneric()` + 60 行体 | 报出（旧版已支持，防回归） |
| A3 | `(int, String) _probePositional()` + 60 行体 | 报出 |
| A4 | 同 A1 形态但只有 20 行 | **不**报（不误报） |
| A5 | 参数含 `required void Function(int) cb,` + 一条调用行 | 只报外层 1 个（过滤仍生效） |
| A6 | 全库真源，**旧正则** vs **新正则** 两次扫描 | 旧结果 ⊆ 新结果（不少报）且新增非空 |

★ A6 用**旧正则现算**而不是钉死一份清单：钉清单会在债务清偿后腐化成假红。
  旧正则由本脚本从**当前源码**做两处字符串还原得到（还原失败即 assert 报错，
  fail-closed）—— 它同时说明「本修复改的恰好是这两处」。

强度自检（V1）
==============
把 ret 字符类里的 `(){}` 删掉（= 还原成旧形态），跑同一套夹具 ⇒ **A1 / A3 必须变红**。
若仍全绿，说明本自测对「判据被改回去」没有鉴别力，等于装饰。

用法
====
    python scripts/_selftest_check_r019.py

退出码：0 = 全过；1 = 有探针/变体未过。
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

REPO = Path(__file__).resolve().parent.parent
CHECKER = REPO / "tool" / "check_r019.py"
LIMIT = 50

# 修复前 / 后的两处源码形态（A6 与 V1 都靠它们做还原）
RET_NEW = "(?P<ret>[\\w<>?,\\s\\[\\](){}]{1,60}?)"
RET_OLD = "(?P<ret>[\\w<>?,\\s\\[\\]]{1,60}?)"
PAREN_NEW = "open_paren = m.end() - 1"
PAREN_OLD = "open_paren = line.index('(', m.start())"


def run_checker(checker: Path, target: Path, json_out: Path | None = None):
    """跑一次扫描，返回 (rc, 命中列表)。命中列表来自 --json（全量，非基线过滤）。"""
    cmd = [sys.executable, str(checker), "--dir", str(target), "--limit", str(LIMIT)]
    if json_out is not None:
        cmd += ["--json", str(json_out)]
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    proc = subprocess.run(cmd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", env=env)
    hits = []
    if json_out is not None and Path(json_out).exists():
        hits = json.loads(Path(json_out).read_text(encoding="utf-8"))["violations"]
    return proc.returncode, hits


def long_fn(sig_line: str, total: int) -> str:
    """构造 total 行的函数：签名 1 行 + 体内 total-2 行 + 收尾 `}`。"""
    body = ["  var v%d = %d;" % (i, i) for i in range(total - 2)]
    return "\n".join([sig_line] + body + ["}"])


def write_case(root: Path, name: str, text: str) -> Path:
    d = root / name
    d.mkdir(parents=True, exist_ok=True)
    (d / "probe.dart").write_text(text, encoding="utf-8", newline="\n")
    return d


def variant_src(tmp: Path, tag: str, ret: str, paren: str):
    """从当前源码还原出指定变体；还原失败返回 (None, 原因) —— 不抛，交给调用方记账。

    还原失败本身就是一条**判据腐化**信号（源码形态变了，本自测的对照失效），
    ⇒ 不能静默跳过（那是恒绿），必须作为失败项报出。
    """
    src = CHECKER.read_text(encoding="utf-8")
    if RET_NEW not in src:
        return None, "源码里找不到新版 ret 字符类（本自测的对照失效，须同步更新）"
    if PAREN_NEW not in src:
        return None, "源码里找不到新版 open_paren 取法（须同步更新）"
    out = tmp / ("variant_%s.py" % tag)
    out.write_text(src.replace(RET_NEW, ret).replace(PAREN_NEW, paren),
                   encoding="utf-8", newline="\n")
    return out, ""


def names(hits) -> list:
    return sorted("%s:%s" % (h["file"].split("/")[-1], h["func"]) for h in hits)


def main() -> int:
    failures = []
    with tempfile.TemporaryDirectory(prefix="r019_selftest_") as td:
        tmp = Path(td)

        # ── A1–A5 夹具探针（同一套夹具对「当前检查器」跑一次）──
        cases = {
            "A1": long_fn("Future<({String a, bool b})> _probeRecord() {", 60),
            "A2": long_fn("Future<Map<String, int>> _probeGeneric() {", 60),
            "A3": long_fn("(int, String) _probePositional() {", 60),
            "A4": long_fn("Future<({String a, bool b})> _probeShort() {", 20),
            "A5": long_fn("void _probeOuter({\n  required void Function(int) cb,\n}) {", 60)
            + "\n\nvoid _probeCaller() {\n  _probeOuter(cb: (x) => x);\n}\n",
        }
        dirs = {k: write_case(tmp, k, v) for k, v in cases.items()}
        got = {}
        for k, d in dirs.items():
            rc, hits = run_checker(CHECKER, d, tmp / ("%s.json" % k))
            got[k] = (rc, names(hits))

        def has(key, frag):
            return any(frag in n for n in got[key][1])

        if not has("A1", "_probeRecord"):
            failures.append("A1 记录返回类型未被报出（盲区仍在）")
        if not has("A2", "_probeGeneric"):
            failures.append("A2 泛型括号返回类型未被报出")
        if not has("A3", "_probePositional"):
            failures.append("A3 位置记录返回类型未被报出")
        if got["A4"][1]:
            failures.append("A4 误报：20 行函数被报出 %s" % got["A4"][1])
        if len(got["A5"][1]) != 1 or not has("A5", "_probeOuter"):
            failures.append("A5 误报：期望只报 _probeOuter，实得 %s" % got["A5"][1])

        # ── A6 全库：旧 ⊆ 新（不少报），且新增非空 ──
        old_checker, why = variant_src(tmp, "old", RET_OLD, PAREN_OLD)
        if old_checker is None:
            failures.append("A6 无法对照：%s" % why)
        else:
            _, hits_o = run_checker(old_checker, REPO / "lib", tmp / "lib_old.json")
            _, hits_n = run_checker(CHECKER, REPO / "lib", tmp / "lib_new.json")
            ko, kn = set(names(hits_o)), set(names(hits_n))
            lost = sorted(ko - kn)
            added = sorted(kn - ko)
            if lost:
                failures.append("A6 少报（旧有新无）%d 个：%s" % (len(lost), lost[:5]))
            # ★「新增非空」**不作判据**：存量清偿后必然为空，钉死会在还完债那天变假红。
            #   多报的鉴别力由 A1/A3 夹具负责（形态固定，不受存量影响）。
            print("A6 全库：旧 %d 条 / 新 %d 条；新增 %s%s" % (
                len(ko), len(kn), added, "" if added else "（存量已清，A1/A3 仍作判据）"))

        # ── V1 强度自检：把 ret 字符类还原成旧形态 ⇒ A1/A3 必须变红 ──
        broken, why = variant_src(tmp, "broken", RET_OLD, PAREN_NEW)
        if broken is None:
            failures.append("V1 无法执行：%s" % why)
        else:
            expect = {"A1": "_probeRecord", "A3": "_probePositional"}
            still_green = []
            for k, frag in expect.items():
                _, v_hits = run_checker(broken, dirs[k], tmp / ("v1_%s.json" % k))
                if any(frag in n for n in names(v_hits)):
                    still_green.append(k)
            if still_green:
                failures.append("V1 判据强度不足：还原旧正则后 %s 仍被报出"
                                "（本自测对「判据被改回去」无鉴别力）" % still_green)

    print("")
    for f in failures:
        print("  [FAIL] %s" % f)
    print("" if failures else "全过：A1–A6 探针 + V1 强度自检 ✓")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
