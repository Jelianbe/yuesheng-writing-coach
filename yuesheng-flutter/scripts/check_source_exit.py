#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""S4 · 造物主侧真源出口对账 —— 「真源自动发现 + 双出口判定 + 覆盖面漂移检测」。

它补的是什么
------------
S1（check_surface_visibility.py）量的是**判据语言词频**，有三个已实测的局限：

1. **MAKER_SOURCES 硬编码 9 个文件** ⇒ 第 10 个真源出现时它天然看不见。
   实测（2026-10-21）：`training_kb_content_1..4` + `training_few_shot_library`
   共 **1279 代码行**从未进入 S1 视野 —— 因为它们不在那张硬编码清单里。
   ⇒ **守卫的判据集合本身会静默腐化，且腐化时零输出**。
2. **只扫诊断卡** ⇒ 教学链产品面（`features/` 178 文件 / 45050 行）不在判据范围。
3. **只量「量」不量「质」** ⇒ 词频 > 0 可能只是一句套话。

本脚本的判据对象不是词频，而是**关系**：
> **每一个造物主侧真源，是否至少有一个「出口」通向产品面？**
> 出口 = 该真源的内容经由某条调用链，其**渲染文本**会出现在用户可见的 widget 上。

三条判据
--------
- **S4-1 真源自动发现**：按命名形态自动发现真源（不硬编码清单）。
  ⇒ 新增真源若未登记进 `tool/surface_baseline.json`，直接 rc=1（**防清单腐化**）。
- **S4-2 双出口判定**：每个真源必须至少命中「prompt 出口」或「产品面出口」之一。
  两出口都空的 ⇒ rc=1（孤儿真源）。
- **S4-3 覆盖面漂移**：基线登记的出口若在代码中已不存在 ⇒ rc=1（**基线腐烂检测**）。

★ 与 S1 的分工（为什么不能只留 S1）
----------------------------------------
| 守卫 | 判据对象 | 能抓 | 抓不到 |
|:--|:--|:--|:--|
| `check_wiring` | 「有人消费吗」 | 字段死没死 | 用户看不看得见 |
| `check_surface_visibility`（S1） | 产品面**判据语言词频** | 诊断卡判据语言量 | ①真源清单腐化 ②教学链产品面 ③「量≠质」 |
| **本脚本（S4）** | **真源 → 出口的关系** | 孤儿真源 / 清单腐化 / 基线腐烂 | 具体内容质量（交给人工走查） |

★ 已知局限（勿删，方法论教训）
--------------------------------
① **出口判定基于调用链字符串匹配**，不是执行追踪 ⇒ 若出口经由反射 / 动态注册，
   本脚本会误报为「无出口」。**报红须人工确认后再登记豁免**，不得直接改脚本。
② **真源命名形态是启发式**：`_kb_content*` / `_content_manual_*` / `*few_shot*`。
   命名不符的真源不在发现范围 ⇒ 「自动发现」的完整性取决于命名约定。
   ⇒ 若发现数长期不变而造物主侧在长，**先怀疑本局限，而不是相信「没新增真源」**。
③ **本脚本是约定层守卫**（与 check_wiring / S1 同款定性）：WARN 起步，不阻断收尾。
④ **不做像素级还原**：它判「出口是否存在」，不判「出口设计得好不好」。

用法
----
    python scripts/check_source_exit.py --baseline tool/surface_baseline.json
    python scripts/check_source_exit.py --list          # 只列真源与出口，不判定

退出码
------
    0 = 通过（或全部命中基线豁免且未到期）
    1 = 有真源无出口 / 新真源未登记 / 基线出口已腐烂 / 豁免已到期
    2 = 环境错误
"""

from __future__ import annotations

import argparse
import datetime
import json
import re
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

REPO = Path(__file__).resolve().parent.parent
LIB = REPO / "lib"

# ── 真源命名形态（② 局限：启发式，依赖命名约定）──
RE_MAKER_NAME = re.compile(
    r"(_kb_content(_lib)?(_[\d]+)?\.dart$"      # 判据/技法/训练三族内容库
    r"|_content_manual_[\d]+\.dart$"            # 判据手册分卷
    r"|few_shot[\w]*\.dart$)"                    # few-shot 示例库
)

# ── 产品面目录（S1 只扫诊断卡；本脚本显式覆盖教学链产品面）──
SURFACE_DIRS = ["lib/features", "lib/widgets"]

# ── prompt 装配面（用于判「prompt 出口」是否真实存在）──
PROMPT_DIRS = ["lib/services", "lib/providers"]

RE_PART_OF = re.compile(r"part\s+['\"]([\w.]+\.dart)['\"]")
RE_IMPORT_OF = re.compile(r"import\s+['\"][^'\"]*?([\w/]+\.dart)['\"]")
RE_STRIP_LINE_COMMENT = re.compile(r"//.*$")

# ★ Dart 内置类型名：出现在顶层声明里时它是泛型的一部分，不是本真源的出口。
BUILTIN_TYPE_NAMES = {
    "List", "Map", "Set", "String", "int", "double", "bool", "num",
    "Future", "Stream", "Iterable", "Object", "dynamic", "void",
}


def strip_line_comments(text: str) -> str:
    """逐行剥离行注释（不做字符串配平：真源里 // 极少出现在字面量中，
    而引入配平逻辑会引入新的不可验证分支 ⇒ 保守更安全）。"""
    return "\n".join(RE_STRIP_LINE_COMMENT.sub("", l) for l in text.split("\n"))


def code_lines(path: Path) -> int:
    raw = path.read_text(encoding="utf-8", errors="ignore")
    clean = strip_line_comments(raw)
    return len([l for l in clean.split("\n") if l.strip()])


def discover_sources() -> list[Path]:
    """S4-1 真源自动发现（不硬编码清单）。"""
    out = []
    for p in sorted(LIB.rglob("*.dart")):
        if RE_MAKER_NAME.search(p.name):
            out.append(p)
    return out


def find_holders(src: Path) -> list[tuple[str, Path]]:
    """找谁 part/import 了这个真源。"""
    holders = []
    for q in LIB.rglob("*.dart"):
        if q == src:
            continue
        t = q.read_text(encoding="utf-8", errors="ignore")
        if RE_PART_OF.search(t) and src.name in t:
            holders.append(("part", q))
        elif re.search(r"import\s+['\"][^'\"]*%s['\"]" % re.escape(src.name), t):
            holders.append(("import", q))
    return holders


def public_exports(holder: Path, src: Path) -> list[str]:
    """该真源对外暴露的符号（= 它的出口面）。

    ★ 必须排除 Dart 内置类型名（List/Map/String/Set/…）：
    它们是泛型声明的一部分，不是「这个真源对外暴露的出口」。
    实测踩坑（2026-10-21）：不排除时 `List` 会在产品面 178 个 features 文件里
    命中 `List<Widget>` ⇒ 每个真源都判「产品面 YES」⇒ **守卫恒绿 = 静音**。
    同族纪律：**判据集合必须排除与判据无关的同名符号**。

    ★ 两处必须都扫（实测踩坑）：
    (a) **holder**（part/import 它的 library 文件）—— `part` 形态下符号在 holder 里；
    (b) **真源自身** —— 少数真源直接定义自己的导出函数。
        实测：`training_few_shot_library.dart` 的真出口是自身的
        `getTrainingFewShot` + `const Map<String,String> kTrainingFewShotLibrary`；
        只扫 holder 会把它的出口错报成 holder 的 `parseSyndromeOrdinalList`
        ⇒ **判据对象错位，比漏检更危险（它会让真源看起来有别的出口）**。
    """
    names = []
    for p in (holder, src):
        t = strip_line_comments(p.read_text(encoding="utf-8", errors="ignore"))
        # const/final X = / String f( / List<T> f( / Map<K,V> f( ... 具名声明
        found = re.findall(
            r"^(?:const|final)\s+(?:Map|List|Set|String|int|double|bool)\s*[<][^=]*[>]\s*(\w+)\s*=",
            t, re.M)
        found += re.findall(
            r"^(?:String|List<[^>]+>|Map<[^>]+>|Set<[^>]+>|int|double|bool)\s+(\w+)\s*\(",
            t, re.M)
        names.extend(found)
    seen, out = set(), []
    for n in names:
        if n.startswith("_") or n in BUILTIN_TYPE_NAMES or n in seen:
            continue
        seen.add(n)
        out.append(n)
    return out


def has_prompt_exit(exports: list[str]) -> tuple[bool, str]:
    """判「prompt 出口」：导出的符号是否被 prompt 装配面调用。"""
    corpus = []
    for d in PROMPT_DIRS:
        dd = REPO / d
        if not dd.exists():
            continue
        for p in dd.rglob("*.dart"):
            if p.name in ("prompt_assembly_service.dart", "skill_dispatcher.dart",
                          "chat_service.dart", "message_injector.dart",
                          "chat_context_builder.dart", "progressive_diagnosis.dart"):
                corpus.append(strip_line_comments(
                    p.read_text(encoding="utf-8", errors="ignore")))
    blob = "\n".join(corpus)
    hit = [e for e in exports if re.search(r"\b%s\s*\(" % re.escape(e), blob)]
    return (bool(hit), ", ".join(hit[:3]))


def has_surface_exit(exports: list[str]) -> tuple[bool, str]:
    """判「产品面出口」：导出符号是否被产品面（features/widgets）引用。"""
    corpus = []
    for d in SURFACE_DIRS:
        dd = REPO / d
        if not dd.exists():
            continue
        for p in dd.rglob("*.dart"):
            corpus.append(strip_line_comments(
                p.read_text(encoding="utf-8", errors="ignore")))
    blob = "\n".join(corpus)
    hit = [e for e in exports if re.search(r"\b%s\b" % re.escape(e), blob)]
    return (bool(hit), ", ".join(hit[:3]))


def load_baseline(path: Path) -> dict:
    if not path.exists():
        return {"sources": {}, "exemptions": []}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print("基线 JSON 非法：%s" % e, file=sys.stderr)
        sys.exit(2)
    if not isinstance(data, dict):
        print("基线结构非法：根须为对象", file=sys.stderr)
        sys.exit(2)
    data.setdefault("sources", {})
    data.setdefault("exemptions", [])
    return data


def expiry_of(exempt: dict) -> tuple[bool, int | None]:
    due_raw = exempt.get("due", "")
    if not due_raw:
        return (False, None)
    try:
        due = datetime.date.fromisoformat(due_raw)
    except ValueError:
        return (False, None)
    today = datetime.date.today()
    return (today > due, (due - today).days)


def main() -> int:
    ap = argparse.ArgumentParser(description="S4 真源出口对账")
    ap.add_argument("--baseline", default="tool/source_exit_baseline.json")
    ap.add_argument("--list", action="store_true", help="只列真源与出口，不判定")
    args = ap.parse_args()

    srcs = discover_sources()
    if not srcs:
        print("环境错误：未发现任何造物主侧真源", file=sys.stderr)
        return 2

    base = load_baseline(REPO / args.baseline)
    known = base["sources"]
    exempts = {e["id"]: e for e in base["exemptions"] if "id" in e}

    print("── S4 造物主侧真源出口对账 ──")
    print("自动发现真源 %d 个（按命名形态启发式，见局限②）" % len(srcs))
    print("产品面目录: %s" % ", ".join(SURFACE_DIRS))
    print("")

    total_lines = 0
    dead: list[tuple[str, int]] = []      # 无任何出口
    unregistered: list[tuple[str, int]] = []  # 新真源未登记
    rotted: list[str] = []                 # 基线登记的出口已腐烂

    rows = []
    for p in srcs:
        rel = p.relative_to(REPO).as_posix()
        cl = code_lines(p)
        total_lines += cl
        holders = find_holders(p)
        exports: list[str] = []
        for _, h in holders:
            exports.extend(public_exports(h, p))
        exports = sorted(set(exports))
        p_ok, p_who = has_prompt_exit(exports)
        s_ok, s_who = has_surface_exit(exports)
        rows.append((rel, cl, len(holders), p_ok, s_ok, exports, p_who, s_who))
        if not p_ok and not s_ok:
            dead.append((rel, cl))
        if rel not in known:
            unregistered.append((rel, cl))

    print("%-52s %6s %6s %8s %8s" % ("source", "code", "hold", "prompt", "surface"))
    for rel, cl, nh, p_ok, s_ok, exports, p_who, s_who in rows:
        print("%-52s %6d %6d %8s %8s" % (
            rel, cl, nh, "YES" if p_ok else "-", "YES" if s_ok else "-"))
        print("      出口符号: %s" % (", ".join(exports) if exports else "<无>"))
        if p_ok:
            print("      prompt 出口 ← %s" % p_who)
        if s_ok:
            print("      产品面出口 ← %s" % s_who)
    print("")
    print("造物主侧真源合计代码行：%d" % total_lines)
    print("")

    if args.list:
        return 0

    rc = 0

    # ── S4-1 新真源未登记 ──
    if unregistered:
        print("FAIL（S4-1）：发现 %d 个**未登记进基线**的造物主侧真源。" % len(unregistered))
        for rel, cl in unregistered:
            print("  - %s（%d 代码行）" % (rel, cl))
        print("  ⇒ 真源清单会静默腐化（S1 硬编码清单已实测漏掉 1279 行）。")
        print("  ⇒ 处置：登记进 %s 的 sources 节（附出口说明），或显式登记豁免。" % args.baseline)
        rc = 1

    # ── S4-2 无任何出口（孤儿真源）──
    if dead:
        print("FAIL（S4-2）：%d 个真源**既无 prompt 出口也无产品面出口**。" % len(dead))
        for rel, cl in dead:
            print("  - %s（%d 代码行）" % (rel, cl))
        print("  ⇒ 这是「造了但完全没接」的一类缺口。")
        rc = 1

    # ── S4-3 基线登记的出口已腐烂 ──
    for rel, rec in known.items():
        holder = rec.get("holder")
        if holder and not (REPO / holder).exists():
            rotted.append("%s → holder 消失：%s" % (rel, holder))
            continue
        if holder:
            ht = (REPO / holder).read_text(encoding="utf-8", errors="ignore")
            if holder_src_name(rel) and holder_src_name(rel) not in ht:
                rotted.append("%s → holder 不再 part 该真源" % rel)
    if rotted:
        print("FAIL（S4-3）：基线登记的出口已腐烂 %d 项。" % len(rotted))
        for r in rotted:
            print("  - %s" % r)
        print("  ⇒ 基线说的「有出口」与代码现状不符 ⇒ 基线在骗人。")
        rc = 1

    # ── 豁免路径：孤儿真源可登记豁免（带到期日）──
    if dead and rc == 1:
        still_dead = []
        for rel, cl in dead:
            e = exempts.get("S4-孤儿真源::" + rel)
            if not e:
                still_dead.append((rel, cl))
                continue
            expired, days = expiry_of(e)
            if expired:
                print("FAIL（S4-2）：%s 的豁免**已到期**（due=%s）。" % (rel, e.get("due")))
                still_dead.append((rel, cl))
            else:
                print("WARN（S4-2，豁免中）：%s 无出口；责任卡=%s 剩余 %s 天" % (
                    rel, e.get("owner_card", "<无>"), days))
        if len(still_dead) == len(dead):
            # 全部孤儿都被有效豁免覆盖 ⇒ 只有 S4-2 这条被豁免，其它问题仍报红
            if not unregistered and not rotted:
                print("")
                print("PASS（S4）：全部孤儿真源均登记有效豁免，其余判据通过。")
                return 0
            print("")

    if rc == 0:
        print("PASS（S4）：%d 个真源全部登记在册，出口关系自洽。" % len(srcs))
    return rc


def holder_src_name(rel: str) -> str:
    return Path(rel).name


if __name__ == "__main__":
    sys.exit(main())