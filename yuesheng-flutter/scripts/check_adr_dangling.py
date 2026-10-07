#!/usr/bin/env python3
"""守卫：ADR 引用不得悬空（被引用的编号必须有实体文件）。

★ 为什么需要（机制缺口，非单次事故）：
  `.ai/adr/` 的编号↔实体对应关系**只靠人记**，没有任何机器执行点。
  2026-10-07 实测：`ADR-0001` 在 `.ai` 文档里被引9 次，但 `.ai/adr/` 下
  **无 0001 实体文件**（原始 ADR 从未落盘）⇒ 引用指向一份不存在的记录，
  却长期无人发现。已按`PROJECT.md §6`「能力地图」先例处置为**如实登记缺口**
  （见 `.ai/adr/README.md` 与 `STATE §2` 的 ADR-0001/0002 缺口跟踪行）。
  ⇒ 但登记是**一次性**的；缺一个「引用→实体」的自动校验，下一个悬空编号还会漂。

判据（G1–G3）：
  G1 扫不到任何 ADR 引用 ⇒ exit 2（fail-closed，防「扫不到就当过」）
  G2 **悬空引用**：被引用的编号在 `.ai/adr/` 下无`NNNN-*.md` 实体 ⇒ FAIL，
     但**豁免已在 `.ai/adr/README.md` 登记为「原始缺失」/「已如实登记」的编号**
     （豁免必须带原因，防「什么都豁免」）
  G3 `.ai/adr/README.md` 索引里登记的编号若已无实体 ⇒ WARN 级提醒（索引陈旧）

豁免口径：**只认显式登记**，不认「看起来是历史遗留」。
新增悬空编号必须写进 EXEMPT 并给出原因 —— 这让「补实体」与「承认缺失」
两条路都被显式化，而不是靠沉默。

用法：
  python scripts/check_adr_dangling.py
  python scripts/check_adr_dangling.py --base <ref>   # 只查相对 base 新增的悬空引用

退出码：0 = 通过；1 = 有未豁免的悬空引用；2 = 空扫/环境不可判定。
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FLUTTER_ROOT = os.path.dirname(HERE)          # yuesheng-flutter/
REPO_ROOT = os.path.dirname(FLUTTER_ROOT)      # D:/ai-teacher（monorepo 根）
ADR_DIR = os.path.join(REPO_ROOT, ".ai", "adr")
ADR_INDEX = os.path.join(ADR_DIR, "README.md")

ADR_RE = re.compile(r"ADR-(\d{4})(?!-)")
# ⚠️ 正则纪律（2026-10-07 实踩）：**必须带 `(?!-)`负向断言**。
#   否则 `ADR-2026-09-16-setting-library-pending.md` 这类
#   「ADR 前缀 + 日期」的**文件名**会被误纳为编号 `2026` ⇒ 假阳性。
#   实证：`.ai/reports/2026-09-16-设定资料库改造监控.md:171` 的 `ADR-2026-09-16-...`
#   是文件名不是编号，且该文件**本就不存在且已被如实登记**（同文件 :179）。

# ★ 键型纪律（2026-10-07 实踩）：本表的键是**裸 4 位数字**（与 scan_refs() 的
#   返回键型一致），**不要**写成 `ADR-0001` 形式 —— 键型不一致会让豁免
#   **静默失效**（实测：表里写 'ADR-0001'、扫描返回 '0001' ⇒ 永不相match，
#   给出「已处置」的假象，比没有豁免更坏）。
EXEMPT: dict[str, str] = {
    "0001": "原始 ADR 从未落盘，且**代码侧零引用**（lib/test/integration_test 全零命中）；"
            "已按 PROJECT.md §6「能力地图」先例在 .ai/adr/README.md + "
            "STATE §2「ADR-0001 / ADR-0002 编号缺口」行如实登记为**永久缺失**"
            "（非待办、不补文件、不编内容）。",
}


def _git(*args: str) -> str | None:
    try:
        r = subprocess.run(["git", *args], cwd=REPO_ROOT, capture_output=True,
                           text=True, timeout=60, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def existing_adrs() -> set[str]:
    if not os.path.isdir(ADR_DIR):
        return set()
    out = set()
    for fn in os.listdir(ADR_DIR):
        m = re.match(r"^(\d{4})-.*\.md$", fn)
        if m:
            out.add(m.group(1))
    return out


def scan_refs() -> dict[str, set[str]]:
    """{编号: {引用该编号的文件路径}} ——扫代码 + .ai 文档。"""
    refs: dict[str, set[str]] = {}
    roots = [
        os.path.join(FLUTTER_ROOT, "lib"),
        os.path.join(FLUTTER_ROOT, "test"),
        os.path.join(FLUTTER_ROOT, "integration_test"),
        os.path.join(REPO_ROOT, ".ai"),
    ]
    for root in roots:
        if not os.path.isdir(root):
            continue
        for dirpath, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".git", "__pycache__", "build"}]
            for fn in files:
                if not fn.endswith((".dart", ".md")):
                    continue
                full = os.path.join(dirpath, fn)
                try:
                    with open(full, encoding="utf-8", errors="ignore") as fh:
                        text = fh.read()
                except OSError:
                    continue
                rel = os.path.relpath(full, REPO_ROOT).replace("\\", "/")
                for m in ADR_RE.finditer(text):
                    refs.setdefault(m.group(1), set()).add(rel)
    return refs


def index_adrs() -> set[str]:
    if not os.path.exists(ADR_INDEX):
        return set()
    try:
        with open(ADR_INDEX, encoding="utf-8") as fh:
            return set(ADR_RE.findall(fh.read()))
    except OSError:
        return set()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=None,
                    help="只报相对该 ref 新增的悬空引用（默认全量）")
    args = ap.parse_args()

    if not os.path.isdir(ADR_DIR):
        print(f"[FAIL] .ai/adr/ 不存在：{ADR_DIR}")
        return 2

    refs = scan_refs()
    exist = existing_adrs()
    idx = index_adrs()

    # G1 空扫 fail-closed
    if not refs:
        print("[FAIL] G1：全仓未扫到任何 ADR-NNNN 引用 —— "
              "判据失效（正则/路径漂移）或确无引用。按 fail-closed 拒绝放行。")
        return 2

    # --base 模式：只看新增引用
    new_only: set[str] | None = None
    if args.base:
        prefix = (_git("rev-parse", "--show-prefix") or "").replace("\\", "/")
        if prefix and not prefix.endswith("/"):
            prefix += "/"
        new_only = set()
        for args_ in (["diff", "--name-only", args.base],
                      ["diff", "--name-only", "--cached", args.base],
                      ["ls-files", "--others", "--exclude-standard"]):
            txt = _git(*args_)
            for line in (txt or "").splitlines():
                p = line.strip().replace("\\", "/")
                if p and prefix and p.startswith(prefix):
                    p = p[len(prefix):]
                full = os.path.join(REPO_ROOT, p.replace("/", os.sep))
                if not os.path.isfile(full):
                    continue
                try:
                    with open(full, encoding="utf-8", errors="ignore") as fh:
                        t = fh.read()
                except OSError:
                    continue
                for m in ADR_RE.finditer(t):
                    new_only.add(m.group(1))

    dangling = {n: files for n, files in refs.items() if n not in exist}
    fails: list[str] = []

    for num in sorted(dangling):
        if new_only is not None and num not in new_only:
            continue  # 既存悬空，不在本次范围
        if num in EXEMPT:
            print(f"[EXEMPT] {num} 悬空但已登记豁免：{EXEMPT[num]}")
            print(f"         引用处（{len(dangling[num])} 个文件）已如实登记，非笔误。")
            continue
        sample = sorted(dangling[num])[:6]
        more = f" …等 {len(dangling[num])} 个" if len(dangling[num]) > 6 else ""
        fails.append(
            f"ADR-{num} 被引{len(dangling[num])} 处但 `.ai/adr/` 下无实体文件"
            f"（悬空引用）\n引用处：{', '.join(sample)}{more}"
        )

    # G3 索引陈旧提醒（★ 已豁免的编号**不算陈旧** —— 索引登记它正是索引的职责：
    #   「这个编号没有实体，因为原始 ADR 从未落盘」本身就是有效信息）
    for num in sorted(idx - exist - set(EXEMPT)):
        print(f"[WARN] `.ai/adr/README.md` 索引登记了 ADR-{num}，但已无实体文件 —— 索引陈旧。")

    if fails:
        print()
        for f in fails:
            print(f"[FAIL] {f}")
        print(f"\n共 {len(fails)} 项未豁免的悬空引用。处置二选一："
              f"\n  (a) 补实体文件 `.ai/adr/{sorted(dangling)[0]}-<标题>.md`"
              f"\n  (b) 若确为「原始实体从未落盘」，写进本脚本 EXEMPT 表并给出原因"
              f"（照实登记，禁止沉默）")
        return 1

    total = sum(len(v) for v in refs.values())
    print(f"[PASS] ADR 引用守卫：{len(refs)} 个编号 / {total} 处引用，"
          f"无未豁免的悬空引用（实体 {len(exist)} 个：{sorted(exist)}）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())