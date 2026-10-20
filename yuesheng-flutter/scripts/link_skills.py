#!/usr/bin/env python3
"""重建 AI 工作台 skills 加载点（.claude / .qoder / .trae）指向单一真源。

为什么需要这个脚本
------------------
`.ai/DECISIONS-DETAIL.md §1-11-a`（2026-10-20 实测）已裁定：
「某台机器上是 symlink」**不能**证明「已去重」，因为
  ① 三个加载点路径全在 `.gitignore` 内 ⇒ 从未被版本控制；
  ② 本机 `core.symlinks = false` ⇒ 即便入库也不会还原为链接；
  ③ 故「换机即退化」。
⇒ 跨机**唯一**可靠的判据是「加载点存在且内容非空」；
  而「本机恢复链接」只能靠**一条可重复执行的命令**，不能靠人记得手工重来。
   这就是本脚本存在的唯一理由。

`.trae/skills` 为什么默认不动（重要，不是遗漏）
-----------------------------------------------
它与另外两个加载点性质完全不同：
  · 被 **`.trae` 独立 git 仓跟踪**（19 个 SKILL.md，主仓 `.gitignore` 忽略整目录）；
  · 内有 **3 个真源没有的 skill**：`智能规则识别` / `月笙代码审查` / `月笙测试规划`
    （后两个是【旧代作废】Electron 代，只标不迁）；
  · 仓里对它们有**未提交的维护中改动**。
整目录换 Junction ⇒ `.trae` 仓凭空少 19 个受跟踪文件、3 个 skill 消失。
⇒ 默认保留实体，只在显式 `--include-trae` 时处理（会先要求把独有目录归档）。

用法:
    python3 scripts/link_skills.py                  # 只检查，不改动（默认）
    python3 scripts/link_skills.py --apply          # 重建 .claude / .qoder
    python3 scripts/link_skills.py --apply --include-trae
    python3 scripts/link_skills.py --json           # 机读结果

退出码:
    0 = 三个加载点均「存在且内容非空」
    1 = 有加载点缺失或为空（`--apply` 后仍失败也是这个码）
    2 = 环境错误：真源 `.agents/skills` 不存在（失败关闭，不做任何改动）
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
FLUTTER_ROOT = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == "scripts" else SCRIPT_DIR
REPO_ROOT = os.path.dirname(FLUTTER_ROOT)

PUBLIC_LIB = os.path.join(REPO_ROOT, ".agents", "skills")

# (相对路径, 是否默认处理)
LOADPOINTS = [
    (".claude/skills", True),
    (".qoder/skills", True),
    (".trae/skills", False),  # 独立仓跟踪 + 平台独有 skill，见顶部说明
]


def _is_reparse(path: str) -> bool:
    """Windows 上 Junction: os.path.islink() 为 False，但 reparse point 位为真。"""
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


def _reparse_target(path: str) -> str | None:
    try:
        return os.readlink(path)
    except OSError:
        return None


def _count_files(path: str) -> int:
    n = 0
    for _root, _dirs, files in os.walk(path):
        n += len(files)
    return n


def inspect(rel: str) -> dict:
    """单个加载点的实测状态。`alive` 是 §1-11-a 认可的跨机判据。"""
    full = os.path.join(REPO_ROOT, rel)
    exists = os.path.isdir(full)
    linked = _is_reparse(full) if exists else False
    target = _reparse_target(full) if exists else None
    files = _count_files(full) if exists else 0
    dangling = bool(linked and target and not os.path.exists(target))
    return {
        "加载点": rel,
        "存在": exists,
        "是链接": linked,
        "目标": target,
        "递归文件数": files,
        # ★ 跨机可验证的判据：存在且有内容（链接是否成立只影响本机去重效率）
        "alive": bool(exists and files > 0),
        "悬空": dangling,
    }


def _norm(p: str) -> str:
    """路径归一 —— 必须剥掉 `\\\\?\\` 长路径前缀。

    ★ 2026-10-20 实测踩坑：`os.readlink()` 对 Junction 返回
    `\\\\?\\D:\\ai-teacher\\.agents\\skills`，而真源常量是 `D:\\ai-teacher\\.agents\\skills`。
    不剥前缀 ⇒ 两者永不相等 ⇒ 脚本把**本来正确的链接**判成「链错了」，
    先 rmdir 再重建；一旦重建失败，加载点直接消失（当场坏了两个）。
    """
    p = os.path.abspath(p)
    if p.startswith("\\\\?\\"):
        p = p[4:]
    return os.path.normcase(p)


def _create_junction(link: str, target: str) -> tuple[bool, str]:
    """建 Junction。优先 `_winapi.CreateJunction`，回退 `cmd mklink /J`。

    为什么不用 `subprocess(["cmd","/c","mklink",...])`：实测 2026-10-20 —— Windows 下
    `cmd /c` 的参数里带反斜杠路径会被**拆成多个开关**，报 `无效开关 - "skills"`，
    且此时目录已被删 ⇒ 加载点直接消失。参数绝对不能靠拼字符串传给 cmd。
    """
    if sys.platform != "win32":
        try:
            os.symlink(target, link, target_is_directory=True)
            return True, "已重建（symlink）"
        except OSError as e:
            return False, f"symlink 失败: {e}"

    try:
        import _winapi  # CPython Windows 专有，Junction 的原生实现

        _winapi.CreateJunction(target, link)
        return True, "已重建（Junction）"
    except Exception as e:  # noqa: BLE001 —— 回退路径比异常类型更重要
        fallback_err = str(e)

    # 回退：整条命令作为一个字符串交给 shell，避免参数被 cmd 重新切分
    proc = subprocess.run(
        f'mklink /J "{link}" "{target}"',
        shell=True,
        capture_output=True,
        text=True,
        errors="replace",
    )
    if proc.returncode == 0 and os.path.isdir(link):
        return True, "已重建（mklink 回退）"
    return False, f"两种方式均失败：_winapi={fallback_err} / mklink={(proc.stdout or proc.stderr).strip()}"


def make_junction(rel: str) -> tuple[bool, str]:
    """把 <repo>/<rel> 建成指向真源的 Junction。目录非空则拒绝（不静默丢文件）。"""
    full = os.path.join(REPO_ROOT, rel)
    if not os.path.isdir(PUBLIC_LIB):
        return False, f"真源不存在: {PUBLIC_LIB}"

    removed: list[str] = []  # 已删的旧内容，失败时用于回滚

    if os.path.isdir(full) and _is_reparse(full):
        target = _reparse_target(full)
        if target and _norm(target) == _norm(PUBLIC_LIB):
            return True, "已是正确链接，跳过"
        os.rmdir(full)  # 只删链接，不动目标

    if os.path.isdir(full):
        n = _count_files(full)
        if n > 0:
            return False, f"拒绝：目录非空（{n} 个文件），请先人工归档后再重建"
        os.rmdir(full)
        removed.append(full)

    parent = os.path.dirname(full)
    os.makedirs(parent, exist_ok=True)
    ok, msg = _create_junction(full, PUBLIC_LIB)
    if not ok:
        # ★ 失败不许留下「加载点消失」这种更糟的状态：把空目录补回去
        for p in removed:
            if not os.path.exists(p):
                os.makedirs(p, exist_ok=True)
                msg += "（已回滚为空目录，加载点仍在但不含内容）"
    return ok, msg


def main() -> int:
    ap = argparse.ArgumentParser(description="重建 AI 工作台 skills 加载点")
    ap.add_argument("--apply", action="store_true", help="执行重建（默认只检查）")
    ap.add_argument("--include-trae", action="store_true",
                    help="连 .trae/skills 一起处理（会删掉 .trae 仓跟踪的实体副本，慎用）")
    ap.add_argument("--json", action="store_true", help="输出机读 JSON")
    args = ap.parse_args()

    if not os.path.isdir(PUBLIC_LIB):
        print(f"[FAIL-CLOSED] 真源缺失，不做任何改动: {PUBLIC_LIB}", file=sys.stderr)
        return 2

    actions: list[str] = []
    if args.apply:
        for rel, default_on in LOADPOINTS:
            if not default_on and not args.include_trae:
                actions.append(f"{rel}: 跳过（独立仓跟踪，需 --include-trae）")
                continue
            ok, msg = make_junction(rel)
            actions.append(f"{rel}: {msg}")
            if not ok:
                print(f"[FAIL] {rel}: {msg}", file=sys.stderr)

    rows = [inspect(rel) for rel, _ in LOADPOINTS]
    dead = [r for r in rows if not r["alive"]]

    if args.json:
        print(json.dumps({"真源": PUBLIC_LIB, "加载点": rows, "动作": actions,
                          "全部存活": not dead}, ensure_ascii=False, indent=1))
    else:
        if actions:
            print("动作：")
            for a in actions:
                print("  · " + a)
            print()
        print(f"真源 {PUBLIC_LIB}")
        print(f"{'加载点':<16}{'存活':<6}{'链接':<6}{'文件数':<8}目标")
        for r in rows:
            print(f"{r['加载点']:<16}{'是' if r['alive'] else '否':<6}"
                  f"{'是' if r['是链接'] else '否':<6}{r['递归文件数']:<8}{r['目标'] or '-'}")
        print()
        if dead:
            print(f"[FAIL] {len(dead)} 个加载点不可用：{', '.join(r['加载点'] for r in dead)}")
            print("       ⇒ 这些工作台扫到的是空目录，等于该平台零 skill 加载。")
            print("       修：python yuesheng-flutter/scripts/link_skills.py --apply")
            return 1
        print("[PASS] 三个加载点均『存在且内容非空』")
        print("       注：链接是否成立只决定本机是否去重；换机后会退化为实体目录，")
        print("           届时重跑本脚本 --apply 即可（§1-11-a：路径不在版本控制内，无法自愈）。")
    return 1 if dead else 0


if __name__ == "__main__":
    sys.exit(main())
