#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""字符串插值 tear-off 形态检测器（Interp-Shape Detector）——「dart analyze 看不见的那一类」。

背景（T-20261024-10）
====================
`T-20261024-08` 修了 `progressive_diagnosis.dart` 的两处 tear-off 插值缺陷；
`T-20261024-10` 在同一形态上找到**第二处**（`chat_service.dart:599`）：

    '… （上限 $ChatService._kFullContentMaxLen）'

缺陷机制：Dart 字符串插值的 `$` **只接受 simple identifier**（不含 `.`）。
故 `$ChatService` 求值为**类型对象**（`toString()` = `"ChatService"`），紧接的
`._kFullContentMaxLen` 变成**字面文本** ⇒ 实测渲染「（上限 ChatService._kFullContentMaxLen）」
而不是「（上限 204800）」。**零编译错误、零 lint 提示**。

现有门禁缺口
============
`dart analyze` 对该形态 **rc=0 不报**（它是合法 Dart）⇒ 门禁 1 结构上看不见它。
于是「同族缺陷出现第三次」时，十九道门禁全绿也拦不住。本脚本补这个检测点。

判据口径
========
只扫 **`lib/**/*.dart`（排除 `*.g.dart`）的字符串字面量内部**（单/双引号、三引号
长字符串、`r` 原始字符串、反斜杠转义、`${…}` 嵌套插值；**跳过注释**），取每处
**简单插值** `$ident`，若其后**紧邻**字符属于 `HIT_SHAPES`（`.` 或 `(`），
且 `ident` 命中下列三条之一，则判违规：

  R1  类型 tear-off：`ident` 命中 lib/ 内的 `class` / `enum` / `mixin` / `typedef` /
      `extension type` 声明 ⇒ `$ChatService.x` 几乎必然是 `${ChatService.x}` 的笔误。
  R2  函数 tear-off：`ident` 命中 lib/ 内的函数/方法声明，**且**同文件内无形参 /
      局部变量 / 字段同名声明（遮蔽检查）⇒ `$fn(` 几乎必然是 `${fn(…)}` 的笔误。
  R3  **SDK / 外部包类型** tear-off：`ident` **大写开头**、紧跟 `.`、但**不在** lib 符号表
      ⇒ `$String.` / `$Duration.zero` 这类形态（dart:core / Flutter SDK / 依赖包的类型
      永远不在 lib 符号表里，只靠 R1 会**静默漏报**）。

★ R3 为什么必要（2026-10-24 复核实测，T-20261024-10 退回项）
------------------------------------------------------------
首版只有 R1/R2。独立复核在真源注入 `const _interpProbe = '$String.';` ⇒ 候选数
27→28（看见了），但**判成合法**（RC=0）——因为 `String` 不在 lib 符号表
（实测 `String/Duration/DateTime/Object/List/Map` 全部不在表内）。
`$Duration.zero` 这种写法在日志/文案里完全写得出，属**原缺陷同族可达面** ⇒ 必须补判据，
不能当成「已声明的局限」放过去。

R3 的判别力来自 **Dart 命名规范**：类型名**必须**大写开头（`class`/`enum`/`typedef`
一律 UpperCamelCase），变量/形参/字段按规范是 lowerCamelCase。
实测本仓 lib：大写开头的候选 **0 处**、`SCREAMING_CAPS` 常量声明 **0 处**、
大写开头的 `final/var/late` 变量声明 **0 处** ⇒ R3 现状误报 **0**。
R3 **不做**遮蔽检查（有意）：`String` / `Object` / `List` 这类名字在正文里到处都是，
宽松遮蔽正则会把真缺陷一起抑制掉；若未来真出现大写局部变量导致误报，
正解是**改成 lowerCamelCase**（符合 Dart 规范），不是加豁免。

★ R3 **只判 `.`、不判 `(`**（有意取舍，探针 P6 钉住）
----------------------------------------------------
`'共 $N(个)'` 这类「大写单字母变量 + 值为括号」的中文日志是可预期形态，
若把大写+`(` 也收进来会误报；而 `${Type(...)}` 意图的笔误在日志里**零观测实例**。
⇒ 代价：`$String(` 形态**不报**（已知、已声明、已被探针固化，不是静默漏报）。

★ 为什么 R1/R2 仍以「符号解析」为主、而不是「后跟点号就算」
==========================================================
本仓实测存在的三类**故意字面文本**，`ident` 都是局部变量，因此不落进 R1/R2/R3：

    'field: $prefix.dimension'     27 处（editor_validator / teacher_validator …）
    "return '$base-$stamp.json'"   点号在引号内即结束（`$base` 后是 `-`，不命中）
    '长度=$len($bucket) 颗粒度=…'   2 处（变量值 + 括号，是给人读的日志）

⇒ 判据不做「点号即违规」（那会误报 27 处），也不做「单文件白名单」（那会漏掉全域）。
判别力来自**符号解析 + 命名规范**（R1/R2 以符号为准，R3 以大写开头为准），
不是来自字符形态本身。

A 类豁免白名单
==============
**无文件级白名单**。豁免只有一种形态：baseline（`tool/interp_shape_baseline.json`）
里**逐条登记 + 逐条写 reason** 的止血项（现状为空 —— 修复后本仓 0 违规）。
不得用「宽松正则」或「只查这一个文件」替代判据（selftest 的第二项会变红）。

已知局限（勿删，方法论实测教训）
================================
① 符号表**排除 `*.g.dart`**：drift 生成类（`ManuscriptsTable` …）不进类型表。
   （必须排除：`database.g.dart` 有 1316 处 `$XxxTable(` —— 那是 drift 的生成类
   构造调用，属**代码**不属字符串，混入即千条误报。）
   **但这不是漏报面**：手写代码里的 `$ManuscriptsTable.x` 仍由 **R3**（大写开头 + `.`）
   抓到；只有小写装配形态（`$manuscriptsTable.x`）不判 —— 与本仓 21 处
   `'$prefix.dimension'` 同形，属故意字面文本。
② 遮蔽检查是**正则级**启发式（形参 / `final|var|const|late` 声明 / `this.x`），
   不做作用域解析，只用于 R2；局部同名变量与全局同名函数共存时**宁可漏报**。
③ R2 依赖**声明形态**（`ReturnType name(`）。只在调用点出现、无本仓声明的名字
   （如 `debugPrint`）不进符号表 ⇒ `$debugPrint(` 会漏报。
④ 只判 `lib/`：`test/` / `tool/` 不在判据面（缺陷的**生产端**在 lib）。
⑤ 词法器不追求完整 Dart 语法：解不开的字节按代码处理（最坏效果是漏报，不是误报）。
⑥ **R3 不判 `(`**（有意取舍）：`'共 $N(个)'` 这类「大写单字母 + 括号」中文日志会误报，
   而 `${Type(...)}` 意图的笔误零观测实例。探针 P6 把「大写+括号不判」钉死，
   使这条取舍**可回归**、不靠记忆。
⑦ **小写开头的顶层常量/变量后跟 `.` 一律不判**：这是本仓 27 处合法形态的主流
   （`'$prefix.dimension'` 字段路径），判它就等于判据报废。代价：
   `$kSomeConst.member` 形态漏报（本仓 0 处；Dart 常量成员访问本身极罕见）。

退出码（与 check_split_shape.py / check_wiring.py 同款）
=======================================================
    0 = 通过（或止血模式下无新增）
    1 = 有违规 / 有新增 / 判据条数守卫失败
    2 = 环境错误（lib 缺失 / 无 dart 文件 / 0 处插值 / 参数冲突 / 基线非法 / 豁免无 reason）

fail-closed：**绝不允许「无法检查 ≠ 通过」**——lib 缺失、扫到 0 个文件、
0 处插值（词法器失效的典型外观）一律 `exit 2`，不得返回 0。

用法
====
    python scripts/check_interp_shape.py --baseline tool/interp_shape_baseline.json
    python scripts/check_interp_shape.py                  # 全量报告（无豁免）
    python scripts/check_interp_shape.py --verbose        # 列出全部候选（含判为合法的）
    python scripts/check_interp_shape.py --json tool/interp_shape_baseline.json --force
    python scripts/check_interp_shape.py --root <副本树>   # 负向自检用
    python scripts/check_interp_shape.py --expect-rule-count 3

⚠️ `--json` 与 `--baseline` **不得同用**：`--json` 落盘一律全量，两者同用会把基线
写成「新增项」⇒ 存量债务一笔勾销（「基线自己把自己清空」型假绿），直接 `exit 2`。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from typing import Dict, List, Tuple

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

#: 代码生成产物后缀：改了会被 build_runner 覆盖，且 `database.g.dart` 内
#: 1316 处 `$XxxTable(` 是 drift 生成的**类名**（代码而非字符串）⇒ 必须排除。
GENERATED_SUFFIX = ".g.dart"

#: ★ 判据本体：简单插值 `$ident` 之后紧跟的字符集合。
#: 强度自检（`_selftest_check_interp_shape.py`）会按下方注释定位并把这一行改坏，
#: 以证明「判据放宽到什么都不报」时自测会变红。
HIT_SHAPES = ".("  # ← 判据本体：只此一处定义，强度自检依赖此行

#: 判据编号（用于 `--expect-rule-count` 守卫与违规项标识）。
RULE_R1 = "R1"
RULE_R2 = "R2"
RULE_R3 = "R3"
RULE_IDS: List[str] = [RULE_R1, RULE_R2, RULE_R3]
RULE_COUNT = len(RULE_IDS)

#: 判据的人类可读描述（用于报告与 JSON）。
RULE_DESC: Dict[str, str] = {
    RULE_R1: "类型 tear-off（lib 内声明）：$Type. / $Type( —— 应为 ${Type.…}",
    RULE_R2: "函数 tear-off：$fn( / $fn. —— 应为 ${fn(…)}",
    RULE_R3: "SDK/外部包类型 tear-off（大写开头 + .）：$String. —— 应为 ${String.…}",
}

#: R3 的形状面：**只判 `.`**（大写 + `(` 的取舍见模块 docstring，探针 P6 钉住）。
R3_SHAPES = "."

#: 基线 JSON 的 schema 标识（结构非法时 exit 2）。
BASELINE_SCHEMA = "interp-shape-baseline/1"

#: `--json` 生成时写入的 reason 占位符。带此占位符的豁免视同**无 reason**（exit 2）——
#: 否则「重生成基线」会自带一批看起来合规、实则未精核的豁免（豁免表腐烂的入口）。
REASON_PLACEHOLDER = "<须人工精核后补写"

#: 类型声明（`class` / `enum` / `mixin` / `typedef` / `extension type`）。
_TYPE_RE = re.compile(
    r"\b(?:class|enum|mixin|typedef|extension\s+type)\s+([A-Za-z_]\w*)"
)

#: 可调用体声明（`ReturnType name(`；行首缩进 + 可选注解/修饰符）。
#: 名字按 Dart 命名惯例要求**小写或下划线开头**（大写开头是构造函数，归 R1）。
_FUNC_RE = re.compile(
    r"^[ \t]*(?:@[\w.]+(?:\([^)]*\))?[ \t]*)*"
    r"(?:static[ \t]+|external[ \t]+|abstract[ \t]+)*"
    r"[A-Za-z_][\w<>,?.\[\] \t]*?[ \t]+"
    r"([a-z_]\w*)[ \t]*\(",
    re.MULTILINE,
)


class EnvError(RuntimeError):
    """环境错误：必须 exit 2（fail-closed），不得降级为「通过」。"""


# ---------------------------------------------------------------------------
# 数据结构
# ---------------------------------------------------------------------------


@dataclass
class Hit:
    """一处「简单插值 + 疑似成员访问/调用」候选。

    Attributes:
        rel: 相对 lib/ 的 POSIX 风格路径。
        line: 1-based 行号（行号会随改动漂移，**不得**用作基线键）。
        ident: 被插值的简单标识符。
        shape: 紧随其后的字符（`.` 或 `(`）。
        rule: 判定命中的判据编号（R1/R2）。
        text: 该行原文本（截断到 160 字符，供人读）。
    """

    rel: str
    line: int
    ident: str
    shape: str
    rule: str
    text: str

    def key(self) -> str:
        """基线键：**不含行号**（行号漂移会让豁免表腐烂）。

        Returns:
            形如 ``services/chat_service.dart|ChatService|.`` 的字符串。
        """
        return "%s|%s|%s" % (self.rel, self.ident, self.shape)

    def where(self) -> str:
        """人类可读定位串（`lib/路径:行号`）。"""
        return "lib/%s:%d" % (self.rel, self.line)


# ---------------------------------------------------------------------------
# 词法扫描：只取字符串字面量内部的「简单插值」
# ---------------------------------------------------------------------------


def _is_ident_start(ch: str) -> bool:
    """Dart 标识符首字符判定（字母或下划线；`$` 允许出现在非首位）。"""
    return ch.isalpha() or ch == "_"


def _is_ident_char(ch: str) -> bool:
    """Dart 标识符后续字符判定。"""
    return ch.isalnum() or ch in "_$"


def scan_interpolations(text: str) -> Tuple[List[Tuple[int, str, str]], int]:
    """扫描一段 Dart 源码，取字符串字面量内部的简单插值。

    状态机：`code` 帧（含 `${…}` 内部）与 `str` 帧交替；
    注释（`//`、`/* */`）在 code 帧内跳过 ⇒ 文档里写的坏例子**不会**被误判。

    Args:
        text: 源文件全文。

    Returns:
        ``(hits, total)``：hits 为 ``[(line, ident, shape)]``（只含 shape ∈ HIT_SHAPES）；
        total 为该文件内**简单插值总数**（用于 fail-closed：全仓 0 处 ⇒ 词法器失效）。
    """
    hits: List[Tuple[int, str, str]] = []
    total = 0
    n = len(text)
    i = 0
    line = 1
    # 帧：["code", brace_depth] 或 ["str", qchar, qlen, raw]
    stack: List[list] = [["code", 0]]
    while i < n:
        fr = stack[-1]
        if fr[0] == "code":
            ch = text[i]
            if ch == "/" and i + 1 < n and text[i + 1] == "/":
                j = text.find("\n", i)
                i = n if j < 0 else j
                continue
            if ch == "/" and i + 1 < n and text[i + 1] == "*":
                j = text.find("*/", i + 2)
                end = n if j < 0 else j + 2
                line += text.count("\n", i, end)
                i = end
                continue
            if ch in ("'", '"'):
                qlen = 3 if text.startswith(ch * 3, i) else 1
                raw = (
                    i > 0
                    and text[i - 1] == "r"
                    and (i == 1 or not _is_ident_char(text[i - 2]))
                )
                stack.append(["str", ch, qlen, raw])
                i += qlen
                continue
            if ch == "{":
                fr[1] += 1
            elif ch == "}":
                if fr[1] == 0 and len(stack) > 1:
                    stack.pop()
                    i += 1
                    continue
                fr[1] -= 1
            elif ch == "\n":
                line += 1
            i += 1
            continue

        # ---- 字符串态 ----
        _, qchar, qlen, raw = fr
        ch = text[i]
        if ch == "\\" and not raw:
            if i + 1 < n and text[i + 1] == "\n":
                line += 1
            i += 2
            continue
        if qlen == 3:
            if text.startswith(qchar * 3, i):
                stack.pop()
                i += 3
                continue
        elif ch == qchar:
            stack.pop()
            i += 1
            continue
        if ch == "\n":
            line += 1
            i += 1
            continue
        if not raw and ch == "$":
            if text.startswith("{", i + 1):
                stack.append(["code", 0])
                i += 2
                continue
            j = i + 1
            if j < n and _is_ident_start(text[j]):
                k = j
                while k < n and _is_ident_char(text[k]):
                    k += 1
                total += 1
                nxt = text[k] if k < n else ""
                if nxt and nxt in HIT_SHAPES:  # ← 判据本体：强度自检按本行定位改坏
                    hits.append((line, text[j:k], nxt))
                i = k
                continue
        i += 1
    return hits, total


# ---------------------------------------------------------------------------
# 符号表
# ---------------------------------------------------------------------------


def _shadowed(src: str, ident: str) -> bool:
    """同文件内是否存在同名「形参 / 局部变量 / 字段」声明（R2 遮蔽检查）。

    正则级启发式（见模块 docstring 局限②）：宁可漏报（多抑制一条），
    不制造误报（把 `'共 $count(个)'` 这类中文日志判成缺陷）。

    Args:
        src: 同文件全文。
        ident: 被插值的标识符。

    Returns:
        True 表示该名字在本文件被局部绑定 ⇒ 不按 R2 判违规。
    """
    i = re.escape(ident)
    patterns = (
        r"(?:^|[^\w$.])this\.%s\b" % i,
        r"\b(?:final|var|const|late)[ \t]+%s\b" % i,
        r"\b[A-Za-z_][\w<>,?.\[\] \t]*?[ \t]+%s[ \t]*(?:=[^=]|[,;)\]])" % i,
    )
    return any(re.search(p, src, re.MULTILINE) for p in patterns)


def build_symbol_tables(sources: Dict[str, str]) -> Tuple[set, set]:
    """从 lib/ 全域源码收集类型名与可调用体名。

    Args:
        sources: ``{相对路径: 源码}``（已排除 `*.g.dart`）。

    Returns:
        ``(type_names, func_names)``。
    """
    types: set = set()
    funcs: set = set()
    for src in sources.values():
        types.update(_TYPE_RE.findall(src))
        funcs.update(_FUNC_RE.findall(src))
    types.discard("")
    funcs.discard("")
    return types, funcs


# ---------------------------------------------------------------------------
# 扫描 / 判定
# ---------------------------------------------------------------------------


def iter_dart_files(root: str) -> List[str]:
    """列出 lib/ 下待扫的 `.dart`（排除生成产物）。判据面 = lib/ 全域。"""
    lib = os.path.join(root, "lib")
    if not os.path.isdir(lib):
        raise EnvError("找不到 lib 目录：%s（须指向 yuesheng-flutter/ 或同构副本树）" % lib)
    out: List[str] = []
    for dirpath, dirnames, filenames in os.walk(lib):
        dirnames.sort()
        for name in sorted(filenames):
            if not name.endswith(".dart") or name.endswith(GENERATED_SUFFIX):
                continue
            out.append(os.path.join(dirpath, name))
        # 判据口径：lib/ 全域，本循环不留「只查单文件」开关
        #（强度自检会把本行改坏，证明「收窄到只认一个文件」时自测会变红）
    return out


def load_sources(paths: List[str], root: str) -> Dict[str, str]:
    """读取全部源文件（读失败 ⇒ EnvError，不得静默跳过）。"""
    lib = os.path.join(root, "lib")
    sources: Dict[str, str] = {}
    for p in paths:
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                sources[os.path.relpath(p, lib).replace(os.sep, "/")] = fh.read()
        except OSError as exc:
            raise EnvError("读取失败：%s（%s）" % (p, exc)) from exc
    return sources


def collect_hits(
    sources: Dict[str, str], types: set, funcs: set
) -> Tuple[List[Hit], List[Tuple[str, int, str, str, str]], int]:
    """对全域源码取候选并判定。

    Args:
        sources: ``{相对路径: 源码}``。
        types: 类型名集合（R1 的判别依据）。
        funcs: 可调用体名集合（R2 的判别依据）。

    Returns:
        ``(hits, legal, interp_total)``：hits=违规项；legal=判为合法的候选
        （`(rel, line, ident, shape, 理由)`，供 `--verbose` 举证不误报）；
        interp_total=全仓简单插值总数。
    """
    hits: List[Hit] = []
    legal: List[Tuple[str, int, str, str, str]] = []
    interp_total = 0
    for rel, src in sources.items():
        raw_hits, total = scan_interpolations(src)
        interp_total += total
        lines = src.split("\n")
        for line, ident, shape in raw_hits:
            text = lines[line - 1].strip() if line - 1 < len(lines) else ""
            if ident in types:
                hits.append(Hit(rel, line, ident, shape, RULE_R1, text[:160]))
            elif shape in R3_SHAPES and ident[:1].isupper():
                # R3：大写开头 + `.` 但不在 lib 类型表 ⇒ SDK / 外部包类型。
                # 不做遮蔽检查（理由见模块 docstring：宽松遮蔽会抑制真缺陷）。
                hits.append(Hit(rel, line, ident, shape, RULE_R3, text[:160]))
            elif ident in funcs and not _shadowed(src, ident):
                hits.append(Hit(rel, line, ident, shape, RULE_R2, text[:160]))
            elif ident in funcs:
                legal.append((rel, line, ident, shape, "同文件有同名变量/形参遮蔽 ⇒ 字面文本"))
            elif ident[:1].isupper():
                legal.append((rel, line, ident, shape, "大写 + `(`（R3 只判 `.`，探针 P6 钉住）"))
            else:
                legal.append((rel, line, ident, shape, "ident 非类型/函数且小写 ⇒ 故意的字面文本"))
    return hits, legal, interp_total


# ---------------------------------------------------------------------------
# 基线
# ---------------------------------------------------------------------------


def _group_by_key(hits: List[Hit]) -> Dict[str, List[Hit]]:
    """按基线键聚合（同一键出现多次要按**次数**比，不能按集合比）。"""
    grouped: Dict[str, List[Hit]] = {}
    for h in hits:
        grouped.setdefault(h.key(), []).append(h)
    return grouped


def write_baseline(path: str, hits: List[Hit], force: bool) -> int:
    """全量重生成基线（`--json`）。"""
    if os.path.exists(path) and not force:
        print("FAIL 基线已存在（%s）；重生成须 --force" % path)
        return 2
    entries: Dict[str, dict] = {}
    for h, group in _group_by_key(hits).items():
        entries[h] = {
            "reason": REASON_PLACEHOLDER + "：为何这处是合法字面文本>",
            "count": len(group),
            "sample": group[0].where(),
            "rule": group[0].rule,
        }
    payload = {
        "schema": BASELINE_SCHEMA,
        "note": "字符串插值 tear-off 形态基线；豁免必带 reason（逐条精核记录）",
        "violations": entries,
    }
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1)
    print("基线已生成：%s（%d 条）" % (path, len(entries)))
    print("⚠️ 重生成后必须逐条补 reason 并做负向验证，否则豁免表会腐烂")
    return 0


def read_baseline(path: str) -> Dict[str, dict]:
    """读基线并校验结构（非法 ⇒ EnvError）。"""
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        raise EnvError("基线读取/解析失败：%s（%s）" % (path, exc)) from exc
    if not isinstance(data, dict) or data.get("schema") != BASELINE_SCHEMA:
        raise EnvError("基线结构非法（schema 应为 %s）：%s" % (BASELINE_SCHEMA, path))
    violations = data.get("violations")
    if not isinstance(violations, dict):
        raise EnvError("基线结构非法（violations 应为对象）：%s" % path)
    return violations


# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------


def print_header(files: int, types: set, funcs: set, interp_total: int,
                 hits: List[Hit], legal: list) -> None:
    """打印扫描口径与规模（缺任一行，读数就无法归因）。"""
    print("== 字符串插值 tear-off 形态检测（%s）==" % ", ".join(RULE_IDS))
    print("扫描：%d 个 .dart（已排除 *%s 生成产物）" % (files, GENERATED_SUFFIX))
    print("符号表：类型 %d / 可调用体 %d" % (len(types), len(funcs)))
    print("简单插值：%d 处（形如 $ident）" % interp_total)
    print(
        "候选（$ident 后紧邻 %s）：%d 处 ⇒ 判违规 %d / 判合法 %d"
        % ("/".join(HIT_SHAPES), len(hits) + len(legal), len(hits), len(legal))
    )


def print_hits(hits: List[Hit], verbose: bool, legal: list) -> None:
    """打印违规项（与 verbose 下的合法候选举证）。"""
    for h in sorted(hits, key=lambda x: (x.rel, x.line)):
        print(
            "  [VIOLATION %s] %s  $%s%s\n      %s  ⇒ 建议形态 ${%s…}"
            % (h.rule, h.where(), h.ident, h.shape, h.text, h.ident)
        )
    if verbose:
        print("-- 判为合法（举证不误报）--")
        for rel, line, ident, shape, why in sorted(legal):
            print("  [ok] lib/%s:%d  $%s%s  ← %s" % (rel, line, ident, shape, why))


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------


def _rule_count_guard(expected: int) -> bool:
    """防判据被静默删减（`--expect-rule-count`）。"""
    if expected and expected != RULE_COUNT:
        print(
            "FAIL 判据条数守卫：期望 %d 条，实测 %d 条（%s）"
            % (expected, RULE_COUNT, ", ".join(RULE_IDS))
        )
        return False
    return True


def _run_check(args, hits: List[Hit]) -> int:
    """检查模式：有基线 ⇒ 止血（只卡新增），无基线 ⇒ 全量报告。"""
    grouped = _group_by_key(hits)
    if not args.baseline:
        print("全量报告（无基线 = 无豁免）：")
        print_hits(hits, args.verbose, args.legal)
        if hits:
            print("----")
            print("判定：FAIL（%d 处违规，%s）" % (len(hits), "/".join(RULE_IDS)))
            return 1
        print("判定：PASS（0 处违规）")
        return 0

    try:
        exempt = read_baseline(args.baseline)
    except EnvError as exc:
        print("FAIL %s" % exc)
        return 2

    bad = 0
    unjustified = 0
    for key, meta in sorted(exempt.items()):
        reason = meta.get("reason") if isinstance(meta, dict) else None
        if not reason or REASON_PLACEHOLDER in reason:
            print("FAIL [G2] 基线条目无有效 reason：%s（豁免必带精核依据）" % key)
            unjustified += 1
    if unjustified:
        print("----")
        print(
            "判定：FAIL（%d 条豁免无有效 reason ⇒ 无效豁免 = 无豁免，exit 2）" % unjustified
        )
        return 2
    # G3：新增违规（基线外的键，或同键次数超出基线）
    for key, group in sorted(grouped.items()):
        base_count = int(exempt.get(key, {}).get("count", 0) or 0)
        if len(group) > base_count:
            for h in group[base_count:]:
                print(
                    "FAIL [G3] 新增违规 %s：%s  $%s%s  ← %s"
                    % (h.rule, h.where(), h.ident, h.shape, h.text)
                )
            bad += 1
    # G1：基线键已不存在（已修 / 已改形）⇒ 豁免腐烂，建议清理（不阻断）
    for key in sorted(exempt):
        if key not in grouped:
            print("WARN [G1] 基线条目已失效：%s（该处已修或已改形）⇒ 建议从基线删除" % key)
    if args.verbose:
        print("-- 判为合法的候选 --")
        print_hits([], True, args.legal)
    if bad:
        print("----")
        print("判定：FAIL（%d 项须处置）" % bad)
        return 1
    print("判定：PASS（基线 %d 条豁免有效，无新增违规）" % len(exempt))
    return 0


def main() -> int:
    """CLI 入口。"""
    default_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--baseline", default=None)
    ap.add_argument("--json", default=None)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--root", default=default_root)
    ap.add_argument("--expect-rule-count", type=int, default=0)
    try:
        args = ap.parse_args()
    except SystemExit:
        print("FAIL 参数解析失败（用 --baseline / --json / --verbose / --root）")
        return 2

    if args.json and args.baseline:
        print("FAIL 参数冲突：--json 与 --baseline 不得同用（重生成 vs 检查）")
        return 2
    if not _rule_count_guard(args.expect_rule_count):
        return 1

    try:
        paths = iter_dart_files(args.root)
        if not paths:
            raise EnvError("lib 下扫到 0 个 .dart（目录空或路径错误）")
        sources = load_sources(paths, args.root)
    except EnvError as exc:
        print("FAIL %s" % exc)
        return 2

    types, funcs = build_symbol_tables(sources)
    if not types:
        print("FAIL 符号表零类型——类型正则或源码结构变化，先人工核实")
        return 2
    hits, legal, interp_total = collect_hits(sources, types, funcs)
    if interp_total == 0:
        print("FAIL 全仓 0 处字符串插值——词法器失效的典型外观，不得当作通过")
        return 2

    print_header(len(sources), types, funcs, interp_total, hits, legal)
    if args.json:
        return write_baseline(args.json, hits, args.force)
    args.legal = legal
    return _run_check(args, hits)


if __name__ == "__main__":
    sys.exit(main())
