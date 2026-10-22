#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""_selftest_surface_visibility.py — S1 守卫（v4）负向验证。

★ 为什么必须有这个：守卫最常见的死法是**恒绿 = 静音**。
  本自测证明 6 个探针分别触发「该红的红 / 该绿的确绿」：

| 探针 | 注入 | 期望 | 验证的判据 |
|:--|:--|:--|:--|
| P0 | 原状 | rc=0 | 基线正常态不误报 |
| P1 | 真源 schema 加一个新字段（不进 DTO） | rc=1 | S1-1 检出「产出了没上卡」 |
| P2 | DTO 加一个真源未声明的字段 | rc=1 | S1-2 清单外对象检出 |
| P3 | 豁免名单混入一个已贯通字段（formFactCount） | rc=1 | S1-5 豁免名存实亡 |
| P4 | 呈现面渲染 confidence（违反 §1-20） | rc=1 | S1-6 设计性不露双向判据 |
| P5 | 基线 due 改成昨天 | rc=1 | S1-4 豁免到期恢复报红 |
| P6 | 全部复原 | rc=0 | 探针无污染 |

★ 探针全部在**副本**上做（不碰真源）⇒ 不污染仓库。
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "scripts" / "check_surface_visibility.py"
BASELINE = REPO / "tool" / "surface_baseline.json"
PROMPT = REPO / "lib" / "services" / "skills_l1_core_p2.dart"
DTO = REPO / "lib" / "services" / "message_card_service.dart"
CARD = REPO / "lib" / "widgets" / "diagnosis_card.dart"

FAILS = []


def run(base: Path) -> tuple:
    p = subprocess.run(
        [sys.executable, str(SCRIPT), "--baseline", str(base)],
        capture_output=True, text=True, encoding="utf-8",
    )
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def check(name: str, cond: bool, detail: str = "") -> None:
    tag = "OK  " if cond else "FAIL"
    print("  [%s] %s%s" % (tag, name, ("  ← " + detail) if detail and not cond else ""))
    if not cond:
        FAILS.append(name)


def make_copy(tmp: Path) -> Path:
    """把仓库里守卫要读的文件复制成一份可改的副本树。"""
    root = tmp / "repo"
    for rel in ("lib/services/skills_l1_core_p2.dart",
                "lib/services/progressive_diagnosis.dart",
                "lib/services/message_card_service.dart",
                "lib/types/teaching_types.dart",
                "lib/widgets/diagnosis_card.dart",
                "lib/features"):
        s = REPO / rel
        d = root / rel
        d.parent.mkdir(parents=True, exist_ok=True)
        if s.is_dir():
            shutil.copytree(s, d)
        else:
            shutil.copy2(s, d)
    return root


def run_on(root: Path, baseline_text: str) -> tuple:
    """在副本树上跑守卫（脚本仍从真仓读，但 --baseline 与 --repo 走副本）。"""
    bl = root / "tool" / "surface_baseline.json"
    bl.parent.mkdir(parents=True, exist_ok=True)
    bl.write_text(baseline_text, encoding="utf-8")
    # 用环境变量把 REPO 指向副本：脚本里 REPO = 脚本父目录的父
    # ⇒ 复制脚本本身到副本 scripts/ 下，让它自解析到副本
    sp = root / "scripts" / "check_surface_visibility.py"
    sp.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SCRIPT, sp)
    p = subprocess.run(
        [sys.executable, str(sp), "--baseline", str(bl)],
        capture_output=True, text=True, encoding="utf-8",
    )
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def main() -> int:
    base_text = BASELINE.read_text(encoding="utf-8")
    tmp = Path(tempfile.mkdtemp(prefix="s1_selftest_"))
    try:
        # ── P0 原状绿 ──
        # 2026-10-22（T-20261021-01 施工后）状态迁移：原 4 断链已销 3 个
        # （interventionValue / formFactCount / formStructure 全通，豁免收窄
        #  为仅 nextFocus，责任卡 T-20261021-04）⇒ 原状 = rc=0 + 断链仅
        #  nextFocus（在豁免登记中，守卫不报红）。
        rc, out = run(BASELINE)
        check("P0 原状 rc=0", rc == 0, "rc=%d\n%s" % (rc, out[-600:]))
        break_line = next(
            (l for l in out.splitlines()
             if l.startswith("WARN") and "断链字段" in l),
            "",
        )
        check(
            "P0 断链仅剩 nextFocus（豁免登记中，不误报）",
            "nextFocus" in break_line
            and "interventionValue" not in break_line
            and "formFactCount" not in break_line
            and "formStructure" not in break_line,
            out[-500:],
        )

        # ── P1 真源加字段 ⇒ S1-1 报红 ──
        root = make_copy(tmp / "p1")
        pt = root / "lib/services/skills_l1_core_p2.dart"
        t = pt.read_text(encoding="utf-8")
        t = t.replace(
            "- feedback_summary (string|null):",
            "- selftest_probe_field (string|null): 自测探针字段\n- feedback_summary (string|null):",
            1)
        pt.write_text(t, encoding="utf-8")
        rc, out = run_on(root, base_text)
        check("P1 真源新增字段 ⇒ rc=1", rc == 1, "rc=%d\n%s" % (rc, out[-600:]))
        check("P1 报红点名 selftestProbeField", "selftestProbeField" in out, out[-400:])

        # ── P2 DTO 加真源未声明字段 ⇒ S1-2 报红 ──
        root2 = make_copy(tmp / "p2")
        dt = root2 / "lib/services/message_card_service.dart"
        t = dt.read_text(encoding="utf-8")
        t = t.replace(
            "  final bool? pendingContext;",
            "  final bool? pendingContext;\n  final String? selftestGhostField;",
            1)
        dt.write_text(t, encoding="utf-8")
        rc, out = run_on(root2, base_text)
        check("P2 DTO 清单外字段 ⇒ rc=1", rc == 1, "rc=%d\n%s" % (rc, out[-600:]))
        check("P2 报红点名 selftestGhostField", "selftestGhostField" in out, out[-400:])

        # ── P3 豁免名单混入已贯通字段 ⇒ S1-5 豁免名存实亡 ──
        # 2026-10-22 改版（T-20261021-01 施工后）：interventionValue 在真仓
        # 已贯通且豁免已收窄 ⇒ 原「呈现面接上 iv」探针失去触发条件。
        # 等价负向验证改为**直接往豁免名单塞一个已贯通字段**——这正是
        # S1-5 要抓的形态（名存实亡的豁免会掩盖新断点）。
        root3 = make_copy(tmp / "p3")
        stale = json.loads(base_text)
        stale["exemptions"][0]["fields"] = ["nextFocus", "formFactCount"]
        rc, out = run_on(root3, json.dumps(stale, ensure_ascii=False, indent=1))
        check("P3 豁免混入已贯通字段 ⇒ rc=1", rc == 1, "rc=%d\n%s" % (rc, out[-600:]))
        check(
            "P3 报红指出豁免名存实亡",
            "S1-5" in out and "formFactCount" in out,
            out[-500:],
        )

        # ── P4 呈现面渲染 confidence ⇒ S1-6 违反 §1-20 ──
        root4 = make_copy(tmp / "p4")
        ct4 = root4 / "lib/widgets/diagnosis_card.dart"
        t = ct4.read_text(encoding="utf-8")
        t = t.replace(
            "  @override\n  Widget build(BuildContext context) {",
            "  // selftest probe\n"
            "  String get _selftestProbe2 => widget.confidence.toString();\n\n"
            "  @override\n  Widget build(BuildContext context) {",
            1)
        ct4.write_text(t, encoding="utf-8")
        rc, out = run_on(root4, base_text)
        check("P4 渲染 confidence ⇒ rc=1", rc == 1, "rc=%d\n%s" % (rc, out[-600:]))
        check("P4 报红指出违反设计性不露正典",
              "S1-6" in out and "confidence" in out, out[-500:])

        # ── P5 豁免到期 ⇒ 恢复报红 ──
        expired = json.loads(base_text)
        expired["exemptions"][0]["due"] = "2026-01-01"
        rc, out = run_on(make_copy(tmp / "p5"), json.dumps(expired, ensure_ascii=False, indent=1))
        check("P5 豁免到期 ⇒ rc=1", rc == 1, "rc=%d\n%s" % (rc, out[-600:]))
        check("P5 报红点名逾期天数", "逾期" in out, out[-400:])

        # ── P6 复原仍绿（探针无污染）──
        rc, out = run(BASELINE)
        check("P6 复原后 rc=0", rc == 0, "rc=%d\n%s" % (rc, out[-400:]))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("")
    if FAILS:
        print("SELFTEST_FAIL（%d 项）：%s" % (len(FAILS), ", ".join(FAILS)))
        return 1
    print("SELFTEST_OK：6/6 探针全过（证明 S1 守卫非恒绿非恒红）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
