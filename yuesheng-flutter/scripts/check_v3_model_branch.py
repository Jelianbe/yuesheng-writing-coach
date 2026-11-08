#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V-3② · ADR-0014「零厂商识别」—— 按模型名做分支的引用扫描（T-20261107-01 甲类第 2 处）。

判据来源（ADR-0014 §2.2 V-3② 原文）
------------------------------------
「② 分支扫描：按模型名做 `if/switch` 分支的引用命中数 = 0
（**分母非空**：打印分支扫描文件清单 N + 逐文件 `if/switch` 引用命中计数）。」

★ V-3① 与 V-3② 的分工
  V-3① 查「字面量**存在**」；V-3② 查「分支**依赖模型身份**」。`const kX = 'deepseek'`
  只红 ①；`if (model == kX)` 无字面量、① 绿，须由 ② 的 H2c 抓 —— 两条不可互替。

命中条件（H1 / H2 / H2b / H2c 作用于分支条件；H3 作用于 switch case；H4 行级）
  H1  条件里出现厂商词 / 模型族前缀的**字符串字面量**。
  H2  条件里同时有 `model` 标识符与**任意**字符串字面量。
  H2b 条件里对模型名做字符串匹配（`.contains(` / `.startsWith(` / `.endsWith(`
      / `.toLowerCase(` / `.toUpperCase(`）。
  H2c 条件里 `model` 与**标识符**做 `==`/`!=`（排除 null/true/false/数字）
      —— 补 H2 的漏：字面量被提成常量后 H2 抓不到。
  H3  `switch` 体的 `case '...'` 标签含厂商/模型词。
  H4  三元 / 条件表达式**行级粗判**：行内含 `model`、含**单个** `?`（排除 `??` `?.`）、
      且 `?` 之后还有 `:` ⇒ 再按 H1/H2/H2b/H2c 的同一套线索判定。

★ **H4 是超出 ADR 字面的扩展，必须知道**：ADR 原文只写「`if/switch` 分支」。但 Dart 里
  `model == kX ? a : b` 与
  `if (model == kX) …` **语义等价**，不覆盖它 ⇒ 规避成本只有「改写成三元」一步，
  判据等于没有牙。本卡按**规格意图**（不得按模型身份改变行为）覆盖，并如实标为
  口径扩展：行级粗判**可能误报，命中须人核** —— 误报成本 = 看一眼，
  漏报成本 = 判据形同虚设。若舰长认为须严格限定 if/switch 字面范围，
  删 `_scan_ternary_lines()` 与第 1 处调用即可，其余部分不依赖它。

不命中（必须保持绿，防判据膨胀成「所有 if 都红」）
  `if (keys.model.isEmpty)`  只有标识符、无字面量无比较 ⇒ 配置完整性判断。
  `if (verdict == 'ok')`     有字面量但无 `model` ⇒ 业务枚举判断。
  `read(key: kVerificationKeyModel) ?? ''`  `??` 是空值合并，不是三元。

分母非空：逐文件打印「if/switch/case 分支数」与「命中数」；文件集空或分支为 0 ⇒ exit 2
（fail-closed）—— 「一个分支都没扫到」既可能真干净，也可能提取器坏了。

退出码：0 = 通过；1 = 判据红；2 = 环境不可判定。
"""
from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAYER_GLOB = "lib/services/verification_gate*.dart"

# ★ 与 check_v3_vendor_literal.py 同一份词表（同源；勿各自维护出两套口径）
VENDOR_WORDS = (
    "deepseek", "openai", "azure", "anthropic", "claude", "moonshot", "kimi", "dashscope",
    "qwen", "通义", "阿里", "zhipu", "智谱", "glm", "bigmodel", "doubao", "volces", "火山",
    "方舟", "字节", "baidu", "ernie", "文心", "hunyuan", "混元", "tencent", "腾讯", "minimax",
    "baichuan", "百川", "sensetime", "商汤", "gemini", "google", "mistral", "llama", "ollama",
)
MODEL_PREFIXES = (
    "gpt-", "deepseek-", "qwen-", "glm-", "kimi-", "moonshot-", "doubao-", "claude-",
    "gemini-", "ernie-", "abab", "yi-",
)
STR_LIT = re.compile(r"'([^'\\\n]*)'|\"([^\"\\\n]*)\"")
IF_RE = re.compile(r"\bif\s*\(")
SWITCH_RE = re.compile(r"\bswitch\s*\(")
CASE_RE = re.compile(r"\bcase\s+('([^'\\\n]*)'|\"([^\"\\\n]*)\")\s*:")
MODEL_IDENT = re.compile(r"\bmodel\b|\bmodelName\b|\bmodelId\b")
STR_MATCH_RE = re.compile(r"\.(contains|startsWith|endsWith|toLowerCase|toUpperCase)\s*\(")
MODEL_CMP_IDENT_RE = re.compile(
    r"\b(?:model|modelName|modelId)\b\s*(==|!=)\s*"
    r"(?!null\b|true\b|false\b|\d)([A-Za-z_$][\w$]*)")
# H4 三元问号：排除 `??`（前后向都要排）与 `?.`
# ★ 2026-11-08 实测教训：初版 `\?(?!\?|\.)` 会匹配 `??` 的**第二个** `?`
#   ⇒ `final model = … ?? '';`（同行有命名参数冒号 `key:`）被误判成三元行（假红）。
TERNARY_Q_RE = re.compile(r"(?<!\?)\?(?!\?|\.)")


def _match_paren(text: str, open_idx: int) -> int:
    """从 `(` 起找配对 `)`，返回下标；找不到返 -1。支持跨行。"""
    depth = 0
    for i in range(open_idx, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i
    return -1


def _literals(expr: str) -> list[str]:
    return [m.group(1) if m.group(1) is not None else m.group(2)
            for m in STR_LIT.finditer(expr)]


def _classify(expr: str) -> tuple[bool, str]:
    """分支条件判定。返回 (是否命中, 理由)。"""
    lits = _literals(expr)
    has_model = bool(MODEL_IDENT.search(expr))
    for lit in lits:
        low = lit.lower()
        for w in VENDOR_WORDS:
            if w in low:
                return True, f"H1 条件含厂商词字面量 '{lit}'（词 {w}）"
        for w in MODEL_PREFIXES:
            if w in low:
                return True, f"H1 条件含模型族字面量 '{lit}'（前缀 {w}）"
    m = STR_MATCH_RE.search(expr)
    if has_model and m:
        return True, f"H2b 条件对模型名做字符串匹配（.{m.group(1)}）"
    if has_model and lits:
        return True, f"H2 条件同时含 model 标识符与字面量 {lits}"
    m = MODEL_CMP_IDENT_RE.search(expr)
    if m:
        return True, f"H2c 条件中 model {m.group(1)} 标识符 '{m.group(2)}'（拿模型名做判断）"
    return False, ""


def _scan_ternary_lines(text: str) -> list[dict]:
    """H4 · 三元 / 条件表达式行级粗判（口径扩展，见 docstring）。"""
    out = []
    for i, line in enumerate(text.splitlines(), 1):
        if not MODEL_IDENT.search(line):
            continue
        if IF_RE.search(line) or SWITCH_RE.search(line):
            continue   # 已由表达式轨覆盖，避免重复计数
        m_q = TERNARY_Q_RE.search(line)
        if not m_q or ":" not in line[m_q.end():]:
            continue   # 命名参数冒号在 ? 之前，不算三元
        ok, why = _classify(line)
        if ok:
            out.append({"kind": "ternary", "line": i,
                        "expr": " ".join(line.split()), "why": "H4 三元行 · " + why})
    return out


def scan_file(p: Path, rel: str) -> dict:
    text = p.read_text(encoding="utf-8", errors="replace")
    branches = []
    for m in IF_RE.finditer(text):
        c = _match_paren(text, m.end() - 1)
        if c > 0:
            branches.append({"kind": "if", "line": text.count("\n", 0, m.start()) + 1,
                             "expr": " ".join(text[m.end():c].split())})
    for m in SWITCH_RE.finditer(text):
        c = _match_paren(text, m.end() - 1)
        if c > 0:
            branches.append({"kind": "switch", "line": text.count("\n", 0, m.start()) + 1,
                             "expr": " ".join(text[m.end():c].split())})
    for m in CASE_RE.finditer(text):
        lit = m.group(2) if m.group(2) is not None else m.group(3)
        branches.append({"kind": "case", "line": text.count("\n", 0, m.start()) + 1,
                         "expr": f"case '{lit}':"})

    hits = []
    for b in branches:
        if b["kind"] == "case":
            low = b["expr"].lower()
            for w in VENDOR_WORDS + MODEL_PREFIXES:
                if w in low:
                    hits.append({**b, "why": f"H3 switch case 标签含厂商/模型词 '{w}'"})
                    break
            continue
        ok, why = _classify(b["expr"])
        if ok:
            hits.append({**b, "why": why})
    tern = _scan_ternary_lines(text)
    hits.extend(tern)
    return {"file": rel, "n_branches": len(branches), "n_ternary": len(tern), "hits": hits,
            "kinds": {k: sum(1 for b in branches if b["kind"] == k)
                      for k in ("if", "switch", "case")}}


def scan(root: Path) -> dict:
    files = sorted(root.glob(LAYER_GLOB))
    rows = [scan_file(f, f.relative_to(root).as_posix()) for f in files]
    return {"files": rows, "n_files": len(rows), "n_branches": sum(r["n_branches"] for r in rows),
            "n_ternary": sum(r["n_ternary"] for r in rows),
            "n_hits": sum(len(r["hits"]) for r in rows)}


def report(res: dict, verbose: bool = True) -> int:
    print(f"V-3② 模型名分支扫描 · 验证层文件集 = {LAYER_GLOB}")
    print(f"[分母非空] 分支扫描文件清单（{res['n_files']} 个 · if/switch/case "
          f"{res['n_branches']} 处 + 三元行 {res['n_ternary']} 处）：")
    for r in res["files"]:
        k = r["kinds"]
        print(f"  {r['file']} —— if {k['if']} / switch {k['switch']} / case {k['case']}"
              f" = {r['n_branches']} 处，三元 {r['n_ternary']} 处，**命中 {len(r['hits'])}**")
    print(f"\n[分母非空] 逐文件 if/switch 引用命中计数（合计 {res['n_hits']}）：")
    for r in res["files"]:
        print(f"  {r['file']}: {len(r['hits'])}")
        if verbose:
            for h in r["hits"]:
                print(f"    [命中] L{h['line']} ({h['kind']}) {h['expr']}\n           ⇒ {h['why']}")
        elif r["hits"]:
            print(f"    （selftest 摘要模式：{len(r['hits'])} 处明细略）")
    print()
    if res["n_hits"]:
        print(f"[FAIL] V-3②：验证层内按模型名分支命中 {res['n_hits']} 处（期望 0）。")
        print("处置：验证层不得按模型身份改变行为（ADR §三「零厂商识别」）。"
              "\n  同一套提示词与流程，对任何模型一视同仁。")
        return 1
    print(f"[PASS] V-3②：{res['n_files']} 个文件 / {res['n_branches']} 处 if·switch·case"
          f" + {res['n_ternary']} 处三元 全 0 命中（逐文件计数见上，分母非空）。")
    return 0


_CLEAN = """\
class Gate {
  final String model;
  const Gate({required this.model});
  bool ok(String? verdict, List<String> hypotheses) {
    if (model.isEmpty) return false;
    if (verdict == 'ok') return true;
    if (hypotheses.isEmpty) return false;
    return false;
  }
}
"""
_H1 = """\
class G { final String model; const G({required this.model});
  bool ok() => true;
  bool f() { if (model == 'deepseek-v4-flash') return true; return false; }
}
"""
_H2 = """\
const String kM = 'some-model';
class G { final String model; const G({required this.model});
  bool f() => model == kM ? true : false;
}
"""
_H3 = """\
class G { final String model; const G({required this.model});
  String f() { switch (model) { case 'qwen-plus': return 'a'; default: return 'b'; } }
}
"""


def _mk_tree(td: Path, body: str) -> Path:
    d = td / "lib" / "services"
    d.mkdir(parents=True, exist_ok=True)
    (d / "verification_gate.dart").write_text(body, encoding="utf-8")
    return td


def selftest() -> int:
    print("selftest · 合成样本证明判据有牙，且不把普通 if 判红")
    cases = [
        ("① 正例：model.isEmpty / verdict=='ok' / hypotheses.isEmpty 等普通分支", _CLEAN, 0),
        ("② 负例 H1：if (model == 'deepseek-v4-flash')", _H1, 1),
        ("③ 负例 H2c+H4：字面量提成常量 kM，三元 model == kM ? : ", _H2, 1),
        ("④ 负例 H3：switch (model) { case 'qwen-plus': }", _H3, 1),
    ]
    failed = 0
    with tempfile.TemporaryDirectory() as td:
        for i, (name, body, expect_rc) in enumerate(cases, 1):
            root = _mk_tree(Path(td) / f"case{i}", body)
            print(f"\n--- 用例 {name}")
            res = scan(root)
            rc = report(res, verbose=False)
            ok = rc == expect_rc and (expect_rc == 0) == (res["n_hits"] == 0)
            print(f"    期望 rc={expect_rc} · 实测 rc={rc}/命中 {res['n_hits']}"
                  f" ⇒ {'OK' if ok else '不符'}")
            failed += 0 if ok else 1
    print()
    if failed:
        print(f"[SELFTEST FAIL] {failed} 例不符预期 ⇒ 判据自身不可信。")
        return 1
    print(f"[SELFTEST PASS] {len(cases)} 例全部符合预期"
          f"（H1/H2c+H4/H3 必红，普通 if 不误伤）。")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(add_help=True, description="V-3② 模型名分支扫描")
    ap.add_argument("--selftest", action="store_true", help="跑合成样本自测")
    ap.add_argument("--root", default=str(ROOT), help="仓库根（默认本仓）")
    ap.add_argument("--quiet", action="store_true", help="不打印逐处明细")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    res = scan(Path(args.root))
    if res["n_files"] == 0:
        print(f"[EXIT 2] 空扫：{LAYER_GLOB} 匹配 0 个文件 ⇒ 分母为空（fail-closed）。")
        return 2
    if res["n_branches"] == 0:
        print(f"[EXIT 2] 分支提取为 0（{res['n_files']} 个文件内无 if/switch/case）"
              f" ⇒ 无法区分「真干净」与「提取器坏了」，不判绿（fail-closed）。")
        return 2
    return report(res, verbose=not args.quiet)


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main(sys.argv[1:]))
