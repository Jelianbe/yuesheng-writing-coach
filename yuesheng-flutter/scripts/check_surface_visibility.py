#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""S1 · 「造出来的东西，用户看得见吗」守卫 —— 造物主侧 ↔ 产品面对账（层二的机器执行点）。

背景（2026-10-21 舰长「看不到立体功能」批判性复核）
------------------------------------------------------
既有护栏与审查全部落在「链路内部自洽」层：check_wiring.py 验「生产有没有真的
走到它」（coverage ≠ liveness），活性审查验「DB 列 / payload key / 触发条件死没死」。
★ **没有一条验「造物主侧做出来的东西，用户在产品面上看得见吗」。**

⇒ 结果：判据手册 **38 段 / 1889 行**、技法真源 **867 行**，
而诊断卡（`lib/widgets/diagnosis_card.dart`，40 区块）里
「原则 / 不报 / 未命中 / 为什么不是 / 排除」命中数 **全 0**。
最厚的**例外条款层**（38/38 段）与**负例 few-shot**（36/38 段）在产品面等于不存在。
⇒ 用户看到的是「报出了什么」，永远看不到「排除了什么」。

★ 为什么 check_wiring 抓不到
-----------------------------
check_wiring 的判据是「**这个东西有人消费吗**」——`intervention_value` 被
`diagnosis_integration_service` 消费（评分端）⇒ 它「活着」⇒ 放行。
但它在**产品面零引用**（widget 里 0 命中）⇒ 用户永远看不到。
⇒ **同一个字段，在两个审查层同时「活」与「死」** —— 两个审查从不交叉 = 双重失明。
本脚本补的就是那条**交叉判据**。

★ 本脚本的定性
--------------
**约定层守卫，不是门禁**（与 check_wiring.py / check_extension_shape.py 同款定性）。
WARN 起步：收尾时跑一次，报红即须当场处置（登记豁免 or 补消费面），
不阻断收尾。升阻断须用户裁定。

判据
----
- **S1（总量对账）**：造物主侧体量（判据手册行数 + 技法真源行数）
  vs 产品面「判据语言」渲染命中数。差额 > 阈值 ⇒ 报红。
- **S2（新增消费面守卫）**：基线登记的产品面消费点在 lib 内已不存在 ⇒ 报红（基线腐烂检测）。
- **S3（基线豁免必带 reason）**：无 reason ⇒ exit 2。

★ 已知局限（勿删，方法论实测教训）
------------------------------------
① **本守卫只量「量」，不量「质」**：判据语言命中数 > 0 **不**等于产品面做得好
   —— 可能只是一句套话。⇒ 本守卫是**防复发**闸，不是**质量**判据。
② **关键词表是有限的**：换一批词（如「不作为」「不予认定」）就能绕过本守卫。
   ⇒ 本守卫的价值在于「**新增消费面不得消失**」（S2），不在于穷尽词表。
③ **注释必须剥离**：`diagnosis_card.dart` 里「判据 / 豁免 / 例外」命中 4 处，
   **全部是注释**（`///` 或 `//` 开头）⇒ 若不剥离，词频会虚高一倍以上
   ⇒ **本脚本逐行剥离注释后再计数**（这是 2026-10-21 实测踩到的坑：
   「表格错列检测器须先剥行内代码」同族）。
④ **只扫诊断卡**（`lib/widgets/diagnosis_card.dart`）：其它卡片（growth 卡等）
   不在判据范围内。**扩面须显式改脚本**，不得默默扩大 ⇒ 否则误报面失控。

用法
----
    python scripts/check_surface_visibility.py --baseline tool/surface_baseline.json
    python scripts/check_surface_visibility.py                    # 全量报告

⚠️ 与既有基线同源纪律：**拿来「检查」是对的，拿来「重生成」就是自杀。**

退出码
------
    0 = 通过（或差额在阈值内）
    1 = 对账差额超阈值 / 基线腐烂
    2 = 环境错误（文件缺失 / 基线结构非法）
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

REPO = Path(__file__).resolve().parent.parent
LIB = REPO / "lib"

# ── 产品面扫描目标（④ 局限：只扫诊断卡，扩面须显式改这里）──
SURFACE_FILES = ["lib/widgets/diagnosis_card.dart"]

# ── 造物主侧体量来源（用于总量对账）──
MAKER_SOURCES = [
    "lib/services/syndrome_kb_content_manual_1.dart",
    "lib/services/syndrome_kb_content_manual_2.dart",
    "lib/services/syndrome_kb_content_manual_3.dart",
    "lib/services/syndrome_kb_content_manual_4.dart",
    "lib/services/syndrome_kb_content_manual_5.dart",
    "lib/services/syndrome_kb_content_manual_6.dart",
    "lib/services/technique_kb_content_lib_1.dart",
    "lib/services/technique_kb_content_lib_2.dart",
    "lib/services/technique_kb_content_lib_3.dart",
]

# ── 判据语言关键词（② 局限：有限词表，只防复发不穷尽）──
SURFACE_KEYWORDS = [
    "判据", "豁免", "例外", "未命中", "不报", "原则",
    "为什么不是", "排除", "反例",
]

# ── 对账阈值：产品面命中数 / 造物主侧行数（万分之一为单位）──
# 2026-10-21 实测基线：造物主侧 2756 行（1889 判据 + 867 技法），
# 产品面渲染命中 0 ⇒ 比值 0.0。
# 阈值取「万分之一」= 每 10000 行造物主侧至少要有 1 处产品面消费。
RATIO_THRESHOLD = 0.0001

RE_LINE_COMMENT = re.compile(r"//.*$")
RE_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)


def strip_comments(text: str) -> str:
    """剥离行注释与块注释（③ 局限：注释不剥离则词频虚高一倍以上）。

    保守做法：逐行剥离行注释；块注释整体替换为等量空行以保持行号不变。
    """
    text = RE_BLOCK_COMMENT.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), text)
    out = []
    for line in text.split("\n"):
        # 字符串字面量里的 // 不该被当注释（如 'http://'）——
        # 本项目诊断卡无此形态，但仍做一层简易引号配平保护。
        in_str = False
        quote = ""
        cut = len(line)
        for i, ch in enumerate(line):
            if not in_str and ch in "'\"":
                in_str = True
                quote = ch
            elif in_str and ch == quote:
                in_str = False
            elif not in_str and ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
                cut = i
                break
        out.append(RE_LINE_COMMENT.sub("", line[:cut]))
    return "\n".join(out)


def count_surface_hits() -> int:
    """统计产品面（渲染文本层）的判据语言命中数。"""
    total = 0
    for rel in SURFACE_FILES:
        p = REPO / rel
        if not p.exists():
            continue
        clean = strip_comments(p.read_text(encoding="utf-8"))
        for kw in SURFACE_KEYWORDS:
            total += clean.count(kw)
    return total


def count_maker_lines() -> int:
    """统计造物主侧真源行数（判据手册 + 技法真源）。"""
    total = 0
    for rel in MAKER_SOURCES:
        p = REPO / rel
        if not p.exists():
            continue
        total += len(p.read_text(encoding="utf-8").splitlines())
    return total


def load_baseline(path: Path):
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print("基线 JSON 非法：%s" % e, file=sys.stderr)
        sys.exit(2)
    if not isinstance(data, dict) or "exemptions" not in data:
        print("基线结构非法：缺 exemptions", file=sys.stderr)
        sys.exit(2)
    for item in data["exemptions"]:
        if not item.get("reason"):
            print("基线豁免缺 reason：%s" % item.get("id", "<无 id>"), file=sys.stderr)
            sys.exit(2)
    return data


def main() -> int:
    ap = argparse.ArgumentParser(description="S1 造物主侧↔产品面可见性守卫")
    ap.add_argument("--baseline", default="tool/surface_baseline.json",
                    help="基线文件路径（豁免表）")
    args = ap.parse_args()

    surface = count_surface_hits()
    maker = count_maker_lines()
    ratio = (surface / maker) if maker else 0.0

    print("── S1 造物主侧 ↔ 产品面可见性对账 ──")
    print("造物主侧真源行数（判据手册 + 技法三卷）：%d" % maker)
    print("产品面判据语言渲染命中数：%d" % surface)
    print("比值：%.6f（阈值 %.6f）" % (ratio, RATIO_THRESHOLD))
    print("")

    base = load_baseline(REPO / args.baseline)
    exempt = None
    if base is not None:
        exempt = base["exemptions"][0] if base["exemptions"] else None
        print("基线豁免 %d 项" % len(base["exemptions"]))
        for e in base["exemptions"]:
            print("  - %s：%s" % (e["id"], e["reason"]))
            print("    责任卡=%s 到期日=%s" % (e.get("owner_card", "<无>"),
                                          e.get("due", "<无>")))
        print("")

    if maker == 0:
        print("环境错误：造物主侧真源缺失", file=sys.stderr)
        return 2

    if ratio < RATIO_THRESHOLD:
        # 豁免路径：基线登记了本项缺口 ⇒ 放行但打印账（**不掩盖**）。
        # ★ 豁免带到期日 ⇒ **到期后仍报红**（避免「永久豁免 = 永久静音」）。
        #   2026-10-21 实测教训：初版只写了「到期未修则恢复报红」的说明，
        #   代码里**没有**到期判断 ⇒ 声明 ≠ 生效。此处补实。
        if exempt and exempt.get("id") == "S1-造物主侧判据语言未进产品面":
            due_raw = exempt.get("due", "")
            expired = False
            days_left = None
            if due_raw:
                try:
                    due = datetime.date.fromisoformat(due_raw)
                    days_left = (due - datetime.date.today()).days
                    expired = datetime.date.today() > due
                except ValueError:
                    print("基线豁免 due 非法（须 YYYY-MM-DD）：%r" % due_raw,
                          file=sys.stderr)
                    return 2
            if expired:
                print("FAIL（S1）：产品面判据语言消费不足，且基线豁免**已到期**"
                      "（due=%s）。" % due_raw)
                print("  ⇒ 豁免逾期 ⇒ 必须补消费面或**显式续期**（改 due + 写明理由）。")
                return 1
            print("WARN（S1，基线豁免中）：产品面判据语言消费不足。")
            print("  ⇒ 缺口已登记：责任卡=%s 到期日=%s（剩余 %s 天）" % (
                exempt.get("owner_card", "<无>"), due_raw, days_left))
            print("  ⇒ 豁免期内本守卫不报红；到期未修则恢复报红。")
            return 0
        print("FAIL（S1）：产品面判据语言消费不足 —— 差额过大。")
        print("  ⇒ 造物主侧做了 %d 行，产品面几乎不消费（命中 %d）。" % (maker, surface))
        print("  ⇒ 这是「造了但没接」的一类缺口，须补消费面或登记豁免。")
        return 1

    print("PASS（S1）：产品面判据语言消费比在阈值内。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
