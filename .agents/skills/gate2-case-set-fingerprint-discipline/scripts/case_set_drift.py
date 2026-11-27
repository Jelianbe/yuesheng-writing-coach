#!/usr/bin/env python3
"""Case-set drift forensics for gate 2 (P2 suite fingerprint).

Read-only. Reproduces the exact fingerprint input of
yuesheng-flutter/scripts/lib_gate_evidence.sh::_ev_suite_fingerprint so the
name-level evidence matches what the gate actually hashes.

Usage:
  compare two gate json reports:
    python case_set_drift.py --old <a.json> --new <b.json>
  check one report against the pinned baseline:
    python case_set_drift.py --report <x.json> --baseline tool/test_count_baseline.json

Exit: 0 = no drift / identical set; 1 = drift or usage error.
stdout is ASCII-only (Windows cp936 consoles mangle CJK); readable names go to
the UTF-8 file printed as DETAIL=.
"""
import argparse
import difflib
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import datetime

TEST_START = re.compile(r'"type":"testStart"')


def names_from_report(path):
    """Full test names, deduped + sorted -- exactly what the gate hashes.

    MUST decode each testStart line as JSON, same as
    `scripts/lib_gate_evidence.sh::_ev_suite_fingerprint`. Do NOT go back to
    a name-capturing regex: `"name":"([^"]*)"` stops at the first quote, so
    any test name containing an escaped quote (`\\"`) gets truncated. This
    repo has such names, and the truncated extraction silently disagrees
    with the gate on both size and fingerprint => every comparison reports
    a fake drift and invites a wrong re-pin.
    """
    if not os.path.isfile(path):
        fail("report not found: %s" % path)
    out = set()
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if not TEST_START.search(line):
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                # A truncated line must not abort the whole report; the gate
                # skips it too, so skipping keeps the two口径 identical.
                continue
            name = (obj.get("test") or {}).get("name") or ""
            # "loading <file>" is a suite-load event, not a test case.
            if name.startswith("loading "):
                continue
            out.add(name)
    if not out:
        fail("no testStart names extracted (empty/wrong-format report): %s" % path)
    # Plain `sorted` (code-point order) -- UTF-8 preserves code-point order,
    # and this is literally what the gate does; do not "improve" it.
    return sorted(out)


def fingerprint(names):
    blob = "".join(n + "\n" for n in names).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()[:16]


def baseline_fields(path):
    if not os.path.isfile(path):
        fail("baseline not found: %s" % path)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except ValueError as exc:
        fail("baseline is not valid JSON (%s): %s" % (path, exc))
    return data


def pair(removed, added):
    """Greedy best-similarity pairing of removed vs added names."""
    pairs = []
    pool = list(added)
    for old in removed:
        if not pool:
            break
        best = max(pool, key=lambda new: difflib.SequenceMatcher(None, old, new).ratio())
        ratio = difflib.SequenceMatcher(None, old, best).ratio()
        pool.remove(best)
        pairs.append((old, best, ratio))
    for leftover in removed:
        if not any(o == leftover for o, _, _ in pairs):
            pairs.append((leftover, None, 0.0))
    return pairs


def fail(msg):
    print("ERROR: %s" % msg)
    print("VERDICT=UNAVAILABLE")
    sys.exit(1)


def write_detail(lines, out_path):
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser(description="gate 2 case-set drift forensics (read-only)")
    ap.add_argument("--old", help="earlier gate json report")
    ap.add_argument("--new", help="later gate json report")
    ap.add_argument("--report", help="a gate json report to check against --baseline")
    ap.add_argument("--baseline", help="tool/test_count_baseline.json")
    ap.add_argument("--rename-threshold", type=float, default=0.60)
    ap.add_argument("--out", help="UTF-8 detail file (default: system temp)")
    args = ap.parse_args()

    if bool(args.old) != bool(args.new):
        fail("--old and --new must be given together")
    if bool(args.report) != bool(args.baseline):
        fail("--report and --baseline must be given together")
    if not (args.old or args.report):
        fail("nothing to do: give --old/--new or --report/--baseline")

    detail = []
    rc = 0
    verdict = ""

    if args.old:
        old_names = names_from_report(args.old)
        new_names = names_from_report(args.new)
        old_fp, new_fp = fingerprint(old_names), fingerprint(new_names)
        print("OLD  size=%d fp=%s  (%s)" % (len(old_names), old_fp, os.path.basename(args.old)))
        print("NEW  size=%d fp=%s  (%s)" % (len(new_names), new_fp, os.path.basename(args.new)))
        detail.append("OLD size=%d fp=%s file=%s" % (len(old_names), old_fp, args.old))
        detail.append("NEW size=%d fp=%s file=%s" % (len(new_names), new_fp, args.new))
        if old_fp == new_fp:
            verdict = "IDENTICAL"
            print("SET  identical (rename/add/remove would have changed the fp)")
        else:
            rc = 1
            removed = sorted(set(old_names) - set(new_names), key=lambda s: s.encode("utf-8"))
            added = sorted(set(new_names) - set(old_names), key=lambda s: s.encode("utf-8"))
            print("SET  removed=%d added=%d size_delta=%d" % (len(removed), len(added), len(new_names) - len(old_names)))
            pairs = pair(removed, added) if removed and added else []
            ratios = [r for _, b, r in pairs if b is not None]
            worst = min(ratios) if ratios else 0.0
            for old, new, ratio in pairs:
                tag = "RENAME sim=%.3f" % ratio if new is not None else "REMOVED (no counterpart)"
                detail.append("- %s" % old)
                detail.append("  %s" % tag)
                if new is not None:
                    detail.append("+ %s" % new)
            if new_names and len(removed) == len(added) and worst >= args.rename_threshold:
                verdict = "LIKELY-RENAME"
                print("VERDICT=LIKELY-RENAME  worst_similarity=%.3f (threshold %.2f)" % (worst, args.rename_threshold))
                print("ACTION  restore the original test description strings; do NOT re-pin the baseline")
            else:
                verdict = "REAL-CHANGE"
                print("VERDICT=REAL-CHANGE  removed=%d added=%d (paired=%d, worst_sim=%.3f)" % (len(removed), len(added), len(ratios), worst))
                print("ACTION  reconcile every removed/added name against this batch scope, then re-pin on a green round with UPDATE_TEST_BASELINE=1")
    else:
        names = names_from_report(args.report)
        data = baseline_fields(args.baseline)
        cur_fp = fingerprint(names)
        base_fp = data.get("suite_fingerprint") or ""
        base_size = data.get("suite_size")
        base_count = data.get("count")
        print("REPORT size=%d fp=%s  (%s)" % (len(names), cur_fp, os.path.basename(args.report)))
        print("BASE   size=%s fp=%s count=%s head=%s reason_present=%s" % (
            base_size, base_fp or "-", base_count, data.get("head", "-"), bool(data.get("reason"))))
        detail.append("REPORT size=%d fp=%s file=%s" % (len(names), cur_fp, args.report))
        detail.append("BASE   size=%s fp=%s count=%s head=%s generated_at=%s" % (
            base_size, base_fp or "-", base_count, data.get("head", "-"), data.get("generated_at", "-")))
        if not base_fp:
            verdict = "BASELINE-HAS-NO-FINGERPRINT"
            rc = 1
            print("VERDICT=BASELINE-HAS-NO-FINGERPRINT  gate does not judge F1 this round")
            print("ACTION  re-pin once on a green round so suite_fingerprint gets written")
        elif base_fp == cur_fp:
            verdict = "MATCH"
            print("SET  report matches baseline fingerprint")
        else:
            verdict = "MISMATCH"
            rc = 1
            print("SET  report fp=%s != baseline fp=%s => case set changed since the pin" % (cur_fp, base_fp))
            print("ACTION  diff the name sets (see DETAIL=) before deciding rename vs re-pin")

    out_path = args.out or os.path.join(
        tempfile.gettempdir(),
        "case_set_drift_%s_%d.txt" % (datetime.now().strftime("%Y%m%d-%H%M%S"), os.getpid()))
    write_detail(detail if detail else ["(no per-name drift)"], out_path)
    print("DETAIL=%s" % out_path)
    print("RC=%d" % rc)
    return rc


if __name__ == "__main__":
    sys.exit(main())
