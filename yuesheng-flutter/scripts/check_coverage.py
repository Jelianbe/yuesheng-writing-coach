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
        --t2 "lib/services/chat_service.dart:75" \
        --t2 "lib/services/focus_resolver.dart:40"

Exit code:
    0  -> T1 is PASS or WARN (within tolerance) AND all T2 pass.
    1  -> T1 FAIL (below target - margin) OR any T2 fails / missing.
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from typing import Dict, List, Optional


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


def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lcov", default="coverage/lcov.info")
    ap.add_argument("--t1-target", type=float, default=65.0)
    ap.add_argument("--t1-margin", type=float, default=2.0)
    ap.add_argument("--t2", action="append", default=[])
    args = ap.parse_args(argv)

    t1_target = args.t1_target
    t1_floor = max(0.0, t1_target - args.t1_margin)

    t2_rules = []
    for raw in args.t2:
        if ":" not in raw:
            print(f"{C.RED}ERROR{C.RESET}: bad --t2 value (missing colon): {raw!r}", file=sys.stderr)
            return 2
        path_part, pct_part = raw.rsplit(":", 1)
        try:
            pct = float(pct_part)
        except ValueError:
            print(f"{C.RED}ERROR{C.RESET}: bad --t2 pct: {raw!r}", file=sys.stderr)
            return 2
        t2_rules.append(T2Rule(sf_cli=_norm(path_part), min_pct=pct))

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
    if t1_verdict == "WARN" and not any_t2_bad:
        print(f"{C.YELLOW}{C.BOLD}T1 SOFT WARNING:{C.RESET} "
              f"overall {t1_rate:.2f}% is below target {t1_target:.1f}% but within +/-{args.t1_margin:.1f}% tolerance "
              f"(floor >= {t1_floor:.1f}%). Not blocking, but please investigate coverage drift.")
        print()

    if t1_fails_job or any_t2_bad:
        print(f"{C.RED}{C.BOLD}THRESHOLD FAIL{C.RESET}")
        if t1_fails_job:
            print(f"  - T1 FAIL: {t1_rate:.2f}% < hard floor {t1_floor:.1f}% "
                  f"(target {t1_target:.1f}%, tolerance +/-{args.t1_margin:.1f}%)")
        for r in t2_results:
            if r.status == "FAIL":
                print(f"  - T2 FAIL: {r.rule.sf_cli}  actual {r.rate_pct:.2f}% < min {r.rule.min_pct:.1f}%")
            elif r.status == "MISSING":
                print(f"  - T2 MISSING: {r.rule.sf_cli} -- {r.detail}")
        print()
        return 1

    print(f"{C.GREEN}{C.BOLD}ALL THRESHOLDS PASS{C.RESET}  "
          f"(T1 {t1_rate:.2f}% >= {t1_target:.1f}%; T2 {t2_pass_cnt}/{t2_total})")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))