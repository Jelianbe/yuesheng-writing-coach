"""层 3 重放口径勘查（只勘查，不算分、不算焦点）。

目的
----
层 3 要做「双重重放」：
  ① 新模拟 cells（闸 v1：form 置空）vs 旧 cells ⇒ **prompt 效应**
  ② 新模拟 cells（闸 v2：form 保留）vs 同 cells 闸 v1 ⇒ **闸门效应**
两侧必须**同一口径**才可归因 ⇒ 本脚本先把口径勘查清楚：

  Q1 旧 cells 的 log_focus_id 非空比例？（非空 ⇒ AI 建议分支，不走 fallback ⇒ 闸不生效）
  Q2 旧 cells 的 arm_a_source 分布？
  Q3 旧 cells 的 active_problems.syndrome_id 集合 vs syndromes.syndrome_id 集合
     是否一一对应？（对应 ⇒ 模拟侧「syndromes ⇒ active_problems」推导成立）
  Q4 active_problems 的 status / confirmation_status / severity 分布？
  Q5 旧 cells 的 syndromes 是否带 intervention_value / 形态字段？（旧 prompt 无 ⇒ 应全无）

纪律：本脚本**不做任何评分/焦点计算**（那必须由 Dart 生产纯函数做），
只统计字段分布，供定重放口径用。
"""

import collections
import io
import json

CELLS = r"D:/ai-teacher/.ai/research/cross-validation/data/w23/w23_cells.json"

with io.open(CELLS, encoding="utf-8") as f:
    cells = json.load(f)["cells"]

print("总格数 =", len(cells))

# Q1 log_focus_id
log_null = sum(1 for c in cells if not c.get("log_focus_id"))
print("Q1 log_focus_id 为空 =", log_null, "/", len(cells),
      "非空 =", len(cells) - log_null)

# Q2 arm_a_source
print("Q2 arm_a_source =", dict(collections.Counter(c["arm_a_source"] for c in cells)))

# Q3 active_problems vs syndromes 的 syndrome_id 集合
mismatch = []
for c in cells:
    ap = {p["syndrome_id"] for p in c["active_problems"]}
    sy = {s["syndrome_id"] for s in c["syndromes"]}
    if ap != sy:
        mismatch.append((c["cell_id"], sorted(ap), sorted(sy)))
print("Q3 集合不一致格数 =", len(mismatch), "/", len(cells))
for m in mismatch[:5]:
    print("   ", m)

# Q3b 顺序是否一致（AP 顺序 == syndromes 顺序？）
order_mismatch = 0
for c in cells:
    ap = [p["syndrome_id"] for p in c["active_problems"]]
    sy = [s["syndrome_id"] for s in c["syndromes"]]
    if ap != sy:
        order_mismatch += 1
print("Q3b 顺序（含重复）不一致格数 =", order_mismatch)

# Q4 状态分布
st = collections.Counter()
cs = collections.Counter()
sev = collections.Counter()
conf_null = 0
for c in cells:
    for p in c["active_problems"]:
        st[p["status"]] += 1
        cs[p["confirmation_status"]] += 1
        sev[p["severity"]] += 1
        if p.get("evidence_confidence") is None:
            conf_null += 1
print("Q4 status =", dict(st))
print("Q4 confirmation_status =", dict(cs))
print("Q4 severity =", dict(sev))
print("Q4 evidence_confidence 为 null 的条目数 =", conf_null)

# Q5 旧 cells 的 syndromes 是否带 iv / 形态字段
has_iv = sum(1 for c in cells for s in c["syndromes"] if s.get("intervention_value"))
has_fc = sum(1 for c in cells for s in c["syndromes"] if s.get("form_fact_count"))
has_fs = sum(1 for c in cells for s in c["syndromes"] if s.get("form_structure"))
total_sy = sum(len(c["syndromes"]) for c in cells)
print("Q5 syndromes 总条数 =", total_sy,
      "带 iv =", has_iv, "带 form_fact_count =", has_fc, "带 form_structure =", has_fs)

# 附加：每格 syndrome 条数分布
print("附加 每格 syndrome 条数分布 =",
      dict(sorted(collections.Counter(len(c["syndromes"]) for c in cells).items())))

# 附加：旧 cells 的 syndromes 键名样本
print("附加 syndromes[0] 键名 =", list(cells[0]["syndromes"][0].keys()))
print("附加 active_problems[0] 键名 =", list(cells[0]["active_problems"][0].keys()))
