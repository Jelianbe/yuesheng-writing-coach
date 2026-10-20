"""层 3 · 子代理模拟重跑：分片任务单生成器（零 API / 零 key）

用途
----
把 W-23 的 240 格（24 样本 × 2 温度档 × 5 轮）切成 **24 个分片任务单**，
每个任务单 = 1 个样本的 10 格，供一个子代理扮演 LLM 逐格判读。

★ 为什么按「样本」切而不是按「格」切
  同一样本的 10 格共享同一段原文（长度 107–3510 字）⇒ 按格切会让同一段
  原文被重复读 10 次（上下文成本 ×10）；按样本切则原文只进一次上下文，
  10 格共用该上下文逐格判读。

★ 为什么需要「同一段原文判 10 次」
  真实 W-23 跑测的 10 格 = 同原文 × 2 温度档 × 5 轮（真实 LLM 的采样差异）。
  子代理模拟**无法复现采样随机性**（同一子代理同一上下文 ⇒ 输出趋同），
  因此本层的 10 格是「同一判读在 10 个采样位上的重复」——
  ⚠️ **诚实边界**：层 3 验的是「**prompt 变更后模型会不会照新规范输出**」
  （产出率 + 字段正确性 + 闸门净效应），**不验 LLM 采样方差**。
  方差面仍归真实 key 跑测（舰长已裁本批不用 key ⇒ 该面登记为未覆盖）。

产物
----
.ai/research/cross-validation/data/w23_sim/tasks/<sample>.md   （任务单）
.ai/research/cross-validation/data/w23_sim/answers/<sample>.json（子代理回填）

用法
----
python tool/build_sim_tasks.py
"""

import io
import json
import os

W23_CELLS = r"D:/ai-teacher/.ai/research/cross-validation/data/w23/w23_cells.json"
OUT_DIR = r"D:/ai-teacher/.ai/research/cross-validation/data/w23_sim"
TASK_DIR = os.path.join(OUT_DIR, "tasks")
ANSWER_DIR = os.path.join(OUT_DIR, "answers")
PROMPT_REF = (
    "D:/ai-teacher/yuesheng-flutter/outputs/gate/single_chain_prompt.txt"
)

# 温度档标签（cells 里 temp 是 float 0.3 / 0.7）
TEMP_LABEL = {0.3: "t03", 0.7: "t07"}


def load_cells():
    with io.open(W23_CELLS, encoding="utf-8") as f:
        return json.load(f)["cells"]


def build_task(sample, cells):
    """生成 1 个样本的判读任务单（Markdown）。"""
    manuscript = cells[0]["manuscript"]
    lines = []
    lines.append(f"# 模拟诊断任务单 · 样本 {sample}")
    lines.append("")
    lines.append(
        "## 你的角色\n\n"
        "你是**月笙写作教练**的诊断模块（单次链）。你必须严格按"
        "「判读依据」中那份**真实 system prompt** 的规范，对给定文本做症候诊断，"
        "并输出规定格式的 `[YS_DIAGNOSIS]` JSON 块。\n\n"
        "**你不是在写代码，不是在写报告**——你是在扮演该诊断模块本身，"
        "按 prompt 规范产出它的真实输出。"
    )
    lines.append("")
    lines.append("## 判读依据（真实 system prompt · 必须逐条遵守）")
    lines.append("")
    lines.append(
        f"完整 prompt 在：`{PROMPT_REF}`\n\n"
        "**请先完整读取该文件**（约 6000 字符），它包含：严重度三维标定 / "
        "诊断输出规范（含「干预价值（S3）三判据」段与「形态字段」段）/ "
        "输出格式（`[YS_DIAGNOSIS]` JSON 块模板）/ 排除的「伪问题」。"
    )
    lines.append("")
    lines.append("## 待判读文本（原文 · 只读一次，10 格共用）")
    lines.append("")
    lines.append("```text")
    lines.append(manuscript)
    lines.append("```")
    lines.append("")
    lines.append("## 你要判读的 10 格（每格独立输出一次）")
    lines.append("")
    lines.append(
        "每格 = 一次独立的诊断调用。**每格都要完整输出一份** "
        "`[YS_DIAGNOSIS]` JSON 块（自然说明部分可省略，只输出 JSON 块即可）。"
    )
    lines.append("")
    lines.append("| 格 ID | 温度档 | 轮次 |")
    lines.append("|:--|:--|:--|")
    for c in cells:
        lines.append(
            f"| `{c['cell_id']}` | {TEMP_LABEL.get(c['temp'], c['temp'])} "
            f"| r{c['round']} |"
        )
    lines.append("")
    lines.append("## 输出格式（严格遵守）")
    lines.append("")
    lines.append(
        "把 10 格的 JSON 块合成**一个 JSON 对象**写到 "
        f"`{ANSWER_DIR}/{sample}.json`，结构如下：\n\n"
        "```json\n"
        "{\n"
        '  "sample": "' + sample + '",\n'
        '  "cells": [\n'
        "    {\n"
        '      "cell_id": "X01|t03|r1",\n'
        '      "syndromes": [\n'
        "        {\n"
        '          "syndrome_id": "P002",\n'
        '          "name": "信息倾泻症",\n'
        '          "severity": "L2",\n'
        '          "evidence": ["原文片段（5-20字）"],\n'
        '          "explanation": "问题描述 + 判断理由",\n'
        '          "reader_impact": "可选：读者影响",\n'
        '          "intervention_value": "high | medium | low",\n'
        '          "form_fact_count": 4,\n'
        '          "form_structure": "expository"\n'
        "        }\n"
        "      ],\n"
        '      "suggested_actions": ["A0XX"],\n'
        '      "feedback_summary": "可选"\n'
        "    }\n"
        "  ]\n"
        "}\n"
        "```"
    )
    lines.append("")
    lines.append("## 本批的三个特别要求（务必照做）")
    lines.append("")
    lines.append(
        "1. **`intervention_value` 必须输出**（单次链自此产出该字段，按 prompt 的"
        "「干预价值（S3）三判据」评定：`high` / `medium` / `low`；"
        "判定不了时按 prompt 缺省 `low`，但**不要省略该键**）。"
    )
    lines.append(
        "2. **形态字段只对「信息倾泻/量形式」症候输出**（如 P002 等信息倾泻类）："
        "`form_fact_count` = 成段出现的设定/背景事实条数（单句带过 = 1）；"
        "`form_structure` ∈ `expository`（论文式/说明书结构，如「原因有二：其一……」）/ "
        "`interruption`（读者关切时刻被打断）/ `narrative`（嵌在叙事流中、无结构标记）。"
        "**其余症候一律省略这两个键**（不要输出 null，也不要输出 0）。"
    )
    lines.append(
        "3. **按「判据收敛报出」**：只报判据逐条满足且能引原文证据的症候，"
        "宁缺勿滥；合格条目超过 5 条时只保留最前的 5 条。"
    )
    lines.append("")
    lines.append(
        "## 完成判据\n\n"
        "- 10 格全部有 `cell_id` 与 `syndromes` 数组；\n"
        "- 文件是**合法 JSON**（可被 `json.load` 解析）；\n"
        "- 每个 syndrome 对象含 `syndrome_id` / `name` / `severity` / `evidence` / "
        "`explanation`；\n"
        "- **不要写任何解释性文字到 JSON 之外**（文件里只有 JSON）。"
    )
    lines.append("")
    return "\n".join(lines)


def main():
    cells = load_cells()
    by_sample = {}
    for c in cells:
        by_sample.setdefault(c["sample"], []).append(c)

    for d in (TASK_DIR, ANSWER_DIR):
        os.makedirs(d, exist_ok=True)

    for sample, sub in sorted(by_sample.items()):
        sub.sort(key=lambda c: (c["temp"], c["round"]))
        task = build_task(sample, sub)
        path = os.path.join(TASK_DIR, sample + ".md")
        with io.open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(task)
        # 预置空答案文件（子代理覆盖写入）
        ans = {
            "sample": sample,
            "cells": [
                {"cell_id": c["cell_id"], "syndromes": [], "suggested_actions": []}
                for c in sub
            ],
        }
        apath = os.path.join(ANSWER_DIR, sample + ".json")
        if not os.path.exists(apath):
            with io.open(apath, "w", encoding="utf-8", newline="\n") as f:
                f.write(json.dumps(ans, ensure_ascii=False, indent=2))

    print("[build] 样本数 =", len(by_sample), "（每样本 10 格）")
    print("[build] 任务单目录 =", TASK_DIR)
    print("[build] 答案目录 =", ANSWER_DIR)
    print("[build] 单元格总数 =", sum(len(v) for v in by_sample.values()))


if __name__ == "__main__":
    main()
