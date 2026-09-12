#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A 类豁免准入守卫（A-Class Exemption Admission Guard）。

背景与动机
==========
`R-019-代码规范标准.md:57-60` 明文豁免「A 类纯常量知识库」不触发伪拆分审查。
**豁免原文的前提**（逐字）：

    part 拆分与内容领域边界严格一致、无逻辑耦合、无 override 契约

注意前提的**主语是「part 拆分」**——豁免的是**分片**的形态合法性，而不是
「宿主不得有逻辑」。后者与既定设计相反：批次 96-26/96-27 的数据/逻辑分离，
**宿主保留的正是「检索/渲染逻辑」**（台账 `:2313-2314` 原文）。

但 `check_split_shape.py:104-109` 的豁免是**纯按文件名 fullmatch** 的
（`_A_CLASS_PATTERNS`），**没有任何一处校验内容是否真的满足上述前提**
⇒ 豁免是 **fail-open** 的。可完全绕过门禁 10 的路径（实测代码直读）：

    建 `foo.dart`（任意名）声明 `part 'skills_data.dart';`，
    而 `skills_data.dart` 装 800 行逻辑——
    家族宿主 `foo.dart` 照常判 S1/S2（行数没超），
    而分片 `skills_data.dart` 因 basename 命中豁免而**跳过 S3** ⇒ 800 行零报警。

这与项目硬纪律正面冲突，见
`docs/ADR-C92-ungated-scripts-gate-accession.md:111`：
「**任何检查都必须显式 fail-closed：绝不允许「无法检查 ≠ 通过」**」。

实测漂移与清偿（2026-09-12，`RECON-P3-knowledge-relief-2026-09-12.md`）
--------------------------------------------------------------------
侦察发现 55 个 A 类豁免文件（4 宿主 + 51 分片）中 **2 个分片已含逻辑**：
  - `lib/services/skills_beginner_p9.dart`：`_crSlice` / `coachingRhythmContentFor`
  - `lib/services/skills_advanced_outline_p7.dart`：`_apSlice` / `_apSliceToEnd` /
    `advancedPhasesContentFor`
二者是 Phase 3「阶段裁剪」的**行为实现**（原由 `skill_dispatcher.dart:163`
经 `Skill.contentForPhase?.call(ctx.phase)` 消费），**不是常量**。

**★ P3-R3 已清偿**：5 个函数逐字迁至真 library
`lib/services/skill_phase_slicing.dart`（纯逻辑：`(phase, raw)` → 裁剪串）；
两个承载逻辑的分片随之删除，宿主 `skill_registry.dart` 的 `part` 声明同步
移除。为跨越 Dart 库私有性（part 私有常量跨库不可见），
`Skill.contentForPhase` 签名扩为 `(TeachingPhase phase, String content)`，
原文由 dispatcher 从 `skill.content` 送入，入口保持顶层 tear-off
（编译期常量，`const Skill(...)` 不变）。
⇒ 现状：**49 个分片全部为纯常量**，基线 `allowedFunctions` 归零 ——
A3 由「基线豁免」升为**硬卡**（任何新增顶层函数立即 FAIL）。

四条判据（每条都锚定 R-019 的一处前提）
----------------------------------------
  A1  **分片**不得声明 `class` / `extension` / `mixin`
      —— 纯常量文件不定义类型（前提②「纯常量」）。
  A2  **任何 A 类文件**不得出现 `@override`
      —— 直接检验前提③「无 override 契约」。
  A3  **分片**的顶层函数必须逐名登记在基线内；未登记的新函数 ⇒ 违规
      —— 前提②「无逻辑耦合」。
  A4  **任何 A 类文件**必须真的是「part 家族成员」
      （含 `part of '…';`，或含 `part '…';` 声明）
      —— 守住豁免的**适用范围**：防「借 A 类文件名但无 part 结构」滥用。

> 宿主**不做** A1/A3 断言：宿主按设计持有检索/渲染逻辑，对其施加「无函数」
> 会与 96-26/96-27 的既定分离设计冲突（越权改规则）。宿主仍受 A2/A4 约束。

两条防绕过 / 防假绿守卫（fail-closed）
--------------------------------------
  G1  分片数**不得少于**基线登记的 `minPartCount`
      —— 防「把分片改名移出豁免集」从而躲开门禁 10 的 S3。
  G2  A 类文件数为 0 ⇒ `exit 2`
      —— 空扫等于没检查，**绝不返回 0**（对齐 check_split_shape 的 fail-closed）。

单一真源（关键设计）
--------------------
豁免文件名模式**不复制**：本脚本通过文件路径 import `check_split_shape.py`，
直接复用其 `_A_CLASS_PATTERNS` 与 `is_exempt_basename`。理由：若两处各存一份，
将来给门禁 10 新增一类豁免时本守卫**不会自动覆盖**新类 ⇒ 又出现无人守卫的
豁免类。导入失败（文件缺失 / 语法错误）⇒ `exit 2`，绝不静默降级。

CLI 与退出码
------------
    python scripts/check_a_class_exemption.py                       # 全量报告
    python scripts/check_a_class_exemption.py --baseline <path>     # 止血模式：只报新增
    python scripts/check_a_class_exemption.py --json <path>         # 输出/写入基线 JSON
    python scripts/check_a_class_exemption.py --expect-rule-count 4 # 防判据被静默删减

    0 = 通过（或止血模式下无新增）
    1 = 有违规 / 有新增 / 判据条数守卫失败
    2 = 环境错误（lib 缺失 / 0 个 dart / 豁免模式真源载入失败 / 参数冲突）

重生成基线的陷阱（务必遵守）
----------------------------
`--json` 落盘一律**全量**；若同时传 `--json` 与 `--baseline`，本脚本直接报错
`exit 2` —— 否则写进去的只是「新增项」而非全量（「基线自己把自己清空」型假绿）。
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sys
from dataclasses import dataclass
from typing import Dict, List, Optional

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

#: 生成文件后缀：改了会被 build_runner 覆盖，永不可清偿，一律排除。
GENERATED_SUFFIX = ".g.dart"

#: 单个分片允许登记的顶层函数名上限（防「登记成百上千个函数」把守卫架空）。
MAX_REGISTERED_FUNCTIONS_PER_FILE = 5

#: 分片标志：`part of '…';`（该文件是别的库的一部分）。
_PART_OF_RE = re.compile(r"^\s*part\s+of\s+'", re.MULTILINE)

#: 宿主标志：`part '…';`（该文件声明了分片）。
_PART_HOST_RE = re.compile(r"^\s*part\s+'", re.MULTILINE)

#: 类型声明（分片里出现即违反「纯常量」）。含 `mixin class` / `abstract class` 等修饰。
_TYPE_DECL_RE = re.compile(
    r"^\s*(?:(?:abstract|sealed|base|final|interface)\s+)*(?:class|extension|mixin)\s+\w+",
    re.MULTILINE,
)

#: 顶层函数声明的行首模式：`<返回类型> <名字>(`，且**必须顶格**（0 缩进）。
#: 缩进的方法（类型内）不计入——分片里本就不该有类型（见 A1）。
_TOPLEVEL_FUNC_RE = re.compile(
    r"^(?P<ret>[A-Za-z_][\w<>,?\[\]\s]*?)\s+(?P<name>[A-Za-z_]\w*)\s*\(",
    re.MULTILINE,
)

#: 行首关键字：这些词的「首词」出现在 ret 里说明不是函数声明，须排除。
_LEADING_KEYWORDS = frozenset(
    {
        "if", "for", "while", "switch", "return", "case", "else", "do",
        "try", "catch", "finally", "assert", "const", "final", "var",
        "late", "await", "yield", "throw", "new", "super", "this",
        "part", "library", "import", "export", "typedef", "class",
        "enum", "extension", "mixin", "abstract", "sealed", "base",
        "interface", "when", "on", "deferred", "show", "hide", "as",
        "with", "static", "required", "covariant", "external",
    }
)

#: 判据编号（用于 --expect-rule-count 守卫与违规项标识）。
RULE_A1 = "A1"
RULE_A2 = "A2"
RULE_A3 = "A3"
RULE_A4 = "A4"
RULE_IDS: List[str] = [RULE_A1, RULE_A2, RULE_A3, RULE_A4]
RULE_COUNT = len(RULE_IDS)

#: 判据的人类可读描述（用于报告与 JSON）。
RULE_DESC: Dict[str, str] = {
    RULE_A1: "分片声明了 class/extension/mixin（违反前提②「纯常量」）",
    RULE_A2: "含 @override（违反前提③「无 override 契约」）",
    RULE_A3: "分片出现未登记的顶层函数（违反前提②「无逻辑耦合」）",
    RULE_A4: "非 part 家族成员（既无 part of 也无 part 声明）——豁免适用范围外",
}

#: 守卫编号（不计入 --expect-rule-count，属防绕过/防假绿层）。
GUARD_G1 = "G1"
GUARD_G2 = "G2"


class C:
    """终端着色常量（无 TTY 时无害，仅输出转义序列）。"""

    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    RED = "\033[31m"
    BOLD = "\033[1m"
    RESET = "\033[0m"


# ---------------------------------------------------------------------------
# 单一真源：从 check_split_shape.py 载入豁免模式
# ---------------------------------------------------------------------------


@dataclass
class ExemptionSource:
    """从 check_split_shape.py 载入的豁免定义（单一真源）。

    Attributes:
        module_path: 来源脚本路径（报告用）。
        pattern_count: 豁免模式条数（报告用）。
        is_exempt_basename: 豁免判定函数（按 basename fullmatch）。
    """

    module_path: str
    pattern_count: int
    is_exempt_basename: object


def load_exemption_source() -> tuple[Optional[ExemptionSource], Optional[str]]:
    """按文件路径 import `check_split_shape.py`，复用其豁免模式。

    豁免模式**不复制**：本脚本直接复用门禁 10 的 `_A_CLASS_PATTERNS` 与
    `is_exempt_basename`，从结构上消除「两处模式漂移 ⇒ 新豁免类无人守卫」。

    Returns:
        ``(source, error)``；成功时 ``error`` 为 None，失败时 ``source`` 为 None。
    """
    here = os.path.dirname(os.path.abspath(__file__))
    target = os.path.join(here, "check_split_shape.py")
    if not os.path.isfile(target):
        return None, f"豁免模式真源缺失：{target}"
    try:
        spec = importlib.util.spec_from_file_location(
            "_yuesheng_check_split_shape", target
        )
        if spec is None or spec.loader is None:
            return None, f"无法为 {target} 构造 import spec"
        module = importlib.util.module_from_spec(spec)
        # 必须先登记进 sys.modules 再 exec：真源含 `from __future__ import
        # annotations` + `@dataclass`，Python 3.12+ 的 dataclasses 会走
        # `sys.modules.get(cls.__module__).__dict__` 解析注解，未登记则
        # AttributeError（`'NoneType' object has no attribute '__dict__'`）。
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
    except Exception as exc:  # noqa: BLE001 - 任何载入失败都按环境错误处理
        sys.modules.pop("_yuesheng_check_split_shape", None)
        return None, f"载入豁免模式真源失败：{target}: {exc}"
    patterns = getattr(module, "_A_CLASS_PATTERNS", None)
    is_exempt = getattr(module, "is_exempt_basename", None)
    if not patterns or not callable(is_exempt):
        return None, f"{target} 未提供 _A_CLASS_PATTERNS / is_exempt_basename"
    return (
        ExemptionSource(
            module_path=target,
            pattern_count=len(patterns),
            is_exempt_basename=is_exempt,
        ),
        None,
    )


# ---------------------------------------------------------------------------
# 数据结构
# ---------------------------------------------------------------------------


@dataclass
class ExemptFile:
    """一个 A 类豁免文件的静态事实。

    Attributes:
        path: 项目根相对路径（POSIX 风格）。
        is_part: 是否为**分片**（含 `part of '…';`）。
        is_host: 是否为**宿主**（含 `part '…';` 声明）。
        type_decls: 类型声明的原文列表（class / extension / mixin）。
        override_count: ``@override`` 出现次数。
        top_level_functions: 顶层函数名列表（出现顺序）。
    """

    path: str
    is_part: bool
    is_host: bool
    type_decls: List[str]
    override_count: int
    top_level_functions: List[str]

    @property
    def in_family(self) -> bool:
        """是否为 part 家族成员（分片或宿主）。

        Returns:
            True 表示含 `part of` 或 `part '…';`。
        """
        return self.is_part or self.is_host


@dataclass
class Violation:
    """一条豁免准入违规。

    Attributes:
        file: 豁免文件相对路径。
        rule: 判据编号（A1/A2/A3/A4/G1）。
        detail: 人类可读细节。
    """

    file: str
    rule: str
    detail: str = ""


# ---------------------------------------------------------------------------
# 扫描
# ---------------------------------------------------------------------------


def _norm(path: str) -> str:
    """把路径归一化为 POSIX 风格（统一分隔符、去掉前导 `./`）。

    Args:
        path: 原始路径。

    Returns:
        归一化后的相对路径。
    """
    return path.replace("\\", "/").lstrip("./")


def collect_dart_files(lib_dir: str) -> List[str]:
    """递归收集 ``lib`` 下所有非生成 ``.dart`` 文件的绝对路径。

    Args:
        lib_dir: ``lib`` 目录绝对路径。

    Returns:
        排序后的 ``.dart`` 文件绝对路径列表。
    """
    files: List[str] = []
    for root, dirs, fnames in os.walk(lib_dir):
        dirs[:] = [d for d in dirs if d not in (".git", "build", ".dart_tool")]
        for fn in fnames:
            if fn.endswith(".dart") and not fn.endswith(GENERATED_SUFFIX):
                files.append(os.path.join(root, fn))
    return sorted(files)


def find_top_level_functions(text: str) -> List[str]:
    """提取源码中的顶层函数名（顶格声明，排除关键字开头）。

    Args:
        text: 文件全文。

    Returns:
        顶层函数名列表（按出现顺序，去重）。
    """
    names: List[str] = []
    for match in _TOPLEVEL_FUNC_RE.finditer(text):
        ret = match.group("ret").strip()
        words = ret.split()
        if words and words[0] in _LEADING_KEYWORDS:
            continue
        name = match.group("name")
        if name not in names:
            names.append(name)
    return names


def inspect_exempt_file(rel: str, text: str) -> ExemptFile:
    """抽取单个豁免文件的静态事实。

    Args:
        rel: 文件的项目根相对路径。
        text: 文件全文。

    Returns:
        该文件的静态事实对象。
    """
    return ExemptFile(
        path=rel,
        is_part=bool(_PART_OF_RE.search(text)),
        is_host=bool(_PART_HOST_RE.search(text)),
        type_decls=[m.group(0).strip() for m in _TYPE_DECL_RE.finditer(text)],
        override_count=text.count("@override"),
        top_level_functions=find_top_level_functions(text),
    )


def scan_exempt_files(
    lib_dir: str, all_dart: List[str], source: ExemptionSource, errors: List[str]
) -> List[ExemptFile]:
    """扫描全部 A 类豁免文件。

    Args:
        lib_dir: ``lib`` 目录绝对路径。
        all_dart: 候选 ``.dart`` 文件绝对路径列表。
        source: 豁免定义真源。
        errors: 错误累积列表（读取失败追加于此，不静默跳过）。

    Returns:
        豁免文件事实列表（按路径排序）。
    """
    assert callable(source.is_exempt_basename)
    found: List[ExemptFile] = []
    for path in all_dart:
        rel = _norm(os.path.relpath(path, lib_dir))
        if not source.is_exempt_basename(os.path.basename(rel)):
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError as exc:
            errors.append(f"read failed: {rel}: {exc}")
            continue
        found.append(inspect_exempt_file(rel, text))
    return found


def evaluate(
    files: List[ExemptFile],
    allowed: Dict[str, List[str]],
    min_part_count: int,
) -> List[Violation]:
    """按四条判据 + 一条守卫求值，返回违规列表。

    Args:
        files: 豁免文件事实列表。
        allowed: 基线登记的 ``{分片: [允许的顶层函数名]}``。
        min_part_count: 基线登记的分片数下限（G1）。

    Returns:
        违规列表（A1/A2/A3/A4/G1）。
    """
    violations: List[Violation] = []
    for item in files:
        if item.is_part:
            for decl in item.type_decls:
                violations.append(
                    Violation(
                        file=item.path,
                        rule=RULE_A1,
                        detail=f"分片声明类型：{decl}",
                    )
                )
        if item.override_count:
            violations.append(
                Violation(
                    file=item.path,
                    rule=RULE_A2,
                    detail=f"@override x{item.override_count}",
                )
            )
        if item.is_part:
            permitted = set(allowed.get(item.path, []))
            for name in item.top_level_functions:
                if name not in permitted:
                    violations.append(
                        Violation(
                            file=item.path,
                            rule=RULE_A3,
                            detail=f"分片未登记顶层函数 {name}",
                        )
                    )
        if not item.in_family:
            violations.append(
                Violation(
                    file=item.path,
                    rule=RULE_A4,
                    detail="既无 `part of` 也无 `part '…';`——不属 part 家族",
                )
            )

    part_count = sum(1 for f in files if f.is_part)
    if part_count < min_part_count:
        violations.append(
            Violation(
                file="<guard>",
                rule=GUARD_G1,
                detail=(
                    f"分片数 {part_count} < 基线下限 {min_part_count}"
                    "（疑似改名移出豁免集）"
                ),
            )
        )
    return violations


# ---------------------------------------------------------------------------
# 基线
# ---------------------------------------------------------------------------


def load_baseline(path: str) -> tuple[Dict[str, List[str]], int, int]:
    """读取基线 JSON，返回（允许函数表, 分片数下限, 判据条数）。

    Args:
        path: 基线 JSON 路径。

    Returns:
        ``(allowed, min_part_count, rule_count)``。

    Raises:
        OSError: 读取失败。
        ValueError: JSON 结构非法（含「单文件登记函数数超上限」的防架空校验）。
    """
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    allowed = data.get("allowedFunctions")
    if not isinstance(allowed, dict):
        raise ValueError("baseline JSON has no 'allowedFunctions' object")
    # 防架空守卫：单文件登记的函数数不得超上限，否则「登记」就成了
    # 「把逻辑合法化」的通道（R-019 豁免语义是「纯常量知识库」）。
    for path_key, names in allowed.items():
        if not isinstance(names, list):
            raise ValueError(f"allowedFunctions[{path_key!r}] 不是列表")
        if len(names) > MAX_REGISTERED_FUNCTIONS_PER_FILE:
            raise ValueError(
                f"allowedFunctions[{path_key!r}] 登记 {len(names)} 个函数，"
                f"超出上限 {MAX_REGISTERED_FUNCTIONS_PER_FILE}"
                "（豁免语义为「纯常量知识库」，不接受批量登记逻辑）"
            )
    min_parts = data.get("minPartCount")
    if not isinstance(min_parts, int):
        raise ValueError("baseline JSON has no integer 'minPartCount'")
    rules = data.get("ruleCount")
    if not isinstance(rules, int):
        raise ValueError("baseline JSON has no integer 'ruleCount'")
    return {k: list(v) for k, v in allowed.items()}, min_parts, rules


def build_snapshot(
    dir_arg: str, files: List[ExemptFile], source: ExemptionSource
) -> Dict[str, object]:
    """构造基线快照字典（全量）。

    基线**不记录** A1/A2/A4 的存量（它们必须恒为 0）；只登记两类
    「既有可容忍事实」：
    ① ``allowedFunctions``：分片中已存在且经侦察确认的顶层函数
       （存量漂移，**透明登记**而非隐藏）；
    ② ``minPartCount``：分片数下限（G1 防绕过）。

    Args:
        dir_arg: 扫描目录参数。
        files: 豁免文件事实列表。
        source: 豁免定义真源。

    Returns:
        可直接 json.dump 的快照字典。
    """
    parts = [f for f in files if f.is_part]
    return {
        "dir": dir_arg,
        "exemptionSource": os.path.basename(source.module_path),
        "exemptionPatternCount": source.pattern_count,
        "ruleCount": RULE_COUNT,
        "fileCount": len(files),
        "partCount": len(parts),
        "minPartCount": len(parts),
        "allowedFunctions": {
            f.path: list(f.top_level_functions)
            for f in parts
            if f.top_level_functions
        },
        "violations": [],
    }


# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------


def _print_header(
    dir_arg: str,
    files: List[ExemptFile],
    source: ExemptionSource,
    by_rule: Dict[str, int],
    baseline: Optional[str],
    baseline_min_parts: int,
) -> None:
    """打印报告表头。

    Args:
        dir_arg: 扫描目录参数。
        files: 豁免文件事实列表。
        source: 豁免定义真源。
        by_rule: 各判据命中计数。
        baseline: 基线路径（None 表示全量模式）。
        baseline_min_parts: 基线登记的分片数下限。
    """
    parts = sum(1 for f in files if f.is_part)
    hosts = sum(1 for f in files if f.is_host and not f.is_part)
    mode = (
        f"止血模式（基线 {baseline}，分片下限 {baseline_min_parts}，只报新增）"
        if baseline
        else "全量模式"
    )
    print("=" * 68)
    print(
        f"A 类豁免准入扫描：目录={dir_arg}  豁免文件={len(files)}"
        f"（分片 {parts} / 宿主 {hosts}）"
    )
    print(f"模式：{mode}")
    print(f"豁免模式真源：{source.module_path}（{source.pattern_count} 条模式）")
    print("=" * 68)
    print()
    print(f"{C.BOLD}判据条数：{RULE_COUNT}{C.RESET}")
    for rid in RULE_IDS:
        print(f"  {rid}  {RULE_DESC[rid]}：{by_rule.get(rid, 0)} 个")
    print()


def _print_violations(violations: List[Violation], baseline: Optional[str]) -> None:
    """打印违规列表。

    Args:
        violations: 待展示的违规列表。
        baseline: 基线路径（None 表示全量模式）。
    """
    header = "新增违规" if baseline else "违规"
    print(f"{C.RED}{C.BOLD}{header}：{len(violations)} 个{C.RESET}")
    print()
    print(f"  {'判据':<4} 文件 / 细节")
    print("  " + "-" * 64)
    for item in sorted(violations, key=lambda x: (x.rule, x.file)):
        print(f"  {item.rule:<4} {item.file}  {item.detail}")
    print()


def _print_info(files: List[ExemptFile]) -> None:
    """打印信息型小节（宿主函数分布）。

    宿主按设计持有检索/渲染逻辑，**不参与** A1/A3 判定；此处仅透明列出，
    便于人工审阅「宿主是否在无节制膨胀」。

    Args:
        files: 豁免文件事实列表。
    """
    hosts = sorted(
        (f for f in files if f.is_host and not f.is_part),
        key=lambda x: -len(x.top_level_functions),
    )
    if not hosts:
        return
    print(f"{C.BOLD}信息型：宿主函数分布（不参与判定）{C.RESET}")
    for item in hosts:
        print(
            f"  {len(item.top_level_functions):>3} 个顶层函数  {item.path}"
        )
    print()


def print_report(
    dir_arg: str,
    files: List[ExemptFile],
    source: ExemptionSource,
    violations: List[Violation],
    shown: List[Violation],
    baseline: Optional[str],
    baseline_min_parts: int,
) -> None:
    """打印终端报告。

    Args:
        dir_arg: 扫描目录参数。
        files: 豁免文件事实列表。
        source: 豁免定义真源。
        violations: 全量违规列表。
        shown: 待展示的违规列表（全量或过滤后）。
        baseline: 基线路径（None 表示全量模式）。
        baseline_min_parts: 基线登记的分片数下限。
    """
    by_rule: Dict[str, int] = {rid: 0 for rid in RULE_IDS}
    for item in violations:
        by_rule[item.rule] = by_rule.get(item.rule, 0) + 1

    _print_header(
        dir_arg, files, source, by_rule, baseline, baseline_min_parts
    )

    if not shown:
        if baseline:
            print(
                f"{C.GREEN}无**新增**豁免准入违规 ✓{C.RESET}"
                f"（全量 {len(violations)} 个均已在基线内）"
            )
        else:
            print(f"{C.GREEN}无豁免准入违规 ✓{C.RESET}")
    else:
        _print_violations(shown, baseline)

    _print_info(files)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _build_arg_parser() -> argparse.ArgumentParser:
    """构造命令行解析器。

    Returns:
        配置好的 ``argparse.ArgumentParser``。
    """
    ap = argparse.ArgumentParser(
        description=(
            "A 类豁免准入守卫（R-019:57-60 豁免前提的内容级检查，只测不改）"
        )
    )
    ap.add_argument("--dir", default="lib", help="扫描目录（默认 lib）")
    ap.add_argument("--json", default="", help="当前扫描结果落盘 JSON 路径（全量）")
    ap.add_argument(
        "--baseline",
        default="",
        help="基线 JSON；给出后**只报基线之外的新增项**（债务止血模式）。"
        "不可与 --json 同时使用（否则基线会被清空）。",
    )
    ap.add_argument(
        "--expect-rule-count",
        type=int,
        default=None,
        help="校验判据条数（应为 4）；不符则 exit 1（防判据被静默删减）",
    )
    return ap


def resolve_lib_dir(dir_arg: str) -> str:
    """把 ``--dir`` 解析为绝对路径（项目根优先，其次 cwd）。

    Args:
        dir_arg: ``--dir`` 原始值。

    Returns:
        绝对目录路径。
    """
    if os.path.isabs(dir_arg):
        return dir_arg
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    primary = os.path.join(project_root, dir_arg)
    if os.path.isdir(primary):
        return primary
    cwd_candidate = os.path.abspath(dir_arg)
    if os.path.isdir(cwd_candidate):
        return cwd_candidate
    return primary


def _validate_env(dir_arg: str) -> tuple[Optional[str], List[str], int]:
    """fail-closed 环境校验：目录存在 + 非空。

    Args:
        dir_arg: ``--dir`` 参数。

    Returns:
        ``(lib_dir, dart_files, exit_code)``；失败时 ``lib_dir`` 为 None。
    """
    lib_dir = resolve_lib_dir(dir_arg)
    if not os.path.isdir(lib_dir):
        print(
            f"{C.RED}ERROR{C.RESET}: 扫描目录不存在或不是目录：{lib_dir}",
            file=sys.stderr,
        )
        return None, [], 2
    all_dart = collect_dart_files(lib_dir)
    if not all_dart:
        print(
            f"{C.RED}ERROR{C.RESET}: 扫描到 0 个 .dart 文件：{lib_dir}"
            "（空的检查等于没检查，按环境错误处理）",
            file=sys.stderr,
        )
        return None, [], 2
    return lib_dir, all_dart, 0


def _write_snapshot(json_path: str, snapshot: Dict[str, object]) -> Optional[str]:
    """把全量快照写入 JSON（锁 LF 换行）。

    Args:
        json_path: 输出路径。
        snapshot: 全量快照字典。

    Returns:
        成功返回 None，失败返回错误消息。
    """
    try:
        parent = os.path.dirname(os.path.abspath(json_path))
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(json_path, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(snapshot, fh, ensure_ascii=False, indent=2)
    except OSError as exc:
        return f"无法写入 {json_path!r}: {exc}"
    return None


def main(argv: List[str]) -> int:
    """脚本入口。

    Args:
        argv: 命令行参数（不含程序名）。

    Returns:
        进程退出码（0 通过 / 1 违规或守卫失败 / 2 环境错误）。
    """
    args = _build_arg_parser().parse_args(argv)

    if args.json and args.baseline:
        print(
            f"{C.RED}ERROR{C.RESET}: --json 与 --baseline 不可同时使用："
            "--json 一律落全量，若带 --baseline 只会写入「新增项」，"
            "会把存量一笔勾销（基线自清空型假绿）。",
            file=sys.stderr,
        )
        return 2

    source, src_err = load_exemption_source()
    if source is None:
        print(f"{C.RED}ERROR{C.RESET}: {src_err}", file=sys.stderr)
        return 2

    lib_dir, all_dart, code = _validate_env(args.dir)
    if lib_dir is None:
        return code

    errors: List[str] = []
    files = scan_exempt_files(lib_dir, all_dart, source, errors)
    if errors:
        for msg in errors:
            print(f"{C.YELLOW}ERROR{C.RESET}: {msg}", file=sys.stderr)
        print(
            f"{C.RED}ERROR{C.RESET}: {len(errors)} 个文件读取失败，"
            "按 fail-closed 原则视为环境错误。",
            file=sys.stderr,
        )
        return 2

    # G2：A 类文件数为 0 ⇒ 模式匹配逻辑失效（空扫假绿），按环境错误处理。
    if not files:
        print(
            f"{C.RED}ERROR{C.RESET}: 未匹配到任何 A 类豁免文件"
            f"（lib={lib_dir}，真源 {source.module_path}）"
            "—— 空扫等于没检查，按环境错误处理。",
            file=sys.stderr,
        )
        return 2

    # 判据条数守卫
    if args.expect_rule_count is not None and RULE_COUNT != args.expect_rule_count:
        print(
            f"{C.RED}{C.BOLD}RULE COUNT GUARD FAIL: "
            f"expected {args.expect_rule_count}, got {RULE_COUNT}{C.RESET}"
        )
        return 1

    allowed: Dict[str, List[str]] = {}
    min_part_count = 0
    if args.baseline:
        try:
            allowed, min_part_count, rules = load_baseline(args.baseline)
        except (OSError, ValueError) as exc:
            print(
                f"{C.RED}ERROR{C.RESET}: 无法读取基线 {args.baseline!r}: {exc}",
                file=sys.stderr,
            )
            return 2
        if rules != RULE_COUNT:
            print(
                f"{C.RED}ERROR{C.RESET}: 基线的 ruleCount={rules} 与当前判据条数 "
                f"{RULE_COUNT} 不符（判据被增删后必须重生成基线）",
                file=sys.stderr,
            )
            return 2

    violations = evaluate(files, allowed, min_part_count)
    # 止血模式下「已登记」的存量不再重复报出：A3 由 allowed 表吸收，
    # G1 由 min_part_count 满足，故基线下 violations 即为「新增」。
    shown = violations

    print_report(
        dir_arg=args.dir,
        files=files,
        source=source,
        violations=violations,
        shown=shown,
        baseline=args.baseline or None,
        baseline_min_parts=min_part_count,
    )

    if args.json:
        write_err = _write_snapshot(
            args.json, build_snapshot(args.dir, files, source)
        )
        if write_err:
            print(f"{C.RED}ERROR{C.RESET}: {write_err}", file=sys.stderr)
            return 2
        print(f"\n已落盘：{args.json}（全量 {len(files)} 个豁免文件）")

    return 1 if shown else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
