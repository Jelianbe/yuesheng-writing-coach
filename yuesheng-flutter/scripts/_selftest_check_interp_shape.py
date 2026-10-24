#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""_selftest_check_interp_shape.py —— `check_interp_shape.py` 负向验证 + 判据强度自检。

★ 为什么必须有这个
==================
守卫的头号死法是**恒绿**（判据写宽了什么都报不出来，或写窄了只认一个文件）。
本自测用 8 个探针回答「它会不会红 / 会不会误红」：

| 探针 | 注入 | 期望 | 验证的判据 |
|:--|:--|:--|:--|
| P0 | 原状（修好后的树） | rc=0 | 现状零违规、合法形态不误报 |
| P1 | 把 `chat_service.dart` 的修复**回退**成 `$ChatService._kFullContentMaxLen` | rc=1 且报出该文件 | R1 在真实缺陷树上必红（零假绿） |
| P2 | 在 `export_service.dart` 注入 `'$TeacherValidationError.field'` | rc=1 且报出该文件 | R1 **不是只查 chat_service.dart** |
| P3 | 同文件注入函数 tear-off `'$_probeFn(1)'` | rc=1 且含 `R2` | R2 判据有牙齿 |
| P4 | 六种**合法**形态各一处（`${…}` / 局部变量点路径 / 变量+括号 / raw / 注释 / 转义 / 三引号） | rc=0 | 不误报 |
| P5 | 注入 **SDK 类型** `'$String.'`（不在 lib 符号表） | rc=1 且含 `R3` | R3 堵住「SDK 类型不在符号表 ⇒ 静默漏报」（2026-10-24 复核退回项） |
| P6 | 注入 **大写 + `(`** `'共 $N(个)'` | rc=0 | 「大写+括号不判」这一**有意取舍**被钉死（不是静默漏报） |
| P7 | 全部复原 | rc=0 | 探针零残留 |

★ 探针全部在**副本树**上做（`tempfile` 复制 `lib/`），**不碰真源**：
  这比「改真源 + try/finally 恢复」更强 —— 没有恢复步骤，就没有恢复失败。
  每个探针仍用 try/finally 回写原始字节（同一副本内多探针互不污染）。

★ 第二段：判据强度自检（本团「判据必须能变红」纪律）
====================================================
在临时目录里把 `check_interp_shape.py` 的**源码改坏**成三个变体，然后跑同一套探针：

  V1「放宽到什么都不报」（`HIT_SHAPES = ""`）⇒ 探针**必须**变红。
  V2「收窄到只认 chat_service.dart」⇒ 探针**必须**变红。
  V3「把 R3 整条分支删掉」（`elif shape in R3_SHAPES …` → `elif False:`）⇒ 探针**必须**变红
     （由 P5 捕获：`$String.` 不再上报）。V3 专治「判据被静默删一条」。

三个变体都失败 ⇒ 证明「自测在判据被弱化时会红」，即自测**不是**恒绿装饰。

用法
====
    python scripts/_selftest_check_interp_shape.py                 # 探针 + 强度自检
    python scripts/_selftest_check_interp_shape.py --probes-only   # 只跑探针（内部用）

退出码：0 = 全过；1 = 有探针/变体未过。
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

REPO = Path(__file__).resolve().parent.parent
CHECKER = REPO / "scripts" / "check_interp_shape.py"

FAILS: list = []

#: P1 的锚点：修复后的合法形态（`${…}`）与缺陷形态（`$Type.…`）。
FIXED_TEXT = "'[ChatService] 步骤8: fullContent 超上限截断头部 $overflow 字符（上限 ${ChatService._kFullContentMaxLen}）',"
BUGGY_TEXT = "'[ChatService] 步骤8: fullContent 超上限截断头部 $overflow 字符（上限 $ChatService._kFullContentMaxLen）',"

#: P4 的六种合法形态（追加到 export_service.dart）。
LEGAL_PROBES = """// 探针 P4：以下六种都是**合法**形态，判据不得报
final _probeLocal = 'x';
// '$ChatService._kFullContentMaxLen'  ← 注释里的坏例子不判
final _probeOk1 = '${ChatService._kFullContentMaxLen}';
final _probeOk2 = '$_probeLocal.dimension';
final _probeOk3 = '$_probeLocal(item)';
final _probeOk4 = r'$ChatService._kFullContentMaxLen';
final _probeOk5 = '\\$ChatService._kFullContentMaxLen';
final _probeOk6 = '''多行 $_probeLocal.dimension 文本''';
"""

#: P3 的 R2 探针（先声明函数，再在字符串里插值它 —— 编译级合法，语义级是缺陷）。
R2_PROBE = """String _probeFn(int a) => '$a';
final _probeR2 = 'v=$_probeFn(1)';
"""

#: P2 的 R1 探针（注入到 chat_service.dart 之外的文件）。
R1_PROBE = "final _probeR1 = 'field=$TeacherValidationError.field';"

#: P5 的 R3 探针：SDK 类型（`String` 不在 lib 符号表）后紧跟 `.`。
#: 这是 2026-10-24 独立复核退回项的原形：只靠 R1 时它被判「合法」= 静默漏报。
R3_PROBE = "final _probeR3 = '类型=$String. 名字';"

#: P6 的取舍探针：大写单字母 + `(`（中文日志可预期形态）⇒ 有意不判，必须保持 rc=0。
R3_PAREN_PROBE = "final _probeP6 = '共 $N(个)';"



def check(name: str, cond: bool, detail: str = "") -> None:
    """登记一条断言并打印结果。"""
    tag = "OK  " if cond else "FAIL"
    print("  [%s] %s%s" % (tag, name, ("  ← " + detail[-400:]) if detail and not cond else ""))
    if not cond:
        FAILS.append(name)


def run(checker: Path, root: Path) -> tuple:
    """跑一次护栏，返回 (rc, 输出)。"""
    p = subprocess.run(
        [sys.executable, str(checker), "--root", str(root)],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def _eol(data: bytes) -> bytes:
    """按文件既有行尾返回换行字节（副本树也要守住行尾纪律）。"""
    return b"\r\n" if b"\r\n" in data else b"\n"


def _probe(root: Path, path: Path, new_text: str, expect_rc: int,
           must_contain: tuple, name: str, checker: Path) -> None:
    """施加一次文本改动 → 跑护栏 → 断言 → finally 回写原始字节。"""
    orig = path.read_bytes()
    try:
        path.write_bytes(new_text.encode("utf-8"))
        rc, out = run(checker, root)
        ok = rc == expect_rc and all(s in out for s in must_contain)
        check(name, ok, out)
    finally:
        path.write_bytes(orig)


def _append_probe(root: Path, path: Path, probe: str, expect_rc: int,
                  must_contain: tuple, name: str, checker: Path) -> None:
    """追加一段探针文本后断言（同样由 `_probe` 负责 try/finally 恢复）。"""
    data = path.read_bytes()
    nl = _eol(data)
    text = data.decode("utf-8")
    new_text = text + nl.decode("utf-8") + probe
    if not text.endswith(("\n", "\r")):
        new_text = text + nl.decode("utf-8") + probe
    _probe(root, path, new_text, expect_rc, must_contain, name, checker)


def run_probes(checker: Path) -> int:
    """跑 P0–P7 八探针（副本树内，不碰真源）。"""
    global FAILS
    FAILS = []
    print("== 探针（副本树，真源零触碰）==")
    with tempfile.TemporaryDirectory() as td:
        root = Path(td) / "repo"
        shutil.copytree(REPO / "lib", root / "lib")
        chat = root / "lib" / "services" / "chat_service.dart"
        other = root / "lib" / "services" / "export_service.dart"

        rc, out = run(checker, root)
        check("P0 修好后的树 ⇒ rc=0（零违规、合法形态不误报）", rc == 0, out)

        src = chat.read_text(encoding="utf-8")
        if FIXED_TEXT not in src:
            check("P1 锚点存在（修复形态应恰有 1 处）", False, "未找到 FIXED_TEXT 锚点")
        else:
            _probe(root, chat, src.replace(FIXED_TEXT, BUGGY_TEXT), 1,
                   ("chat_service.dart", "$ChatService."), "P1 回退缺陷 ⇒ rc=1 且报出该处", checker)

        _append_probe(root, other, R1_PROBE, 1, ("export_service.dart", "R1"),
                      "P2 他文件注入 R1 ⇒ rc=1（非只查单文件）", checker)
        _append_probe(root, other, R2_PROBE, 1, ("export_service.dart", "R2"),
                      "P3 注入函数 tear-off ⇒ rc=1（R2 有牙齿）", checker)
        _append_probe(root, other, LEGAL_PROBES, 0, (),
                      "P4 六种合法形态 ⇒ rc=0（不误报）", checker)
        _append_probe(root, other, R3_PROBE, 1, ("export_service.dart", "R3"),
                      "P5 SDK 类型 $String. ⇒ rc=1（R3 堵静默漏报）", checker)
        _append_probe(root, other, R3_PAREN_PROBE, 0, (),
                      "P6 大写 + `(` ⇒ rc=0（有意取舍被钉住）", checker)

        rc, out = run(checker, root)
        check("P7 探针全部复原 ⇒ rc=0（零残留）", rc == 0, out)

    print()
    if FAILS:
        print("探针 FAIL：%d 项未过 —— %s" % (len(FAILS), FAILS))
        return 1
    print("探针 PASS：8/8（该红的红、该绿的绿、副本零残留）")
    return 0


def _neuter(src: str, pattern: str, repl: str, tag: str) -> str:
    """把校验器源码的某一处改坏（断言锚点唯一，否则抛错而不是静默放过）。"""
    hits = len(re.findall(re.escape(pattern), src))
    if hits != 1:
        raise RuntimeError("%s 变体锚点命中 %d 次（应为 1）：%s" % (tag, hits, pattern))
    return src.replace(pattern, repl)


def verify_strength() -> int:
    """判据强度自检：两个被弱化的变体必须让探针变红。"""
    global FAILS
    FAILS = []
    print("== 判据强度自检（被弱化的护栏必须让探针变红）==")
    src = CHECKER.read_text(encoding="utf-8")
    variants = {
        "V1 放宽到什么都不报": _neuter(src, 'HIT_SHAPES = ".("', 'HIT_SHAPES = ""', "V1"),
        "V2 收窄到只认 chat_service.dart": _neuter(
            src,
            '            if not name.endswith(".dart") or name.endswith(GENERATED_SUFFIX):',
            '            if name != "chat_service.dart":\n'
            '                continue\n'
            '            if not name.endswith(".dart") or name.endswith(GENERATED_SUFFIX):',
            "V2",
        ),
        "V3 删掉 R3 分支": _neuter(
            src,
            "            elif shape in R3_SHAPES and ident[:1].isupper():",
            "            elif False:  # V3 变体：R3 被删",
            "V3",
        ),
    }
    with tempfile.TemporaryDirectory() as td:
        for name, text in variants.items():
            vpath = Path(td) / (name.split()[0] + ".py")
            vpath.write_bytes(text.encode("utf-8"))
            p = subprocess.run(
                [sys.executable, str(__file__), "--probes-only", "--checker", str(vpath)],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
            check("%s ⇒ 探针变红（rc≠0）" % name, p.returncode != 0,
                  (p.stdout or "") + (p.stderr or ""))
    print()
    if FAILS:
        print("强度自检 FAIL：%d 项 —— %s" % (len(FAILS), FAILS))
        return 1
    print("强度自检 PASS：3/3（判据放宽 / 收窄 / 删一条都会让本自测变红 ⇒ 本自测非恒绿）")
    return 0


def main() -> int:
    """CLI 入口。"""
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--probes-only", action="store_true")
    ap.add_argument("--checker", default=str(CHECKER))
    args, _ = ap.parse_known_args()
    checker = Path(args.checker)
    if not checker.is_file():
        print("FAIL 找不到被检脚本：%s" % checker)
        return 1
    rc = run_probes(checker)
    if args.probes_only:
        return rc
    return rc or verify_strength()


if __name__ == "__main__":
    sys.exit(main())
