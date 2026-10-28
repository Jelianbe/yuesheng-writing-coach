#!/usr/bin/env python3
"""守卫：git hook **生效副本**必须与仓内源文件一致（md5 相同）。

★ 为什么需要这条守卫（2026-10-07 实踩）：
  `scripts/git-hooks/pre-commit` 是**源文件**（受版本控制），
  而 git 实际执行的是 `<git-dir>/hooks/pre-commit`（**安装副本**，不受版本控制）。
  二者靠手工跑 `scripts/install-git-hooks.ps1`的 `Copy-Item` 同步 ——
  **无任何自动机制，也无守卫**。
  实踩：改了源文件里的门禁道数文案（十二道→十四道）并提交，
  提交输出里 pre-commit 提醒**仍显示旧文案** ⇒ 改了不生效，
  而一切检查都绿（源文件本身没问题）。
  ⇒ 「源文件改了但生效副本没同步」是一个**静默失效**的坑，必须有机器执行点。

用法：
  python scripts/check_hook_sync.py            # 校验，不一致则 exit 1
  python scripts/check_hook_sync.py --quiet    # 只在不一致时输出

退出码：0 = 一致（或副本未安装，属可接受状态，见下）；1 = 不一致；2 = 环境不可判定。
"""
from __future__ import annotations

import hashlib
import os
import subprocess
import sys

# 仓内源 hook（相对本文件的上级目录 = yuesheng-flutter/）
REPO_SRC = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "scripts",
    "git-hooks",
    "pre-commit",
)
HOOK_NAME = "pre-commit"


def _git(*args: str) -> str | None:
    """跑 git 并返回 stdout；失败返回 None。"""
    try:
        r = subprocess.run(
            ["git", *args],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    return r.stdout.strip()


def _md5(path: str) -> str | None:
    try:
        with open(path, "rb") as fh:
            return hashlib.md5(fh.read()).hexdigest()
    except OSError:
        return None


def main() -> int:
    quiet = "--quiet" in sys.argv

    src_md5 = _md5(REPO_SRC)
    if src_md5 is None:
        print(f"[FAIL] 源 hook 不存在或不可读：{REPO_SRC}")
        return 2

    git_dir = _git("rev-parse", "--absolute-git-dir")
    if not git_dir:
        if not quiet:
            print("[SKIP] 非 git 仓库或 git 不可用，跳过 hook 同步校验")
        return 2

    dst = os.path.join(git_dir, "hooks", HOOK_NAME)
    dst_md5 = _md5(dst)
    if dst_md5 is None:
        # 副本未安装：不是漂移（首次 clone 常见），但值得提示。
        if not quiet:
            print(f"[SKIP] hook 副本未安装（{dst} 不存在）——非漂移。")
            print(f"       安装：bash <repo>/yuesheng-flutter/scripts/install-git-hooks.ps1"
                  f"（PowerShell: pwsh -File ...）")
        return 2

    if dst_md5 == src_md5:
        if not quiet:
            print(f"[PASS] hook 副本与源一致 md5={src_md5}")
            print(f"       源   {REPO_SRC}")
            print(f"       副本 {dst}")
        return 0

    # ★ 方向必须判（2026-10-20 实证补）：本检查只能证明「两个文件不同」，
    #   但**谁才是新的它不知道**。旧文案只写「重装副本」——
    #   若副本比源新（有人直接改了 `.git/hooks/`），照做会**静默覆盖丢失那些改动**。
    #   实测：W-43 的 eval 闸自检 45 行只写在副本里，本检查报红后若按旧文案重装，
    #   这段代码就没了。**报红是对的，但「怎么修」必须带方向。**
    try:
        with open(REPO_SRC, encoding="utf-8", errors="replace") as f:
            _a = f.read().splitlines()
        with open(dst, encoding="utf-8", errors="replace") as f:
            _b = f.read().splitlines()
    except OSError:
        _a = _b = None

    added = removed = 0
    if _a is not None and _b is not None:
        import difflib

        # 用 get_opcodes 而非 unified_diff 文本：后者靠 `+`/`-` 前缀计数，
        # 内容行本身以 `---` 开头时会被误当成 diff 头部而漏计。结构化判据无此歧义。
        _sm = difflib.SequenceMatcher(None, _a, _b, autojunk=False)
        for tag, i1, i2, j1, j2 in _sm.get_opcodes():
            if tag == "delete":
                removed += i2 - i1
            elif tag == "insert":
                added += j2 - j1
            elif tag == "replace":
                removed += i2 - i1
                added += j2 - j1

    print("[FAIL] hook 生效副本与仓内源不一致 —— 二者的改动都不会完整生效")
    print(f"       源   {REPO_SRC}")
    print(f"           md5={src_md5}")
    print(f"       副本 {dst}")
    print(f"           md5={dst_md5}")

    if _a is None or _b is None:
        print("       方向：无法判定（读取失败）⇒ 先手工 diff 两个文件再决定")
        print("       diff yuesheng-flutter/scripts/git-hooks/pre-commit .git/hooks/pre-commit")
    elif added > 0 and removed == 0:
        print(f"       方向：**副本更新**（副本多 {added} 行，源一行不缺）")
        print("       ⚠️ 有人直接改了 .git/hooks/pre-commit，没有回源。")
        print("       **不要直接重装** —— 重装会用旧源覆盖副本，那 " + str(added) + " 行会丢失。")
        print("       修复：先把副本差异并入源，再重装：")
        print("         diff yuesheng-flutter/scripts/git-hooks/pre-commit .git/hooks/pre-commit")
        print("         pwsh yuesheng-flutter/scripts/install-git-hooks.ps1")
    elif removed > 0 and added == 0:
        print(f"       方向：源更新（源多 {removed} 行，副本是旧版）—— 常见的正常情形")
        print("       修复：pwsh yuesheng-flutter/scripts/install-git-hooks.ps1")
    else:
        print(f"       方向：**双方分叉**（副本 +{added} / 源 +{removed}）—— 改动都还在，但各有各的")
        print("       修复：逐段合并两边差异到源，**再**重装副本；不要直接二选一覆盖。")
    return 1


if __name__ == "__main__":
    sys.exit(main())