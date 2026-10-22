#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""_selftest_check_pilot_surface.py — P1~P4 守卫负向验证。

★ 为什么必须有这个：守卫最常见的死法是**恒绿 = 静音**。
  本自测证明 6 个探针分别触发「该红的红 / 该绿的确绿」：

| 探针 | 注入 | 期望 | 验证的判据 |
|:--|:--|:--|
| P0 | 原状 | rc=0 | 现状不误报 |
| P1 | 呈现文件加 `item['h']`（引文原文键访问） | rc=1 | P1 不呈明细 |
| P2 | 呈现文件加 `syndromeId` | rc=1 | P2 不含症候维度 |
| P3 | prompt 链文件加 pilot 引用 | rc=1 | P3 零流入 prompt |
| P4 | 呈现文件加 `cardWallEntered` | rc=1 | P4 停写类不呈 |
| P5 | 全部复原 | rc=0 | 探针无污染 |

★ 探针全部在**副本树**上做（不碰真源）⇒ 不污染仓库。
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "scripts" / "check_pilot_surface.py"

# 守卫要读的全部文件（探针树须同构）
GUARD_FILES = [
    "lib/services/pilot_metrics_summary.dart",
    "lib/features/growth/pilot_metrics_card.dart",
    "lib/services/chat_service.dart",
    "lib/services/message_injector.dart",
    "lib/services/llm_circuit_breaker.dart",
    "lib/features/writing/writing_coach_panel_chat_runner.dart",
    "lib/features/writing/writing_coach_panel_session_controller.dart",
]

SUMMARY = "lib/services/pilot_metrics_summary.dart"
CHAT = "lib/services/chat_service.dart"

FAILS = []


def run(root: Path) -> tuple:
    p = subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(root)],
        capture_output=True, text=True, encoding="utf-8",
    )
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def check(name: str, cond: bool, detail: str = "") -> None:
    tag = "OK  " if cond else "FAIL"
    print("  [%s] %s%s" % (tag, name, ("  ← " + detail) if detail and not cond else ""))
    if not cond:
        FAILS.append(name)


def make_copy(tmp: Path) -> Path:
    """把守卫要读的文件复制成可改的副本树。"""
    root = tmp / "repo"
    for rel in GUARD_FILES:
        s = REPO / rel
        d = root / rel
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(s, d)
    return root


def append(path: Path, line: str) -> None:
    with path.open("a", encoding="utf-8") as f:
        f.write("\n" + line + "\n")


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        root = make_copy(Path(td))

        rc, out = run(root)
        check("P0 原状 ⇒ rc=0", rc == 0, out)

        append(root / SUMMARY, "final leak = item['h']; // 探针：引文原文键")
        rc, out = run(root)
        check("P1 呈现文件访问 ['h'] ⇒ rc=1", rc == 1 and "P1" in out, out)

        (root / SUMMARY).write_text(
            (root / SUMMARY).read_text(encoding="utf-8").replace("item['h'];", "item['k'];"),
            encoding="utf-8",
        )
        append(root / SUMMARY, "final syn = syndromeId; // 探针：症候 ID")
        rc, out = run(root)
        check("P2 呈现文件含 syndromeId ⇒ rc=1", rc == 1 and "P2" in out, out)

        (root / SUMMARY).write_text(
            (root / SUMMARY).read_text(encoding="utf-8").replace("final syn = syndromeId; // 探针：症候 ID\n", ""),
            encoding="utf-8",
        )
        append(root / CHAT, "// 探针：pilot 数据流入 prompt 构造链")
        rc, out = run(root)
        check("P3 prompt 链出现 pilot ⇒ rc=1", rc == 1 and "P3" in out, out)

        (root / CHAT).write_text(
            (root / CHAT).read_text(encoding="utf-8").replace("// 探针：pilot 数据流入 prompt 构造链\n", ""),
            encoding="utf-8",
        )
        append(root / SUMMARY, "const e = PilotEventTypes.cardWallEntered; // 探针")
        rc, out = run(root)
        check("P4 呈现文件引用停写常量 ⇒ rc=1", rc == 1 and "P4" in out, out)

        (root / SUMMARY).write_text(
            (root / SUMMARY).read_text(encoding="utf-8").replace("const e = PilotEventTypes.cardWallEntered; // 探针\n", ""),
            encoding="utf-8",
        )
        rc, out = run(root)
        check("P5 全部复原 ⇒ rc=0", rc == 0, out)

    print()
    if FAILS:
        print(f"自测 FAIL：{len(FAILS)} 个探针未过——{FAILS}")
        return 1
    print("自测 PASS：6/6 探针（守卫该红的红、该绿的绿，副本零污染）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
