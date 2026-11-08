#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V-6 · ADR-0014「验证层 E2 语义判定读数永不进必过门」—— **主锚**执行点
（T-20261107-01 甲类第 4 处 · 全卡最关键的一处）。

判据来源（ADR-0014 §2.3 V-6 原文，逐字对齐）
--------------------------------------------
「**主锚**: 断言「验证层 E2 语义判定读数**不出现在任何一道的 PASS 判定输入 /
 `hits_added` 计数来源里」——扫描 `gate.sh` **每道的输入产物路径清单**,
 **分母非空：显式打印全部道次清单（道数 N 取现场 `grep` 实测、不硬编码数字）
 + 逐道命中计数**, 任一道命中 `验证层E2读数` 标识或 E2 产物路径 ⇒ 红。
 「塞进现有第 5 道作该道 PASS 输入、不新增 echo 行、道数仍 19」与「新增第 20 道」
 两种违规形态**都变红**（判据锚在每道取数清单、不在道数）。」

★ 为什么这条不能用 V-7 顶替
  V-7 只数道数。把 E2 判定塞进现有第 5 道、不新增 echo 行时道数仍 19、V-7 全绿，
  而规格已被违反 ⇒ **V-7 是必要条件、非充分条件**（ADR §2.3 §4.2 F-14-2 原文）。
  本脚本锚在「每道**取数来源**」，因此两种违规形态都变红。

★★ 两个必须做对的技术点（做错任一处，判据就变成摆设）
-------------------------------------------------------
**其一：取数路径常藏在**变量**里，不是字面路径。**
  gate.sh 写法是 `COVERAGE_LOG="$OUT_DIR/coverage.txt"`（第 113–139 行区）再在道内
  `> "$COVERAGE_LOG"`。只扫道内文本会只看 `$COVERAGE_LOG` 这个**名字**，
  看不到它指向哪个文件 ⇒ 必须先把全文的 `VAR=…` 建成映射再解析引用。
  本脚本对**变量名**与**解析后的路径**都做标识匹配（两条都算命中）：
  名字叫 `VERIF_E2_LOG` 的文件，和 `L="$OUT_DIR/verify_e2.txt"` 一样违规。

**其二：`verif` 子串会撞上英文动词。**
  `gate.sh:578` 现有 `echo "FAIL: evidence lib unreadable, cannot verify lcov freshness"`
  —— 那是 `verify`（动词），不是验证层产物。若按 `verif` 子串匹配，本判据**一上来就假红**。
  ⇒ 标识定为：`\bE2\b` / `验证层` / `verification`（名词）/ `verificationGate`，
  **不含**裸 `verify`。selftest 第 4 例专测这条边界。

退出码：0 = 通过；1 = 判据红（某道取数来源指向 E2 读数）；2 = 环境不可判定（切不出道次）。
"""
from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GATE_REL = "scripts/gate.sh"

# ★ 道次分割锚（与 check_v7_gate_count.py 同一精确锚；**不硬编码道数**）
STAGE_ANCHOR = 'echo "--> 门禁'
STAGE_RE = re.compile(r'echo\s+"-->\s*门禁\s*([0-9]+)/([0-9]+)\s*:\s*(.*?)"')

# ★ E2 / 验证层产物标识 —— **两套**，因为变量名与路径的形态不同：
#   ① 变量名：全大写，认 `VERIF` / `VERIFICATION` / `E2`（全部变量名都是大写形态，
#      不会撞上英文动词）。
#   ② 路径文本：`verify` 后**必须跟** `_` 或 `-`（`verify_e2_readout.jsonl` 命中、
#      `cannot verify lcov` 不命中 —— 后者 verify 后是空格）。
#   ★ 2026-11-08 实测教训：初版只用 `\bE2\b|verification` 一套，
#     `VERIF_LOG` 与 `verify_e2_readout.jsonl` **两个都不命中** ⇒「塞进现有道」
#     这个最关键的违规形态被判绿（selftest 用例②当场抓出）。
#     另：`\bE2\b` 对 `_e2_` 无效（`_` 是 word 字符，无词边界）⇒ 补 `_e2`。
E2_IDENT_VAR = re.compile(r"VERIF|VERIFICATION|(?:^|_)E2(?:_|$)")
E2_IDENT_TEXT = re.compile(
    r"\bE2\b|验证层|verification|verify[_-]|verif[_-]|_verif|_e2", re.IGNORECASE)

# 变量赋值：VAR="..." 或 VAR=...
VAR_ASSIGN = re.compile(r'^\s*([A-Z][A-Z0-9_]*)=("?)([^"\n]*)\2\s*$', re.MULTILINE)
# 道内变量引用：$VAR / ${VAR}
VAR_REF = re.compile(r"\$\{?([A-Z][A-Z0-9_]*)\}?")
# 道内字面路径：outputs/… 或 "$OUT_DIR/…"
LIT_PATH = re.compile(r'"?\$?\{?OUT_DIR\}?/([A-Za-z0-9_.\-/]+)"?')


def parse_var_map(text: str) -> dict[str, str]:
    """全文 VAR=value 映射（取最后一次赋值，后写覆盖前写）。"""
    m: dict[str, str] = {}
    for mo in VAR_ASSIGN.finditer(text):
        m[mo.group(1)] = mo.group(3).strip()
    return m


def split_stages(text: str) -> list[dict]:
    """按精确锚切段。返回 [{no, total, title, line, body}]。"""
    lines = text.splitlines()
    idx = [i for i, ln in enumerate(lines) if STAGE_ANCHOR in ln]
    stages = []
    for k, i in enumerate(idx):
        end = idx[k + 1] if k + 1 < len(idx) else len(lines)
        mo = STAGE_RE.search(lines[i])
        stages.append({
            "no": int(mo.group(1)) if mo else -1,
            "total": int(mo.group(2)) if mo else -1,
            "title": (mo.group(3) if mo else lines[i]).strip(),
            "line": i + 1,
            "body": "\n".join(lines[i:end]),
        })
    return stages


def extract_sources(body: str, var_map: dict[str, str]) -> list[dict]:
    """道内取数来源：变量引用（含解析路径）+ 字面路径。"""
    out, seen = [], set()
    for mo in VAR_REF.finditer(body):
        name = mo.group(1)
        if name in ("OUT_DIR",):
            continue
        resolved = var_map.get(name, "")
        key = ("var", name)
        if key in seen:
            continue
        seen.add(key)
        out.append({"kind": "var", "ref": f"${name}", "resolved": resolved})
    for mo in LIT_PATH.finditer(body):
        ref = f"$OUT_DIR/{mo.group(1)}"
        key = ("lit", ref)
        if key in seen:
            continue
        seen.add(key)
        out.append({"kind": "lit", "ref": ref, "resolved": ref})
    return out


def judge_stage(st: dict, var_map: dict[str, str]) -> dict:
    srcs = extract_sources(st["body"], var_map)
    hits = []
    if E2_IDENT_TEXT.search(st["title"]):
        hits.append({"where": "道名", "detail": st["title"]})
    for s in srcs:
        if s["kind"] == "var" and E2_IDENT_VAR.search(s["ref"]):
            hits.append({"where": "变量名", "detail": s["ref"]})
        elif E2_IDENT_TEXT.search(s["ref"]):
            hits.append({"where": "变量名(文本形态)", "detail": s["ref"]})
        elif s["resolved"] and E2_IDENT_TEXT.search(s["resolved"]):
            hits.append({"where": "解析路径", "detail": f"{s['ref']} → {s['resolved']}"})
    return {**st, "sources": srcs, "hits": hits}


def scan(gate_path: Path) -> dict:
    text = gate_path.read_text(encoding="utf-8", errors="replace")
    var_map = parse_var_map(text)
    stages = [judge_stage(st, var_map) for st in split_stages(text)]
    return {"gate": gate_path, "var_map": var_map, "stages": stages,
            "n_stages": len(stages),
            "n_hits": sum(len(s["hits"]) for s in stages)}


def report(res: dict, gate_label: str, verbose: bool = True) -> int:
    n = res["n_stages"]
    print(f"V-6 主锚 · E2 读数不进必过门 · 扫描对象 = {gate_label}")
    print(f"切段锚 = {STAGE_ANCHOR!r} · **道数现场实测 = {n}**（不硬编码）")
    print(f"变量映射表（{len(res['var_map'])} 条 VAR=…）：")
    for k, v in sorted(res["var_map"].items()):
        print(f"  {k} = {v}")

    print(f"\n[分母非空] 全部道次清单 + 逐道取数来源与命中计数：")
    for s in res["stages"]:
        srcs = ", ".join(x["ref"] for x in s["sources"]) or "（无取数变量/路径）"
        flag = f"**命中 {len(s['hits'])}**" if s["hits"] else "命中 0"
        print(f"  道 {s['no']:>2}/{s['total']} · L{s['line']} · {s['title'][:28]:<28}"
              f" | 取数 {len(s['sources'])} 项：{srcs[:60]} | {flag}")
        if verbose:
            for h in s["hits"]:
                print(f"      [命中] {h['where']}：{h['detail']}")

    print()
    if res["n_hits"]:
        print(f"[FAIL] V-6：{res['n_hits']} 处取数来源指向验证层 E2 读数（期望 0）。")
        print("处置：E2 语义判定只能作方向性判断，永不进必过门（协议 §十四 + 选型终裁单 §四）。"
              "\n  违规形态两种：① 塞进现有某道作 PASS 输入（道数不变，V-7 抓不到）；"
              "\n                ② 新增一道（道数变，V-7 也抓，但本判据先抓）。")
        return 1
    print(f"[PASS] V-6：{n} 道全部取数来源均无 E2 / 验证层标识"
          f"（逐道清单见上，道数现场实测、未硬编码）。")
    return 0


# ─────────────────────────── selftest ───────────────────────────

_HEAD = """\
OUT_DIR="$ROOT/outputs/gate"
FORMAT_LOG="$OUT_DIR/format.txt"
COVERAGE_LOG="$OUT_DIR/coverage.txt"
VERIF_LOG="$OUT_DIR/verify_e2_readout.jsonl"
HITS_LOG="$OUT_DIR/hits.jsonl"
"""


def _mk_gate(path: Path, n: int = 19, poison_stage: int | None = None,
             extra_stage: bool = False, noise: bool = False) -> None:
    out = [_HEAD]
    for k in range(n):
        out.append(f'echo "--> 门禁 {k}/{n}: 道 {k}"')
        if poison_stage is not None and k == poison_stage:
            out.append(f'dart run tool/x.dart > "$VERIF_LOG" 2>&1')
        else:
            out.append(f'echo hi > "$FORMAT_LOG"')
        if noise:
            out.append('echo "FAIL: evidence lib unreadable, cannot verify lcov freshness"')
        out.append(f'log_result "道 {k}" "$RC_{k}"')
    if extra_stage:
        out.append(f'echo "--> 门禁 {n}/{n}: 偷偷加的验证层道"')
        out.append('python tool/judge.dart > "$VERIF_LOG" 2>&1')
        out.append('log_result "验证层 E2 读数" "$RC_X"')
    path.write_text("\n".join(out) + "\n", encoding="utf-8")


def selftest() -> int:
    print("selftest · 两种违规形态都必红 + 英文动词 verify 不误伤")
    cases = [
        ("① 正例：19 道，取数来源全是普通 log，无 E2 标识", dict(), 0),
        ("② 负例·塞进现有道：第 5 道取数改成 $VERIF_LOG（不新增 echo，道数仍 19）",
         dict(poison_stage=5), 1),
        ("③ 负例·新增道：追加第 20 道「验证层 E2 读数」", dict(extra_stage=True), 1),
        ("④ 正例·边界：段内含英文动词 “cannot verify lcov”（不得假红）",
         dict(noise=True), 0),
    ]
    failed = 0
    with tempfile.TemporaryDirectory() as td:
        for i, (name, kw, expect_rc) in enumerate(cases, 1):
            p = Path(td) / f"gate_case{i}.sh"
            _mk_gate(p, **kw)
            print(f"\n--- 用例 {name}")
            res = scan(p)
            rc = report(res, p.name, verbose=False)
            n_ok = res["n_stages"] == (20 if kw.get("extra_stage") else 19)
            ok = rc == expect_rc and n_ok
            print(f"    期望 rc={expect_rc}/道数{'20' if kw.get('extra_stage') else '19'}"
                  f" · 实测 rc={rc}/道数{res['n_stages']} ⇒ {'OK' if ok else '不符'}")
            failed += 0 if ok else 1
    print()
    if failed:
        print(f"[SELFTEST FAIL] {failed} 例不符预期 ⇒ 判据自身不可信。")
        return 1
    print(f"[SELFTEST PASS] {len(cases)} 例全部符合预期"
          f"（塞进现有道必红、新增道必红、英文 verify 不误伤）。")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(add_help=True, description="V-6 E2 不进必过门主锚（ADR-0014）")
    ap.add_argument("--selftest", action="store_true", help="跑合成样本自测")
    ap.add_argument("--gate", default=str(ROOT / GATE_REL), help="gate.sh 路径")
    ap.add_argument("--quiet", action="store_true", help="不打印逐道命中明细")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    gate = Path(args.gate)
    if not gate.is_file():
        print(f"[EXIT 2] 环境不可判定：找不到 {gate}（fail-closed）。")
        return 2
    res = scan(gate)
    if res["n_stages"] == 0:
        print(f"[EXIT 2] 空扫：0 行匹配切段锚 {STAGE_ANCHOR!r} ⇒ 分母为空（fail-closed）。")
        return 2
    label = GATE_REL if gate == ROOT / GATE_REL else str(gate)
    return report(res, label, verbose=not args.quiet)


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main(sys.argv[1:]))
