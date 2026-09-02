#!/usr/bin/env python3
"""
月笙 Flutter 端 — Skill 一致性家族扫描（只读分析工具，advisory）。

背景：综合审阅台账 N1~N38 与 C 系列发现，绝大多数缺陷落在可静态枚举的
「家族」里（副本漂移 / 阈值冲突 / 枚举一致性 / 引用完整性 / Schema 字段 /
指令冲突对）。本脚本对 lib/services/skills_*.dart 的 prompt 文本做全量
家族式扫描，一次产出完整候选清单，取代逐点 worker 采样式发现。

真源（代码侧，动态解析，不硬编码值）：
    - 相位/新手层/教学方式/严重度白名单  lib/services/diagnosis_parser.dart
    - 症候 ID                            lib/services/syndrome_registry*.dart
    - 技法 ID                            lib/services/technique_kb_content*.dart
    - 诊断块 JSON 字段                    lib/services/diagnosis_parser.dart

检测项（家族）:
    enum-doc        枚举文档缺漏: prompt「取值 A/B/C」清单 vs 代码白名单
    enum-token      非法枚举值: prompt 中出现白名单外的枚举 token（解析器会静默丢弃）
    threshold       阈值冲突候选: 同主题同单位的数字断言出现 ≥2 个不同值
    copy-drift      副本漂移: 跨文件近似重复的规则句（V-05 家族）
    ref-integrity   引用完整性: 「见 X / [skill-id] / §N.M」目标不存在
    schema-field    Schema 字段一致性: prompt 文档字段 vs 解析器实际读取字段
    conflict-pair   指令冲突对候选: 同一主题同时存在相反极性的指令

用法:
    python scripts/skill_consistency_scan.py            # 全量扫描（advisory，恒 exit 0）
    python scripts/skill_consistency_scan.py --json OUT # 同时输出 JSON 机器可读报告

注意：本工具是「候选生成器」不是「判决器」——threshold/conflict-pair 的输出
必须经人工裁决（哪些是真冲突、哪些是有意的设计分层）。
"""
import difflib
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SERVICES = os.path.join(ROOT, "lib", "services")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# ───────────────────────── 基础设施 ─────────────────────────

CONTENT_BLOCK = re.compile(r"r?'''(.*?)'''", re.DOTALL)


def content_blocks(text: str):
    """提取 '''...''' prompt 块，返回 [(块起始行, 块内容)]。与
    check_prompt_antipattern.py 同款提取方式。"""
    out = []
    for m in CONTENT_BLOCK.finditer(text):
        start_line = text.count("\n", 0, m.start()) + 1
        out.append((start_line, m.group(1)))
    return out


class PromptLine:
    __slots__ = ("file", "lineno", "text")

    def __init__(self, file, lineno, text):
        self.file = file
        self.lineno = lineno
        self.text = text

    @property
    def loc(self):
        return f"{self.file}:{self.lineno}"

    def __repr__(self):
        return f"<{self.loc} {self.text[:30]}>"


PROMPT_FILE_PAT = re.compile(
    r"(skills_.*|syndrome_kb_content.*|technique_kb_content.*)\.dart$")


def load_prompt_lines():
    """全部注入 prompt 的 dart 数据分片行（含真实行号）：
    skills_*（skill 注册表分片）+ syndrome_kb_content*（L2/L3 症候库文本）
    + technique_kb_content*（L2/L3 技法库文本）。"""
    lines = []
    files = sorted(f for f in os.listdir(SERVICES) if PROMPT_FILE_PAT.match(f))
    for fname in files:
        with open(os.path.join(SERVICES, fname), encoding="utf-8") as f:
            text = f.read()
        for base_line, block in content_blocks(text):
            for offset, line in enumerate(block.split("\n")):
                lines.append(PromptLine(fname, base_line + offset, line))
    return lines


def read(rel: str) -> str:
    with open(os.path.join(SERVICES, rel), encoding="utf-8") as f:
        return f.read()


# ───────────────────────── 代码侧真源解析 ─────────────────────────

#: (扫描器内部族名, diagnosis_parser.dart 常量名, 基线取值个数)
#:
#: 常量名**前缀下划线可选**：N19 把 phase / beginner 两组由 `_kValidXxx`
#: 改为公开 `kValidXxx`（供 test/services/enum_consistency_test.dart 引用），
#: 扫描器必须同时认两种写法，否则该族白名单会被**静默**解析成空集。
WHITELIST_KEYS = [
    ("phase", "kValidPhases", 5),
    ("beginner", "kValidBeginnerLevels", 5),
    ("mode", "kValidTeachingModes", 4),
    ("severity", "kValidSeverities", 3),
]


def parse_whitelists():
    """从 diagnosis_parser.dart 解析四组枚举白名单。

    任一族解析为空集时**直接中止**（raise SystemExit），不静默降级。
    静默降级会让 enum-token 把全部合法取值报成「不在白名单」，
    比不扫描更糟。N19 落地时真实踩过一次：改名后本函数解析不到 phase /
    beginner 两族，白名单总数由 19 掉到 7，enum-token 一次性冒出 45 条
    假阳性，而脚本仍 exit 0 —— 这就是为什么这里改成硬失败。数字对账：
    正常 17 值（5 phase + 5 beginner + 4 mode + 3 severity），踩坑时掉到 7。
    """
    src = read("diagnosis_parser.dart")
    wl = {}
    for name, key, expect in WHITELIST_KEYS:
        m = re.search(r"_{0,1}" + key + r"\s*=\s*\[(.*?)\]", src, re.DOTALL)
        values = set(re.findall(r"'([^']+)'", m.group(1))) if m else set()
        if not values:
            raise SystemExit(
                f"[skill-consistency-scan] FATAL: 白名单 {key} 解析为空集。"
                "diagnosis_parser.dart 里该常量改名或改结构了？"
                "（本工具虽为 advisory，但白名单缺失会造成大面积假阳性，故中止）"
            )
        if expect and len(values) != expect:
            print(f"[skill-consistency-scan] WARN: {key} 取值 {len(values)} 个，"
                  f"基线为 {expect} 个：{sorted(values)}")
        wl[name] = values
    return wl


def parse_syndrome_ids():
    """syndrome_registry*.dart: {id: retired?}，另返回历史合并映射
    （'P001': 'P004' 形式的 merged-into 表）。"""
    out, merged = {}, {}
    for fname in sorted(f for f in os.listdir(SERVICES)
                        if re.match(r"syndrome_registry(_p\d)?\.dart$", f)):
        src = read(fname)
        for rec in re.finditer(r"SyndromeRecord\((.*?)\n\s*\)", src, re.DOTALL):
            body = rec.group(1)
            mid = re.search(r"id:\s*'([^']+)'", body)
            if not mid:
                continue
            retired = "retired:" in body and "retired: null" not in body
            out[mid.group(1)] = retired
        # 历史合并映射（kMergedSyndromeIds 之类）：'P001': 'P004'
        for m in re.finditer(r"'(P\d{3})'\s*:\s*'(P\d{3})'", src):
            a, b = m.group(1), m.group(2)
            if a != b and b in out:
                merged[a] = b
    return out, merged


def parse_technique_ids(prompt_lines):
    """教学动作 A-ID 真源：skills_training_p4.dart 方法目录的 '### Axxx' 标题
    （prompt 块内）。"""
    out = set()
    for ln in prompt_lines:
        m = re.match(r"###\s+(A\d{3})\s", ln.text)
        if m:
            out.add(m.group(1))
    return out


def parse_parser_fields():
    """diagnosis_parser.dart 中 obj['x'] / teachingPlan['x'] / s['x'] 实际读取字段。"""
    src = read("diagnosis_parser.dart")
    top = set(re.findall(r"obj\['(\w+)'\]", src))
    plan = set(re.findall(r"teachingPlan\['(\w+)'\]", src))
    syn = set(re.findall(r"\bs\['(\w+)'\]", src))
    return top, plan, syn


def parse_skill_ids():
    """skill 全量: (id 集合, SKILL 标题集合)。含 skill_registry.dart 本体
    （虚拟索引 skill 的 id 定义在那里，不在 part 文件）。"""
    ids, titles = set(), set()
    fnames = [f for f in os.listdir(SERVICES)
              if f.startswith("skills_") and f.endswith(".dart")]
    fnames.append("skill_registry.dart")
    for fname in sorted(fnames):
        src = read(fname)
        ids.update(re.findall(r"id:\s*'([\w-]+)'", src))
        titles.update(re.findall(r"#\s*SKILL:\s*(.+)", src))
    return ids, titles


# ───────────────────────── 检查 1/2: 枚举一致性 ─────────────────────────

def check_enum_doc(lines, wl):
    """prompt「取值 A / B / C」文档 vs 代码白名单。"""
    findings = []
    pat = re.compile(r"取值[:：]?\s*([A-Z][A-Z0-9_]*(?:\s*/\s*[A-Z][A-Z0-9_]*)+)")
    family_of = {}
    for fam, values in wl.items():
        for v in values:
            family_of[v] = fam
    for ln in lines:
        for m in pat.finditer(ln.text):
            tokens = [t.strip() for t in m.group(1).split("/")]
            fams = {family_of.get(t) for t in tokens}
            fams.discard(None)
            if len(fams) != 1:
                continue  # 混合或未知族，交给 enum-token 报
            fam = fams.pop()
            doc, truth = set(tokens), wl[fam]
            for v in sorted(doc - truth):
                findings.append(("enum-doc", ln.loc,
                                 f"「取值」文档列出 {v}，但代码白名单（diagnosis_parser.dart）无此值——"
                                 f"模型若照填会被静默丢弃"))
            for v in sorted(truth - doc):
                findings.append(("enum-doc", ln.loc,
                                 f"「取值」文档只列 {sorted(doc)}，白名单还有 {v} 未列入——"
                                 f"模型不知道可以填（N21 同型）"))
    return findings


def check_enum_token(lines, wl, syndromes, merged, techniques):
    """prompt 中出现但不在任何真源里的枚举 token。"""
    findings = []
    token_pat = re.compile(r"\b(P[0-4]_[A-Z_]{3,}|N[0-4]_[A-Z_]{3,})\b")
    for ln in lines:
        for m in token_pat.finditer(ln.text):
            t = m.group(0)
            fam = "phase" if t.startswith("P") and "_" in t and t[1].isdigit() else "beginner"
            if t not in wl.get(fam, set()):
                findings.append(("enum-token", ln.loc,
                                 f"枚举 token {t} 不在 {fam} 白名单（解析器会丢弃整个字段值）"))
    for ln in lines:
        for m in re.finditer(r"\b([PA]\d{3})\b", ln.text):
            t = m.group(1)
            if t.startswith("P"):
                if t in merged:
                    if re.search(r"含原|原.*子[类症]", ln.text):
                        continue  # 「P004（含原 P001 子类型）」式历史标注，良性
                    findings.append(("enum-token", ln.loc,
                                     f"症候 ID {t} 是历史合并 ID（已并入 {merged[t]}），"
                                     f"prompt 仍在引用旧号"))
                elif t not in syndromes:
                    findings.append(("enum-token", ln.loc,
                                     f"症候 ID {t} 不在 syndrome_registry（39 条真源）里"))
                elif syndromes[t]:
                    findings.append(("enum-token", ln.loc,
                                     f"症候 ID {t} 已退役（retired），prompt 仍在引用"))
            else:
                if t not in techniques:
                    findings.append(("enum-token", ln.loc,
                                     f"教学动作 ID {t} 不在方法目录"
                                     f"（skills_training_p4.dart '### Axxx'）真源里"))
    return findings


# ───────────────────────── 检查 3: 阈值冲突 ─────────────────────────

TOPIC_VOCAB = [
    "症候", "问题", "数量", "上限", "草稿", "展示", "文本", "字数", "追问",
    "诊断块", "附加", "升档", "降档", "证据", "引用", "原文", "练习", "训练",
    "反馈", "句子", "段落", "钩子", "严重度", "置信度", "轮", "教学计划",
    "重叠", "修改", "比喻", "对话", "描写", "伏笔",
]

NUM_PAT = re.compile(
    r"(?<![\w])(\d+)\s*[-~到至]\s*(\d+)\s*(字|个|条|轮|次|处|遍|句|段|%)"
    r"|(?<![\w])(\d+)\s*(?:\+|多|个以上|个及以上)?\s*(字|个|条|轮|次|处|遍|句|段|%)")


def check_threshold(lines):
    """同主题同单位的数字断言出现 ≥2 个不同值 → 冲突候选。
    每个数字断言按窗口内命中的每个主题词各发射一次（多射），
    使「字数阈值」这类家族能聚进同一桶交人工裁决。"""
    findings = []
    buckets = defaultdict(lambda: defaultdict(list))
    for ln in lines:
        for m in NUM_PAT.finditer(ln.text):
            if m.group(1):
                val, unit = f"{m.group(1)}-{m.group(2)}", m.group(3)
            else:
                val, unit = m.group(4), m.group(5)
            s = max(0, m.start() - 45)
            window = ln.text[s:m.end() + 25]
            topics = [w for w in TOPIC_VOCAB if w in window]
            if not topics:
                continue  # 无主题锚点的数字（如百分比修辞）不聚类
            for key in topics[:3]:
                buckets[(key, unit)][val].append(ln)

    for (topic, unit), vals in sorted(buckets.items()):
        if len(vals) < 2:
            continue
        parts = []
        for val, locs in sorted(vals.items(), key=lambda x: x[0]):
            parts.append(f"{val}{unit} ×{len(locs)} @ {locs[0].loc}"
                         + (f" 等 {len(locs)} 处" if len(locs) > 1 else ""))
        findings.append(("threshold", "; ".join(f"{l.loc}" for l in
                        [v[1][0] for v in sorted(vals.items())]),
                         f"主题「{topic}」单位「{unit}」存在 {len(vals)} 个不同值: "
                         + " | ".join(parts) + " ——需人工裁决是否冲突或有意分层"))
    return findings


# ───────────────────────── 检查 4: 副本漂移 ─────────────────────────

RULE_MARK = re.compile(r"必须|严禁|禁止|不得|不要|应当|务必|只能|一律|不允许|不可")
NORM_STRIP = re.compile(r"[\s>\-\|`#*「」『』()（）:：,，。、;;！？\"'→]")


def _norm_rule(s: str) -> str:
    return NORM_STRIP.sub("", s)


def _bigrams(s: str) -> set:
    return {s[i:i + 2] for i in range(len(s) - 1)}


def check_copy_drift(lines, min_len=9):
    findings = []
    rules = []
    seen_exact = {}
    for ln in lines:
        if not RULE_MARK.search(ln.text):
            continue
        norm = _norm_rule(ln.text)
        if len(norm) < min_len:
            continue
        if norm in seen_exact:
            if seen_exact[norm].file != ln.file:
                findings.append(("copy-drift", f"{seen_exact[norm].loc} ↔ {ln.loc}",
                                 f"规则句逐字重复: {ln.text.strip()[:60]}"))
            continue
        seen_exact[norm] = ln
        rules.append((ln, norm))

    # 模糊近似: 2-gram Jaccard ≥0.72（不同文件之间才报）
    by_file = defaultdict(list)
    for ln, norm in rules:
        by_file[ln.file].append((ln, norm, _bigrams(norm)))

    files = sorted(by_file)
    reported = set()
    for i, fa in enumerate(files):
        for fb in files[i + 1:]:
            for la, na, ba in by_file[fa]:
                for lb, nb, bb in by_file[fb]:
                    key = (na[:20], nb[:20])
                    if key in reported:
                        continue
                    inter = len(ba & bb)
                    if not inter:
                        continue
                    j = inter / len(ba | bb)
                    if j >= 0.72 and na != nb:
                        ratio = difflib.SequenceMatcher(None, na, nb).ratio()
                        if ratio >= 0.75:
                            reported.add(key)
                            findings.append(("copy-drift",
                                             f"{la.loc} ↔ {lb.loc}",
                                             f"规则句近似重复（相似度 {ratio:.0%}，V-05 家族特征）:\n"
                                             f"        A: {la.text.strip()[:70]}\n"
                                             f"        B: {lb.text.strip()[:70]}"))
    return findings


# ───────────────────────── 检查 5: 引用完整性 ─────────────────────────

def check_ref_integrity(lines, skill_ids, skill_titles):
    findings = []
    # [skill-id] 形式引用（排除协议大写标记）
    for ln in lines:
        for m in re.finditer(r"\[([a-z][a-z0-9-]{2,})\]", ln.text):
            ref = m.group(1)
            if ref not in skill_ids and ref not in skill_titles:
                findings.append(("ref-integrity", ln.loc,
                                 f"方括号引用 [{ref}] 未命中任何 skill id/标题——"
                                 f"若意图是引用 skill，则是断链"))
    # §N.M 节引用：仅检查「见/详见/参考/遵循/按 §N」式活引用；
    # 来源标注行（> **来源**: xxx.md §N）与章节叙述（第51章）不算断链。
    headings = set()
    for ln in lines:
        for m in re.finditer(r"^#{2,4}\s+([0-9]+(?:\.[0-9]+)*)", ln.text):
            headings.add(m.group(1))
        for m in re.finditer(r"^#{2,4}\s+([一二三四五六七八九十]+)、", ln.text):
            headings.add(m.group(1))
    for ln in lines:
        stripped = ln.text.lstrip()
        if stripped.startswith(">"):
            continue  # 来源/loadWhen 标注行，非活引用
        for m in re.finditer(
                r"(?:见|详见|参考|遵循|按)\s*§\s*([0-9]+(?:\.[0-9]+)*)", ln.text):
            if m.group(1) not in headings:
                findings.append(("ref-integrity", ln.loc,
                                 f"节引用 §{m.group(1)} 未在全部 prompt 标题中找到"
                                 f"（注意 part 分片跨文件拼接，此为全库级检查）"))
    return findings


# ───────────────────────── 检查 6: Schema 字段 ─────────────────────────

def check_schema_field(lines):
    findings = []
    top_fields, plan_fields, syn_fields = parse_parser_fields()
    style_fields = {"sensory", "rhythm", "narrative_distance", "tone_texture",
                    "structure", "summary", "confidence"}
    doc_pat = re.compile(r"^[\s*-]*(\w+)\s*\((?:string|number|array|object|bool|null)")
    doc_top, doc_plan, doc_style, doc_syn = set(), set(), set(), set()
    for ln in lines:
        m = doc_pat.match(ln.text)
        if not m:
            continue
        f = m.group(1)
        indent = len(ln.text) - len(ln.text.lstrip())
        if f in syn_fields:
            doc_syn.add(f)
        elif indent >= 2 and f in style_fields:
            doc_style.add(f)
        elif indent >= 2 and f in plan_fields:
            doc_plan.add(f)
        else:
            doc_top.add(f)

    for f in sorted(doc_top - top_fields):
        findings.append(("schema-field", "-",
                         f"prompt 文档字段 {f} 未被 diagnosis_parser 读取——死字段（模型填了也白填）"))
    for f in sorted(top_fields - doc_top):
        findings.append(("schema-field", "-",
                         f"解析器读取字段 {f} 未在 prompt JSON 字段说明中文档化——未声明字段"))
    for f in sorted(doc_plan - plan_fields):
        findings.append(("schema-field", "-",
                         f"prompt 文档的 teaching_plan 子字段 {f} 不被解析器读取"))
    for f in sorted(plan_fields - doc_plan):
        findings.append(("schema-field", "-",
                         f"解析器读取 teaching_plan.{f}，prompt 未文档化"))
    for f in sorted(doc_style - style_fields):
        findings.append(("schema-field", "-",
                         f"prompt 文档的 style_profile 子字段 {f} 不被解析器读取"))
    for f in sorted(style_fields - doc_style):
        findings.append(("schema-field", "-",
                         f"解析器读取 style_profile.{f}，prompt 未文档化"))
    return findings


# ───────────────────────── 检查 7: 指令冲突对 ─────────────────────────

SUBJECTS = [
    "suggested_phase", "suggested_beginner_level", "teaching_plan",
    "style_profile", "teaching_mode", "诊断块", "附加", "severity",
    "严重度", "教学计划", "症候数量", "问题数量", "数量", "症候",
]
POS = r"必须|务必|必填|都要|就要|应当|需要|须|必附加|迁移动作|最多|不超过|上限|封顶"
NEG = (r"不要|不得|禁止|严禁|不能|避免|无需|不必|可选|仅当|仅在|不输出|不填"
       r"|不附加|不限制|不限")


def check_conflict_pair(lines):
    """同一主题词附近（±30 字符）同时出现相反极性指令 → 冲突对候选。
    主题词与极性标记必须邻近，避免跨句误配。"""
    findings = []
    buckets = defaultdict(lambda: defaultdict(list))
    for ln in lines:
        t = ln.text
        if not (RULE_MARK.search(t) or re.search(r"填|附加|迁移动作|数量|上限", t)):
            continue
        for subj in SUBJECTS:
            idx = t.find(subj)
            if idx == -1:
                continue
            # 邻近窗口：主题词前后 30 字符内找极性标记
            lo, hi = max(0, idx - 30), min(len(t), idx + len(subj) + 30)
            window = t[lo:hi]
            if re.search(NEG, window):
                buckets[subj]["neg/cond"].append(ln)
            elif re.search(POS, window):
                buckets[subj]["pos"].append(ln)
    for subj, pol in sorted(buckets.items()):
        keys = set(pol)
        if len(keys) < 2:
            continue
        locs = []
        for pol_key in sorted(keys):
            for l in pol[pol_key][:4]:
                locs.append(f"[{pol_key}] {l.loc}: {l.text.strip()[:55]}")
        findings.append(("conflict-pair", " / ".join(
            l.loc for ls in pol.values() for l in ls[:2]),
            f"主题「{subj}」同时存在相反极性指令（需人工裁决）:\n        "
            + "\n        ".join(locs)))
    return findings


# ───────────────────────── 主流程 ─────────────────────────

CHECKS_ORDER = ["enum-doc", "enum-token", "threshold", "copy-drift",
                "ref-integrity", "schema-field", "conflict-pair"]


def main():
    args = sys.argv[1:]
    json_out = None
    if "--json" in args:
        json_out = args[args.index("--json") + 1]

    lines = load_prompt_lines()
    wl = parse_whitelists()
    syndromes, merged = parse_syndrome_ids()
    techniques = parse_technique_ids(lines)
    skill_ids, skill_titles = parse_skill_ids()

    all_findings = []
    all_findings += check_enum_doc(lines, wl)
    all_findings += check_enum_token(lines, wl, syndromes, merged, techniques)
    all_findings += check_threshold(lines)
    all_findings += check_copy_drift(lines)
    all_findings += check_ref_integrity(lines, skill_ids, skill_titles)
    all_findings += check_schema_field(lines)
    all_findings += check_conflict_pair(lines)

    grouped = defaultdict(list)
    for check, loc, msg in all_findings:
        grouped[check].append((loc, msg))

    print(f"[skill-consistency-scan] 扫描 {len(lines)} 行 prompt 文本，"
          f"真源: 白名单 {sum(len(v) for v in wl.values())} 值 / "
          f"症候 {len(syndromes)} / 技法 {len(techniques)} / "
          f"skill {len(skill_ids)} —— 共 {len(all_findings)} 条候选\n")

    for check in CHECKS_ORDER:
        items = grouped.get(check, [])
        print(f"── {check} ({len(items)}) ──")
        for loc, msg in items:
            print(f"  {loc}\n      {msg}" if "\n" in msg else f"  {loc}  {msg}")
        print()

    if json_out:
        with open(json_out, "w", encoding="utf-8") as f:
            json.dump({c: grouped.get(c, []) for c in CHECKS_ORDER},
                      f, ensure_ascii=False, indent=1)
        print(f"JSON 报告已写入 {json_out}")
    return 0  # advisory 工具，恒 0


if __name__ == "__main__":
    sys.exit(main())
