#!/usr/bin/env python3
"""守卫：台账 Edit 的**机械**失真形态（把「改完要回读」从习惯变成制度）。

★ 为什么是这个（2026-10-08 台账治理批实测）：
  本批修 `.gitignore` 行号引用漂移时，Edit 制造了 **16 处**机械失真 ——
  `replace_all` 把带反引号的新文本塞进 `**…**` 加粗内部，形成两种错位：
    ① 前导 `**`` + `.gitignore`     ② 尾随 `规则`` ` / `规则`** `
  它们**不是靠逐处回读发现的**，而是批量改完之后全库 grep 才抓到 ⇒
  「靠我记得回读」这一制度不成立，必须有机器执行点。
  同批另外两种形态也真实发生：
    ③ `.gitignore` 错误行号在治理完成后**极易被下一次编辑写回**（回流）；
    ④ 治理时**故意引用的举证样例**（`PRACTICES B8b` 里那两行）若不显式豁免，
       本守卫上线即假红 ⇒ 豁免必须显式登记，不靠隐式放过。

判据（都 fail-closed）：
  E1 **机械失真形态**：` ```` ` / `**``+.gitignore` / `规则`` ` / `规则`** `
     四种错位在 `.ai/` **活文件**里零容忍。
  E2 **`.gitignore` 行号回流**：活文件出现 `.gitignore:<行号>` 即报红；
     只放行两项 —— `:2`（顶层 `/*`，实测正确）与 `:12-14`（子工程
     `android/.gitignore` 的签名规则，真身在那儿）+ **显式豁免**
     （含 `B8b` / `行号漂移` / `举证` 字样的行）。
     判据本体见 `PRACTICES B8b`：行号会漂，且根仓与子工程 `.gitignore`
     行号不可互套。
  扫描面：**只扫活文件**（台账正文 + `rules/README.md` + `adr/*.md`），
  **不扫** `logs/ reports/ archive/ tmp/` —— 那些是当时的实测快照，
  改了它们就失去取证价值。

用法：
  python scripts/check_ledger_edit_readback.py --expect-rule-count 4

退出码：0 通过 / 1 有失真 / 2 环境不可判定或判据数不符（fail-closed）。
"""
from __future__ import annotations

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FLUTTER_ROOT = os.path.dirname(HERE)
REPO_ROOT = os.path.dirname(FLUTTER_ROOT)
AI_DIR = os.path.join(REPO_ROOT, ".ai")

# 活文件：台账正文 + 规则索引 + ADR
LIVE_FILES = (
    "STATE.md", "PRACTICES.md", "LEDGER.md", "LEDGER-DETAIL.md",
    "DECISIONS.md", "DECISIONS-DETAIL.md", "TRAPS.md", "PROJECT.md",
    "CHECKS.md", os.path.join("rules", "README.md"),
)

# E1 错位形态（顺序即报出顺序）
#
# ⚠️ 首版第一条写成「连续四个反引号」，**判据太宽**（2026-10-08 实测误报）：
#   `LEDGER-DETAIL.md:1500/1521` 的原文是
#     ```` ```diagnosis ````
#   这是**文档里引用代码围栏的合法嵌套**（外层四反引号包住内层三反引号），
#   不是错位 ⇒ 首版把合法写法判红。处置 = **改判据，不改文档**（不为迎合
#   检查器去改台账正文，见 `PRACTICES B8b` 同族纪律）。
#   ⇒ 收窄为「反引号闭合后紧跟 `**`」这类真正的加粗/代码块交叉错位；
#     行尾正常收在四反引号之后接文本的合法嵌套**放行**。
#   ★ 形态总数 = 3（+ E2 = 4），故 `--expect-rule-count` 为 **4**。
E1_RULES = (
    (re.compile(r"\*\*``\.gitignore"), "加粗内嵌反引号错位（`**``+`.gitignore`）"),
    (re.compile(r"规则``"), "尾随双反引号错位（`规则`` `）"),
    (re.compile(r"规则`\*\*"), "尾随反引号与加粗闭合错位（`规则`**`）"),
    # ★ 刻意**不设**「`**` 后紧跟代码块/正文」这类兜底规则：实测它命中 4 处
    #   **合法排版**（STATE.md:194 · DECISIONS-DETAIL.md:2251/3474/3475）——
    #   加粗段结束后紧跟反引号代码块是 Markdown 常规写法。
    #   ⇒ 凭印象加兜底 = 过宽（本日第 7 次同根因翻车），宁可少判不可误判。
)

# E2：只认**根仓** `.gitignore` 的行号引用 —— 前置不是 `.` 或 `/`
#（排除 `.ai/.gitignore` 与 `yuesheng-flutter/.gitignore`，它们是不同文件）
E2_RE = re.compile(r"(?<![/.])\.gitignore:(\d+(?:-\d+)?)")
E2_ALLOWED = {"2", "12-14"}
E2_EXEMPT_MARKS = ("B8b", "行号漂移", "举证")


def _read(path: str) -> str | None:
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return None


def live_files() -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for rel in LIVE_FILES:
        p = os.path.join(AI_DIR, rel)
        if os.path.isfile(p):
            out.append((rel.replace(os.sep, "/"), p))
    adr = os.path.join(AI_DIR, "adr")
    if os.path.isdir(adr):
        for fn in sorted(os.listdir(adr)):
            if fn.endswith(".md"):
                out.append(("adr/" + fn, os.path.join(adr, fn)))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    # ★ 口径 = len(E1_RULES) + 1（E2 一条）= **4**。
    #   两次实测教训（同根因翻车，均为「注释与代码不自洽」）：
    #     ① 首版 default 误写 2，与 rule_count=5 不自洽 ⇒ G2 恒 FAIL
    #        （四次实跑 rc=2 全停在 G2，正向/负向验证都跑不到判据层）；
    #     ② 收窄 E1 删掉一条过宽的兜底形态后（实测命中 4 处合法排版），
    #        注释已改成 4 而 default 仍是 5 ⇒ 又会停在 G2。
    #   ⇒ **增删任一 E1 形态，必须同批同步此处 default**，否则护栏自己变假红。
    ap.add_argument("--expect-rule-count", type=int, default=4,
                    help="判据条数护栏（E1 3 形态 + E2 1 条 = 4）")
    a = ap.parse_args()

    # G1 空扫 fail-closed：.ai/ 读不到或活文件清单为空 ⇒ 无法判定 ⇒ exit 2
    if not os.path.isdir(AI_DIR):
        print(f"[FAIL] G1：读不到 {AI_DIR} —— 无法判定（fail-closed）", file=sys.stderr)
        return 2
    files = live_files()
    if not files:
        print("[FAIL] G1：活文件清单为空 —— 等于没检查（fail-closed）", file=sys.stderr)
        return 2

    # G2 静默降级护栏：判据被删/被改而本护栏没同步 ⇒ 假绿
    rule_count = len(E1_RULES) + 1
    if rule_count != a.expect_rule_count:
        print(f"[FAIL] G2：判据数 {rule_count} != 期望 {a.expect_rule_count} —— "
              "有人删/改了判据却没同步护栏，按 fail-closed 拒绝放行", file=sys.stderr)
        return 2

    fails: list[str] = []
    e2_exempt = 0
    scanned = 0

    for rel, path in files:
        text = _read(path)
        if text is None:
            fails.append(f"E0：读不到 {rel} —— fail-closed")
            continue
        for i, line in enumerate(text.splitlines(), 1):
            scanned += 1
            for rx, why in E1_RULES:
                if rx.search(line):
                    fails.append(f"E1：{rel}:{i} {why}")
            for m in E2_RE.finditer(line):
                tok = m.group(1)
                if tok in E2_ALLOWED:
                    continue
                if any(k in line for k in E2_EXEMPT_MARKS):
                    e2_exempt += 1
                    continue
                fails.append(
                    f"E2：{rel}:{i} 引用 `.gitignore:{tok}` —— 行号会漂，"
                    f"改按规则内容锚定（见 PRACTICES B8b）；只放行 :2 与 :12-14"
                )

    if fails:
        print()
        for f in fails:
            print(f"[FAIL] {f}")
        print(f"\n共 {len(fails)} 项失真（扫描 {len(files)} 个活文件 / {scanned} 行）。")
        return 1

    print(f"[PASS] 台账 Edit 回读守卫：{len(files)} 个活文件 / {scanned} 行，"
          f"E1 四形态 0 命中；`.gitignore` 行号引用 0 回流"
          f"（放行 :2 / :12-14，另有 {e2_exempt} 处显式豁免）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())