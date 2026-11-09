#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V-7 · ADR-0014「不新增门禁道次」—— 可执行判据（T-20261107-01 甲类第 5 处）。

★ 2026-11-09 舰长裁定（「都做，按最优方案走」）：V-7 定值 **19 → 20 道**，
   唯一新增 = B0c 前半件 L0-b 分片外依赖静态审计（门禁 19/20）。
   ADR-0014 §2.3 已同批登记该例外；本判据语义不变 —— 仍守「不新增道次」，
   期望值仍硬编码取自 ADR 定值（异源，不取现场实测），21 道仍必红。

判据来源（ADR-0014 §2.3 V-7 原文，逐字对齐；下引为 19 道时期原文）
------------------------------------------------
「`grep -c 'echo "--> 门禁 .*/19' gate.sh` = 19，且
 `grep -n '门禁 19/19\\|门禁 .*/20' gate.sh` 命中数 = 0
（**分母非空**：打印全部匹配行清单 + 计数）；`gate.sh` 本批 `git status` 无改动。」

★ 两处口径必须分清（写错任一处，判据就失去意义）
------------------------------------------------
1. **精确锚 = `echo "--> 门禁`**，不是宽松的 `门禁 .*/19`。
   2026-11-07 现场实测：宽松口径返回 **20**，多出的那一处是**注释行**
   `#  本表现行总道数 = **19 道（0–18）**`（`gate.sh:24`）。
   ⇒ 用宽松口径，判据会「自己把自己判红」——数道数的判据必须锚 echo。
   本脚本对两种口径**都打印**，让差异持续可见（selftest 第 3 例专测这一点）。

2. **期望道数必须硬编码 20**（与 V-6 相反；19 道时期硬编码 19）。
   V-7 的判据本体是「道数**不变**」⇒ 期望值必须来自异源（ADR 定值），
   取现场实测值当期望就是「期望=实际」同源 ⇒ 恒真（`PRACTICES A3c` 第 1 条）。
   V-6 的分母反而**必须现场实测**（那里问的是「每道取数来源里有没有 E2」，
   分母是「现有几道」这个事实，不是「应该是几道」这个规格）。

范围边界（本卡守住，勿扩）
--------------------------
本判据**只守「不新增道次」**，不证明「E2 未进必过门」——
把 E2 判定塞进现有第 5 道、不新增 echo 行时道数仍 19、本脚本仍全绿，
此时由 **V-6 主锚**（`check_v6_e2_not_gate.py`，扫描每道取数来源）变红。
道数不变是必要条件、非充分条件（ADR §2.3 §4.2 F-14-2 两条违规形态）。

退出码：0 = 通过；1 = 判据红；2 = 环境不可判定（gate.sh 不存在 / 空扫）。
"""
from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GATE_REL = "scripts/gate.sh"

# ★ 精确锚（唯一正确的计数口径）
EXACT_ANCHOR = 'echo "--> 门禁'
# ★ 宽松口径（仅用于打印差异，**不用于判定**）。
#   必须与 20 道口径的 `grep -c '门禁 .*/20'` **逐字等价**：`.*` 而非 `\d+`。
#   ★ 2026-11-08 实测教训：初版写 `门禁\s+\d+/19`，漏掉 `gate.sh:24` 的注释行
#   `…与下方 echo「门禁 X/19」一致`（X 非数字）⇒ 宽松口径假报「20 与 19 差 0」
#   （20 道口径下同形：注释写「门禁 X/20」，宽松口径会比精确锚多计 1 行），
#   把「注释会被数成第 20 处」这个关键事实抹掉。判据自己看不全形态 = A3k-4 同款。
LOOSE_RE = re.compile(r"门禁.*/20")
# ★ 期望道数：硬编码，来源 = ADR-0014 §2.3 V-7 定值
#   （2026-11-09 舰长裁定升版：20 道 = 0–19）
EXPECTED_COUNT = 20

# ★ 异常编号形态（ADR 原文两条 + 一条扩展：≥20 的任意道次号）
BAD_PATTERNS = (
    (re.compile(r"门禁\s+20/20"), "末道编号写成 20/20（0–19 语境下应为 19/20）"),
    (re.compile(r"门禁\s+\d+/21"), "出现 /21 编号 ⇒ 道数被扩到 21"),
    (re.compile(r"门禁\s+(?:2[1-9]|[3-9]\d)/"), "出现 ≥21 的道次编号"),
)


def read_text(p: Path) -> str:
    return p.read_text(encoding="utf-8")


def scan(gate_path: Path) -> dict:
    """返回读数字典。空分层（无匹配行）由调用方判 exit 2。"""
    text = read_text(gate_path)
    lines = text.splitlines()
    exact = [(i + 1, ln) for i, ln in enumerate(lines) if EXACT_ANCHOR in ln]
    loose = [(i + 1, ln) for i, ln in enumerate(lines) if LOOSE_RE.search(ln)]
    bad = []
    for i, ln in enumerate(lines):
        for pat, why in BAD_PATTERNS:
            if pat.search(ln):
                bad.append((i + 1, ln.strip(), why))
                break
    return {"lines": len(lines), "exact": exact, "loose": loose, "bad": bad}


def report(res: dict, gate_label: str, verbose: bool = True) -> int:
    """verbose=True 时按 ADR 要求打印**全部**匹配行清单（分母非空）；
    selftest 用 verbose=False 只打印摘要，避免合成样本刷屏。"""
    n = len(res["exact"])
    print(f"V-7 道数守卫 · 扫描对象 = {gate_label}（{res['lines']} 行）")
    print(f"精确锚 = {EXACT_ANCHOR!r}（计数口径）")

    print(f"\n[分母非空] 精确锚匹配行清单（{n} 行）：")
    if verbose:
        for ln_no, ln in res["exact"]:
            print(f"  {gate_label}:{ln_no}: {ln.strip()}")
    else:
        print("  （selftest 摘要模式：清单略，真跑打印全部）")

    print(f"\n[口径对照] 宽松口径 门禁 .*/20 命中 {len(res['loose'])} 行"
          f"（差 {len(res['loose']) - n} 行 = 注释/非 echo 行；**不用于判定**）")
    if verbose:
        for ln_no, ln in res["loose"]:
            if EXACT_ANCHOR not in ln:
                print(f"  [非 echo 行，宽松口径误计] {gate_label}:{ln_no}: {ln.strip()}")

    print(f"\n道数 = {n} / 期望 {EXPECTED_COUNT}")
    print(f"[分母非空] 异常编号扫描（{len(res['bad'])} 行命中，期望 0）：")
    if verbose:
        for ln_no, ln, why in res["bad"]:
            print(f"  [命中] {gate_label}:{ln_no}: {ln} —— {why}")
    if not res["bad"]:
        print("  （无命中）")
    elif not verbose:
        print(f"  （selftest 摘要模式：{len(res['bad'])} 行清单略）")

    fails = []
    if n != EXPECTED_COUNT:
        fails.append(f"道数 {n} ≠ 期望 {EXPECTED_COUNT}（V-7：不新增门禁道次）")
    if res["bad"]:
        fails.append(f"异常道次编号 {len(res['bad'])} 处（见上清单）")

    print()
    if fails:
        for f in fails:
            print(f"[FAIL] {f}")
        print("\n处置：本 ADR 的验证层语义判定**不得新增门禁道次**"
              "（20 道为 2026-11-09 舰长裁定的唯一例外）。"
              "\n  再增道次须另批报批并同步 ADR 定值。")
        return 1
    print(f"[PASS] V-7：道数 = {n}（期望 {EXPECTED_COUNT}）· 异常编号 0 命中"
          f" · 精确锚与宽松口径差 {len(res['loose']) - n} 行（已逐行打印，非注释误计）。")
    return 0


# ─────────────────────────── selftest ───────────────────────────

def _mk_gate(path: Path, n: int, comment: bool = False, last_bad: str | None = None) -> None:
    """造一份 n 道的 gate.sh 样本；last_bad 替换末道编号（造异常编号而不改道数）。"""
    out = []
    if comment:
        # ★ 逐字照抄真文件 gate.sh:24 的形态（`门禁 X/19`，X 非数字）
        out.append('#      本表现行总道数 = **20 道（0–19）**，与下方 echo「门禁 X/20」一致。')
    for k in range(n):
        seq = f"{k}/{n}"
        if last_bad is not None and k == n - 1:
            seq = last_bad
        out.append(f'echo "--> 门禁 {seq}: 道 {k}"')
    path.write_text("\n".join(out) + "\n", encoding="utf-8")


def selftest() -> int:
    print("=" * 68)
    print("selftest · 用合成样本证明判据有牙（可红可绿）")
    print("=" * 68)
    # ★ 第二列 expect_loose 不是「道数」，而是要证明「宽松口径**不是**道数计数器」：
    #   ② 21 道时它数成 **0**（所有 echo 都写 /21，不匹配 /20）—— 比多计 1 更危险；
    #   ③ 20 道 + 注释时它数成 **21**（注释里的「门禁 X/20」被算一道）。
    #   两个方向都错 ⇒ 精确锚是唯一可用的计数口径。
    cases = [
        ("① 正例：20 道，无注释，无异常编号", dict(n=20), 0, 20),
        ("② 负例：21 道 ⇒ 宽松口径反而数成 0（全部 /21，不匹配 /20）", dict(n=21), 1, 0),
        ("③ 边界：20 道 + 注释行「…echo「门禁 X/20」一致」"
         "（精确锚 20 / 宽松 21，差 1 行 = 注释）", dict(n=20, comment=True), 0, 21),
        ("④ 负例：20 道但末道编号写成 20/20（异常编号，道数不变）",
         dict(n=20, last_bad="20/20"), 1, 20),
        ("⑤ 负例：21 道 + 一道写成 /21（道数已变 21）", dict(n=21, last_bad="18/21"), 1, 0),
    ]
    failed = 0
    with tempfile.TemporaryDirectory() as td:
        for i, (name, kw, expect_rc, expect_loose) in enumerate(cases, 1):
            p = Path(td) / f"gate_case{i}.sh"
            _mk_gate(p, **kw)
            print(f"\n--- 用例 {name}")
            res = scan(p)
            rc = report(res, p.name, verbose=False)
            # ★ 第二条断言：宽松口径必须把注释行也数进去（否则「差 0 行」是假读数）
            loose_ok = len(res["loose"]) == expect_loose
            ok = rc == expect_rc and loose_ok
            print(f"    期望 rc={expect_rc} · 实测 rc={rc} ⇒ {'OK' if rc == expect_rc else '不符'}")
            print(f"    期望宽松口径={expect_loose} · 实测={len(res['loose'])}"
                  f" ⇒ {'OK' if loose_ok else '不符（正则与 bash 不等价）'}")
            failed += 0 if ok else 1
    print()
    if failed:
        print(f"[SELFTEST FAIL] {failed} 例不符预期 ⇒ 判据自身不可信，不得用于验收。")
        return 1
    print(f"[SELFTEST PASS] {len(cases)} 例全部符合预期"
          f"（红例必红、绿例必绿、注释边界不吃）。")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(add_help=True, description="V-7 道数守卫（ADR-0014）")
    ap.add_argument("--selftest", action="store_true", help="跑合成样本自测（不碰真文件）")
    ap.add_argument("--gate", default=str(ROOT / GATE_REL), help="gate.sh 路径（默认仓库内）")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()

    gate = Path(args.gate)
    if not gate.is_file():
        print(f"[EXIT 2] 环境不可判定：找不到 {gate}（fail-closed，不当过）")
        return 2
    res = scan(gate)
    if not res["exact"]:
        print(f"[EXIT 2] 空扫：{gate} 内 0 行匹配精确锚 {EXACT_ANCHOR!r}"
              f" ⇒ 判据的分母为空，不能判绿（fail-closed）")
        return 2
    label = GATE_REL if gate == ROOT / GATE_REL else str(gate)
    return report(res, label)


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main(sys.argv[1:]))
