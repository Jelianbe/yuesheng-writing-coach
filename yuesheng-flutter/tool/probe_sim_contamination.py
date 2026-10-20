"""层 3 读数 · 污染自检：模拟标注 vs 护栏人工标注表逐格对拍。

为什么必须做这一步
------------------
护栏测试 `form_field_v2_guard_test.dart` 内有一张**人工标注表** `kFormAnnotations`
（覆盖 X01 / X22 两样本 × 各 10 格）。子代理在判读时若读了它，就会**逐格复现**
该表 ⇒ 该样本的「与设计稿标注一致」不再是独立验证，而是抄答案。

判定方法（可验证、不依赖代理自述）
--------------------------------
把模拟标注与 kFormAnnotations 逐格对拍：
  · 若**结构标记**（form_structure）逐格全同 **且** fact 数也逐格全同
    ⇒ 高度疑似读过该表（人工表本身是逐格手写的，10 格全同的巧合概率极低）；
  · 若结构标记有实质分歧 ⇒ 未读过该表（读了会照抄）。

本脚本只做对拍与统计，不改任何数据。
"""

import io
import json
import os
import re

GUARD = r"D:/ai-teacher/yuesheng-flutter/test/services/form_field_v2_guard_test.dart"
ANS = r"D:/ai-teacher/.ai/research/cross-validation/data/w23_sim/answers"

# ── 解析 kFormAnnotations ──────────────────────────────────
src = io.open(GUARD, encoding="utf-8").read()
block = src.split("kFormAnnotations = {", 1)[1].split("};", 1)[0]
ann = {}
for m in re.finditer(
        r"'([A-Z]\d\d\|t\d\d\|r\d)':\s*\((\d+),\s*'(\w+)'\)", block):
    ann[m.group(1)] = (int(m.group(2)), m.group(3))
print(f"护栏人工标注表条数 = {len(ann)}")
assert len(ann) == 20, "标注表应含 20 格（X01 + X22 各 10）"

# ── 逐格对拍 ──────────────────────────────────────────────
print()
print("=" * 78)
print("污染自检：模拟标注 vs 护栏人工标注表")
print("=" * 78)

per_sample = {}
for sample in ("X01", "X22"):
    path = os.path.join(ANS, f"{sample}.json")
    doc = json.load(io.open(path, encoding="utf-8"))
    rows = []
    for c in doc["cells"]:
        cid = c["cell_id"]
        p002 = next((s for s in c["syndromes"] if s["syndrome_id"] == "P002"), None)
        sim = (p002.get("form_fact_count"), p002.get("form_structure")) \
            if p002 else (None, None)
        gt = ann.get(cid)
        rows.append((cid, sim, gt))
    per_sample[sample] = rows

    struct_same = sum(1 for _, s, g in rows if g and s[1] == g[1])
    fact_same = sum(1 for _, s, g in rows if g and s[0] == g[0])
    both_same = sum(1 for _, s, g in rows if g and s == g)

    print()
    print(f"── {sample} ──")
    for cid, s, g in rows:
        gs = "—" if g is None else f"{g[0]}/{g[1]}"
        ss = "—" if s == (None, None) else f"{s[0]}/{s[1]}"
        mark = "  " if (g and s == g) else ("S" if (g and s[1] == g[1]) else "✗")
        print(f"  {mark} {cid}  人工={gs:<18} 模拟={ss:<18}")
    print(f"  → 结构标记相同 {struct_same}/10 · fact 数相同 {fact_same}/10 · "
          f"两者全同 {both_same}/10")
    print(f"  → 判定：{'★疑似读过标注表（逐格全同）' if both_same == 10 else '未见污染证据（有实质分歧）'}")

print()
print("=" * 78)
print("结论")
print("=" * 78)
for sample, rows in per_sample.items():
    both = sum(1 for _, s, g in rows if g and s == g)
    struct = sum(1 for _, s, g in rows if g and s[1] == g[1])
    verdict = "污染（逐格全同 ⇒ 抄了人工表）" if both == 10 else \
              ("部分一致（需人工复核）" if struct >= 8 else "无污染证据")
    print(f"  {sample}: 结构同 {struct}/10 · 全同 {both}/10 ⇒ {verdict}")
