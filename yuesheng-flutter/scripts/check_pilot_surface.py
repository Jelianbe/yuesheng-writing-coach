#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_pilot_surface.py — PilotMetrics 呈现隐私边界守卫（P1~P4）。

DECISIONS §4-232（R-029「都批」）的机器判据落地——把「只呈聚合计数 ·
不含症候维度 · 本地零外发 · 停写类不呈」从自律变成能变红：

| 判据 | 断言 | 对应裁定 |
|:--|:--|:--|
| P1 | 呈现文件不得出现引文原文键访问（`['h']` / `["h"]`） | 口径① 不呈明细 |
| P2 | 呈现文件不得出现症候键访问（`['s']` / `["s"]`）或 syndromeId 字样 | 口径② 不含症候维度 |
| P3 | prompt 构造链文件 pilot 命中 = 0 | 口径③ 零外发（B1 同形态） |
| P4 | 呈现文件不得出现停写两类事件常量 | 裁定④ 停写类不呈 |

用法：
  python scripts/check_pilot_surface.py          # 判定（rc 0/1）
  python scripts/check_pilot_surface.py --list   # 只列读数
  python scripts/check_pilot_surface.py --root X # 指定仓库根（自测副本用）

负向验证：scripts/_selftest_check_pilot_surface.py（6 探针，副本上做）。
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

REPO = Path(__file__).resolve().parent.parent

# 呈现面文件（新增卡 + 其纯函数服务层；改这里 = 改呈现面定义）
PRESENTATION_FILES = [
    "lib/services/pilot_metrics_summary.dart",
    "lib/features/growth/pilot_metrics_card.dart",
]

# prompt 构造链（P3：pilot 数据不得流入；与 chat/prompt 相关的既有文件）
PROMPT_CHAIN_FILES = [
    "lib/services/chat_service.dart",
    "lib/services/message_injector.dart",
    "lib/services/llm_circuit_breaker.dart",
    "lib/features/writing/writing_coach_panel_chat_runner.dart",
    "lib/features/writing/writing_coach_panel_session_controller.dart",
]

# P1：引文原文键的**访问形态**（JSON 键访问），非注释里的文字描述
P1_PATTERNS = [re.compile(r"\['h'\]"), re.compile(r'\["h"\]')]

# P2：症候键访问 + syndromeId 字样（内部 ID 不外显）
P2_PATTERNS = [
    re.compile(r"\['s'\]"),
    re.compile(r'\["s"\]'),
    re.compile(r"syndromeId"),
]

# P4：停写两类事件常量标识符
P4_PATTERNS = [
    re.compile(r"cardWallEntered"),
    re.compile(r"microTaskSubmitted"),
]

# P3：pilot 字样（大小写不敏）出现在 prompt 构造链 = 违规
P3_PATTERN = re.compile(r"pilot", re.IGNORECASE)


def _scan(root: Path, rels: list, patterns: list, label: str) -> list:
    """逐文件逐模式扫，返回违规明细（file:line 形态）。"""
    hits = []
    for rel in rels:
        p = root / rel
        if not p.exists():
            hits.append(f"{label}: 文件不存在 {rel}（呈现面/链路定义漂移？）")
            continue
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            for pat in patterns:
                if pat.search(line):
                    hits.append(f"{label}: {rel}:{i} 命中 /{pat.pattern}/")
    return hits


def run_checks(root: Path) -> dict:
    return {
        "P1": _scan(root, PRESENTATION_FILES, P1_PATTERNS, "P1"),
        "P2": _scan(root, PRESENTATION_FILES, P2_PATTERNS, "P2"),
        "P3": _scan(root, PROMPT_CHAIN_FILES, [P3_PATTERN], "P3"),
        "P4": _scan(root, PRESENTATION_FILES, P4_PATTERNS, "P4"),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="PilotMetrics 呈现隐私边界守卫（P1~P4）")
    ap.add_argument("--root", default=str(REPO), help="仓库根（自测副本用）")
    ap.add_argument("--list", action="store_true", help="只列读数，不判定")
    args = ap.parse_args()
    root = Path(args.root)

    results = run_checks(root)

    if args.list:
        print("── PilotMetrics 呈现隐私边界读数（P1~P4）──")
        for k, v in results.items():
            print(f"  {k}: {len(v)} 处" + ("" if not v else " ⇒ " + "; ".join(v)))
        return 0

    total = sum(len(v) for v in results.values())
    for k, v in results.items():
        if v:
            print(f"WARN {k} 违规 {len(v)} 处：")
            for h in v:
                print(f"  {h}")
    if total == 0:
        print("PASS：P1~P4 全过（呈现面无引文原文/症候 ID/停写常量；prompt 链 pilot 零命中）")
        return 0
    print(f"FAIL：{total} 处违规（DECISIONS §4-232 口径被破坏）")
    return 1


if __name__ == "__main__":
    sys.exit(main())
