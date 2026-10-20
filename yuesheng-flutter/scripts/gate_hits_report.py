#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁命中率报告 —— 回答一个问题：**这道门禁历史上真的拦下过东西吗？**

背景（2026-10-20）：19 道门禁此前**没有任何一处记录「上次失败是什么时候」**。
于是「零命中」与「一直很稳」在输出里长得一模一样，而这两者的处置完全相反 ——
前者是退役候选，后者是资产。本报告把命中率变成可查事实。

数据源：`outputs/gate/hits.jsonl` —— 由 `gate.sh` / `gate-fast.sh` 的 `log_result` 追加，
两个脚本写**同一份**（`profile` 字段区分 full / fast）。

★ 边界，必须如实读：`yuesheng-flutter/.gitignore` 有 `outputs/` 规则
  ⇒ 该文件**不在版本控制内**：**本机累积、换机清零**。
  故本报告**必然**打印数据区间；把「区间内零命中」说成「从未命中」是错的。

用法:
  python scripts/gate_hits_report.py                # 默认全区间
  python scripts/gate_hits_report.py --days 30      # 只看最近 30 天
  python scripts/gate_hits_report.py --json         # 机读输出
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

# 零命中判定阈值：运行次数太少时不下结论（刚上线的门禁本来就还没机会命中）。
MIN_RUNS_FOR_VERDICT = 5


def _display_width(s: str) -> int:
    """中文字符按 2 列宽计算，否则表格对不齐。"""
    import unicodedata

    w = 0
    for ch in s:
        w += 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
    return w


def _pad(s: str, width: int) -> str:
    return s + " " * max(0, width - _display_width(s))


def _rpad(s: str, width: int) -> str:
    return " " * max(0, width - _display_width(s)) + s


def load(path: str) -> tuple[list[dict], int]:
    """读取流水；坏行**跳过并计数**（不静默吞掉，也不因一行坏而整份报废）。"""
    if not os.path.exists(path):
        return [], 0
    rows: list[dict] = []
    bad = 0
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                bad += 1
    return rows, bad


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--days", type=int, default=0, help="只统计最近 N 天（0 = 全区间）")
    ap.add_argument("--json", action="store_true", help="输出 JSON 而非表格")
    ap.add_argument(
        "--file",
        default=os.path.join("outputs", "gate", "hits.jsonl"),
        help="流水文件路径（默认 outputs/gate/hits.jsonl）",
    )
    args = ap.parse_args()

    rows, bad = load(args.file)

    if not rows:
        print(f"[空] 没有命中率流水：{args.file}")
        print("     跑一次 `bash scripts/gate-fast.sh` 或 `bash scripts/gate.sh` 即可生成。")
        print("     注意该文件在 .gitignore 的 `outputs/` 内 ⇒ 本机累积、换机清零。")
        return 0

    # ---- 时间窗过滤 ----
    if args.days > 0:
        cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)
        kept = []
        for r in rows:
            try:
                ts = datetime.strptime(r["ts"], "%Y-%m-%dT%H:%M:%S%z")
            except (KeyError, ValueError):
                kept.append(r)  # 时间不可解析的保留，避免静默丢数据
                continue
            if ts >= cutoff:
                kept.append(r)
        rows = kept
        if not rows:
            print(f"[空] 最近 {args.days} 天内没有记录。")
            return 0

    rows.sort(key=lambda r: (r.get("ts", ""), r.get("run", ""), r.get("seq", 0)))

    # ---- 聚合 ----
    agg: dict[str, dict] = defaultdict(
        lambda: {
            "pass": 0,
            "fail": 0,
            "skip": 0,
            "dur": [],
            "last_fail": None,
            "profiles": set(),
        }
    )
    for r in rows:
        name = r.get("name", "<未命名>")
        a = agg[name]
        res = r.get("result", "?")
        if res == "PASS":
            a["pass"] += 1
        elif res == "FAIL":
            a["fail"] += 1
            ts = r.get("ts", "")
            if a["last_fail"] is None or ts > a["last_fail"]:
                a["last_fail"] = ts
        elif res == "SKIP":
            a["skip"] += 1
        # seq==1 的耗时含脚本前置开销（git rev-parse 74ms 等）——实测偏差 <1%，
        # 故**保留**：排掉它会让「格式校验」这道永远没有耗时数据（它每次都是首道），
        # 那等于为了 0.2s 的精度丢掉一整道门的时间画像。
        if isinstance(r.get("dur_s"), int):
            a["dur"].append(r["dur_s"])
        if r.get("profile"):
            a["profiles"].add(r["profile"])

    ts_all = [r.get("ts", "") for r in rows if r.get("ts")]
    span_from, span_to = min(ts_all), max(ts_all)
    runs = len({r.get("run") for r in rows if r.get("run")})

    summary = []
    for name, a in agg.items():
        executed = a["pass"] + a["fail"]
        hit_rate = (a["fail"] / executed * 100.0) if executed else 0.0
        summary.append(
            {
                "name": name,
                "pass": a["pass"],
                "fail": a["fail"],
                "skip": a["skip"],
                "executed": executed,
                "hit_rate_pct": round(hit_rate, 1),
                "avg_dur_s": round(sum(a["dur"]) / len(a["dur"]), 1) if a["dur"] else None,
                "last_fail": a["last_fail"],
                "profiles": sorted(a["profiles"]),
            }
        )

    # 排序：零命中的排前面（需要看的），其余按耗时降序
    summary.sort(
        key=lambda s: (
            0 if (s["fail"] == 0 and s["executed"] >= MIN_RUNS_FOR_VERDICT) else 1,
            -(s["avg_dur_s"] or 0),
            s["name"],
        )
    )

    if args.json:
        print(
            json.dumps(
                {
                    "file": args.file,
                    "span_from": span_from,
                    "span_to": span_to,
                    "runs": runs,
                    "records": len(rows),
                    "bad_lines": bad,
                    "summary": summary,
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0

    # ---- 表格输出 ----
    print("门禁命中率报告")
    print(f"  数据源 : {args.file}")
    print(f"  数据区间: {span_from}  →  {span_to}")
    print(f"  覆盖    : {runs} 次运行 / {len(rows)} 条记录" + (f" / {bad} 行坏数据已跳过" if bad else ""))
    print("  ⚠️ 该文件不在版本控制内（.gitignore 的 outputs/）⇒ 本机累积、换机清零；")
    print("     以下结论只对这区间成立，不是全量历史。")
    print()

    w_name = max([_display_width("门禁")] + [_display_width(s["name"]) for s in summary]) + 2
    header = (
        _pad("门禁", w_name)
        + _rpad("运行", 5)
        + _rpad("FAIL", 6)
        + _rpad("SKIP", 6)
        + _rpad("命中率", 8)
        + _rpad("均耗时", 8)
        + "  最近 FAIL"
    )
    print(header)
    print("-" * (_display_width(header) + 4))
    for s in summary:
        avg = f"{s['avg_dur_s']}s" if s["avg_dur_s"] is not None else "—"
        last = (s["last_fail"] or "—")[:16].replace("T", " ")
        print(
            _pad(s["name"], w_name)
            + _rpad(str(s["executed"]), 5)
            + _rpad(str(s["fail"]), 6)
            + _rpad(str(s["skip"]), 6)
            + _rpad(f"{s['hit_rate_pct']}%", 8)
            + _rpad(avg, 8)
            + "  " + last
        )

    print()
    zero = [s for s in summary if s["fail"] == 0 and s["executed"] >= MIN_RUNS_FOR_VERDICT]
    if zero:
        print(f"★ 零命中（运行 ≥{MIN_RUNS_FOR_VERDICT} 次、一次 FAIL 都没有）—— 退役候选：")
        for s in zero:
            print(f"    · {s['name']}（{s['executed']} 次 / 均 {s['avg_dur_s']}s）")
        print("  判读：『零命中』有两种含义 —— ①代码从没犯过这类错（门禁是保险，删了就没了）")
        print("        ②门禁的判据其实抓不到真实错误（那它一直在给假绿）。")
        print("  区分办法：手动注入一次该缺陷，看它是否报红。**不验证就退役 = 用假绿换速度。**")
    else:
        print(f"（无运行 ≥{MIN_RUNS_FOR_VERDICT} 次的零命中门禁）")

    thin = [s for s in summary if s["executed"] < MIN_RUNS_FOR_VERDICT]
    if thin:
        print()
        print(f"· 样本不足（运行 <{MIN_RUNS_FOR_VERDICT} 次，暂不下结论）：")
        for s in thin:
            print(f"    · {s['name']}（{s['executed']} 次）")

    # ★ 最危险的形态不是「零命中」，是「长期 SKIP」：门禁存在、报告里不叫失败、
    #   但一次都没真正执行过。它比零命中更隐蔽 —— 零命中至少跑过。
    skip_heavy = [s for s in summary if s["skip"] >= 3 and s["skip"] > s["executed"]]
    if skip_heavy:
        print()
        print("⚠️ 长期 SKIP（从未真正执行，报告里却不叫失败）—— 假绿风险最高：")
        for s in skip_heavy:
            print(f"    · {s['name']}（SKIP {s['skip']} 次 / 真正执行 {s['executed']} 次）")
        print("  说明：SKIP 已是 fail-closed（使退出码非 0），但它**不指出缺什么**。")
        print("        跑一次 `bash scripts/gate-run.sh full`，看 SKIP 的实时原因。")

    print()
    print("注：耗时取『与上一次 log_result 的间隔』；每次运行的首道含 ≤0.2s 前置开销")
    print("    （git rev-parse 等），偏差 <1%，未剔除。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
