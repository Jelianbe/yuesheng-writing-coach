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
    cross-dup       跨文件重复: 同一 ≥20 字句子在 ≥2 个文件出现

用法:
    python3 scripts/check_prompt_antipattern.py                 # 全量扫描
    python3 scripts/check_prompt_antipattern.py --update-baseline   # 将当前命中存为基线
    python3 scripts/check_prompt_antipattern.py --diff-baseline     # 只报相对基线的新增（CI 用）

退出码:
    0 = 无命中（--diff-baseline 时：无新增）
    1 = 有命中（--diff-baseline 时：有新增）
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
    """跨文件重复句：在 ≥2 个文件出现的 ≥20 字句子。"""
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


def main() -> int:
    args = sys.argv[1:]
    update = "--update-baseline" in args
    diff = "--diff-baseline" in args

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
        base_keys = {tuple(x) for v in base.values() for x in v}
        cur_keys = {tuple(x) for v in findings.values() for x in v}
        added = sorted(cur_keys - base_keys)
        removed = base_keys - cur_keys
        if not added:
            print(f"[prompt-lint] 相对基线无新增 ✓（同时消失 {len(removed)} 条，可 --update-baseline 同步）")
            return 0
        print(f"[prompt-lint] 相对基线新增 {len(added)} 条：")
        for rel, lineno, ctx in added:
            print(f"  {rel}:{lineno}  {ctx}")
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
        print(f"\n  ── {rule} ({len(items)}) ──")
        for rel, lineno, ctx in items:
            print(f"    {rel}:{lineno}  {ctx}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
