"""T-20261021-03 分块链读数批：子代理模拟任务单生成器（零 API / 零 key）

用途
----
把 `chunks_para.json` 的 18 个分片切成 **18 个任务单**，每个任务单供一个
子代理扮演「分块诊断模块」逐条判读 39 条判据。

★ 为什么一块一个子代理（不按章批）
  窗口边界语义要求「只看得到本片」：若一个子代理同时拿到同章多片，
  判读第 1 片时已看见第 2/3 片 ⇒ uncertain 会被消解、跨片命中会被放大
  ⇒ ③ 量失真。故按块隔离，原文只进一次上下文（块与块不共享）。

★★ 同构纪律（T-20261027-01 · H7 · 2026-10-27 起强制）
  采样器喂给子代理的 prompt **必须等于生产当前值**，否则行为层读数
  （报出率 / 命中率）不能用于回滚判定 —— 这是本批之前最大的口径洞。
  做法：**每次运行前现场导出生产常量**，不再读手工快照：

    flutter test tool/dump_chunk_prompt_runner.dart      # → chunk_system_prompt_prod.txt

  导出失败 ⇒ 本脚本 **exit 2**（fail-fast）。**不许**退回读旧快照：
  实测旧快照 `chunk_system_prompt.txt`（2026-10-22，4,053 字符）与当前生产
  （5,785 字符）不同构，且 `chunk_system_prompt_c155_after.txt`（5,593）也已过期
  ⇒ 「用一份看起来像的旧文件继续跑」正是本卡要治的病。

  另：任务单里的「待判读文本」段现在**逐字复刻生产的 user 消息**
  （`来源记录：<title>（本片段可能含多章）\n\n文本片段 i/n：\n\n<正文>`，见
  `progressive_diagnosis.dart:1350` `buildChunkUserMessage`）—— 这也属同构面，
  缺了它子代理看到的输入形状与生产不同。
  ★ 2026-10-28（`T-20261027-01` H9）：旧文 `章节标题：<title>` 已随生产一并撤下 ——
  那个标签把**记录标题**当成**块内章节归属**，而系统并不知道后者。

★ 偏向措辞已清（H7 判据 2）
  旧版写死「命中例外条款形态的**不判**」「**宁缺勿滥**…判据例外条款命中的判 miss」
  ⇒ 系统性把子代理推向「不报」，使 `R-4` 回滚条件永远不可能触发。
  现改为中性表述：只要求证据逐字可核、理由引判据原文，**不预设报/不报的倾向**。

产物
----
.ai/research/cross-validation/data/chunk_sim/tasks/<chunk_id>.md
.ai/research/cross-validation/data/chunk_sim/answers/<chunk_id>.json（预置空壳）

用法
----
python tool/build_chunk_sim_tasks.py            # 重新导出 prompt + 重写 18 份任务单
python tool/build_chunk_sim_tasks.py --dry-run  # 只导出 prompt + 打印首份预览，不写任务单
"""

import io
import json
import os
import shutil
import subprocess
import sys

BASE = "D:/ai-teacher/.ai/research/cross-validation/data/chunk_sim"
CHUNKS = BASE + "/chunks_para.json"
CORPUS_JSONL = "D:/ai-teacher/.ai/reports/2026-10-21-长文语料/corpus.jsonl"
TASK_DIR = BASE + "/tasks"
ANSWER_DIR = BASE + "/answers"
# 生产 prompt 的**导出产物**（每次运行前刷新；不是手工快照，不纳入历史证据）
PROMPT_REF = BASE + "/chunk_system_prompt_prod.txt"
CRITERIA_REF = BASE + "/criteria_all39.txt"
FLUTTER_ROOT = "D:/ai-teacher/yuesheng-flutter"
DUMP_RUNNER = "tool/dump_chunk_prompt_runner.dart"

# 语料序号 → 短 ID（L01c1 = 第 1 章第 1 片）
SHORT = {f"LUXUN-20261022-{i:02d}": f"L{i:02d}" for i in range(1, 8)}


def refresh_production_prompt():
    """现场导出生产分块 prompt；失败即退出（不静默使用旧文件）。"""
    env = dict(os.environ)
    env["DUMP_OUT"] = PROMPT_REF
    # Windows：`flutter` 实际是 flutter.BAT，subprocess 直接传 argv 会
    # WinError 2（2026-10-27 实测）⇒ 必须经 shell 解析（或显式 cmd /c）。
    exe = os.environ.get("FLUTTER_BIN") or shutil.which("flutter") or "flutter"
    cmd = f'"{exe}" test {DUMP_RUNNER}'
    print(f"[build] 导出生产分块 prompt → {PROMPT_REF}")
    proc = subprocess.run(cmd, shell=True, cwd=FLUTTER_ROOT, env=env,
                          capture_output=True, text=True, encoding="utf-8",
                          errors="replace")
    for line in (proc.stdout or "").splitlines():
        if "[dump-chunk]" in line or "dump-chunk" in line:
            print("  " + line.strip())
    rc = proc.returncode
    if rc != 0:
        sys.stderr.write(
            f"[build] FATAL: 生产 prompt 导出失败（flutter test rc={rc}）\n"
            f"        不会退回读旧快照 —— 那正是 H7 要治的「采样器与生产不同构」。\n"
            f"        末 600 字输出：{(proc.stdout or '')[-600:]}\n")
        raise SystemExit(2)
    if not os.path.isfile(PROMPT_REF):
        sys.stderr.write(f"[build] FATAL: 导出命令返回 0 但文件不存在：{PROMPT_REF}\n"
                         f"        （rc=0 ≠ 落盘）\n")
        raise SystemExit(2)


def load_titles():
    """corpus_id → 作品名（语料**没有章节标题字段**，只有作品名）。

    ⚠️ 口径（H9 已裁，2026-10-28 —— `DECISIONS §4-361`）：语料是按「作品段落跨度」
    切章合成的，因此 `primary_work` 是**作品名**而非章节标题。⇒ 标签不再主张
    「这是章节标题」，生产与会话同改为中性的「来源记录：」+「本片段可能含多章」；
    本脚本只保证**形状同构**（同一行形态），不主张语义正确。
    """
    titles = {}
    if not os.path.isfile(CORPUS_JSONL):
        return titles
    with io.open(CORPUS_JSONL, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            cid = rec.get("corpus_id")
            work = rec.get("primary_work") or rec.get("works") or ""
            if cid and work:
                titles[cid] = work
    return titles



def build_task(chunk, title):
    cid = f"{SHORT[chunk['corpus_id']]}c{chunk['chunk_index'] + 1}"
    # 长度动态读，不写死：写死字符数会在 prompt 每次变更后变成假描述。
    prompt_chars = len(io.open(PROMPT_REF, encoding="utf-8").read())
    criteria_chars = len(io.open(CRITERIA_REF, encoding="utf-8").read())
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
        f"   （{prompt_chars} 字符，**本次运行前刚从生产常量导出**）——含"
        "「片段窗口边界」判读前提 / 块内可自证探针 / 例外情况指引 / 输出格式。"
        "**窗口边界一节优先于其余一切**：你看不到本片段之外的任何内容。\n"
        f"2. **本次注入实验的判据原文**：`{CRITERIA_REF}`\n"
        f"   （{criteria_chars} 字符）——每条含判断原则 / 例外情况 / 诊断锚点。"
        "逐条核对；**判据自带的例外条款请按原文判**（本任务单不预设结论）。"
    )
    lines.append("")
    lines.append("## 待判读文本（本片段全文 · 你只看得到这一片）")
    lines.append("")
    lines.append(
        "**下面这一段就是该模块实际收到的 user 消息全文，逐字复刻**"
        "（含块首注入行，见 `progressive_diagnosis.dart:1350` "
        "`buildChunkUserMessage`）："
    )
    lines.append("")
    # 与生产同形：标题为空则整行省略（生产 `chapters.title` 默认空串）。
    if title:
        lines.append(f"来源记录：{title}（本片段可能含多章）")
        lines.append("")
    lines.append(f"文本片段 {chunk['chunk_index'] + 1}/{chunk['chunk_count']}：")
    lines.append("")
    lines.append(chunk["text"])
    lines.append("")
    lines.append(
        "**不要推测片段外内容**；片段外信息只能把你引向 `uncertain`，"
        "不能把「像是有问题」写成肯定结论。"
    )
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
        "3. **每条判定都按判据原文判**：`hit` 要能指出本片内可指认的位置；"
        "判据自带的例外条款、以及「片段外才能判定」的情形，一律按判据原文处理，"
        "**本任务单不替你预设方向**。\n"
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


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    dry_run = "--dry-run" in argv

    refresh_production_prompt()

    with io.open(CHUNKS, encoding="utf-8") as f:
        chunks = json.load(f)["chunks"]

    titles = load_titles()
    missing = sorted({c["corpus_id"] for c in chunks
                      if c["corpus_id"] not in titles})
    if missing:
        print(f"[build] WARN: {len(missing)} 个 corpus_id 无 primary_work ⇒ "
              f"标题回退为 corpus_id：{', '.join(missing)}")

    if dry_run:
        ch = chunks[0]
        title = titles.get(ch["corpus_id"], ch["corpus_id"])
        cid, task = build_task(ch, title)
        print(f"[build][dry-run] {cid} 预览（前 1600 字）—— 不写任何文件：")
        print(task[:1600])
        return 0

    os.makedirs(TASK_DIR, exist_ok=True)
    os.makedirs(ANSWER_DIR, exist_ok=True)
    for ch in chunks:
        title = titles.get(ch["corpus_id"], ch["corpus_id"])
        cid, task = build_task(ch, title)
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
