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
        return 0

    if dst_md5 == src_md5:
        if not quiet:
            print(f"[PASS] hook 副本与源一致 md5={src_md5}")
            print(f"       源   {REPO_SRC}")
            print(f"       副本 {dst}")
        return 0

    print("[FAIL] hook 生效副本与仓内源不一致 —— 改了源文件不会生效（静默失效）")
    print(f"       源   {REPO_SRC}")
    print(f"           md5={src_md5}")
    print(f"       副本 {dst}")
    print(f"           md5={dst_md5}")
    print("       修复：运行 yuesheng-flutter/scripts/install-git-hooks.ps1 重装副本")
    return 1


if __name__ == "__main__":
    sys.exit(main())