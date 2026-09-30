#!/usr/bin/env python3
"""
月笙 Flutter 端 — Skill 公共库链接与元数据校验（ADR-C115 · 门禁 12）。

背景（2026-10-01 收编批）：项目 skill 已收编为「单一真源 .agents/skills/ + 各工作台
Junction」结构。本脚本保证该结构不被悄悄破坏：

  ① Junction 目标必须存在 —— 悬空链接（如旧 .claude/.qoder 的 find-skills /
     react-component-generator）会让工作台扫到死链接，且曾真实发生（git 全历史无踪迹）；
  ② 公共库每个 SKILL.md 必须有合法 frontmatter（name + description）—— 缺失时豆包
     发现机制静默跳过，skill 隐形无提示；
  ③ 旧代 skill 必须带作废标注 —— 若被误迁入公共库会被豆包当可用技能加载（误用旧规则）。

用法:
    python3 scripts/check_skills_links.py [REPO_ROOT]
退出码:
    0 = 全部通过
    1 = 存在断链 / frontmatter 缺失 / 旧代未标注（详细打印）
    2 = 环境错误：公共库目录不存在（**失败关闭**，绝不静默放行）
"""
import os
import sys

# 相对脚本位置（scripts/）定位仓库根：脚本位于 <root>/yuesheng-flutter/scripts/ 或 <root>/scripts/
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if os.path.basename(SCRIPT_DIR) == "scripts":
    FLUTTER_ROOT = os.path.dirname(SCRIPT_DIR)
else:  # 直接以仓库根为参数传入
    FLUTTER_ROOT = SCRIPT_DIR
REPO_ROOT = os.path.dirname(FLUTTER_ROOT)

# 工作台技能目录（相对仓库根）
WORKBENCH_DIRS = [
    ".trae/skills",
    "yuesheng-flutter/.workbuddy/skills",
    ".claude/skills",
    ".qoder/skills",
]
PUBLIC_LIB = os.path.join(REPO_ROOT, ".agents", "skills")

# 旧代 skill：必须带作废标注（本批裁定：只标不迁不删）
OBSOLETE_SKILLS = [
    ("yuesheng-flutter/.workbuddy/skills", "月笙代码审查"),  # 占位，实际在 .trae
    (".trae/skills", "月笙代码审查"),
    (".trae/skills", "月笙测试规划"),
]
OBSOLETE_MARKERS = ("旧代", "作废", "obsolete", "Electron 代", "electron")


def is_junction(path: str) -> bool:
    """Windows Junction 判断：os.readlink 能读出目标即链接（Junction 与 symlink 均可）。

    实证（2026-10-01）：Windows 上 Python 对 Junction，os.path.islink() 返回 False，
    但 os.readlink() 始终可读（即使目标已不存在 → 断链）；ctypes reparse point 检测
    也可靠。三者任一命中即视为链接。
    """
    try:
        os.readlink(path)
        return True
    except OSError:
        pass
    try:
        if os.path.islink(path):
            return True
    except OSError:
        pass
    try:
        import ctypes

        FILE_ATTRIBUTE_REPARSE_POINT = 0x400
        attrs = ctypes.windll.kernel32.GetFileAttributesW(path)
        return bool(attrs != -1 and (attrs & FILE_ATTRIBUTE_REPARSE_POINT))
    except Exception:
        return False


def check_workbench_junctions() -> list[str]:
    """① 工作台 Junction 目标必须存在。返回违规清单。"""
    violations = []
    for rel in WORKBENCH_DIRS:
        base = os.path.join(REPO_ROOT, rel)
        if not os.path.isdir(base):
            continue  # 目录不存在（如 .claude/skills 已清空）不算违规
        for entry in os.listdir(base):
            full = os.path.join(base, entry)
            if is_junction(full):
                try:
                    target = os.readlink(full)
                except OSError:
                    target = None
                if target is None or not os.path.exists(target):
                    violations.append(f"[悬空 Junction] {rel}/{entry} -> {target}")
    return violations


def check_public_lib_frontmatter() -> list[str]:
    """② 公共库每个 SKILL.md 必须有 name + description。返回违规清单。"""
    violations = []
    if not os.path.isdir(PUBLIC_LIB):
        return ["[环境] 公共库缺失: " + PUBLIC_LIB]
    for skill in sorted(os.listdir(PUBLIC_LIB)):
        sk_dir = os.path.join(PUBLIC_LIB, skill)
        if not os.path.isdir(sk_dir):
            continue
        md = os.path.join(sk_dir, "SKILL.md")
        if not os.path.isfile(md):
            violations.append(f"[缺 SKILL.md] {skill}/")
            continue
        try:
            with open(md, encoding="utf-8") as fh:
                content = fh.read()
        except (OSError, UnicodeDecodeError) as e:
            violations.append(f"[读取失败] {skill}/SKILL.md: {e}")
            continue
        if not content.startswith("---"):
            violations.append(f"[frontmatter 缺开符] {skill}/SKILL.md")
            continue
        # 提取 frontmatter 块
        try:
            fm_end = content.index("\n---", content.index("---") + 3)
            fm = content[3:fm_end]
        except ValueError:
            violations.append(f"[frontmatter 未闭合] {skill}/SKILL.md")
            continue
        has_name = any(line.strip().startswith("name:") for line in fm.splitlines())
        has_desc = any(line.strip().startswith("description:") for line in fm.splitlines())
        if not has_name:
            violations.append(f"[缺 name:] {skill}/SKILL.md")
        if not has_desc:
            violations.append(f"[缺 description:] {skill}/SKILL.md")
    return violations


def check_obsolete_markers() -> list[str]:
    """③ 旧代 skill 必须带作废标注。返回违规清单。"""
    violations = []
    for rel, skill in OBSOLETE_SKILLS:
        md = os.path.join(REPO_ROOT, rel, skill, "SKILL.md")
        if not os.path.isfile(md):
            continue  # 不存在 = 已被清理，不拦
        try:
            with open(md, encoding="utf-8") as fh:
                head = fh.read(2000).lower()
        except (OSError, UnicodeDecodeError):
            continue
        if not any(m in head for m in OBSOLETE_MARKERS):
            violations.append(f"[旧代未标注] {rel}/{skill}/SKILL.md 需含作废标记")
    return violations


def main() -> int:
    problems = []
    problems += check_workbench_junctions()
    problems += check_public_lib_frontmatter()
    problems += check_obsolete_markers()

    if problems:
        print(f"Skill 公共库校验失败：{len(problems)} 项问题")
        for p in problems:
            print("  - " + p)
        return 1
    print("Skill 公共库校验通过：Junction 全有效 / frontmatter 全合法 / 旧代已标注")
    return 0


if __name__ == "__main__":
    sys.exit(main())
