#!/usr/bin/env python3
"""内容增减规范 V1.0 §3.3 —— 元数据头 advisory 巡检。

只校验「带元数据头的条目」：九个必填字段是否齐全、是否有空值占位。
存量内容无头 = 零命中（存量豁免，与门禁 5 止血模式同一逻辑——只管新增，不追溯）。

用法：
    python scripts/check_content_metadata.py               # 扫默认内容分片（advisory）
    python scripts/check_content_metadata.py --strict      # 有 finding 时退出码 1（晋升硬卡口后用）
    python scripts/check_content_metadata.py --file <path> # 只扫单个文件（脚本自身变异验证用）

退出码：0 = advisory 通过或无 finding；1 = --strict 且有 finding；2 = 环境错误（失败关闭，
绝不因路径/编码问题静默放行——AGENTS.md V4.15）。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# 九个必填字段（内容增减规范-V1.0 §3.2；顺序即规范顺序）
REQUIRED_FIELDS = [
    "归属组件",
    "加载范围",
    "依赖数据",
    "数据缺失兜底",
    "引用目标",
    "冲突与优先级",
    "副本登记",
    "示例标注",
    "校验方式",
]

# 空值占位：写了等于没写（规范 §3.2：无内容写「无」，「无」本身合法）
PLACEHOLDERS = {"", "todo", "tbd", "待定", "待补", "待写", "-"}

# 默认扫描的内容分片（相对仓库根；与规范 §3.3 口径一致）
DEFAULT_PATTERNS = [
    "lib/services/skills_*.dart",
    "lib/services/*_knowledge_base.dart",
    "lib/services/syndrome_*.dart",
    "lib/services/skill_registry.dart",
    "lib/services/skill_layers.dart",
    "lib/services/progressive_diagnosis.dart",
]

# 头起始行：`// ### <内容ID> · <一句话职责>`（规范 §3.1 存放约定：Dart 注释）
HEADER_PREFIX = "###"


def find_repo_root(start: Path) -> Path:
    """从脚本位置向上找仓库根（以 scripts/ 或 yuesheng-flutter/ 为标志）。"""
    for p in [start, *start.parents]:
        if (p / "pubspec.yaml").exists() or (p / "AGENTS.md").exists():
            return p
    return start


def parse_headers(text: str):
    """解析一个 dart 文件里的全部元数据头。

    返回 [(header_line_no, header_id, {字段: (值, 行号)}, 问题行号列表)]。
    头块 = 起始行 + 其后连续的注释行（允许空注释行）；遇非注释行即终止。
    """
    lines = text.splitlines()
    headers = []
    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        if stripped.startswith("//") and HEADER_PREFIX in stripped:
            # 形如 `// ### id · desc` 或 `/// ### id · desc`
            after = stripped.lstrip("/").strip()
            if after.startswith(HEADER_PREFIX):
                header_id = after[len(HEADER_PREFIX):].strip()
                fields: dict[str, tuple[str, int]] = {}
                table_seen = False
                j = i + 1
                while j < len(lines):
                    row = lines[j].strip()
                    if not row.startswith("//"):
                        break
                    content = row.lstrip("/").strip()
                    if not content:
                        j += 1
                        continue
                    if content.startswith("|"):
                        table_seen = True
                        cells = [c.strip() for c in content.strip("|").split("|")]
                        if len(cells) >= 2 and cells[0] not in ("字段", ":--", "---"):
                            name = cells[0].lstrip(":").strip()
                            if name in REQUIRED_FIELDS:
                                if name in fields:
                                    fields[name] = ("<<重复>>", j + 1)
                                else:
                                    fields[name] = (cells[1], j + 1)
                    elif table_seen:
                        break  # 表格结束后又出现说明文字 → 头块结束
                    j += 1
                headers.append((i + 1, header_id, fields, []))
                i = j
                continue
        i += 1
    return headers


def check_file(path: Path):
    """返回 [(文件, 行号, 消息)]；只报带头条目的问题，无头文件零命中。"""
    findings = []
    try:
        text = path.read_text(encoding="utf-8-sig", errors="strict")
    except UnicodeDecodeError as e:
        return [(str(path), 0, f"编码错误（失败关闭）: {e}")]
    for line_no, header_id, fields, _ in parse_headers(text):
        if not fields:
            findings.append((str(path), line_no, f"头「{header_id}」下方没有字段表"))
            continue
        missing = [f for f in REQUIRED_FIELDS if f not in fields]
        if missing:
            findings.append(
                (str(path), line_no, f"头「{header_id}」缺字段: {'、'.join(missing)}")
            )
        for name, (value, vline) in fields.items():
            if value == "<<重复>>":
                findings.append((str(path), vline, f"头「{header_id}」字段「{name}」重复出现"))
            elif value.strip().lower() in PLACEHOLDERS:
                findings.append(
                    (str(path), vline, f"头「{header_id}」字段「{name}」为空值占位「{value}」（无内容请写「无」）")
                )
    return findings


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description="内容增减规范元数据头 advisory 巡检")
    ap.add_argument("--file", action="append", default=[], help="只扫指定文件（可多次）")
    ap.add_argument("--strict", action="store_true", help="有 finding 时退出码 1")
    args = ap.parse_args()

    root = find_repo_root(Path(__file__).resolve())
    if args.file:
        files = [Path(p) for p in args.file]
    else:
        files = []
        for pat in DEFAULT_PATTERNS:
            files.extend(sorted(root.glob(pat)))

    if not files:
        # 失败关闭：扫不到任何文件说明路径配置坏了，必须显式暴露（V4.15）
        print(f"[content-metadata] ERROR: 未找到任何待扫文件（root={root}）", file=sys.stderr)
        return 2

    findings = []
    headers_seen = 0
    for f in files:
        if not f.exists():
            print(f"[content-metadata] ERROR: 文件不存在: {f}", file=sys.stderr)
            return 2
        findings.extend(check_file(f))
        headers_seen += len(parse_headers(f.read_text(encoding="utf-8-sig")))

    print(f"[content-metadata] 扫描 {len(files)} 个文件，元数据头 {headers_seen} 个，finding {len(findings)} 条")
    for path, line, msg in findings:
        print(f"  {path}:{line}  {msg}")
    if findings:
        mode = "STRICT" if args.strict else "advisory（不拦截）"
        print(f"[content-metadata] 结果: FAIL（{mode}）")
        return 1 if args.strict else 0
    print("[content-metadata] 结果: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
