"""T-20261021-03 分块链读数批：子代理模拟任务单生成器（零 API / 零 key）

用途
----
把 `chunks_para.json` 的 18 个分片切成 **18 个任务单**，每个任务单供一个
子代理扮演「分块诊断模块」逐条判读 39 条判据。

★ 为什么一块一个子代理（不按章批）
  窗口边界语义要求「只看得到本片」：若一个子代理同时拿到同章多片，
  判读第 1 片时已看见第 2/3 片 ⇒ uncertain 会被消解、跨片命中会被放大
  ⇒ ③ 量失真。故按块隔离，原文只进一次上下文（块与块不共享）。

★ 判读依据两份都必须先读（A3-15 ①：判据 = 模型实际看到的 prompt）
  ① chunk_system_prompt.txt —— 生产真实分块层 system prompt（4053 字符）
  ② criteria_all39.txt —— 39 条判据原文 verbatim（61514 字符，
     getSyndromeCriteriaSections 同短链注入提取函数）——读数批测
     「若注入判据原文，各条在长文分片上的行为」，故判据面取全集

产物
----
.ai/research/cross-validation/data/chunk_sim/tasks/<chunk_id>.md
.ai/research/cross-validation/data/chunk_sim/answers/<chunk_id>.json（预置空壳）

用法
----
python tool/build_chunk_sim_tasks.py
"""

import io
import json
import os

BASE = "D:/ai-teacher/.ai/research/cross-validation/data/chunk_sim"
CHUNKS = BASE + "/chunks_para.json"
TASK_DIR = BASE + "/tasks"
ANSWER_DIR = BASE + "/answers"
PROMPT_REF = BASE + "/chunk_system_prompt.txt"
CRITERIA_REF = BASE + "/criteria_all39.txt"

# 语料序号 → 短 ID（L01c1 = 第 1 章第 1 片）
SHORT = {f"LUXUN-20261022-{i:02d}": f"L{i:02d}" for i in range(1, 8)}


def build_task(chunk):
    cid = f"{SHORT[chunk['corpus_id']]}c{chunk['chunk_index'] + 1}"
    lines = []
    lines.append(f"# 模拟诊断任务单 · 分块 {cid}")
    lines.append("")
    lines.append(
        f"语料 {chunk['corpus_id']} · 本章第 {chunk['chunk_index'] + 1}/"
        f"{chunk['chunk_count']} 片 · 本片 {chunk['chunk_chars']} 字符"
    )
    lines.append("")
    lines.append("## 你的角色")
    lines.append("")
    lines.append(
        "你是**月笙写作教练**的**分块诊断模块**。你必须严格按「判读依据」"
        "中两份文件的规范，对给定文本片段做症候诊断。\n\n"
        "**你不是在写代码，不是在写报告**——你是在扮演该诊断模块本身，"
        "按规范产出它的真实判读。"
    )
    lines.append("")
    lines.append("## 判读依据（两份都必须先完整读取，逐条遵守）")
    lines.append("")
    lines.append(
        f"1. **真实分块层 system prompt**：`{PROMPT_REF}`\n"
        "   （约 4053 字符）——含「片段窗口边界」判读前提 / 块内可自证探针 / "
        "例外情况指引 / 输出格式。**窗口边界一节优先于其余一切**：你看不到"
        "本片段之外的任何内容。\n"
        f"2. **本次注入实验的判据原文（39 条完整判据）**：`{CRITERIA_REF}`\n"
        "   （约 61514 字符）——每条含判断原则 / 例外情况 / 诊断锚点。"
        "逐条核对，命中例外条款形态的**不判**。"
    )
    lines.append("")
    lines.append("## 待判读文本（本片段全文 · 你只看得到这一片）")
    lines.append("")
    lines.append(
        f"这是全章的第 {chunk['chunk_index'] + 1}/{chunk['chunk_count']} 片。"
        "**不要推测片段外内容**；片段外信息只能把你引向 `uncertain`，"
        "不能把「像是有问题」写成肯定结论。"
    )
    lines.append("")
    lines.append("```text")
    lines.append(chunk["text"])
    lines.append("```")
    lines.append("")
    lines.append("## 你要做的事：39 条判据逐条判定")
    lines.append("")
    lines.append(
        "对 **P001–P039 全部 39 条**逐条给出判定（不是只报命中的那种）：\n\n"
        "| verdict | 含义 | 必填字段 |\n"
        "|:--|:--|:--|\n"
        "| `hit` | 本片内有**可指认位置**的证据支撑该症候成立 | evidence + severity + reason |\n"
        "| `miss` | 本片内不成立（含命中例外条款的） | 无 |\n"
        "| `uncertain` | 成立与否**依赖片段外信息**（前文铺垫 / 后文解释 / "
        "片段外人物关系 / 全文节奏比例 / 角色长期状态） | reason（缺哪类） |"
    )
    lines.append("")
    lines.append("## 输出格式（严格遵守）")
    lines.append("")
    lines.append(
        "把结果写成**一个 JSON 对象**存到 "
        f"`{ANSWER_DIR}/{cid}.json`，结构：\n\n"
        "```json\n"
        "{\n"
        f'  "chunk_id": "{cid}",\n'
        f'  "corpus_id": "{chunk["corpus_id"]}",\n'
        '  "verdicts": [\n'
        "    {\"id\": \"P001\", \"verdict\": \"hit\", "
        "\"evidence\": [\"原文片段（逐字）\"], \"severity\": \"L2\", "
        "\"reason\": \"判断理由\"},\n"
        "    {\"id\": \"P002\", \"verdict\": \"miss\"},\n"
        "    {\"id\": \"P003\", \"verdict\": \"uncertain\", "
        "\"reason\": \"缺前文铺垫：…\"}\n"
        "    // …… 恰好 39 条，P001–P039 全覆盖，不重不漏\n"
        "  ]\n"
        "}\n"
        "```"
    )
    lines.append("")
    lines.append("## 特别要求（务必照做）")
    lines.append("")
    lines.append(
        "1. **`hit` 的 evidence 必须逐字出自本片段原文**（校验脚本会逐字比对，"
        "对不上即幻觉引用）；severity 按判据原文的严重度三维标定取 L1/L2/L3。\n"
        "2. **`uncertain` 必须写清缺哪类信息**，不得用 uncertain 逃避判断"
        "（片段内可自证的照常判）。\n"
        "3. **宁缺勿滥**：没有可指认证据不得判 hit；判据例外条款命中的判 miss。\n"
        "4. **文件里只有 JSON**，不要任何解释性文字；JSON 必须可被 "
        "`json.load` 解析。"
    )
    lines.append("")
    lines.append(
        "## 完成判据\n\n"
        "- 文件存在于指定路径且是合法 JSON；\n"
        "- `verdicts` 恰好 39 条，id 集合 = P001–P039（不重不漏）；\n"
        "- 每条 verdict ∈ {hit, miss, uncertain}，必填字段齐全。"
    )
    lines.append("")
    return cid, "\n".join(lines)


def main():
    with io.open(CHUNKS, encoding="utf-8") as f:
        chunks = json.load(f)["chunks"]
    os.makedirs(TASK_DIR, exist_ok=True)
    os.makedirs(ANSWER_DIR, exist_ok=True)
    for ch in chunks:
        cid, task = build_task(ch)
        with io.open(TASK_DIR + "/" + cid + ".md", "w",
                      encoding="utf-8", newline="\n") as f:
            f.write(task)
        apath = ANSWER_DIR + "/" + cid + ".json"
        if not os.path.exists(apath):
            with io.open(apath, "w", encoding="utf-8", newline="\n") as f:
                f.write(json.dumps(
                    {"chunk_id": cid, "corpus_id": ch["corpus_id"],
                     "verdicts": []},
                    ensure_ascii=False, indent=2))
    print(f"[build] 任务单 {len(chunks)} 个 → {TASK_DIR}")
    print(f"[build] 答案壳 {len(chunks)} 个 → {ANSWER_DIR}")


if __name__ == "__main__":
    main()
