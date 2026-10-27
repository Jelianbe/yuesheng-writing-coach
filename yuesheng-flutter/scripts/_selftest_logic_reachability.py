#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""逻辑面可达性读数的负向自检（T-20261024-13 · C-4）。

为什么要有这个文件
------------------
C-4 的读数是「**读数**不是判据」：不设条数基线、不判红。这带来一个结构性风险 ——
**读数坏掉时和「全绿」长得一模一样**（清单恒空、或恒非空）。所以本自检不验
「读数对不对」，只验它**能不能变**：

  P1 正常分离：可达文件不进 A、零可达文件进 A（两类必须各取到一条）
  P2 孤儿文件必须进 A —— 证明读数不是恒空（★ 最关键的一条）
  P3 test 目录为空 ⇒ `main` 必须 rc=2（「空扫不是通过」，与 lcov 缺失同族纪律）
  P4 生成物（`.g.dart`）不进读数 —— 排除规则生效，否则分母被噪声污染
  P5 `part` 分片随属主可达 —— 2026-10-27 实测：不加 part 边时 A 读数 51 个，
     而 `lib/` 下 `^part of` 文件恰好也是 51 个 ⇒ 读数 100% 是假象

★ 探针全部在临时目录里构造，**不碰真仓**（真仓零污染）。

用法：`python scripts/_selftest_logic_reachability.py`
退出码：0 = 全部 PASS；1 = 有探针失败。
"""

from __future__ import annotations

import importlib.util
import os
import shutil
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load_module():
    path = os.path.join(_HERE, "check_coverage.py")
    spec = importlib.util.spec_from_file_location("_cc_under_test", path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    # ★ 必须先登记进 sys.modules：Python 3.14 的 @dataclass 会回查
    #   sys.modules[cls.__module__]，未登记 ⇒ AttributeError: 'NoneType' object
    #   该错误信息完全指不到根因（看起来像 dataclass 自己的 bug）。
    sys.modules["_cc_under_test"] = mod
    spec.loader.exec_module(mod)
    return mod


def _write(root: str, rel: str, content: str) -> None:
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(content)


def _fixture(root: str, with_orphan: bool, with_generated: bool) -> None:
    _write(root, "lib/services/a.dart",
           "class Alpha {\n  int v = 1;\n}\n")
    _write(root, "lib/services/b.dart",
           "import 'package:writingcoach/services/a.dart';\n\n"
           "class Beta {\n  final Alpha a = Alpha();\n}\n")
    _write(root, "test/b_test.dart",
           "import 'package:writingcoach/services/b.dart';\n\n"
           "void main() {\n  print(Beta());\n}\n")
    if with_orphan:
        _write(root, "lib/services/_probe_nobody.dart",
               "class NobodyWatchesThis {\n  int v = 0;\n}\n")
    if with_generated:
        _write(root, "lib/services/thing.g.dart",
               "class GeneratedThing {\n  int v = 0;\n}\n")


def _run(mod, root: str):
    return mod.logic_face_report(root)


def main() -> int:
    mod = _load_module()
    results = []

    tmp = tempfile.mkdtemp(prefix="t13c4_selftest_")
    try:
        # ---- P1 正常分离 -------------------------------------------------
        root1 = os.path.join(tmp, "p1")
        _fixture(root1, with_orphan=False, with_generated=False)
        rep1 = _run(mod, root1)
        ok = (rep1["zero_reach"] == []
              and "lib/services/a.dart" in rep1["reach_no_symbol"]
              and rep1["logic_total"] == 2
              and rep1["test_files"] == 1)
        results.append(("P1 正常分离（可达/软读数各一条，A 为空）", ok, rep1))

        # ---- P2 孤儿文件必须进 A ----------------------------------------
        root2 = os.path.join(tmp, "p2")
        _fixture(root2, with_orphan=True, with_generated=False)
        rep2 = _run(mod, root2)
        ok = rep2["zero_reach"] == ["lib/services/_probe_nobody.dart"]
        results.append(("P2 孤儿文件必进 A（读数非恒空）", ok, rep2))

        # ---- P3 空扫 ⇒ rc=2 ---------------------------------------------
        root3 = os.path.join(tmp, "p3")
        _fixture(root3, with_orphan=False, with_generated=False)
        shutil.rmtree(os.path.join(root3, "test"))
        rc = mod.main(["--lcov", os.path.join(root3, "no_such_lcov.info"),
                       "--repo-root", root3])
        results.append(("P3 test 为空 ⇒ rc=2（空扫不是通过）", rc == 2, {"rc": rc}))

        # ---- P4 生成物不进读数 ------------------------------------------
        root4 = os.path.join(tmp, "p4")
        _fixture(root4, with_orphan=False, with_generated=True)
        rep4 = _run(mod, root4)
        ok = (rep4["logic_total"] == 2
              and all("thing.g.dart" not in p for p in rep4["zero_reach"])
              and all("thing.g.dart" not in p for p in rep4["reach_no_symbol"]))
        results.append(("P4 生成物 .g.dart 不进读数", ok, rep4))

        # ---- P5 part 分片随属主可达 --------------------------------------
        root5 = os.path.join(tmp, "p5")
        _write(root5, "lib/services/owner.dart",
               "part 'piece.dart';\n\nclass Owner {\n  int v = 1;\n}\n")
        _write(root5, "lib/services/piece.dart",
               "part of 'owner.dart';\n\nclass Piece {\n  int v = 2;\n}\n")
        _write(root5, "test/owner_test.dart",
               "import 'package:writingcoach/services/owner.dart';\n\n"
               "void main() {\n  print(Owner());\n}\n")
        rep5 = _run(mod, root5)
        ok = rep5["zero_reach"] == []
        results.append(("P5 part 分片随属主可达（防 part 假象回归）", ok, rep5))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("=" * 68)
    print("逻辑面可达性读数 · 负向自检（T-20261024-13 C-4）")
    print("=" * 68)
    failed = 0
    for name, ok, detail in results:
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
        if not ok:
            failed += 1
            print(f"         实测：{detail}")
    print("-" * 68)
    print(f"结果：{len(results) - failed}/{len(results)} PASS")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
