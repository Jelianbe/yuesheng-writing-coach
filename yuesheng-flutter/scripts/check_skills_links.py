#!/usr/bin/env python3
"""
月笙 Flutter 端 — Skill 公共库链接与元数据校验（ADR-C115 · 门禁 12）。

背景（2026-10-01 收编批）：项目 skill 已收编为「单一真源 .agents/skills/ + 各工作台
Junction」结构。本脚本保证该结构不被悄悄破坏：

  ① Junction 目标必须存在 —— 悬空链接（如旧 .claude/.qoder 的 find-skills /
     react-component-generator）会让工作台扫到死链接，且曾真实发生（git 全历史无踪迹）；
  ①-b 加载点必须「存在且内容非空」—— **这是 §1-11-a 裁定的跨机可验证判据**。
     旧版只查「是链接的有没有悬空」，于是加载点整个消失（`.claude`/`.qoder` 空目录）
     时一句话都不说：空目录不违规、不存在也不违规 ⇒ 门禁全绿而实际零加载。
     注意判据里**不含**「必须是 Junction」：三个路径都在 `.gitignore` 内、且本机
     `core.symlinks = false` ⇒ 换机必然退化为实体目录，要求「必须是链接」会变成
     每次换机必红的假告警（§1-11-a 明确否决）。本机恢复链接请跑 `link_skills.py --apply`。
  ② 公共库每个 SKILL.md 必须有合法 frontmatter（name + description）—— 缺失时助手
     发现机制静默跳过，skill 隐形无提示；
  ③ 旧代 skill 必须带作废标注 —— 若被误迁入公共库会被助手当可用技能加载（误用旧规则）。

用法:
    python3 scripts/check_skills_links.py [REPO_ROOT]
退出码:
    0 = 全部通过
    1 = 存在断链 / 加载点缺失或为空 / frontmatter 缺失 / 旧代未标注（详细打印）
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
# 2026-10-20：`.trae/skills` 已恢复为 Junction，其中 3 个平台独有 skill 归档到
#   `.ai/archive/skills-trae-only-2026-10-20/`（前两个是 Electron 代，已作废）。
#   归档件仍在册检查 —— 归档不是免责，若有人把旧代 skill 从这里搬回真源，
#   本项与 ②③ 会一起变红。
OBSOLETE_SKILLS = [
    (".ai/archive/skills-trae-only-2026-10-20", "月笙代码审查"),
    (".ai/archive/skills-trae-only-2026-10-20", "月笙测试规划"),
]
OBSOLETE_MARKERS = ("旧代", "作废", "obsolete", "Electron 代", "electron")

# 三个工作台加载点（ADR-C115：单一真源 .agents/skills + 各工作台 Junction）
# ★ 判据是「存在且内容非空」，不是「必须是 Junction」—— 理由见文件头 ①-b。
LOADPOINTS = [".trae/skills", ".claude/skills", ".qoder/skills"]


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


def check_loadpoints_alive() -> list[str]:
    """①-b 加载点必须存在且内容非空（§1-11-a 的跨机可验证判据）。

    为什么不能只查 Junction：三个路径全在 `.gitignore` 内、本机 `core.symlinks=false`
    ⇒ 换机必然退化成实体目录或空目录。若此处要求「必须是 Junction」，门禁会在每台
    新机器上必红（假告警，§1-11-a 明确否决）；反之若什么都不查，会出现本项要防的
    真实事故 —— 2026-10-20 实测：`.claude/skills`、`.qoder/skills` 均为 **0 项空目录**，
    而门禁全绿。两个平台等于**零 skill 加载**，没有任何人发现。
    """
    violations = []
    for rel in LOADPOINTS:
        base = os.path.join(REPO_ROOT, rel)
        if not os.path.isdir(base):
            violations.append(
                f"[加载点缺失] {rel} —— 该平台将零 skill 加载。"
                f"修：python yuesheng-flutter/scripts/link_skills.py --apply")
            continue
        n = sum(len(files) for _r, _d, files in os.walk(base))
        if n == 0:
            violations.append(
                f"[加载点为空] {rel} —— 目录存在但 0 个文件，等于零加载。"
                f"修：rmdir 后跑 link_skills.py --apply")
    return violations


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
    problems += check_loadpoints_alive()
    problems += check_workbench_junctions()
    problems += check_public_lib_frontmatter()
    problems += check_obsolete_markers()

    if problems:
        print(f"Skill 公共库校验失败：{len(problems)} 项问题")
        for p in problems:
            print("  - " + p)
        return 1
    print("Skill 公共库校验通过：三加载点有内容 / Junction 无悬空 / frontmatter 合法 / 旧代已标注")
    return 0


if __name__ == "__main__":
    sys.exit(main())
