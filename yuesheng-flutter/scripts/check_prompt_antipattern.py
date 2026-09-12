#!/usr/bin/env python3
"""
月笙 Flutter 端 — Prompt 话术反模式扫描（综合审阅 E.6 / AGENTS.md 四闸配套）。

扫描 lib/services/skills_*.dart 中注入 LLM 的 content 文本，检测会削弱 AI 灵活性
或诱发幻觉的写法。开发者注释（// 与 /// 开头的行）不参与检测。

检测项:
    force-trigger   强制触发: 必须输出 / 每轮都要 / 每次必须 / 必须加载 / 必须追加
    fixed-format    固定格式: 格式：/ 开头用 / 按照以下格式 / 标准话术
    assert-conclude 断言式下结论: 我注意到你 / 你的问题是 / 你有一个
    report-tone     报告腔: 置信度 / 已确认事实 / 验证方法
    cross-dup       跨文件重复: 同一 ≥20 字句子在 ≥2 个文件出现（信息型，非违规）

假阳性抑制（2026-xx 假阳性治理，实测 12 条命中里 11 条为假阳性）:
    report-tone 的三类排除：
      (1) 协议字段 —— 产品诊断块的 JSON schema 键（如 `confidence (number)`），
          「诊断置信度/识别置信度」是产品的核心协议字段，不是报告腔。
      (2) 否定语境 —— 命中词前若有否定词，则该句是在「禁止降置信度」，语义相反。
      (3) 复合协议名词 —— 「症候置信度/诊断置信度/识别置信度/确认置信度」是
          产品的术语整体，词素含「置信度」不代表报告腔。
    assert-conclude 的反例语境排除：命中片段处于 `❌`/`不要`/「说太早」等反例标记
    上下文时，是在示范「禁止的说法」，不是断言式下结论。

cross-dup 语义（2026-xx 修订）:
    跨文件重复句是**有意的教学规则一致性**（同一条规则在 l1_core 与 advanced_outline
    都需引用），属设计要求而非缺陷。因此 cross-dup **不参与 FAIL 判定**：
    --diff-baseline 模式下过滤掉 cross-dup，仅全量报告中作为「跨文件一致性参考」列出。

用法:
    python3 scripts/check_prompt_antipattern.py                 # 全量扫描
    python3 scripts/check_prompt_antipattern.py --update-baseline   # 将当前命中存为基线
    python3 scripts/check_prompt_antipattern.py --diff-baseline     # 只报相对基线的新增（CI 用）
    python3 scripts/check_prompt_antipattern.py --expect-rule-count 4   # 规则数守卫（fail-closed）

退出码:
    0 = 无命中（--diff-baseline 时：无新增）
    1 = 有命中（--diff-baseline 时：有新增；或 --expect-rule-count 不符）
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SERVICES = os.path.join(ROOT, "lib", "services")
BASELINE = os.path.join(ROOT, "scripts", "prompt_antipattern_baseline.json")

# 每条规则: (规则名, 正则)
KEYWORD_RULES = [
    ("force-trigger", r"必须输出|每轮都要|每次必须|必须加载|必须追加"),
    ("fixed-format", r"格式：|开头用|按照以下格式|标准话术"),
    ("assert-conclude", r"我注意到你|你的问题是|你有一个"),
    ("report-tone", r"置信度|已确认事实|验证方法"),
]

# 句子切分：中文句末标点或换行
SENT_SPLIT = re.compile(r"[。！？\n]")
MIN_DUP_LEN = 16

# 规则名 -> 是否为「违规型」。信息型规则（cross-dup）不参与 FAIL 判定。
VIOLATION_RULES = {"force-trigger", "fixed-format", "assert-conclude", "report-tone"}

# ---- 假阳性抑制用常量 ----

# 否定词：命中词前若出现，说明该句是在禁止/规避该词所指行为。
NEGATION_WORDS = ("不要", "禁止", "不得", "不能", "≠", "避免", "无需", "不应")

# 否定词的探测窗口：命中词起始位置之前的字符数。
NEGATION_WINDOW = 30

# report-tone 协议字段的 schema 类型标注（如 `confidence (number)` / `(number|null)`）。
SCHEMA_TYPE_RE = re.compile(r"\(\s*(?:number|string|object|boolean|array)\b")

# 协议字段行：形如 `- confidence (` / `| confidence (` 等 schema 定义行。
PROTOCOL_FIELD_RE = re.compile(r"^\s*[-|>]?\s*\w*\s*confidence\s*\(")

# 复合协议名词：置信度直接前接领域限定词，构成产品术语整体。
PROTOCOL_COMPOUND_RE = re.compile(r"(?:症候|诊断|识别|确认|情绪)置信度")

# assert-conclude 的反例标记：命中片段处于反例说明上下文。
# 除 ❌ 与否定词外，另含「明示反例」的措辞。
COUNTEREXAMPLE_MARKERS = (
    "❌",
    "说太早",
    "反例",
    "错误示范",
    "反面",
)


def _diff_by_text(base, cur):
    """按 (文件, 文本) 计数比对，**行号不参与身份判定**。

    行号不能作身份：prompt 里插入或删除几行，其后所有命中的行号会整体位移，
    于是既有命中全部被误报成"新增"。实测改动 V-03 与 §3.9 两处措辞
    （分别 +6 / +2 行）后，4 条既有命中因位移被报为新增，文本一字未变。

    改为按文本计数：同一文本在当前比基线多出几条，就报几条。行号只用于展示。

    返回项为 (规则名, 文件, 行号, 命中原文) 四元组——规则名必须随条目返回，
    以便调用方按规则区分「违规型」与「信息型」（cross-dup），否则无法正确过滤。
    """
    def multiset(groups):
        out = {}
        for rule, entries in groups.items():
            for rel, lineno, ctx in entries:
                out.setdefault((rule, rel, ctx), []).append(lineno)
        return out

    base_items = multiset(base)
    cur_items = multiset(cur)
    added, removed = [], []
    for key, lines in cur_items.items():
        for lineno in sorted(lines)[len(base_items.get(key, ())):]:
            added.append((key[0], key[1], lineno, key[2]))
    for key, lines in base_items.items():
        for lineno in sorted(lines)[len(cur_items.get(key, ())):]:
            removed.append((key[0], key[1], lineno, key[2]))
    return sorted(added), sorted(removed)


def is_comment(line: str) -> bool:
    """跳过开发者注释——它们不注入 prompt。"""
    s = line.lstrip()
    return s.startswith("//") or s.startswith("///") or s.startswith("*")


# Dart 多行字符串块（content 本体），非贪婪 + DOTALL
CONTENT_BLOCK = re.compile(r"r?'''(.*?)'''", re.DOTALL)


def content_blocks(text: str) -> list[tuple[int, str]]:
    """提取 '''...''' 块，返回 [(块起始行号, 块内容)]。

    只扫描这些块——Dart 代码与开发者注释不注入 prompt，不应产生命中。
    """
    out: list[tuple[int, str]] = []
    for m in CONTENT_BLOCK.finditer(text):
        start_line = text.count("\n", 0, m.start()) + 1
        out.append((start_line, m.group(1)))
    return out


# ---- 假阳性抑制判定函数 ----

def _is_near_negation(line: str, start: int, window: int = NEGATION_WINDOW) -> bool:
    """命中词前 `window` 个字符内是否存在否定词。

    改写自 A1 的「否定语境排除」与 A2 的反例判定，两处复用同一判断函数。
    """
    prefix = line[max(0, start - window):start]
    return any(neg in prefix for neg in NEGATION_WORDS)


def _is_report_tone_fp(line: str, hit_text: str, start: int) -> bool:
    """判定一个 report-tone 命中是否为假阳性（协议字段 / 否定语境 / 复合名词）。

    Args:
        line: 命中所在原文行。
        hit_text: 命中的词（如「置信度」）。
        start: 命中词在行内的起始下标。

    Returns:
        True 表示该命中应被排除（属假阳性）。
    """
    # (1) 协议字段：JSON schema 定义行（含 `confidence (` 或 `(number...)` 类型标注）。
    if PROTOCOL_FIELD_RE.match(line) or SCHEMA_TYPE_RE.search(line):
        return True
    # (1b) 复合协议名词：症候置信度 / 诊断置信度 / 识别置信度 / 确认置信度。
    if PROTOCOL_COMPOUND_RE.search(line[max(0, start - len("情绪")):start + len(hit_text) + 2]):
        return True
    # (2) 否定语境：命中词前有否定词（「不要降低置信度」语义相反）。
    if _is_near_negation(line, start):
        return True
    return False


def _is_counterexample_fp(line: str, start: int, hit_text: str) -> bool:
    """判定一个 assert-conclude 命中是否处于反例说明上下文。

    判据（任一命中即排除）：
      - 命中片段邻近窗口内含 `❌`
      - 含否定词（复用 _is_near_negation）
      - 含「说太早」「反例」「错误示范」「反面」等明示反例措辞
    """
    win_start = max(0, start - 30)
    win_end = min(len(line), start + len(hit_text) + 30)
    window = line[win_start:win_end]
    if any(marker in window for marker in COUNTEREXAMPLE_MARKERS):
        return True
    # 否定词：既看命中词前，也看命中词后的窗口（「不直接说出……」）。
    if _is_near_negation(line, start):
        return True
    return any(neg in window for neg in NEGATION_WORDS)


def scan_file(path: str) -> list[tuple[str, int, str]]:
    """返回 [(规则名, 行号, 命中原文)]。行号为文件真实行号。"""
    hits: list[tuple[str, int, str]] = []
    with open(path, encoding="utf-8") as f:
        text = f.read()
    for base_line, block in content_blocks(text):
        for offset, line in enumerate(block.split("\n")):
            lineno = base_line + offset
            for rule, pattern in KEYWORD_RULES:
                for m in re.finditer(pattern, line):
                    hit_text = m.group(0)
                    # 假阳性抑制：按规则分派。
                    if rule == "report-tone" and _is_report_tone_fp(line, hit_text, m.start()):
                        continue
                    if rule == "assert-conclude" and _is_counterexample_fp(line, m.start(), hit_text):
                        continue
                    start = max(0, m.start() - 25)
                    end = min(len(line), m.end() + 25)
                    ctx = line[start:end].strip()
                    hits.append((rule, lineno, ctx))
    return hits


def collect_sentences(path: str) -> set[str]:
    """提取 content 块中 ≥MIN_DUP_LEN 字的句子。

    归一化处理：占位符 [xxx] 统一替换为 _，去 Markdown 标记与空白，
    使「有一个[问题模式]」与「有一个[问题描述]的模式」这类近义模板能被识别为同源。
    """
    with open(path, encoding="utf-8") as f:
        text = f.read()
    out: set[str] = set()
    for _, block in content_blocks(text):
        norm = re.sub(r"\[[^\]]*\]", "_", block)
        norm = re.sub(r"[>\-\|`#]", " ", norm)
        for seg in SENT_SPLIT.split(norm):
            s = re.sub(r"\s+", "", seg)
            if len(s) < MIN_DUP_LEN:
                continue
            # 跳过元数据头（体积/定位/来源/loadWhen）——它们是样板，重复无意义
            if re.match(r"^(\*\*(体积|定位|来源|loadWhen)\*\*|\d+tokens)", s):
                continue
            out.add(s)
    return out


def scan_cross_dup(files: list[str]) -> list[tuple[str, int, str]]:
    """跨文件重复句：在 ≥2 个文件出现的 ≥20 字句子。

    标注为「跨文件一致性参考，非违规」——属信息型，不参与 FAIL 判定。
    """
    owner: dict[str, set[str]] = {}
    for path in files:
        for s in collect_sentences(path):
            owner.setdefault(s, set()).add(os.path.basename(path))

    hits: list[tuple[str, int, str]] = []
    for s, owners in owner.items():
        if len(owners) < 2:
            continue
        # 定位行号：在第一个文件里找
        for path in files:
            if os.path.basename(path) not in owners:
                continue
            with open(path, encoding="utf-8") as f:
                for lineno, line in enumerate(f, 1):
                    if is_comment(line):
                        continue
                    if re.sub(r"\s+", "", s)[:20] in re.sub(r"\s+", "", line):
                        hits.append(
                            ("cross-dup", lineno, f"{s[:40]}… (另见于 {', '.join(sorted(owners - {os.path.basename(path)}))})")
                        )
                        break
            break  # 每个重复句只报一次
    return hits


def _parse_expect_rule_count(args: list[str]) -> tuple[int | None, int | None]:
    """从 argv 解析 --expect-rule-count N。返回 (值, 错误退出码)。

    支持 `--expect-rule-count 4` 与 `--expect-rule-count=4` 两种写法。
    值缺失或非整数 → 返回 (None, 1) 表示参数错误。
    """
    for i, a in enumerate(args):
        if a == "--expect-rule-count":
            if i + 1 >= len(args):
                print("RULE COUNT GUARD FAIL: --expect-rule-count requires a value",
                      file=sys.stderr)
                return None, 1
            raw = args[i + 1]
        elif a.startswith("--expect-rule-count="):
            raw = a.split("=", 1)[1]
        else:
            continue
        try:
            return int(raw), None
        except ValueError:
            print(f"RULE COUNT GUARD FAIL: --expect-rule-count value not an integer: {raw!r}",
                  file=sys.stderr)
            return None, 1
    return None, None


def main() -> int:
    args = sys.argv[1:]
    update = "--update-baseline" in args
    diff = "--diff-baseline" in args

    # 规则数守卫（fail-closed）：防规则被静默删减。
    expect_rule_count, guard_err = _parse_expect_rule_count(args)
    if guard_err is not None:
        return guard_err
    if expect_rule_count is not None:
        got = len(KEYWORD_RULES)
        if got != expect_rule_count:
            print(f"RULE COUNT GUARD FAIL: expected {expect_rule_count}, got {got}")
            return 1

    if not os.path.isdir(SERVICES):
        print(f"找不到目录: {SERVICES}", file=sys.stderr)
        return 1

    files = sorted(
        os.path.join(SERVICES, f)
        for f in os.listdir(SERVICES)
        if f.startswith("skills_") and f.endswith(".dart")
    )

    findings: dict[str, list[list]] = {}
    for path in files:
        rel = os.path.relpath(path, ROOT)
        for rule, lineno, ctx in scan_file(path):
            findings.setdefault(rule, []).append([rel, lineno, ctx])
    for rule, lineno, ctx in scan_cross_dup(files):
        # cross-dup 的行号定位是近似，统一挂在第一个文件上，这里改用文件级提示
        findings.setdefault(rule, []).append(["(跨文件)", lineno, ctx])

    total = sum(len(v) for v in findings.values())

    if update:
        with open(BASELINE, "w", encoding="utf-8") as f:
            json.dump(findings, f, ensure_ascii=False, indent=2)
        print(f"[prompt-lint] 基线已写入 {os.path.relpath(BASELINE, ROOT)}（{total} 条命中）")
        return 0

    if diff:
        if not os.path.exists(BASELINE):
            print("[prompt-lint] 无基线，请先运行 --update-baseline", file=sys.stderr)
            return 1
        with open(BASELINE, encoding="utf-8") as f:
            base = json.load(f)
        added, removed = _diff_by_text(base, findings)
        # cross-dup 属信息型（有意的跨文件一致性），不参与 FAIL 判定。
        added_viol = [x for x in added if x[0] in VIOLATION_RULES]
        cross_dup_added = [x for x in added if x[0] == "cross-dup"]
        if cross_dup_added:
            print(f"[prompt-lint] 跨文件一致性参考 {len(cross_dup_added)} 条（非违规，不阻断）：")
            for rule, rel, lineno, ctx in cross_dup_added:
                print(f"  {rel}:{lineno}  {ctx}")
        if not added_viol:
            print(f"[prompt-lint] 相对基线无新增 ✓（同时消失 {len(removed)} 条，可 --update-baseline 同步）")
            return 0
        print(f"[prompt-lint] 相对基线新增 {len(added_viol)} 条：")
        for rule, rel, lineno, ctx in added_viol:
            print(f"  [{rule}] {rel}:{lineno}  {ctx}")
        return 1

    # 全量报告
    if total == 0:
        print("[prompt-lint] 未检测到话术反模式 ✓")
        return 0
    print(f"[prompt-lint] 共 {total} 条命中：")
    for rule in ["force-trigger", "fixed-format", "assert-conclude", "report-tone", "cross-dup"]:
        items = findings.get(rule, [])
        if not items:
            continue
        suffix = "（跨文件一致性参考，非违规）" if rule == "cross-dup" else ""
        print(f"\n  ── {rule} ({len(items)}){suffix} ──")
        for rel, lineno, ctx in items:
            print(f"    {rel}:{lineno}  {ctx}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
