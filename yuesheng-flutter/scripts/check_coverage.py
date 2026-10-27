#!/usr/bin/env python3
"""
Coverage threshold enforcer (T1 overall + T2 per-file hard gates).

Usage:
    python3 scripts/check_coverage.py \
        --lcov coverage/lcov.info \
        --t1-target 65.0 --t1-margin 2.0 \
        --t2 "lib/services/training_evaluator.dart:85" \
        --t2 "lib/services/evaluation_service.dart:85" \
        --t2 "lib/data/repositories/diagnosis_repository.dart:85" \
        --t2 "lib/services/chat_service.dart:85" \
        --t2 "lib/services/focus_resolver.dart:85" \
        [--expect-t2-count 5] \
        [--warn-event-file coverage/warn-event.json]

Exit code:
    0  -> T1 is PASS or WARN (within tolerance) AND all T2 pass.
    1  -> T1 FAIL (below target - margin) OR any T2 fails / missing
          OR --expect-t2-count is not met (silent-degradation guard).
    2  -> environment error (lcov missing / 0 records / bad --t2 syntax).

Silent-degradation guards (2026-09-12, QA 审计结论 §T2 加固):
    The CI step (.github/workflows/flutter_ci.yaml) pins exactly 5 --t2 rules.
    If a future edit drops one, the remaining rules still all PASS and the job
    would go green while guarding fewer files -- a fail-open hole. Passing
    --expect-t2-count 5 turns that into a hard FAIL. A negative --t2 min_pct
    is rejected for the same reason (r >= -1.0 is always true -> rubber stamp).

Structured event (X-029-T1WARN):
    When --warn-event-file is given, a JSON event is written for CI tracking:
      {"event":"pass|warn|fail","t1_rate":67.03,"t1_target":65.0,"t1_floor":63.0,
       "t1_verdict":"PASS|WARN|FAIL","t2_pass_count":5,"t2_total":5,"timestamp": "..."}
    Cross-run WARN counter is maintained by the CI step (gh CLI + Issue tracker),
    not by this script — keeps Python side single-responsibility (parse + report).
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import sys
from dataclasses import dataclass
from typing import Dict, List, Optional, Set, Tuple


class C:
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    RED = "\033[31m"
    BOLD = "\033[1m"
    RESET = "\033[0m"


def _norm(p: str) -> str:
    return p.replace("\\", "/").lstrip("./")


@dataclass
class T2Rule:
    sf_cli: str
    min_pct: float


@dataclass
class SfRecord:
    lf: int
    lh: int


def parse_lcov(path: str) -> Dict[str, SfRecord]:
    records: Dict[str, SfRecord] = {}
    cur_sf: Optional[str] = None
    cur_lf: Optional[int] = None
    cur_lh: Optional[int] = None
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if line.startswith("SF:"):
                cur_sf = _norm(line[3:])
                cur_lf = None
                cur_lh = None
            elif line.startswith("LF:") and cur_sf is not None:
                try:
                    cur_lf = int(line[3:])
                except ValueError:
                    cur_lf = None
            elif line.startswith("LH:") and cur_sf is not None:
                try:
                    cur_lh = int(line[3:])
                except ValueError:
                    cur_lh = None
            elif line.startswith("end_of_record"):
                if cur_sf is not None and cur_lf is not None and cur_lh is not None:
                    records[cur_sf] = SfRecord(lf=cur_lf, lh=cur_lh)
                cur_sf = None
                cur_lf = None
                cur_lh = None
    return records


def rate_pct(lf: int, lh: int) -> float:
    if lf <= 0:
        return 0.0
    return 100.0 * lh / lf


def _parse_t2_rules(raw_list: List[str]) -> Optional[List[T2Rule]]:
    """Parse --t2 "path:pct" entries. Returns None on malformed input.

    Negative min_pct is rejected: `rate >= -1.0` is trivially true, so such a
    rule can never FAIL -- it would silently rubber-stamp the file.
    """
    rules: List[T2Rule] = []
    for raw in raw_list:
        if ":" not in raw:
            print(f"{C.RED}ERROR{C.RESET}: bad --t2 value (missing colon): {raw!r}", file=sys.stderr)
            return None
        path_part, pct_part = raw.rsplit(":", 1)
        try:
            pct = float(pct_part)
        except ValueError:
            print(f"{C.RED}ERROR{C.RESET}: bad --t2 pct: {raw!r}", file=sys.stderr)
            return None
        if pct < 0:
            print(f"{C.RED}ERROR{C.RESET}: --t2 min_pct must be >= 0 (got {pct}): {raw!r}",
                  file=sys.stderr)
            return None
        rules.append(T2Rule(sf_cli=_norm(path_part), min_pct=pct))
    return rules


def _count_guard(expect: Optional[int], actual: int) -> Optional[str]:
    """Return an error message when the T2 rule count does not match, else None."""
    if expect is None:
        return None
    if actual == expect:
        return None
    return (f"T2 rule count mismatch: expected {expect}, got {actual} "
            f"-- a --t2 rule was dropped or added; the gate would guard fewer files")


# ─────────────────────────────────────────────────────────────────────────────
# 逻辑面可达性读数（T-20261024-13 · C-4）
#
# ★ 定性：**读数，不是判据** —— 不设条数基线、不判红、不新增门禁道数。
#   本段挂在门禁 6（覆盖率）内执行，因为它回答的是同一个问题：
#   「哪些代码从测试出发根本走不到」。
#
# ★ 口径（C-1 报告 §1.1 两步法 + §3.3 修正）：
#   ① **符号级**，不按文件名同名（同名口径会把「19 个变体测试」记成「1 个文件没测试」）；
#   ② 公开符号 = 顶层 class/enum/mixin/extension/typedef + 顶层函数 + 顶层 final/const；
#   ③ 可达 = 测试文件 import 的 lib 文件，沿 lib 内部 import 边做**传递闭包**。
#
# ★★ 效力边界（不许夸大，读之前先读这三条）：
#   1. **A 零可达是上界不是下界**：import 可达 ≠ 被执行、更 ≠ 被断言。
#      所以 A 为空**不能**读成「全覆盖」。
#   2. **B 是软读数**：符号在 test/ 零字面命中，但仍可能被消费侧间接断言
#      （C-1 实测 7/16 条属这一类）⇒ B 里每一条都必须手工追消费链才算缺口。
#   3. **空扫不是通过**：分母为 0 或 test 文件为 0 ⇒ 判环境错误（rc=2），
#      与「lcov 缺失 / 解析 0 记录」同族纪律。否则判据坏掉时会静默全绿。
# ─────────────────────────────────────────────────────────────────────────────

LOGIC_DIRS: Tuple[str, ...] = (
    "lib/services",
    "lib/providers",
    "lib/utils",
    "lib/data",
    "lib/config",
)

# 生成物 / 非手写文件：不作为读数对象（它们的覆盖由生成源负责）
_GENERATED_SUFFIXES: Tuple[str, ...] = (".g.dart", ".freezed.dart", ".gr.dart")

_IMPORT_RE = re.compile(
    r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""", re.MULTILINE)
# ★ part / part of 必须一起算边，否则分片文件会被整片误判成「零可达」。
#   实测（2026-10-27）：不加这两条时 A 读数 51 个，而 lib/ 下 `^part of` 文件恰好
#   也是 51 个 ⇒ 读数 100% 是 part 假象，是坏尺子而不是缺口。
_PART_RE = re.compile(r"""^\s*part\s+['"]([^'"]+)['"]""", re.MULTILINE)
_PART_OF_RE = re.compile(r"""^\s*part\s+of\s+['"]([^'"]+)['"]""", re.MULTILINE)
_DECL_RE = re.compile(
    r"^(?:abstract\s+|sealed\s+|base\s+|final\s+)*"
    r"(?:class|enum|mixin|extension|typedef)\s+([A-Za-z_]\w*)", re.MULTILINE)
_TOPFN_RE = re.compile(
    r"^(?:Future<[^\n]*?>|void|bool|int|double|num|String|"
    r"List<[^\n]*?>|Map<[^\n]*?>|Set<[^\n]*?>|[A-Z]\w*\??)"
    r"\s+([a-z_]\w*)\s*[<(]", re.MULTILINE)
_CONST_RE = re.compile(
    r"^(?:final|const)\s+[^=\n;]+?\s+([A-Za-z_]\w*)\s*=", re.MULTILINE)
_IDENT_RE = re.compile(r"[A-Za-z_]\w*")


def _walk_dart(root: str) -> List[str]:
    out: List[str] = []
    for base, _dirs, files in os.walk(root):
        for name in files:
            if name.endswith(".dart"):
                out.append(os.path.join(base, name).replace("\\", "/"))
    return sorted(out)


def _read(path: str) -> str:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def _resolve_spec(from_file: str, spec: str, lib_root: str) -> Optional[str]:
    """把 import 字符串解析成绝对路径（统一正斜杠）。非本仓目标返回 None。"""
    if spec.startswith("dart:") or spec.startswith("package:test") \
            or spec.startswith("package:flutter"):
        return None
    if spec.startswith("package:"):
        if not spec.startswith("package:writingcoach/"):
            return None
        rel = spec[len("package:writingcoach/"):]
        return os.path.normpath(os.path.join(lib_root, rel)).replace("\\", "/")
    target = os.path.normpath(os.path.join(os.path.dirname(from_file), spec))
    return target.replace("\\", "/")


def _public_symbols(src: str) -> Set[str]:
    """提取顶层公开符号名（近似：正则，保守取，不做完整语法解析）。"""
    syms: Set[str] = set()
    for rx in (_DECL_RE, _TOPFN_RE, _CONST_RE):
        for m in rx.finditer(src):
            name = m.group(1)
            # 私有符号（_foo）与单一字母噪声不进读数
            if len(name) > 1 and not name.startswith("_"):
                syms.add(name)
    return syms


def logic_face_report(repo_root: str = ".") -> Dict[str, object]:
    """算逻辑面可达性读数。返回结构见模块注释；空输入不在这里判错，由调用方判。"""
    root = os.path.abspath(repo_root)
    lib_root = os.path.join(root, "lib")
    test_root = os.path.join(root, "test")

    logic_files: List[str] = []
    for sub in LOGIC_DIRS:
        d = os.path.join(root, sub)
        if not os.path.isdir(d):
            continue
        for p in _walk_dart(d):
            if not p.endswith(_GENERATED_SUFFIXES):
                logic_files.append(p)

    test_files = _walk_dart(test_root) if os.path.isdir(test_root) else []

    # test 全树标识符集合（一次扫描，供符号级命中判定）
    test_idents: Set[str] = set()
    test_direct: Set[str] = set()
    for tf in test_files:
        src = _read(tf)
        test_idents |= set(_IDENT_RE.findall(src))
        for spec in _IMPORT_RE.findall(src):
            resolved = _resolve_spec(tf, spec, lib_root)
            if resolved:
                test_direct.add(resolved)

    # lib 内部 import 图（只保留 lib/ 内的边，用于传递闭包）
    # 边 = import/export + part + part of（分片的可达性完全由属主决定，双向都要连）
    graph: Dict[str, Set[str]] = {}
    for lf in _walk_dart(lib_root) if os.path.isdir(lib_root) else []:
        src = _read(lf)
        edges: Set[str] = set()
        for spec in _IMPORT_RE.findall(src) + _PART_RE.findall(src) \
                + _PART_OF_RE.findall(src):
            resolved = _resolve_spec(lf, spec, lib_root)
            if resolved and resolved.startswith(lib_root.replace("\\", "/")):
                edges.add(resolved)
        graph[lf] = edges

    # 传递闭包：从 test 直接可达的 lib 文件出发
    reached: Set[str] = set(test_direct)
    frontier = list(test_direct)
    while frontier:
        cur = frontier.pop()
        for nxt in graph.get(cur, ()):  # noqa: E501 - 显式空集合，避免默认分支被误读
            if nxt not in reached:
                reached.add(nxt)
                frontier.append(nxt)

    zero_reach: List[str] = []
    reach_no_symbol: List[str] = []
    for lf in logic_files:
        if lf not in reached:
            zero_reach.append(lf)
            continue
        syms = _public_symbols(_read(lf))
        if syms and not (syms & test_idents):
            reach_no_symbol.append(lf)

    def rel(p: str) -> str:
        return os.path.relpath(p, root).replace("\\", "/")

    return {
        "logic_total": len(logic_files),
        "test_files": len(test_files),
        "reached": len([f for f in logic_files if f in reached]),
        "zero_reach": sorted(rel(p) for p in zero_reach),
        "reach_no_symbol": sorted(rel(p) for p in reach_no_symbol),
    }


def print_logic_face(rep: Dict[str, object]) -> None:
    total = rep["logic_total"]
    print(f"{C.BOLD}[逻辑面可达性读数]{C.RESET} 分母 {total} 个文件 "
          f"(lib/{{services,providers,utils,data,config}}，排除生成物) · "
          f"test 文件 {rep['test_files']} 个")
    zero = rep["zero_reach"]
    soft = rep["reach_no_symbol"]
    print(f"  A 零可达（不在 test 的 import 传递闭包内）：{len(zero)} 个")
    for p in zero:
        print(f"    - {p}")
    print(f"  B 可达但公开符号在 test/ 零字面命中：{len(soft)} 个")
    for p in soft:
        print(f"    - {p}")
    print("  口径：A 是**上界**（import 可达 ≠ 被执行/被断言）；B 是**软读数**"
          "（消费侧间接断言不计入，每条须手工追链才算缺口）")
    print("  纪律：不设条数基线、不判红（T-20261024-13 C-4）；"
          "空扫（分母或 test 文件为 0）⇒ 环境错误")



def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lcov", default="coverage/lcov.info")
    ap.add_argument("--t1-target", type=float, default=65.0)
    ap.add_argument("--t1-margin", type=float, default=2.0)
    ap.add_argument("--t2", action="append", default=[])
    ap.add_argument("--expect-t2-count", type=int, default=None,
                    help="hard-fail when the number of --t2 rules differs (anti silent-degradation)")
    ap.add_argument("--warn-event-file", default=None,
                    help="optional path to write a JSON event for CI WARN tracker")
    ap.add_argument("--repo-root",
                    default=os.path.normpath(
                        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")),
                    help="仓库根（逻辑面读数用；默认=脚本上一级）")
    ap.add_argument("--no-logic-face", action="store_true",
                    help="跳过硬编码的逻辑面可达性读数（C-4）；默认打印")
    args = ap.parse_args(argv)

    # ── 逻辑面可达性读数（T-20261024-13 C-4）────────────────────────────
    # 读数、不判红、不设基线；但**空扫必须判错** —— 否则判据坏掉时静默全绿。
    if not args.no_logic_face:
        try:
            rep = logic_face_report(args.repo_root)
        except OSError as exc:
            print(f"{C.RED}ERROR{C.RESET}: logic-face scan failed: {exc}", file=sys.stderr)
            return 2
        if rep["logic_total"] == 0 or rep["test_files"] == 0:
            print(f"{C.RED}ERROR{C.RESET}: logic-face 空扫（分母 {rep['logic_total']} 个逻辑层文件 / "
                  f"test {rep['test_files']} 个）—— 空扫不是通过：判据可能已坏", file=sys.stderr)
            return 2
        print_logic_face(rep)
        print()

    t1_target = args.t1_target
    t1_floor = max(0.0, t1_target - args.t1_margin)

    t2_rules = _parse_t2_rules(args.t2)
    if t2_rules is None:
        return 2

    if not os.path.isfile(args.lcov):
        print(f"{C.RED}ERROR{C.RESET}: lcov file not found: {args.lcov}", file=sys.stderr)
        return 2

    records = parse_lcov(args.lcov)
    if not records:
        print(f"{C.RED}ERROR{C.RESET}: lcov file parsed 0 records: {args.lcov}", file=sys.stderr)
        return 2

    total_lf = sum(r.lf for r in records.values())
    total_lh = sum(r.lh for r in records.values())
    t1_rate = rate_pct(total_lf, total_lh)

    if t1_rate >= t1_target:
        t1_verdict, t1_color = "PASS", C.GREEN
    elif t1_rate >= t1_floor:
        t1_verdict, t1_color = "WARN", C.YELLOW
    else:
        t1_verdict, t1_color = "FAIL", C.RED

    @dataclass
    class T2Result:
        rule: T2Rule
        status: str
        lf: int
        lh: int
        rate_pct: float
        detail: str = ""

    t2_results = []
    for rule in t2_rules:
        rec = records.get(rule.sf_cli)
        if rec is None:
            fallbacks = [k for k in records if k.endswith("/" + rule.sf_cli.split("/")[-1])]
            if len(fallbacks) == 1:
                rec = records[fallbacks[0]]
        if rec is None:
            t2_results.append(T2Result(rule=rule, status="MISSING", lf=0, lh=0, rate_pct=0.0,
                                       detail="file not found in lcov SF: records"))
            continue
        r = rate_pct(rec.lf, rec.lh)
        status = "PASS" if r >= rule.min_pct else "FAIL"
        t2_results.append(T2Result(rule=rule, status=status, lf=rec.lf, lh=rec.lh, rate_pct=r))

    any_t2_bad = any(r.status != "PASS" for r in t2_results)
    t2_pass_cnt = sum(1 for r in t2_results if r.status == "PASS")
    t2_total = len(t2_results)

    count_err = _count_guard(args.expect_t2_count, t2_total)

    print()
    print(f"{C.BOLD}===== Coverage Threshold Report ====={C.RESET}")
    print(f"Lcov file       : {args.lcov}")
    print(f"SF records      : {len(records)}")
    print(f"Instrumented    : LF={total_lf}  LH={total_lh}")
    print()
    print(f"{C.BOLD}T1  Overall line coverage (soft gate, target >= {t1_target:.1f}%, warn-floor >= {t1_floor:.1f}%){C.RESET}")
    bar_w = 40
    filled = int(round(bar_w * min(max(t1_rate, 0), 100) / 100.0))
    bar = ("█" * filled) + ("░" * (bar_w - filled))
    print(f"  [{t1_color}{bar}{C.RESET}]  {t1_rate:6.2f}%   [{t1_color}{t1_verdict}{C.RESET}]")
    print()
    if t2_rules:
        print(f"{C.BOLD}T2  Core file hard gates ({t2_pass_cnt}/{t2_total} PASS){C.RESET}")
        col1 = max(len("FILE"), max((len(r.rule.sf_cli) for r in t2_results), default=4))
        col_status = 7
        print(f"  {'STATUS':<{col_status}}  {'FILE':<{col1}}  {'MIN%':>5}  {'RATE%':>6}  {'LH/LF':>14}")
        print("  " + "-" * (col_status + col1 + 5 + 6 + 14 + 6))
        for r in t2_results:
            color = C.GREEN if r.status == "PASS" else C.RED
            sf_short = r.rule.sf_cli
            if r.status == "MISSING":
                print(f"  {color}{r.status:<{col_status}}{C.RESET}  {sf_short:<{col1}}  {r.rule.min_pct:>5.1f}  {'N/A':>6}  {r.detail}")
            else:
                print(f"  {color}{r.status:<{col_status}}{C.RESET}  {sf_short:<{col1}}  {r.rule.min_pct:>5.1f}  {r.rate_pct:>6.2f}  {r.lh:>5}/{r.lf:<5}")
        print()

    t1_fails_job = (t1_verdict == "FAIL")
    job_fails = t1_fails_job or any_t2_bad or bool(count_err)

    # X-029-T1WARN: emit structured JSON event for CI WARN tracker.
    # Cross-run counter is maintained by the CI step (gh CLI + Issue), not here.
    if args.warn_event_file:
        if job_fails:
            event_type = "fail"
        elif t1_verdict == "WARN":
            event_type = "warn"
        else:
            event_type = "pass"
        event = {
            "event": event_type,
            "t1_rate": round(t1_rate, 2),
            "t1_target": t1_target,
            "t1_floor": t1_floor,
            "t1_verdict": t1_verdict,
            "t2_pass_count": t2_pass_cnt,
            "t2_total": t2_total,
            "expected_t2_count": args.expect_t2_count,
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        }
        try:
            parent = os.path.dirname(args.warn_event_file)
            if parent:
                os.makedirs(parent, exist_ok=True)
            with open(args.warn_event_file, "w", encoding="utf-8") as fh:
                json.dump(event, fh, ensure_ascii=False, indent=2)
        except OSError as exc:
            print(f"{C.YELLOW}WARN{C.RESET}: failed to write warn-event file "
                  f"{args.warn_event_file!r}: {exc}", file=sys.stderr)

    if t1_verdict == "WARN" and not any_t2_bad and not count_err:
        print(f"{C.YELLOW}{C.BOLD}T1 SOFT WARNING:{C.RESET} "
              f"overall {t1_rate:.2f}% is below target {t1_target:.1f}% but within +/-{args.t1_margin:.1f}% tolerance "
              f"(floor >= {t1_floor:.1f}%). Not blocking, but please investigate coverage drift.")
        print()

    if job_fails:
        print(f"{C.RED}{C.BOLD}THRESHOLD FAIL{C.RESET}")
        if t1_fails_job:
            print(f"  - T1 FAIL: {t1_rate:.2f}% < hard floor {t1_floor:.1f}% "
                  f"(target {t1_target:.1f}%, tolerance +/-{args.t1_margin:.1f}%)")
        for r in t2_results:
            if r.status == "FAIL":
                print(f"  - T2 FAIL: {r.rule.sf_cli}  actual {r.rate_pct:.2f}% < min {r.rule.min_pct:.1f}%")
            elif r.status == "MISSING":
                print(f"  - T2 MISSING: {r.rule.sf_cli} -- {r.detail}")
        if count_err:
            print(f"  - T2 COUNT GUARD FAIL: {count_err}")
        print()
        return 1

    print(f"{C.GREEN}{C.BOLD}ALL THRESHOLDS PASS{C.RESET}  "
          f"(T1 {t1_rate:.2f}% >= {t1_target:.1f}%; T2 {t2_pass_cnt}/{t2_total})")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
