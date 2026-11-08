#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V-3① · ADR-0014「全流程零厂商识别」—— 厂商 / 模型名字面量扫描（T-20261107-01 甲类第 1 处）。

判据来源（ADR-0014 §2.2 V-3① 原文，逐字对齐）
------------------------------------------------
「① 厂商字面量扫描：在**验证层文件集内** grep 厂商名 / 模型名字面量，命中数 = 0
（**分母非空**：打印扫描文件清单 + 每个关键字逐项命中计数）。」

★★ 两条口径必须显式钉死，否则判据会假红或假绿
------------------------------------------------
**口径一：验证层文件集 = `lib/services/verification_gate*.dart`（现为 1 个文件）。**
  为什么只有这一个：ADR §2.1 V-1 把验证层落点定在「诊断链装配层（`lib/services/` 侧）」，
  而 `productionVerificationGate()` 定义（`verification_gate.dart:320`）与三键常量
  （`kVerificationKey*`）都在这个文件里，它**自足**。
  **为什么不含 `lib/features/app_settings/api_config_page.dart`**：那是**用户主链的**
  供应商预设页（`_llmPresets` 六家），是 ADR §三 明确允许的主链配置面，不属验证层实现。
  把配置页算进「验证层文件集」会让判据永久红 —— 那不是发现有违规，是把范围搞错了。
  **本卡不扩大也不缩小 ADR 的范围**；若要扩集，须先改 ADR。

**口径二：注释行也算命中（不豁免）。**
  ADR 原文是「在验证层文件集内 grep … 命中数 = 0」，没有「排除注释」这一说；
  而 ADR 规格句写的是「代码面**无任何**按厂商名 / 模型名分支的判断」——
  注释里写「不像 DeepSeek 那样」不构成判断，但它确实是「厂商识别」的痕迹。
  ⇒ 本脚本**严格按原文判红**，同时在报告里单独标出「其中注释行 N 处」，
  让人一眼看出是不是注释引起的，而不是让我用口径替人做决定。
  这是 `PRACTICES A3k-4` 的反面用法：**宁可报出全部，也不悄悄少看一半形态**。

词表来源（不私造）
------------------
厂商 / 别名 / 模型族前缀取自项目内**可查真源** `api_config_page.dart` 的 `_llmPresets`
（DeepSeek / OpenAI / Kimi / 通义千问 / 智谱 GLM / 火山方舟）+ 该页注释里点名的别名。
新增词条须能指到项目内出处，不得凭印象加。

退出码：0 = 通过（0 命中）；1 = 判据红（有命中）；2 = 环境不可判定（文件集为空）。
"""
from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# ★ 验证层文件集（glob，相对仓库根；口径见 docstring 口径一）
LAYER_GLOB = "lib/services/verification_gate*.dart"

# ★ 厂商名 / 别名（大小写不敏感）
VENDOR_WORDS = (
    "deepseek", "openai", "azure", "anthropic", "claude",
    "moonshot", "kimi", "dashscope", "qwen", "通义", "阿里",
    "zhipu", "智谱", "glm", "bigmodel",
    "doubao", "volces", "火山", "方舟", "字节",
    "baidu", "ernie", "文心", "hunyuan", "混元", "tencent", "腾讯",
    "minimax", "baichuan", "百川", "sensetime", "商汤",
    "gemini", "google", "mistral", "llama", "ollama",
)
# ★ 模型族前缀（命中即视为模型名字面量；`gpt-` 带连字符以免误伤普通词）
MODEL_PREFIXES = (
    "gpt-", "deepseek-", "qwen-", "glm-", "kimi-", "moonshot-",
    "doubao-", "claude-", "gemini-", "ernie-", "abab", "yi-",
)


def collect_files(root: Path) -> list[Path]:
    return sorted(root.glob(LAYER_GLOB))


def read_lines(p: Path) -> list[str]:
    try:
        return p.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return p.read_text(encoding="utf-8", errors="replace").splitlines()


def is_comment_line(line: str) -> bool:
    s = line.strip()
    return s.startswith("//") or s.startswith("///") or s.startswith("*") or s.startswith("/*")


def scan(root: Path) -> dict:
    files = collect_files(root)
    per_file = []
    keyword_hits: dict[str, int] = {w: 0 for w in VENDOR_WORDS}
    for w in MODEL_PREFIXES:
        keyword_hits[w] = 0
    for f in files:
        rows = []
        for i, line in enumerate(read_lines(f), 1):
            low = line.lower()
            hit_words = [w for w in VENDOR_WORDS if w in low]
            hit_pref = [w for w in MODEL_PREFIXES if w in low]
            if not hit_words and not hit_pref:
                continue
            for w in hit_words + hit_pref:
                keyword_hits[w] = keyword_hits.get(w, 0) + 1
            rows.append({
                "line_no": i,
                "text": line.strip(),
                "words": hit_words + hit_pref,
                "is_comment": is_comment_line(line),
            })
        per_file.append({"file": f.relative_to(root).as_posix(), "hits": rows})
    return {"files": per_file, "keyword_hits": keyword_hits,
            "n_files": len(files), "n_hits": sum(len(x["hits"]) for x in per_file)}


def report(res: dict, verbose: bool = True) -> int:
    print(f"V-3① 厂商 / 模型名字面量扫描 · 验证层文件集 = {LAYER_GLOB}")
    print(f"[分母非空] 扫描文件清单（{res['n_files']} 个）：")
    for f in res["files"]:
        print(f"  {f['file']} —— 命中 {len(f['hits'])} 行")

    kh = res["keyword_hits"]
    nonzero = {k: v for k, v in kh.items() if v}
    print(f"\n[分母非空] 关键字逐项计数（共 {len(kh)} 个关键字：厂商名 {len(VENDOR_WORDS)}"
          f" + 模型族前缀 {len(MODEL_PREFIXES)}）：")
    if nonzero:
        for k, v in sorted(nonzero.items(), key=lambda x: -x[1]):
            print(f"  {k:12s} 命中 {v}")
    zero_names = [k for k, v in kh.items() if not v]
    print(f"  其余 {len(zero_names)} 个关键字均 0 命中：{', '.join(zero_names)}")

    n_cmt = sum(1 for f in res["files"] for h in f["hits"] if h["is_comment"])
    print(f"\n命中明细（{res['n_hits']} 行；其中**注释行 {n_cmt} 行**）：")
    if verbose:
        for f in res["files"]:
            for h in f["hits"]:
                tag = "[注释]" if h["is_comment"] else "[代码]"
                print(f"  {tag} {f['file']}:{h['line_no']}: {h['text']}"
                      f"\n        命中词：{', '.join(h['words'])}")
    else:
        print("  （selftest 摘要模式：明细略）")

    print()
    if res["n_hits"]:
        print(f"[FAIL] V-3①：验证层内厂商 / 模型名字面量命中 {res['n_hits']} 行"
              f"（期望 0；其中注释 {n_cmt} 行，注释亦不豁免 —— 见 docstring 口径二）。")
        print("处置：验证层必须对**任何**厂商 / 模型一视同仁。"
              "\n  若确为注释里的说明性提及，改写成不点名的表述"
              "（如「与主链同源」），不要靠豁免绕过判据。")
        return 1
    print(f"[PASS] V-3①：{res['n_files']} 个验证层文件 / {len(kh)} 个关键字全 0 命中"
          f"（厂商名 {len(VENDOR_WORDS)} + 模型族前缀 {len(MODEL_PREFIXES)}，逐项计数见上）。")
    return 0


# ─────────────────────────── selftest ───────────────────────────

_CLEAN = """\
// VerificationGate — 验证层（样例）
const String kVerificationKeyModel = 'yuesheng_verify_api_model';
const String kVerificationEvidenceGrade = 'E2';

class Gate {
  final String model;
  const Gate({required this.model});
  bool get ok => model.isNotEmpty;
}
"""

_CODE_HIT = _CLEAN + "\nconst String kLeak = 'deepseek-v4-flash';\n"
_COMMENT_HIT = _CLEAN + "\n// 这里不像 OpenAI 那样做同源检测\n"
_URL_HIT = _CLEAN + "\nconst String kBase = 'https://api.openai.com/v1';\n"


def _mk_tree(td: Path, body: str) -> Path:
    d = td / "lib" / "services"
    d.mkdir(parents=True, exist_ok=True)
    (d / "verification_gate.dart").write_text(body, encoding="utf-8")
    return td


def selftest() -> int:
    print("=" * 68)
    print("selftest · 合成样本证明判据有牙（含「不误伤」的绿例）")
    print("=" * 68)
    cases = [
        ("① 正例：验证层无任何厂商词（含 kVerificationKeyModel 等配置符号）",
         _CLEAN, 0, 0),
        ("② 负例：代码行含 'deepseek-v4-flash'", _CODE_HIT, 1, 1),
        ("③ 负例：**注释行**含「不像 OpenAI 那样」（注释不豁免）", _COMMENT_HIT, 1, 1),
        ("④ 负例：baseUrl 字面量 https://api.openai.com/v1", _URL_HIT, 1, 1),
    ]
    failed = 0
    with tempfile.TemporaryDirectory() as td:
        for i, (name, body, expect_rc, expect_hits) in enumerate(cases, 1):
            root = _mk_tree(Path(td) / f"case{i}", body)
            print(f"\n--- 用例 {name}")
            res = scan(root)
            rc = report(res, verbose=False)
            ok = rc == expect_rc and res["n_hits"] == expect_hits
            print(f"    期望 rc={expect_rc}/命中 {expect_hits} · "
                  f"实测 rc={rc}/命中 {res['n_hits']} ⇒ {'OK' if ok else '不符'}")
            failed += 0 if ok else 1
    print()
    if failed:
        print(f"[SELFTEST FAIL] {failed} 例不符预期 ⇒ 判据自身不可信。")
        return 1
    print(f"[SELFTEST PASS] {len(cases)} 例全部符合预期"
          f"（代码命中必红、注释命中必红、配置符号不误伤）。")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(add_help=True, description="V-3① 厂商字面量扫描（ADR-0014）")
    ap.add_argument("--selftest", action="store_true", help="跑合成样本自测")
    ap.add_argument("--root", default=str(ROOT), help="仓库根（默认本仓）")
    ap.add_argument("--quiet", action="store_true", help="不打印逐行明细")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()

    root = Path(args.root)
    res = scan(root)
    if res["n_files"] == 0:
        print(f"[EXIT 2] 空扫：{LAYER_GLOB} 在 {root} 下匹配到 **0 个文件**"
              f" ⇒ 分母为空，不能判绿（fail-closed）。")
        return 2
    return report(res, verbose=not args.quiet)


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main(sys.argv[1:]))
