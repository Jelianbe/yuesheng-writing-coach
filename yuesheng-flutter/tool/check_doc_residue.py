"""文档「已推翻前提」残留扫描器（通用版）。

用途：方案文档里某个前提被推翻后，正文常残留以该错前提成立的句子。
本脚本按「错误关键短语」扫全文，并要求：命中必须落在**合法语境**内
（作废说明块 / 修订记录删除线 / 更正标注 / 引用原文）。

背景（2026-09-13 实证）：同一轮里连续 2 次「以为改了、实际没落盘」。
纪律化为脚本 —— 改完必须跑出「非法命中 = 0」，不许凭记忆说"改过了"。

⚠️ 口径声明（QA 第四轮终检建议）：本脚本**由主理人自跑，属"自证"**。
**残留检查以 QA 的独立 Grep 为权威口径**，本脚本仅作日常自查 / CI 兜底。

用法：
    python tool/check_doc_residue.py                      # 扫内置目标 + 内置模式
    python tool/check_doc_residue.py --strict             # CI 口径：零命中才通过
    python tool/check_doc_residue.py <file> <pat1> ...    # 自定义

判定：
    默认模式 —— 把每个命中行分类为 LEGAL（合法）或 !!CHECK（需人工确认）。
    --strict  —— **只有命中 0 条才算通过**（连 LEGAL 也不接受）。
                  用于 CI：迫使"清理到彻底"，而非依赖白名单判断。

退出码：存在 !!CHECK（默认）或存在任何命中（--strict）→ 1；否则 0。
"""

import io
import re
import sys

# 合法语境标记：命中行里出现这些词，视为「在讲作废/更正这件事本身」
LEGAL_MARKERS = (
    '⛔', '~~', '作废', '已推翻', '更正', '修正', '收敛', '更换立论',
    '遗留', '原写', '原文写', '旧文本', '第一轮', '第二轮', 'V2.3', 'V2.4',
    '不得', '勿再', '误读', '不准确', '亦不准', '不算', '前提', '教训',
    '不是', '非死代码', '不成立', '删', '归档', '背景', '引用',
    # 续行/引用原文：解释「错的原文长什么样」的行，往往以引号、箭头、括号开头
    '」', '）', '**是错的**', '已改为', '原句', '本句', '此表述', '该表述',
    '仅在', '现称',
)

# 默认目标：本轮涉及的方案文档
DEFAULT_TARGETS = [
    'docs/designs/2026-09-13-ia-refactor-architecture.md',
    'docs/designs/2026-09-13-ia-refactor-prd.md',
    'docs/research/2026-09-13-code-recon-for-ia-refactor.md',
    'docs/class-diagram.mermaid',
    'docs/sequence-diagram.mermaid',
]

# 默认模式：被推翻的平台/结构前提的"幽灵关键词"
DEFAULT_PATTERNS = [
    '嵌套在 _AppShell',
    '天然位于全局',
    '空间竞争',
    '不再嵌套',
    '三 Tab 之上',
    '资源栏(常驻)',
    '写作 / 成长',
    '这台桌面 App',
    '死代码',
    '不可达代码',
    'position_不再 global',
]


def classify(line: str) -> str:
    return 'LEGAL' if any(m in line for m in LEGAL_MARKERS) else '!!CHECK'


def scan(path: str, patterns, strict: bool = False) -> int:
    """返回『问题条数』（strict 下任何命中都算问题，否则只算 !!CHECK）。"""
    try:
        lines = io.open(path, encoding='utf-8').read().split('\n')
    except OSError as e:
        print(f'  [跳过] {path} — {e}')
        return 0
    hits = 0
    bad = 0
    print(f'=== {path} ({len(lines)} 行) ===')
    for i, ln in enumerate(lines, 1):
        for pat in patterns:
            if re.search(pat, ln):
                hits += 1
                kind = classify(ln)
                if strict or kind == '!!CHECK':
                    bad += 1
                print(f'  {kind} L{i} [{pat}] {ln.strip()[:130]}')
                break
    if hits == 0:
        print('  ✓ 零命中')
    print(f'  → 命中 {hits} 条，其中{"需处理的" if strict else "需人工确认的"} {bad} 条')
    return bad


def main() -> int:
    argv = [a for a in sys.argv[1:]]
    strict = '--strict' in argv
    argv = [a for a in argv if a != '--strict']

    if argv:
        targets = [argv[0]]
        patterns = argv[1:] or DEFAULT_PATTERNS
    else:
        targets = DEFAULT_TARGETS
        patterns = DEFAULT_PATTERNS

    mode = 'STRICT（CI 口径：零命中才通过）' if strict else '日常自查（允许作废语境）'
    print(f'模式：{mode}\n')

    total_bad = 0
    for t in targets:
        total_bad += scan(t, patterns, strict)

    print()
    if total_bad:
        print(f'❌ 存在 {total_bad} 条需处理项 —— 逐条判定/清理后再声称"已完成"。')
        print('   注：权威口径以 QA 的独立 Grep 为准，本脚本仅作自查兜底。')
        return 1
    print('✅ 无残留（合法语境判定通过）。')
    print('   注：权威口径以 QA 的独立 Grep 为准，本脚本仅作自查兜底。')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
