"""层 3 模拟答案质量校验（零 API / 零 key）。

校验项
------
C1 每个样本文件恰好 10 格，且 cell_id 集合与 W-23 原始 cells **逐字一致**
   （按样本 + 温度档 + 轮次对齐，防张冠李戴）。
C2 每个 syndrome 必含 syndrome_id / name / severity / evidence / explanation。
C3 severity ∈ {L1, L2, L3}。
C4 syndrome_id ∈ P001–P039 且与 registry 的 name 一致（防自造名）。
C5 intervention_value ∈ {high, medium, low} 且**每条都有**（不许省键）。
C6 形态字段：只允许出现在量形式症候（P002 / P037）；
   form_fact_count 必须是 ≥0 整数；form_structure ∈ {expository, interruption, narrative}；
   **其余症候不得出现这两键**（含 null / 0）。
C7 evidence 非空、每条长度 5–20 字、且**逐字出自该样本原文**（防幻觉引用）。
C8 每格报出条数 ≤ 5（prompt 上限）。
C9 形态 bulk 双要素同时成立时，记入 bulk 统计（供闸门效应重放对账）。

只读校验，不改答案。退出码非 0 = 有 C 项失败。
"""

import io
import json
import os
import re
import sys

W23_CELLS = r"D:/ai-teacher/.ai/research/cross-validation/data/w23/w23_cells.json"
ANSWERS = r"D:/ai-teacher/.ai/research/cross-validation/data/w23_sim/answers"
REGISTRY = r"D:/ai-teacher/yuesheng-flutter/lib/services/syndrome_registry.dart"

FORM_ALLOWED_SYNDROMES = {"P002", "P037"}
VALID_STRUCTURES = {"expository", "interruption", "narrative"}
VALID_IV = {"high", "medium", "low"}

errors = []
warnings = []


def err(cid, msg):
    errors.append(f"[{cid}] {msg}")


def warn(cid, msg):
    warnings.append(f"[{cid}] {msg}")


# ── 载入真源 ──────────────────────────────────────────────
with io.open(W23_CELLS, encoding="utf-8") as f:
    w23 = json.load(f)["cells"]
expected_cells = {}
manuscript_by_sample = {}
for c in w23:
    expected_cells.setdefault(c["sample"], set()).add(c["cell_id"])
    manuscript_by_sample[c["sample"]] = c["manuscript"]

# registry name 表（P001–P039）
# ★ registry 里 id / name 分行写（SyndromeRecord(id: 'P017', \n name: '...')），
#   故必须**按块**解析（以 `id:` 行为块首，取块内第一个 `name:`），
#   同行正则会把 P017 匹配到下一块的 P036 名（实测已踩）。
reg_names = {}
with io.open(REGISTRY, encoding="utf-8") as f:
    cur_id = None
    for line in f:
        m_id = re.search(r"\bid:\s*'(P\d{3})'", line)
        if m_id:
            cur_id = m_id.group(1)
            continue
        m_name = re.search(r"\bname:\s*'([^']+)'", line)
        if m_name and cur_id and cur_id not in reg_names:
            reg_names[cur_id] = m_name.group(1)
            cur_id = None
        if '],' in line or ');' in line:
            cur_id = None

# ── 逐文件校验 ────────────────────────────────────────────
files = sorted(
    f for f in os.listdir(ANSWERS) if f.endswith(".json"))
stats = {
    "files": 0,
    "cells": 0,
    "syndromes": 0,
    "cells_with_iv": 0,
    "syndromes_with_iv": 0,
    "cells_with_form": 0,
    "syndromes_with_form": 0,
    "bulk_syndromes": 0,
    "iv_dist": {},
    "struct_dist": {},
    "form_by_syndrome": {},
}

for fn in files:
    sample = fn[:-5]
    path = os.path.join(ANSWERS, fn)
    try:
        with io.open(path, encoding="utf-8") as f:
            doc = json.load(f)
    except Exception as e:
        err(fn, f"JSON 解析失败：{e}")
        continue
    stats["files"] += 1

    if doc.get("sample") != sample:
        err(fn, f"sample 字段 = {doc.get('sample')}，应为 {sample}")

    cells = doc.get("cells", [])
    stats["cells"] += len(cells)
    got_ids = [c.get("cell_id") for c in cells]
    exp_ids = expected_cells.get(sample, set())
    if len(cells) != 10:
        err(fn, f"格数 = {len(cells)}，应为 10")
    got_set = set(got_ids)
    if got_set != exp_ids:
        err(fn, f"cell_id 集合不匹配：缺 {sorted(exp_ids - got_set)} / "
                f"多 {sorted(got_set - exp_ids)}")
    if len(got_ids) != len(got_set):
        err(fn, "cell_id 有重复")

    manuscript = manuscript_by_sample.get(sample, "")
    for cell in cells:
        cid = cell.get("cell_id", "?")
        syndromes = cell.get("syndromes")
        if not isinstance(syndromes, list):
            err(cid, "syndromes 不是数组")
            continue
        if len(syndromes) == 0:
            warn(cid, "本格无症候产出")
        if len(syndromes) > 5:
            err(cid, f"报出 {len(syndromes)} 条 > prompt 上限 5")
        cell_iv = False
        cell_form = False
        for s in syndromes:
            stats["syndromes"] += 1
            sid = s.get("syndrome_id")
            for key in ("syndrome_id", "name", "severity", "evidence",
                        "explanation"):
                if key not in s:
                    err(cid, f"syndrome 缺必填键 {key}")
            sev = s.get("severity")
            if sev not in ("L1", "L2", "L3"):
                err(cid, f"severity 非法 = {sev!r}")
            if sid and not re.fullmatch(r"P0\d\d", sid):
                err(cid, f"syndrome_id 非法 = {sid!r}")
            if sid in reg_names and s.get("name") != reg_names[sid]:
                warn(cid, f"{sid} name={s.get('name')!r}，registry="
                          f"{reg_names[sid]!r}")
            # C5 iv
            iv = s.get("intervention_value")
            if iv is None:
                err(cid, f"{sid} 缺 intervention_value（prompt 要求必出）")
            elif iv not in VALID_IV:
                err(cid, f"{sid} intervention_value 非法 = {iv!r}")
            else:
                cell_iv = True
                stats["syndromes_with_iv"] += 1
                stats["iv_dist"][iv] = stats["iv_dist"].get(iv, 0) + 1
            # C6 形态字段
            has_fc = "form_fact_count" in s
            has_fs = "form_structure" in s
            if has_fc or has_fs:
                cell_form = True
                stats["syndromes_with_form"] += 1
                stats["form_by_syndrome"][sid] = \
                    stats["form_by_syndrome"].get(sid, 0) + 1
                if sid not in FORM_ALLOWED_SYNDROMES:
                    err(cid, f"{sid} 出现形态字段，但非量形式症候"
                             f"（只允许 {sorted(FORM_ALLOWED_SYNDROMES)}）")
                fc = s.get("form_fact_count")
                fs = s.get("form_structure")
                if not isinstance(fc, int) or isinstance(fc, bool) or fc < 0:
                    err(cid, f"{sid} form_fact_count 非法 = {fc!r}")
                if fs not in VALID_STRUCTURES:
                    err(cid, f"{sid} form_structure 非法 = {fs!r}")
                else:
                    stats["struct_dist"][fs] = stats["struct_dist"].get(fs, 0) + 1
                if isinstance(fc, int) and fs in ("expository", "interruption") \
                        and fc >= 3:
                    stats["bulk_syndromes"] += 1
            # C7 evidence
            ev = s.get("evidence")
            if not isinstance(ev, list) or len(ev) == 0:
                err(cid, f"{sid} evidence 空或非数组")
            else:
                for e in ev:
                    if not isinstance(e, str) or not (5 <= len(e) <= 20):
                        err(cid, f"{sid} evidence 长度越界 = {e!r} "
                                 f"(len={len(e) if isinstance(e, str) else '?'})")
                    elif manuscript and e not in manuscript:
                        err(cid, f"{sid} evidence 不出自原文（幻觉引用）= {e!r}")
        if cell_iv:
            stats["cells_with_iv"] += 1
        if cell_form:
            stats["cells_with_form"] += 1

# ── 汇总输出 ──────────────────────────────────────────────
print("=" * 62)
print("层 3 模拟答案质量校验")
print("=" * 62)
print(f"文件数 = {stats['files']} / 24")
print(f"格数   = {stats['cells']} / 240")
print(f"症候条数 = {stats['syndromes']}")
print(f"iv：条级 {stats['syndromes_with_iv']}/{stats['syndromes']} "
      f"· 格级 {stats['cells_with_iv']}/{stats['cells']} "
      f"· 分布 {stats['iv_dist']}")
print(f"形态：条级 {stats['syndromes_with_form']} · 格级 {stats['cells_with_form']} "
      f"· bulk(双要素成立) {stats['bulk_syndromes']}")
print(f"形态结构分布 = {stats['struct_dist']}")
print(f"形态字段所在症候 = {stats['form_by_syndrome']}")
print()
if errors:
    print(f"✗ 错误 {len(errors)} 条（前 40）：")
    for e in errors[:40]:
        print("   ", e)
else:
    print("✓ 错误 0 条")
if warnings:
    print(f"⚠ 警告 {len(warnings)} 条（前 20）：")
    for w in warnings[:20]:
        print("   ", w)
else:
    print("✓ 警告 0 条")
print("=" * 62)
sys.exit(1 if errors else 0)
