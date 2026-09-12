#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""拆分之形检测器（Split-Shape Detector）——R-019「文件 ≤ 300 行 / 禁止伪拆分」。

背景与动机
==========
R-019 有两条**从未被机器执行**的规则：
  ① 文件 ≤ 300 行；
  ② 服务层禁止用 `part` / `extension` 机械拆分凑行数（史称「伪拆分」）。

现有门禁缺口
------------
`tool/check_r019.py` 只统计**函数**行数（`limit: 50`），基线
`tool/r019_baseline.json` 里**没有任何文件行数字段**。于是历史上执行过的
「伪拆分」（用 `part` 把超长文件切成碎片来凑行数）**七道门禁全绿也无法察觉**。
本脚本补上这个检测能力：**只测不拆**，把「拆分之形」显式暴露出来。

三条判据（口径）
----------------
给定「宿主 → 其 part 文件列表」的家族关系，设家族内**宿主** H、任一 part P：

  S1  宿主 >300 行 **且** 家族内存在任一 part >300 行
      —— 伪拆分（拆分净效果为负：宿主没变小，还多造一个超限文件）。
  S2  宿主 >300 行（无论 part 如何）
      —— 文件级超限未解决（含「拆了没拆动」形态）。
  S3  家族内任一 part >300 行（宿主未超限也算）
      —— 拆分产物本身超限。

行数口径：**物理行数**（`sum(1 for _ in open(...))`），与 R-019 现有口径一致。

数据模型
--------
1. 遍历 `lib/**/*.dart`，**排除** `*.g.dart`（代码生成产物，改了会被
   build_runner 覆盖，永不可清偿）。
2. 读取宿主文件中的手写 `part 'xxx.dart';` 声明，**排除** `.g.dart` 结尾的
   （那是合法代码生成）。part 路径**相对宿主所在目录**解析。
3. 由家族关系 + 行数，按三条判据产出违规项。

A 类豁免白名单（**必须实现，否则会误报**）
------------------------------------------
`R-019-代码规范标准.md:57-60` 明文豁免「A 类纯常量知识库」：
part 拆分与内容领域边界严格一致、无逻辑耦合、无 override 契约，
**不触发伪拆分审查**。豁免模式（按**文件名** fullmatch）：
  - `skills_<任意>.dart`（如 `skills_l1_core_p1.dart`、`skills_diagnosis.dart`）
  - `skill_registry.dart`
  - 任意含 `_knowledge_base` 的
  - `{syndrome,technique,training}_kb_content*.dart`

豁免规则：被豁免的**宿主**不参与 S1/S2 判定；但豁免**不递归**——
非豁免宿主下的 part 仍照常判定。

CLI 与退出码
------------
    python scripts/check_split_shape.py                          # 全量报告
    python scripts/check_split_shape.py --baseline <path>        # 止血模式：只报新增
    python scripts/check_split_shape.py --json <path>            # 输出/写入基线 JSON
    python scripts/check_split_shape.py --expect-rule-count 3    # 防判据被静默删减

退出码：
    0 = 通过（或止血模式下无新增）
    1 = 有违规 / 有新增 / 判据条数守卫失败
    2 = 环境错误（lib 目录不存在 / 空目录 / 无 dart 文件 / 参数冲突）

重生成基线的陷阱（务必遵守）
----------------------------
`--json` 落盘一律**全量**；若同时传 `--json` 与 `--baseline`，本脚本直接
报错 `exit 2` —— 否则写进去的只是「新增项」而非全量，等于把存量债务
一笔勾销（「基线自己把自己清空」型假绿）。

fail-closed（项目硬纪律）
-------------------------
**绝不允许「无法检查 ≠ 通过」**：
  - `lib` 不存在 / 空目录 / 扫到 0 个 `.dart` → `exit 2`，**不得**返回 0。
  - 读取某文件失败 → 记 stderr 并计入错误，**不得静默跳过**。
这条是项目前车之鉴：`check_coverage.py` 接入时曾因「lcov 被抽走记 SKIP
不阻断」而 fail-open。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field
from typing import Dict, List, Optional

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

#: 文件行数阈值：S1/S2 判「宿主超限」、S3 判「part 超限」共用。
DEFAULT_FILE_LIMIT = 300

#: 生成文件后缀：改了会被 build_runner 覆盖，永不可清偿，一律排除。
GENERATED_SUFFIX = ".g.dart"

#: 手写 part 声明（行首 `part '...';`，允许前置空白）。
PART_RE = re.compile(r"^\s*part\s+'([^']+)'\s*;", re.MULTILINE)

#: A 类纯常量知识库的豁免文件名模式（按 basename fullmatch）。
#: 与 `R-019-代码规范标准.md:57-60` 逐条对齐。
_A_CLASS_PATTERNS = [
    re.compile(r"skills_[\w]+\.dart"),                                   # skills_<任意>.dart
    re.compile(r"skill_registry\.dart"),                                 # skill_registry.dart
    re.compile(r"[\w]*_knowledge_base[\w]*\.dart"),                      # 任意含 _knowledge_base
    re.compile(r"(?:syndrome|technique|training)_kb_content[\w]*\.dart"),  # 三大 KB 内容分片
]

#: 判据编号（用于 --expect-rule-count 守卫与违规项标识）。
RULE_S1 = "S1"
RULE_S2 = "S2"
RULE_S3 = "S3"
RULE_IDS: List[str] = [RULE_S1, RULE_S2, RULE_S3]
RULE_COUNT = len(RULE_IDS)

#: 判据的人类可读描述（用于报告与 JSON）。
RULE_DESC: Dict[str, str] = {
    RULE_S1: "宿主 >300 行 且 家族内存在任一 part >300 行（伪拆分）",
    RULE_S2: "宿主 >300 行（文件级超限未解决）",
    RULE_S3: "家族内任一 part >300 行（拆分产物超限）",
}


class C:
    """终端着色常量（无 TTY 时无害，仅输出转义序列）。"""

    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    RED = "\033[31m"
    BOLD = "\033[1m"
    RESET = "\033[0m"


# ---------------------------------------------------------------------------
# 数据结构
# ---------------------------------------------------------------------------


@dataclass
class Violation:
    """一条拆分之形违规。

    Attributes:
        host: 宿主文件相对路径（POSIX 风格）。
        rule: 判据编号（S1/S2/S3）。
        host_lines: 宿主物理行数。
        part_lines: 触发判据的 part 行数（S2 且无超限 part 时为 0）。
        part: 触发判据的 part 相对路径（无则空串）。
        oversized_parts: 家族内所有超限 part 的 ``{路径: 行数}``。
    """

    host: str
    rule: str
    host_lines: int
    part_lines: int = 0
    part: str = ""
    oversized_parts: Dict[str, int] = field(default_factory=dict)

    def key(self) -> str:
        """唯一定位键：宿主 + 判据 + 触发 part（用于基线比对）。

        Returns:
            形如 ``doc:rule:part`` 的字符串键。
        """
        return f"{self.host}:{self.rule}:{self.part}"


@dataclass
class Family:
    """一个「宿主 → part 列表」家族。

    Attributes:
        host: 宿主文件相对路径（POSIX 风格）。
        host_lines: 宿主物理行数。
        parts: ``{part 相对路径: part 物理行数}``。
        exempt: 宿主是否为 A 类豁免（豁免则不参与 S1/S2）。
    """

    host: str
    host_lines: int
    parts: Dict[str, int]
    exempt: bool


# ---------------------------------------------------------------------------
# 扫描辅助
# ---------------------------------------------------------------------------


def _norm(path: str) -> str:
    """把路径归一化为 POSIX 风格（统一分隔符、去掉前导 `./`）。

    Args:
        path: 原始路径（可能含反斜杠或前导 `./`）。

    Returns:
        归一化后的相对路径。
    """
    return path.replace("\\", "/").lstrip("./")


def is_exempt_basename(basename: str) -> bool:
    """判断文件名是否属于 A 类纯常量知识库（豁免伪拆分审查）。

    Args:
        basename: 文件名（不含路径），如 ``skills_l1_core_p1.dart``。

    Returns:
        命中任一豁免模式返回 True。按文件名 fullmatch，非路径匹配。
    """
    return any(p.fullmatch(basename) for p in _A_CLASS_PATTERNS)


def count_lines(path: str) -> int:
    """统计文件的物理行数（与 R-019 现有口径一致）。

    采用 ``sum(1 for _ in open(...))`` 语义：逐行计数，不依赖文件末尾是否有
    换行符。读取失败时**向上抛出**，由调用方计入错误（fail-closed）。

    Args:
        path: 文件绝对路径。

    Returns:
        物理行数。

    Raises:
        OSError: 读取失败时抛出。
    """
    with open(path, encoding="utf-8", errors="replace") as fh:
        return sum(1 for _ in fh)


def parse_part_targets(path: str, host_dir_rel: str) -> List[str]:
    """解析宿主文件中的手写 ``part`` 声明，返回 part 相对路径列表。

    排除 ``.g.dart`` 结尾的 part（合法代码生成）。part 路径**相对宿主所在
    目录**解析，并归一到项目根相对路径。读取失败时向上抛出（fail-closed）。

    Args:
        path: 宿主文件绝对路径。
        host_dir_rel: 宿主所在目录相对项目根的 POSIX 路径。

    Returns:
        part 文件的项目根相对路径列表（去重后保持顺序）。
    """
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    targets: List[str] = []
    for raw in PART_RE.findall(text):
        target = raw.strip()
        if target.endswith(GENERATED_SUFFIX):
            continue
        # 相对宿主目录解析后再归一化，得到项目根相对路径。
        joined = os.path.join(host_dir_rel, target) if host_dir_rel else target
        norm = _norm(os.path.normpath(joined))
        if norm not in targets:
            targets.append(norm)
    return targets


# ---------------------------------------------------------------------------
# 家族构建
# ---------------------------------------------------------------------------


def collect_dart_files(lib_dir: str) -> List[str]:
    """递归收集 ``lib`` 下所有非生成 ``.dart`` 文件的绝对路径。

    排除 ``.g.dart`` 生成产物与 ``.git`` / ``build`` / ``.dart_tool`` 目录。

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


def build_families(
    lib_dir: str, dart_files: List[str], errors: List[str]
) -> List[Family]:
    """构建所有含 part 的「宿主 → part 行数」家族。

    Args:
        lib_dir: ``lib`` 目录绝对路径。
        dart_files: 候选 ``.dart`` 文件绝对路径列表。
        errors: 错误累积列表（读取失败信息追加于此，不静默跳过）。

    Returns:
        家族列表（仅含声明了 ≥1 个手写 part 的宿主）。
    """
    families: List[Family] = []
    for path in dart_files:
        rel = _norm(os.path.relpath(path, lib_dir))
        host_dir_rel = os.path.dirname(rel)
        try:
            targets = parse_part_targets(path, host_dir_rel)
        except OSError as exc:
            errors.append(f"read failed (host): {rel}: {exc}")
            continue
        if not targets:
            continue
        try:
            host_lines = count_lines(path)
        except OSError as exc:
            errors.append(f"read failed (host lines): {rel}: {exc}")
            continue
        parts: Dict[str, int] = {}
        for target in targets:
            abs_part = os.path.join(lib_dir, target)
            if not os.path.isfile(abs_part):
                # 缺失的 part 是异常信号，但不属本脚本判据范围，记 stderr。
                errors.append(f"missing part: {target} (declared by {rel})")
                continue
            try:
                parts[target] = count_lines(abs_part)
            except OSError as exc:
                errors.append(f"read failed (part lines): {target}: {exc}")
        families.append(
            Family(
                host=rel,
                host_lines=host_lines,
                parts=parts,
                exempt=is_exempt_basename(os.path.basename(rel)),
            )
        )
    return families


# ---------------------------------------------------------------------------
# 判据求值
# ---------------------------------------------------------------------------


def oversized_parts(family: Family, limit: int) -> Dict[str, int]:
    """返回家族内所有**非豁免**且超过 limit 行的 part（``{路径: 行数}``）。

    A 类豁免按**part 自身文件名**判定（与宿主豁免独立，故「豁免不递归」
    只表示「非豁免宿主下的 part 照常判定」，而**豁免 part 自身**仍豁免——
    如 ``skill_registry.dart`` 家族下的 ``skills_*.dart`` 分片）。
    与规格实测基线 S3=4 对齐：``skill_registry`` 家族（5852 行 / 16 part）
    与三大 KB 分片全属豁免，不得报出。

    Args:
        family: 家族对象。
        limit: 行数阈值。

    Returns:
        超限 part 映射（保持家族内声明顺序）。
    """
    return {
        p: n
        for p, n in family.parts.items()
        if n > limit and not is_exempt_basename(os.path.basename(p))
    }


def evaluate_family(family: Family, limit: int) -> List[Violation]:
    """对单个家族求值，返回其触发的所有违规项。

    判据（详见模块 docstring）：
      S1 = 宿主 >limit 且 有 part >limit；
      S2 = 宿主 >limit（无论 part）；
      S3 = 有 part >limit（无论宿主）。
    被豁免的宿主不参与 S1/S2；S3 仍照常判定（豁免不递归）。

    Args:
        family: 家族对象。
        limit: 行数阈值。

    Returns:
        违规项列表。
    """
    over = oversized_parts(family, limit)
    host_over = family.host_lines > limit
    violations: List[Violation] = []

    if not family.exempt and host_over and over:
        # S1：取行数最大的超限 part 作为触发标识。
        violations.append(_make_part_violation(family, RULE_S1, over))
    if not family.exempt and host_over:
        # S2：不依赖 part，part 字段留空。
        violations.append(
            Violation(
                host=family.host,
                rule=RULE_S2,
                host_lines=family.host_lines,
                oversized_parts=dict(over),
            )
        )
    if over:
        # S3：豁免不递归——即使宿主被豁免，超限 part 仍报出。
        violations.append(_make_part_violation(family, RULE_S3, over))
    return violations


def _make_part_violation(
    family: Family, rule: str, over: Dict[str, int]
) -> Violation:
    """构造一条以「超限 part」为触发标识的违规（S1 / S3 共用）。

    Args:
        family: 家族对象。
        rule: 判据编号（S1 或 S3）。
        over: 家族内非豁免超限 part 映射（非空）。

    Returns:
        以行数最大的超限 part 为标识的违规项。
    """
    worst = max(over.items(), key=lambda kv: kv[1])
    return Violation(
        host=family.host,
        rule=rule,
        host_lines=family.host_lines,
        part_lines=worst[1],
        part=worst[0],
        oversized_parts=dict(over),
    )


def scan(
    lib_dir: str, limit: int, errors: List[str]
) -> tuple[List[Family], List[Violation]]:
    """扫描 lib 目录，返回（家族列表, 违规列表）。

    Args:
        lib_dir: ``lib`` 目录绝对路径。
        limit: 行数阈值。
        errors: 错误累积列表。

    Returns:
        ``(families, violations)`` 二元组。
    """
    dart_files = collect_dart_files(lib_dir)
    families = build_families(lib_dir, dart_files, errors)
    violations: List[Violation] = []
    for family in families:
        violations.extend(evaluate_family(family, limit))
    return families, violations


# ---------------------------------------------------------------------------
# 基线（止血模式）
# ---------------------------------------------------------------------------


def load_baseline_keys(path: str) -> List[str]:
    """读取基线 JSON，返回其违规项的唯一定位键列表（按计数语义）。

    Args:
        path: 基线 JSON 路径。

    Returns:
        基线中每条违规的 ``host:rule:part`` 键（含重复，供计数比对）。

    Raises:
        OSError: 读取失败。
        ValueError: JSON 结构非法。
    """
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    violations = data.get("violations")
    if not isinstance(violations, list):
        raise ValueError("baseline JSON has no 'violations' list")
    keys: List[str] = []
    for item in violations:
        host = item.get("host", "")
        rule = item.get("rule", "")
        part = item.get("part", "")
        keys.append(f"{host}:{rule}:{part}")
    return keys


def filter_new(
    violations: List[Violation], baseline_keys: List[str]
) -> List[Violation]:
    """按计数语义过滤出「基线之外的新增项」。

    同一键可能在基线内出现多次；仅当当前计数超出基线计数时，超出部分
    计为新增（对齐 check_r019.py 的计数比对，避免同名重复互相顶掉）。

    Args:
        violations: 当前全量违规列表。
        baseline_keys: 基线违规键列表（含重复）。

    Returns:
        新增违规列表。
    """
    from collections import Counter

    base = Counter(baseline_keys)
    seen: Dict[str, int] = {}
    new: List[Violation] = []
    for v in violations:
        k = v.key()
        seen[k] = seen.get(k, 0) + 1
        if seen[k] > base.get(k, 0):
            new.append(v)
    return new


# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------


def violation_to_dict(v: Violation) -> Dict[str, object]:
    """把违规项序列化为 JSON 友好字典。

    Args:
        v: 违规项。

    Returns:
        含 host/rule/hostLines/partLines/part/oversizedParts 的字典。
    """
    return {
        "host": v.host,
        "rule": v.rule,
        "hostLines": v.host_lines,
        "partLines": v.part_lines,
        "part": v.part,
        "oversizedParts": dict(v.oversized_parts),
    }


def build_snapshot(
    dir_arg: str,
    limit: int,
    file_count: int,
    families: List[Family],
    violations: List[Violation],
) -> Dict[str, object]:
    """构造基线快照字典（结构参考 tool/r019_baseline.json）。

    Args:
        dir_arg: 扫描目录参数。
        limit: 行数阈值。
        file_count: 扫描到的 ``.dart`` 文件数。
        families: 家族列表。
        violations: 全量违规列表。

    Returns:
        可直接 json.dump 的快照字典（含 dir/limit/fileCount/familyCount/
        ruleCount/violations）。
    """
    return {
        "dir": dir_arg,
        "limit": limit,
        "fileCount": file_count,
        "familyCount": len(families),
        "ruleCount": RULE_COUNT,
        "violations": [violation_to_dict(v) for v in violations],
    }


def _print_header(
    dir_arg: str,
    limit: int,
    file_count: int,
    gen_skipped: int,
    family_count: int,
    by_rule: Dict[str, int],
    baseline: Optional[str],
    baseline_total: int,
) -> None:
    """打印报告表头与判据条数摘要。

    Args:
        dir_arg: 扫描目录参数。
        limit: 行数阈值。
        file_count: 扫描到的 ``.dart`` 文件数。
        gen_skipped: 被排除的生成文件数。
        family_count: 含 part 的家族数。
        by_rule: 各判据命中计数。
        baseline: 基线路径（None 表示全量模式）。
        baseline_total: 基线内违规总数。
    """
    mode = (
        f"止血模式（基线 {baseline}，存量 {baseline_total} 个豁免，只报新增）"
        if baseline
        else "全量模式"
    )
    print("=" * 68)
    print(
        f"拆分之形扫描：目录={dir_arg}  阈值={limit} 行  "
        f"dart 文件数={file_count}  含 part 家族={family_count}"
    )
    if gen_skipped:
        print(f"已排除生成文件 {gen_skipped} 个（*.g.dart，永不可清偿）")
    print(f"模式：{mode}")
    print("=" * 68)
    print()
    print(f"{C.BOLD}判据条数：{RULE_COUNT}{C.RESET}")
    for rid in RULE_IDS:
        print(f"  {rid}  {RULE_DESC[rid]}：{by_rule.get(rid, 0)} 个")
    print()


def _print_violation_list(violations: List[Violation], baseline: Optional[str]) -> None:
    """打印违规列表与超限 part 明细。

    Args:
        violations: 待展示的违规列表（全量或过滤后）。
        baseline: 基线路径（None 表示全量模式），用于选择标题措辞。
    """
    header = "新增违规" if baseline else "违规"
    print(f"{C.RED}{C.BOLD}{header}：{len(violations)} 个{C.RESET}")
    print()
    print(f"  {'判据':<4} {'宿主行数':>8}  {'part行数':>8}  宿主 / 触发part")
    print("  " + "-" * 64)
    for v in sorted(
        violations, key=lambda x: (x.rule, -x.host_lines, -x.part_lines)
    ):
        part_txt = v.part if v.part else "-"
        print(
            f"  {v.rule:<4} {v.host_lines:>8}  {v.part_lines:>8}  "
            f"{v.host} / {part_txt}"
        )
    print()

    # 超限 part 明细（便于定位拆分产物本身）
    seen_parts = set()
    detail: List[tuple[str, str, int]] = []
    for v in violations:
        for p, n in v.oversized_parts.items():
            if (v.host, p) in seen_parts:
                continue
            seen_parts.add((v.host, p))
            detail.append((v.host, p, n))
    if detail:
        print(f"{C.BOLD}超限 part 明细：{C.RESET}")
        for host, p, n in detail:
            print(f"  {n:>5} 行  {p}  (宿主 {host})")
        print()


def print_report(
    dir_arg: str,
    limit: int,
    file_count: int,
    gen_skipped: int,
    families: List[Family],
    violations: List[Violation],
    shown: List[Violation],
    baseline: Optional[str],
    baseline_total: int,
) -> None:
    """打印终端报告。

    Args:
        dir_arg: 扫描目录参数。
        limit: 行数阈值。
        file_count: 扫描到的 ``.dart`` 文件数。
        gen_skipped: 被排除的生成文件数。
        families: 家族列表。
        violations: 全量违规列表。
        shown: 待展示的违规列表（全量或过滤后）。
        baseline: 基线路径（None 表示全量模式）。
        baseline_total: 基线内违规总数。
    """
    by_rule: Dict[str, int] = {rid: 0 for rid in RULE_IDS}
    for v in violations:
        by_rule[v.rule] = by_rule.get(v.rule, 0) + 1

    _print_header(
        dir_arg, limit, file_count, gen_skipped, len(families), by_rule,
        baseline, baseline_total,
    )

    if not shown:
        if baseline:
            print(
                f"{C.GREEN}无**新增**拆分之形违规 ✓{C.RESET}"
                f"（全量 {len(violations)} 个均已在基线内豁免）"
            )
        else:
            print(f"{C.GREEN}无拆分之形违规 ✓{C.RESET}")
        return

    _print_violation_list(shown, baseline)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def _rule_count_guard(expect: Optional[int]) -> Optional[str]:
    """校验判据条数守卫。

    Args:
        expect: 期望的判据条数（None 表示不检查）。

    Returns:
        守卫失败时返回错误消息，否则 None。
    """
    if expect is None:
        return None
    if RULE_COUNT == expect:
        return None
    return f"RULE COUNT GUARD FAIL: expected {expect}, got {RULE_COUNT}"


def _build_arg_parser() -> argparse.ArgumentParser:
    """构造命令行解析器（含全部选项与帮助文本）。

    Returns:
        配置好的 ``argparse.ArgumentParser``。
    """
    ap = argparse.ArgumentParser(
        description="拆分之形检测器（R-019 文件 ≤300 行 / 禁止伪拆分，只测不拆）"
    )
    ap.add_argument("--dir", default="lib", help="扫描目录（默认 lib）")
    ap.add_argument(
        "--limit", type=int, default=DEFAULT_FILE_LIMIT, help="文件行数阈值（默认 300）"
    )
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
        help="校验判据条数（应为 3）；不符则 exit 1（防判据被静默删减）",
    )
    return ap


def resolve_lib_dir(dir_arg: str) -> str:
    """把 ``--dir`` 参数解析为绝对 ``lib`` 目录路径。

    相对路径优先按「项目根（脚本上一级）相对」解析；若该目录不存在，
    再尝试「当前工作目录相对」解析。两者都不存在时仍返回首选路径，
    由调用方做 fail-closed 判定。

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


def count_generated_files(lib_dir: str) -> int:
    """统计目录下被排除的生成文件（``*.g.dart``）数量。

    Args:
        lib_dir: ``lib`` 目录绝对路径。

    Returns:
        生成文件数量。
    """
    gen = 0
    for root, dirs, fnames in os.walk(lib_dir):
        dirs[:] = [d for d in dirs if d not in (".git", "build", ".dart_tool")]
        for fn in fnames:
            if fn.endswith(GENERATED_SUFFIX):
                gen += 1
    return gen


def _resolve_baseline(
    baseline_arg: str, violations: List[Violation]
) -> tuple[Optional[List[Violation]], int, Optional[str]]:
    """按基线过滤违规，返回（展示列表, 基线总数, 错误消息）。

    Args:
        baseline_arg: 基线路径（空串表示全量模式）。
        violations: 当前全量违规列表。

    Returns:
        ``(shown, baseline_total, error)`` 三元组；``error`` 非空表示
        基线读取失败，调用方应 ``exit 2``。
    """
    if not baseline_arg:
        return violations, 0, None
    try:
        keys = load_baseline_keys(baseline_arg)
    except (OSError, ValueError) as exc:
        return None, 0, f"无法读取基线 {baseline_arg!r}: {exc}"
    return filter_new(violations, keys), len(keys), None


def _write_snapshot(
    json_path: str,
    dir_arg: str,
    limit: int,
    file_count: int,
    families: List[Family],
    violations: List[Violation],
) -> Optional[str]:
    """把当前扫描结果以**全量**写入 JSON 基线快照。

    Args:
        json_path: 输出路径。
        dir_arg: 扫描目录参数。
        limit: 行数阈值。
        file_count: 扫描到的 ``.dart`` 文件数。
        families: 家族列表。
        violations: 全量违规列表。

    Returns:
        成功返回 None，失败返回错误消息。
    """
    snapshot = build_snapshot(dir_arg, limit, file_count, families, violations)
    try:
        parent = os.path.dirname(os.path.abspath(json_path))
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(json_path, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(snapshot, fh, ensure_ascii=False, indent=2)
    except OSError as exc:
        return f"无法写入 {json_path!r}: {exc}"
    return None


@dataclass
class ScanOutcome:
    """扫描阶段结果（供 main 与报告阶段传递）。

    Attributes:
        lib_dir: 解析后的 lib 目录绝对路径。
        file_count: 扫描到的 ``.dart`` 文件数。
        gen_skipped: 被排除的生成文件数。
        families: 家族列表。
        violations: 全量违规列表。
    """

    lib_dir: str
    file_count: int
    gen_skipped: int
    families: List[Family]
    violations: List[Violation]


def _validate_env(dir_arg: str) -> tuple[Optional[str], List[str], int, int]:
    """fail-closed 环境校验：目录存在 + 非空（含 dart 文件）。

    Args:
        dir_arg: ``--dir`` 参数。

    Returns:
        ``(lib_dir, dart_files, gen_skipped, exit_code)``；校验通过时
        ``exit_code`` 为 0；否则 ``lib_dir`` 为 None 且 ``exit_code`` 为 2。
    """
    lib_dir = resolve_lib_dir(dir_arg)

    # fail-closed：lib 不存在 / 非目录 → exit 2，绝不返回 0。
    if not os.path.isdir(lib_dir):
        print(
            f"{C.RED}ERROR{C.RESET}: 扫描目录不存在或不是目录：{lib_dir}",
            file=sys.stderr,
        )
        return None, [], 0, 2

    all_dart = collect_dart_files(lib_dir)

    # fail-closed：空目录 / 扫到 0 个 .dart → exit 2，绝不返回 0。
    if not all_dart:
        print(
            f"{C.RED}ERROR{C.RESET}: 扫描到 0 个 .dart 文件：{lib_dir}"
            "（空的检查等于没检查，按环境错误处理）",
            file=sys.stderr,
        )
        return None, [], 0, 2

    return lib_dir, all_dart, count_generated_files(lib_dir), 0


def _run_scan_phase(dir_arg: str, limit: int) -> tuple[Optional[ScanOutcome], int]:
    """执行环境校验与扫描阶段（fail-closed）。

    依次完成：环境校验 → 扫描 → 读取错误校验。任一步失败均返回错误退出码。

    Args:
        dir_arg: ``--dir`` 参数。
        limit: 行数阈值。

    Returns:
        ``(outcome, exit_code)``；成功时 ``exit_code`` 为 0 且 ``outcome``
        非 None；失败时 ``outcome`` 为 None 且 ``exit_code`` 为 2。
    """
    lib_dir, all_dart, gen_skipped, code = _validate_env(dir_arg)
    if lib_dir is None:
        return None, code

    errors: List[str] = []
    families, violations = scan(lib_dir, limit, errors)

    # 读取失败不得静默跳过：打印到 stderr，并计入错误使退出码升级。
    if errors:
        for msg in errors:
            print(f"{C.YELLOW}ERROR{C.RESET}: {msg}", file=sys.stderr)
        print(
            f"{C.RED}ERROR{C.RESET}: {len(errors)} 个文件读取/解析失败，"
            "按 fail-closed 原则视为环境错误。",
            file=sys.stderr,
        )
        return None, 2

    return (
        ScanOutcome(
            lib_dir=lib_dir,
            file_count=len(all_dart),
            gen_skipped=gen_skipped,
            families=families,
            violations=violations,
        ),
        0,
    )


def _emit_report_and_snapshot(
    args: argparse.Namespace,
    outcome: ScanOutcome,
    shown: List[Violation],
    baseline_total: int,
) -> int:
    """打印报告并在需要时落盘全量快照，返回退出码。

    Args:
        args: 已解析的命令行参数。
        outcome: 扫描阶段结果。
        shown: 待展示的违规列表（全量或过滤后）。
        baseline_total: 基线内违规总数。

    Returns:
        进程退出码（0 通过 / 1 违规 / 2 落盘失败）。
    """
    print_report(
        dir_arg=args.dir,
        limit=args.limit,
        file_count=outcome.file_count,
        gen_skipped=outcome.gen_skipped,
        families=outcome.families,
        violations=outcome.violations,
        shown=shown,
        baseline=args.baseline or None,
        baseline_total=baseline_total,
    )

    # 落盘**全量**（绝不落过滤后的 shown），锁死 LF 换行。
    if args.json:
        write_err = _write_snapshot(
            args.json,
            args.dir,
            args.limit,
            outcome.file_count,
            outcome.families,
            outcome.violations,
        )
        if write_err:
            print(f"{C.RED}ERROR{C.RESET}: {write_err}", file=sys.stderr)
            return 2
        print(f"\n已落盘：{args.json}")
        print(
            f"  （--json 落的是全量结果 {len(outcome.violations)} 条，"
            f"非基线过滤后的 {len(shown)} 条）"
        )

    # 退出码：止血模式下只卡新增；全量模式有任何违规即 1。
    return 1 if shown else 0


def main(argv: List[str]) -> int:
    """脚本入口。

    Args:
        argv: 命令行参数（不含程序名）。

    Returns:
        进程退出码（0 通过 / 1 违规或守卫失败 / 2 环境错误）。
    """
    args = _build_arg_parser().parse_args(argv)

    # 陷阱防护：--json 与 --baseline 同用会把基线写空（存量债务一笔勾销）。
    if args.json and args.baseline:
        print(
            f"{C.RED}ERROR{C.RESET}: --json 与 --baseline 不可同时使用："
            "--json 一律落全量，若带 --baseline 只会写入「新增项」，"
            "会把存量债务一笔勾销（基线自清空型假绿）。",
            file=sys.stderr,
        )
        return 2

    outcome, code = _run_scan_phase(args.dir, args.limit)
    if outcome is None:
        return code

    # 判据条数守卫
    guard_msg = _rule_count_guard(args.expect_rule_count)
    if guard_msg:
        print(f"{C.RED}{C.BOLD}{guard_msg}{C.RESET}")
        return 1

    # 基线过滤（只影响展示与退出码，不影响落盘全量）
    shown, baseline_total, base_err = _resolve_baseline(
        args.baseline, outcome.violations
    )
    if base_err:
        print(f"{C.RED}ERROR{C.RESET}: {base_err}", file=sys.stderr)
        return 2
    assert shown is not None  # base_err 为 None 时 shown 必非 None

    return _emit_report_and_snapshot(args, outcome, shown, baseline_total)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
