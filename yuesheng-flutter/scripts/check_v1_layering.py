#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V-1③ · ADR-0014 分层引用扫描 —— 验证**调用**符号不得渗入判据真源与 UI 层
（T-20261107-01 甲类第 3 处）。

判据来源（ADR-0014 §2.1 V-1 判据③原文）
----------------------------------------
「③ 分层引用扫描——验证调用符号在 `skills_*.dart` / `skill_registry.dart` /
 widget 层命中数 = 0（**分母非空**：显式打印扫描文件清单 N + 逐文件命中计数）。」

★★ 本判据唯一容易写错的地方：**「验证调用符号」≠「验证相关符号」**
------------------------------------------------------------------------
如果把所有含 `Verification` 的字样都算命中，本判据会**永久假红** —— 因为：
  · `lib/features/app_settings/verification_config_page.dart` 引 `VerificationKeysStorage`
    / `VerificationKeys`：那是**三键配置 UI**，ADR §2.2 V-2 明确要求它存在；
  · `chat_diagnosis_controller.dart` / `writing_coach_panel_diagnosis_runner.dart`
    引 `productionVerificationGate()`：那是 B4 批（`c60a4e7a`）的**合法装配点**。
所以本脚本只认**调用符号**（`CALL_SYMBOLS`），不认配置符号与类型符号。
这是「精确到调用」而不是「精确到关键词」——`PRACTICES A3k-4` 的反面用法：
宁可把口径写清并逐条列出，也不用宽口径凑一个好看的红。

★★ 第二处：「widget 层」必须可判，不能靠感觉
------------------------------------------------
本脚本把 widget 层定义为**两个可枚举的集合**（并打印全清单作为分母）：
  B1 `lib/widgets/**/*.dart`（全部）；
  B2 `lib/features/**` 下文件名以 `_page` / `_section` / `_view` / `_panel` /
     `_widget` / `_sheet` / `_dialog` / `_card` 结尾的 `.dart`（UI 渲染面）。
**不含** `*_controller.dart` / `*_runner.dart` / `*_provider.dart` / `*_service.dart`
—— 那些是装配层与逻辑层，本来就该拿到 gate 实例（B4 批的合法形态）。
若把 `lib/features/` 整个算进 UI 层，本判据会因那两个装配点假红。

退出码：0 = 通过；1 = 判据红（有命中）；2 = 环境不可判定（任一组分母为空）。
"""
from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# A 组：判据真源（ADR §2.1 V-1「不在判据真源」）
A_GLOBS = ("lib/services/skills_*.dart", "lib/services/skill_registry.dart")
# B 组：widget 层（见 docstring 第二处）
B_GLOB = "lib/widgets/**/*.dart"
B_FEATURE_DIR = "lib/features"
B_UI_SUFFIXES = ("_page", "_section", "_view", "_panel",
                 "_widget", "_sheet", "_dialog", "_card")

# ★ 只认**调用**符号（调用/构造/静态成员），不认配置与类型符号
CALL_SYMBOLS = (
    (re.compile(r"\bproductionVerificationGate\b"), "productionVerificationGate（装配点工厂）"),
    (re.compile(r"\bVerificationGate\s*\("), "VerificationGate(…（构造调用）"),
    (re.compile(r"\bVerificationGate\s*\."), "VerificationGate.…（静态成员调用）"),
    (re.compile(r"\.verify(?:Hypotheses)?\s*\("), ".verify( / .verifyHypotheses(（自建调用）"),
)
# 明确**不算**命中的符号（写出来防后人误扩，也防我下次手滑）
NON_CALL_SYMBOLS = ("VerificationKeys", "VerificationKeysStorage",
                    "VerificationConfigPage", "VerificationConfigSection",
                    "kVerificationKey", "kVerificationEvidenceGrade",
                    "VerificationHypothesis")


def collect_a(root: Path) -> list[Path]:
    out = []
    for g in A_GLOBS:
        out.extend(root.glob(g))
    return sorted(set(out))


def collect_b(root: Path) -> list[Path]:
    out = list(root.glob(B_GLOB))
    fd = root / B_FEATURE_DIR
    if fd.is_dir():
        for p in fd.rglob("*.dart"):
            if p.stem.endswith(B_UI_SUFFIXES):
                out.append(p)
    return sorted(set(out))


def scan_file(p: Path, rel: str) -> dict:
    text = p.read_text(encoding="utf-8", errors="replace")
    hits = []
    for i, line in enumerate(text.splitlines(), 1):
        for pat, label in CALL_SYMBOLS:
            if pat.search(line):
                hits.append({"line": i, "text": line.strip(), "symbol": label})
                break
    return {"file": rel, "hits": hits}


def scan(root: Path) -> dict:
    a = [scan_file(f, f.relative_to(root).as_posix()) for f in collect_a(root)]
    b = [scan_file(f, f.relative_to(root).as_posix()) for f in collect_b(root)]
    return {"a": a, "b": b, "n_a": len(a), "n_b": len(b),
            "hits_a": sum(len(x["hits"]) for x in a),
            "hits_b": sum(len(x["hits"]) for x in b)}


def _print_group(name: str, rows: list[dict], verbose: bool) -> None:
    print(f"\n[分母非空] {name}（{len(rows)} 个文件）：")
    for r in rows:
        mark = "**命中**" if r["hits"] else "0"
        if verbose or r["hits"]:
            print(f"  {r['file']} —— {mark}")
        if r["hits"] and verbose:
            for h in r["hits"]:
                print(f"    [命中] L{h['line']} {h['symbol']}")
                print(f"           {h['text']}")


def report(res: dict, verbose: bool = True) -> int:
    print(f"V-1③ 分层引用扫描 · 调用符号 {len(CALL_SYMBOLS)} 种，只认调用不认配置")
    print(f"  调用符号：{', '.join(lbl for _, lbl in CALL_SYMBOLS)}")
    print(f"  明确不算：{', '.join(NON_CALL_SYMBOLS[:5])} 等 {len(NON_CALL_SYMBOLS)} 个")
    _print_group("A 组 · 判据真源（skills_*.dart / skill_registry.dart）", res["a"], verbose)
    _print_group("B 组 · widget 层（lib/widgets/** + features 下 UI 后缀）", res["b"], verbose)
    print(f"\n合计：A 组 {res['n_a']} 文件 / 命中 {res['hits_a']}；"
          f"B 组 {res['n_b']} 文件 / 命中 {res['hits_b']}")
    print()
    total = res["hits_a"] + res["hits_b"]
    if total:
        print(f"[FAIL] V-1③：验证调用符号在判据真源 / widget 层命中 {total} 处（期望 0）。")
        print("处置：验证层的装配点只应在 `lib/services/` 侧（ADR §2.1 V-1）。"
              "\n  判据真源不得依赖验证层；UI 层不得直接调验证层。")
        return 1
    print(f"[PASS] V-1③：{res['n_a'] + res['n_b']} 个文件（A {res['n_a']} + B {res['n_b']}）"
          f"全 0 命中（逐文件计数见上，分母非空）。")
    return 0


# ─────────────────────────── selftest ───────────────────────────

_SKILL_CLEAN = "// skills_beginner.dart\nclass SkillsBeginner { int level = 1; }\n"
_SKILL_HIT = _SKILL_CLEAN + "void boot() { productionVerificationGate(); }\n"
_WIDGET_HIT = "class Foo extends StatelessWidget {\n  final g = VerificationGate(repo: r);\n}\n"
# 配置页形态：引配置符号但不是调用符号 ⇒ 必须绿（防误伤，见 docstring）
_CFG_CLEAN = ("class VerificationConfigPage extends StatefulWidget {\n"
              "  final VerificationKeysStorage? storage;\n"
              "  late final VerificationKeysStorage _s;\n"
              "  bool get ok => _s.load() != null;\n}\n")


def _mk_tree(td: Path, skill: str = _SKILL_CLEAN, widget: str | None = None,
             cfg: str | None = None) -> Path:
    (td / "lib" / "services").mkdir(parents=True, exist_ok=True)
    (td / "lib" / "widgets").mkdir(parents=True, exist_ok=True)
    (td / "lib" / "services" / "skills_beginner.dart").write_text(skill, encoding="utf-8")
    (td / "lib" / "services" / "skill_registry.dart").write_text(
        "// registry\n", encoding="utf-8")
    (td / "lib" / "widgets" / "foo.dart").write_text(
        widget or "class A extends StatelessWidget {}\n", encoding="utf-8")
    if cfg is not None:
        d = td / "lib" / "features" / "app_settings"
        d.mkdir(parents=True, exist_ok=True)
        (d / "verification_config_page.dart").write_text(cfg, encoding="utf-8")
    return td


def selftest() -> int:
    print("selftest · 合成样本：调用符号必红、配置符号必绿")
    cases = [
        ("① 正例：A/B 两组都无调用符号", dict(), 0),
        ("② 负例：skills_beginner.dart 内 productionVerificationGate()",
         dict(skill=_SKILL_HIT), 1),
        ("③ 负例：lib/widgets/foo.dart 内 VerificationGate(…) 构造", dict(widget=_WIDGET_HIT), 1),
        ("④ 正例（防误伤）：配置页引 VerificationKeysStorage，无调用符号",
         dict(cfg=_CFG_CLEAN), 0),
    ]
    failed = 0
    with tempfile.TemporaryDirectory() as td:
        for i, (name, kw, expect_rc) in enumerate(cases, 1):
            root = _mk_tree(Path(td) / f"case{i}", **kw)
            print(f"\n--- 用例 {name}")
            res = scan(root)
            rc = report(res, verbose=False)
            ok = rc == expect_rc
            print(f"    期望 rc={expect_rc} · 实测 rc={rc}"
                  f"（A 命中 {res['hits_a']} / B 命中 {res['hits_b']}）"
                  f" ⇒ {'OK' if ok else '不符'}")
            failed += 0 if ok else 1
    print()
    if failed:
        print(f"[SELFTEST FAIL] {failed} 例不符预期 ⇒ 判据自身不可信。")
        return 1
    print(f"[SELFTEST PASS] {len(cases)} 例全部符合预期"
          f"（调用必红 ×2、干净必绿、配置符号不误伤）。")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(add_help=True, description="V-1③ 分层引用扫描（ADR-0014）")
    ap.add_argument("--selftest", action="store_true", help="跑合成样本自测")
    ap.add_argument("--root", default=str(ROOT), help="仓库根（默认本仓）")
    ap.add_argument("--quiet", action="store_true", help="只打印有命中的文件")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    res = scan(Path(args.root))
    if res["n_a"] == 0 or res["n_b"] == 0:
        print(f"[EXIT 2] 空扫：A 组 {res['n_a']} 文件 / B 组 {res['n_b']} 文件"
              f" ⇒ 有一组分母为空，不能判绿（fail-closed）。")
        return 2
    return report(res, verbose=not args.quiet)


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main(sys.argv[1:]))
