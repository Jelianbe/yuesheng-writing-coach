#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""E1 · `extension` 单块行数判据 —— 给「减行数不得用 extension」这条红线补牙齿。

背景（本仓自设红线当前零执行点）
--------------------------------
`AGENTS.md §4.7` 与 `lib/services/chat_service.dart` 文件头 /
`lib/providers/session_providers.dart:192` 都写着「不可用 extension 拆分」，
并被 10+ 处代码注释当作**硬约束**引用。但实测：

- 门禁 10（`check_split_shape.py`）**只对已声明 `part` 的家族**求值；
- 门禁 11（`check_a_class_exemption.py`）**只对文件名匹配 `_A_CLASS_PATTERNS`
  的 A 类文件**求值；
- `chat_service.dart` 两者都不属于 ⇒ **两条门禁都看不见它**，
  而它恰是全仓最大问题块（1,869 行文件 / `ChatServiceSend` 1,193 行 extension）。

⇒ 与 `.ai/rules/README.md §一`「声称硬约束 ⇒ 必须指向一个可执行检查」冲突。
本脚本是该红线的执行点（ADR-0004 §2 子款 **R-2**）。

★ 本脚本的定性
--------------
**约定层守卫，不是门禁。** 加门禁道次须用户裁定（道数以 `scripts/gate.sh`
头部注释为唯一真源）。它「有执行动作」：收尾时跑一次，报红即须当场处置。

判据
----
- **E1**：任一顶格 `extension` 块**行数 > `--limit`** ⇒ 违规。
- **G1**：`extension` 块数为 0 ⇒ `exit 2`（空扫等于没检查，对齐门禁 10/11 的 G2）。
- **G2**：基线登记的块**在 lib 内已不存在** ⇒ 报红（豁免表腐烂检测，
  对齐 `.ai/tools/check_app_pairing.py` 的「未被命中即 = 失效 ⇒ fail-closed」）。
- **G3**：基线里存在**无 `reason` 的豁免** ⇒ `exit 2`（豁免必带原因）。

★ 四条实测纪律（内建，勿删）
----------------------------
① **按「块名 + 宿主文件路径」登记，不按行号**。行数会漂 —— 实测同一个
   `ChatServiceSend`：台账记 1173、外部评审记 1172、括号配平实测 1193。
   按行号登记 ⇒ 下次改文件就静默失效。
② **块体必须用括号配平法收尾**，**不得**用「顶格 `}`」—— 遇嵌套大括号即崩。
   （本仓已记录该探针缺陷 5 次，见 `.ai/DECISIONS-DETAIL.md`。）
③ **去注释与字符串后再配平**：`//` 行注释、单双引号字符串、raw string 内含
   大括号字面量（如 `'''{'a':1}'''`）都会破坏朴素计数。
④ **本脚本只报不改**。拆 `extension` 是架构级改动，须走独立批次 + ADR。

★ 负向验证配方（改判据后必做）
------------------------------
    # 1) 备份
    cp lib/services/app_theme.dart /tmp/app_theme_bak.dart
    # 2) 注入一个超过 limit 的 extension 块
    printf '\nextension ZzNegProbe on Object {\n%s}\n' "$(seq -f '// %g' 1 320)" \\
      >> lib/services/app_theme.dart
    # 3) 跑守卫，必须报红且 rc=1
    python scripts/check_extension_shape.py --baseline tool/extension_shape_baseline.json
    # 4) 恢复 + 回读比对
    两者必须都做；只做前 3 步会留下污染源码的副作用。

用法
----
    python scripts/check_extension_shape.py                                  # 全量报告
    python scripts/check_extension_shape.py --baseline tool/extension_shape_baseline.json
    python scripts/check_extension_shape.py --baseline <b> --limit 300        # 止血模式
    python scripts/check_extension_shape.py --json tool/extension_shape_baseline.json --force
    python scripts/check_extension_shape.py --expect-rule-count 1            # 防判据被静默删减

⚠️ 与既有基线同源纪律：**拿来「检查」是对的，拿来「重生成」就是自杀。**
故写基线做成 `--json` 且要求 `--force` 才覆盖已存在文件；
若同时传 `--json` 与 `--baseline`，本脚本直接 `exit 2`。

退出码
------
    0 = 通过（或止血模式下无新增）
    1 = 有违规 / 有新增 / 失效豁免 / 判据条数守卫失败
    2 = 环境错误（lib 缺失 / 0 个 extension / 基线结构非法 / 参数冲突）
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from typing import Dict, List, Tuple

# ── 判据 / 守卫 编号 ────────────────────────────────────────────────────────
RULE_E1 = "E1"
RULE_IDS: List[str] = [RULE_E1]

GUARD_G1 = "G1"  # extension 块数为 0
GUARD_G2 = "G2"  # 失效豁免（登记的块已不存在）
GUARD_G3 = "G3"  # 无原因豁免（实现上 exit 2）

RULE_MESSAGES: Dict[str, str] = {
    RULE_E1: "extension 块超行数上限（ADR-0004 §2 R-2：减行数不得用 extension）",
}

# 顶格 extension 声明：`extension Name on Type {` / `extension Name<T> on Type<T> {`
# 前导空白一律视为「非顶格」（嵌套在别处的 extension 不是本判据对象）。
_EXT_RE = re.compile(r"^(?:abstract\s+)?extension\s+(\w+)")


# ── 探针：去注释/字符串后按括号配平求块尾（纪律 ② ③）────────────────────────
def _strip_noise(line: str, state: Dict[str, bool]) -> str:
    """粗剥注释与字符串字面量，只留下会影响大括号配平的字符。

    ★ 这是**启发式**，不是 Dart 解析器。已知边界：
      - raw string（r'''…''' / r\"\"\"…\"\"\"）内部的大括号字面量按内容处理，
        故 raw string 内的引号转义不完全正确；本仓 prompt 文本常量里大括号
        极少见，实测未造成误判。**若将来出现误判，先读这里**（§4-153 同型：
        「守卫失败/零命中」必须先 diff 定位是探针形状错还是被测对象真错）。
    """
    out: List[str] = []
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if state["raw_block"]:
            if line.startswith("'''", i) or line.startswith('"""', i):
                state["raw_block"] = False
                i += 3
                continue
            i += 1
            continue
        if line.startswith("//", i):
            break
        if line.startswith("'''", i) or line.startswith('"""', i):
            state["raw_block"] = True
            i += 3
            continue
        if ch in "'\"":
            quote = ch
            i += 1
            while i < n:
                if line[i] == "\\":
                    i += 2
                    continue
                if line[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def block_end(lines: List[str], start: int) -> int:
    """返回 `extension` 块闭合大括号所在行号（含）。找不到则返回末行。"""
    state = {"raw_block": False}
    depth = 0
    started = False
    for j in range(start, len(lines)):
        cleaned = _strip_noise(lines[j], state)
        for ch in cleaned:
            if ch == "{":
                depth += 1
                started = True
            elif ch == "}":
                depth -= 1
                if started and depth == 0:
                    return j
    return len(lines) - 1


@dataclass
class ExtensionBlock:
    name: str
    path: str          # 归一化 posix 风格，相对 lib
    start_line: int    # 1-based
    lines: int

    @property
    def key(self) -> str:
        return f"{self.path}::{self.name}"


def collect_extension_blocks(lib_dir: str) -> Tuple[List[ExtensionBlock], List[str]]:
    """扫描 lib 下全部顶层 extension 块。返回 (块列表, 错误列表)。"""
    blocks: List[ExtensionBlock] = []
    errors: List[str] = []
    for root, _dirs, files in os.walk(lib_dir):
        for fn in sorted(files):
            if not fn.endswith(".dart"):
                continue
            abs_path = os.path.join(root, fn)
            rel = os.path.relpath(abs_path, lib_dir).replace(os.sep, "/")
            if fn.endswith(".g.dart"):
                continue  # 生成文件，永不可清偿
            try:
                with open(abs_path, encoding="utf-8", errors="replace") as fh:
                    lines = fh.read().splitlines()
            except OSError as exc:
                errors.append(f"read failed: {rel}: {exc}")
                continue
            for i, line in enumerate(lines):
                m = _EXT_RE.match(line)
                if not m:
                    continue
                end = block_end(lines, i)
                blocks.append(
                    ExtensionBlock(
                        name=m.group(1),
                        path=rel,
                        start_line=i + 1,
                        lines=end - i + 1,
                    )
                )
    blocks.sort(key=lambda b: (-b.lines, b.path, b.start_line))
    return blocks, errors


def load_baseline(path: str, limit: int) -> Tuple[Dict[str, dict], int]:
    """读取基线 JSON，返回 ({块键: 豁免项}, 判据条数)。"""
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    raw = data.get("exemptions")
    if not isinstance(raw, dict):
        raise ValueError("baseline JSON has no 'exemptions' object")
    out: Dict[str, dict] = {}
    for key, item in raw.items():
        if isinstance(item, str):
            item = {"reason": item}
        if not isinstance(item, dict):
            raise ValueError(f"exemption for {key} is not an object/str")
        out[key] = item
    # ★ 防「基线被静默改宽」：登记的行数上限不得低于本次运行的 limit
    for key, item in out.items():
        recorded = item.get("limit")
        if isinstance(recorded, int) and recorded < limit:
            raise ValueError(
                f"exemption {key} records limit={recorded} < current limit={limit}"
            )
    rules = data.get("ruleCount")
    return out, (rules if isinstance(rules, int) else len(RULE_IDS))


def build_snapshot(blocks: List[ExtensionBlock], lib_dir: str,
                   limit: int, exemption_source: str,
                   reason: str) -> dict:
    """可 json.dump 的快照字典（`--json` 落盘用，**全量**）。

    ``reason`` 必须由人显式传入（``--reason``）。**不允许**工具生成占位原因：
    G3 的全部价值在于「原因是人写的责任句」，占位会让无原因豁免悄悄通过
    ⇒ 「守卫拒绝自己生成的基线」这一实测缺陷的根因就在这里。
    """
    return {
        "_note": (
            "extension 块行数豁免基线（ADR-0004 §2 R-2）。"
            "★ 按「块名 + 宿主路径」登记，**不按行号**（行数会漂：同一块实测"
            "曾出现 1173/1172/1193 三个值）。"
            "每条豁免必须写 reason；登记的块若已不存在 ⇒ 下次报红（G2）。"
            "重生成时**勿**把新发现项顺手写进来 —— 那正是本脚本要拦的行为本身。"
        ),
        "dir": lib_dir,
        "exemptionSource": exemption_source,
        "ruleCount": len(RULE_IDS),
        "blockCount": len(blocks),
        "limit": limit,
        "exemptions": {
            b.key: {"lines": b.lines, "limit": limit, "reason": reason} for b in blocks
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser(
        description="extension 单块行数守卫（约定层，非门禁；ADR-0004 §2 R-2）")
    ap.add_argument("--dir", default="lib", help="扫描目录（默认 lib）")
    ap.add_argument("--limit", type=int, default=300, help="单块行数上限（默认 300）")
    ap.add_argument("--baseline", default=None,
                    help="豁免基线 JSON（止血模式：只报新增）")
    ap.add_argument("--json", dest="json_out", default=None,
                    help="输出/写入基线 JSON（一律全量）")
    ap.add_argument("--force", action="store_true",
                    help="配合 --json 覆盖已存在的基线")
    ap.add_argument("--expect-rule-count", type=int, default=None,
                    help="防判据被静默删减（缺期望值时填基线 ruleCount）")
    ap.add_argument("--reason", default=None,
                    help="写入基线的豁免原因（**必须人工书写**；"
                         "存在超限块而未给此参数 ⇒ G4 拒绝写基线）")
    args = ap.parse_args()

    lib_dir = args.dir
    if not os.path.isdir(lib_dir):
        print(f"[FAIL] 扫描目录不存在: {lib_dir}", file=sys.stderr)
        return 2
    if args.json_out and args.baseline:
        print("[FAIL] --json 一律落全量，若带 --baseline 只会写入「新增项」"
              "（基线自己把自己清空型假绿）", file=sys.stderr)
        return 2

    blocks, errors = collect_extension_blocks(lib_dir)

    print("=" * 68)
    print("extension 分块扫描：目录=%s  上限=%d 行" % (lib_dir, args.limit))
    print("extension 块总数：%d" % len(blocks))
    if errors:
        for e in errors:
            print(f"  [WARN] {e}")

    exemptions: Dict[str, dict] = {}
    if args.baseline:
        if not os.path.exists(args.baseline):
            print(f"[FAIL] 基线不存在: {args.baseline}", file=sys.stderr)
            return 2
        try:
            exemptions, base_rules = load_baseline(args.baseline, args.limit)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            print(f"[FAIL] 基线不可用: {exc}", file=sys.stderr)
            return 2
        expect = args.expect_rule_count if args.expect_rule_count is not None else base_rules
        if expect != len(RULE_IDS):
            print(f"[FAIL] 判据条数守卫失败：期望 {expect}，实际 {len(RULE_IDS)}"
                  "（判据被静默删减）", file=sys.stderr)
            return 1

    # ── 守卫 G3：豁免必须带原因（fail-closed）──────────────────────────────
    for key, item in exemptions.items():
        if not str(item.get("reason") or "").strip():
            print(f"[FAIL] 基线内存在无原因豁免（G3）: {key}", file=sys.stderr)
            return 2

    # ── 守卫 G1：空扫 = 没检查 ─────────────────────────────────────────────
    if not blocks:
        print("[FAIL] extension 块数为 0（G1）—— 空扫等于没检查，绝不返回 0",
              file=sys.stderr)
        return 2

    print("-" * 68)
    print("判据条数：%d" % len(RULE_IDS))
    for rid in RULE_IDS:
        print(f"  {rid}  {RULE_MESSAGES[rid]}")

    over = [b for b in blocks if b.lines > args.limit]
    present_keys = {b.key for b in blocks}
    stale = [k for k in exemptions if k not in present_keys]

    # 止血模式：已登记的键不算新增
    new_over: List[ExtensionBlock] = []
    for b in over:
        item = exemptions.get(b.key)
        if item is None:
            new_over.append(b)
            continue
        rec = item.get("lines")
        if isinstance(rec, int) and b.lines > rec:
            new_over.append(b)  # 同一块又长大了 ⇒ 仍算新增

    if args.json_out:
        # ── 守卫 G4：存在超限块而未给 --reason ⇒ 拒绝落盘 ──────────────────
        # ★ 这条是为了消除实测到的「守卫拒绝自己生成的基线」：
        #   旧版 --json 写 reason: ""，而下一次 --baseline 读回时被 G3 判 exit 2。
        #   原因必须是**人写的责任句**，工具不得代填。
        if over and not str(args.reason or "").strip():
            print("[FAIL] G4：存在超限 extension 块但未提供 --reason，"
                  "拒绝写入基线（原因必须人工书写）\n"
                  "  超限块：" + ", ".join(b.key for b in over), file=sys.stderr)
            return 2
        reason = str(args.reason or "")
        payload = build_snapshot(blocks, lib_dir, args.limit,
                                 exemption_source=os.path.basename(__file__),
                                 reason=reason)
        if os.path.exists(args.json_out) and not args.force:
            print(f"[FAIL] 基线已存在: {args.json_out}（要覆盖请显式加 --force）",
                  file=sys.stderr)
            return 2
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=2)
        print(f"✅ 已写入基线（全量）: {args.json_out}（块 {len(blocks)} 个）")
        if over:
            print(f"   ⚠️ 登记了 {len(over)} 条超限豁免 —— "
                  "**须在同批为每条补写真实原因与生命周期终点**，"
                  "否则下次 `--baseline` 会被 G3 判红。")
        return 0

    print("-" * 68)
    if new_over:
        label = "新增超限" if args.baseline else "超限"
        print(f"  {RULE_E1}  {label}：{len(new_over)} 个\n")
        for b in new_over:
            exempt = exemptions.get(b.key)
            note = f"（基线登记 {exempt.get('lines')} 行）" if exempt else ""
            print(f"  {RULE_E1}   {b.key}  {b.lines} 行"
                  f"  @ {b.path}:{b.start_line}{note}")
    else:
        mode = "无**新增**" if args.baseline else "无"
        print(f"  {RULE_E1}  {mode}超限 extension 块 ✓"
              + ("（全量超限均已在基线内）" if args.baseline and over else ""))

    if stale:
        print(f"\n{GUARD_G2} 失效豁免 {len(stale)} 条（基线登记但块已不存在"
              "⇒ 可能已清偿，请同步基线）:")
        for k in stale[:30]:
            print(f"  {k}")

    print("-" * 68)
    print("信息型：块体量前 10（不参与判定）")
    for b in blocks[:10]:
        mark = "  ← 超限" if b.lines > args.limit else ""
        print(f"  {b.lines:>6} 行  {b.name:<34} {b.path}:{b.start_line}{mark}")

    if new_over or stale:
        return 1
    print("\n✅ extension 分块守卫：无新增超限，无失效豁免")
    return 0


if __name__ == "__main__":
    sys.exit(main())