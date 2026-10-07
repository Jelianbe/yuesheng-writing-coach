#!/usr/bin/env python3
"""守卫：feature flag 值变更时，受影响的测试契约必须**同批同步**。

★ 为什么需要（2026-10-07 实踩的P0 事故）：
  `7d245a75` 把 `kBlockEditorEnabled` 由 `false` 翻成 `true`，提交信息自述
  「+ 同步测试契约」，但**实际只同步了** `block_readonly_view_test.dart`，
  **漏了** `writing_page_test.dart` ⇒ 收尾门禁 54 例红，且事故当时**零台账登记**。
  根因不是「忘了」，而是「**自述已同步 ≠ 已同步**」没有任何机器执行点。

判据（G1–G4）：
  G1空扫 ⇒ exit 2（fail-closed，防「扫不到就当过」）
  G2 登记完整性：每个 `const bool k*Enabled` 必须在 FLAGS 登记（值 + 受影响测试文件）
  G3 **主判据**：flag 值与基线不一致（=有人翻了 flag）⇒ 其「受影响测试文件」
      必须**全部**出现在本次改动里；缺任一 ⇒ FAIL
  G4 值与基线一致时不做要求（没翻flag 就与测试契约无关）

为什么用「基线 + 比对」而不是「查历史提交」：
  —— 门禁在**提交前**跑，要回答的是「这一次改动翻没翻 flag、测试跟没跟」，
     基线比对能覆盖「改了一半先提交」这种最常见的漏法；历史追溯管不了未提交态。

用法：
  python scripts/check_flag_contract.py --base <ref>   # 以某 ref 为基线（默认 HEAD）
  python scripts/check_flag_contract.py --write-baseline  # 确认无误后刷新基线
  python scripts/check_flag_contract.py --baseline-only   # 只查登记完整性

退出码：0 = 通过；1 = 有 FAIL；2 = 空扫/环境不可判定（fail-closed）。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.path.join(ROOT, "tool", "flag_contract_baseline.json")

# flag 声明 → 受影响测试文件（同一控件树/契约面的测试）。
# ⚠️ 这份登记是**人工判断的产物**：翻转 flag 会改变哪些测试的控件树/契约，
#   要靠人读代码确定，机器只能核对「登记齐不齐」与「翻没翻跟没跟」。
FLAGS: dict[str, dict] = {
    "kBlockEditorEnabled": {
        "file": "lib/features/writing/blocked_text/block_readonly_view.dart",
        # flag=true 时 chapterContentField 挂首块 KeyedSubtree（而非 TextField），
        # 且编辑器整串真源是宿主 editorController ⇒ 这两个文件的断言口径随之改变。
        "affected_tests": [
            "test/features/writing/blocked_text/block_readonly_view_test.dart",
            "test/widgets/writing_page_test.dart",
        ],
        "reason": "ADR-0002 分块编辑器开关；翻转会改控件树形态与 controller 归属",
    },
}

FLAG_RE = re.compile(r"^const\s+bool\s+(k[A-Za-z0-9_]*Enabled)\s*=\s*(true|false)\s*;", re.M)


def _git(*args: str) -> str | None:
    try:
        r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True,
                           text=True, timeout=60, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def scan_flags() -> dict[str, dict[str, str]]:
    """扫 lib/ 下所有 flag 声明 → {name: {file, value}}。"""
    found: dict[str, dict[str, str]] = {}
    lib = os.path.join(ROOT, "lib")
    for dirpath, _dirs, files in os.walk(lib):
        for fn in files:
            if not fn.endswith(".dart"):
                continue
            full = os.path.join(dirpath, fn)
            try:
                with open(full, encoding="utf-8") as fh:
                    src = fh.read()
            except OSError:
                continue
            for m in FLAG_RE.finditer(src):
                name, val = m.group(1), m.group(2)
                found[name] = {
                    "file": os.path.relpath(full, ROOT).replace("\\", "/"),
                    "value": val,
                }
    return found


def changed_files(base: str) -> set[str]:
    """相对 base 的改动文件集合（已提交 + 未提交，含暂存区）。

    ⚠️ 2026-10-07 修正（踩坑留档）：**git 仓库根是 `D:/ai-teacher`，不是
    `yuesheng-flutter/`**（本仓是 monorepo 的子目录）⇒ `git diff --name-only` 返回的
    路径**带 `yuesheng-flutter/` 前缀**，而本脚本判据里存的是**仓内相对路径**
    ⇒ 直接比对永不相等 ⇒ 守卫变成「只会报红」的假红（已实测：已同步两个测试文件
    仍报「未改动」）。
    ⇒ 故此处统一把 git 输出剥掉仓库前缀再比对；`git rev-parse
    --show-prefix` 是权威前缀来源（子目录/嵌套仓均正确，不写死字符串）。
    """
    prefix = _git("rev-parse", "--show-prefix") or ""
    prefix = prefix.replace("\\", "/")
    if prefix and not prefix.endswith("/"):
        prefix += "/"

    out: set[str] = set()
    for args in (["diff", "--name-only", base],
                 ["diff", "--name-only", "--cached", base],
                 ["diff", "--name-only"],
                 ["diff", "--name-only", "--cached"],
                 ["ls-files", "--others", "--exclude-standard"]):
        txt = _git(*args)
        if not txt:
            continue
        for line in txt.splitlines():
            p = line.strip().replace("\\", "/")
            if not p:
                continue
            if prefix and p.startswith(prefix):
                p = p[len(prefix):]
            out.add(p)
    return out


def read_baseline() -> dict[str, str]:
    if not os.path.exists(BASELINE):
        return {}
    try:
        with open(BASELINE, encoding="utf-8") as fh:
            return json.load(fh).get("flags", {})
    except (OSError, ValueError):
        return {}


def write_baseline(cur: dict[str, dict[str, str]]) -> int:
    data = {
        "_comment": "flag 值基线 —— check_flag_contract.py 的 G3 判据用。"
                    "翻 flag 时必须同批同步 affected_tests；确认无误后跑 --write-baseline 刷新。",
        "flags": {name: info["value"] for name, info in sorted(cur.items())},
    }
    os.makedirs(os.path.dirname(BASELINE), exist_ok=True)
    with open(BASELINE, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    print(f"[BASELINE] 已刷新 {BASELINE}: {data['flags']}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="HEAD", help="基线 ref（默认 HEAD）")
    ap.add_argument("--write-baseline", action="store_true")
    ap.add_argument("--baseline-only", action="store_true")
    args = ap.parse_args()

    cur = scan_flags()

    # G1 空扫 fail-closed
    if not cur:
        print("[FAIL] G1：lib/ 下未扫到任何 `const bool k*Enabled` —— "
              "要么判据失效（正则/路径漂移），要么 flag 真的绝迹了。"
              "\n       按 fail-closed 处理：拒绝放行，请核实后再改判据。")
        return 2

    if args.write_baseline:
        return write_baseline(cur)

    base = read_baseline()
    fails: list[str] = []

    # G2 登记完整性
    for name in sorted(cur):
        if name not in FLAGS:
            fails.append(f"G2：flag `{name}`（{cur[name]['file']}）未登记在 FLAGS 表中 —— "
                         f"请人工判定它翻转时受影响的测试文件后登记。")
    for name in sorted(FLAGS):
        if name not in cur:
            fails.append(f"G2：FLAGS 登记了 `{name}`，但 lib/ 下已扫不到该 flag —— "
                         f"要么被删/改名，要么正则漏了。")

    if not args.baseline_only:
        # G3 主判据：值变了 ⇒ 受影响测试必须同批改动
        touched = changed_files(args.base)
        for name, info in sorted(cur.items()):
            old = base.get(name)
            if old is None:
                fails.append(f"G3：flag `{name}` 在基线中不存在（首次纳管）—— "
                             f"请确认后跑 --write-baseline 建立基线。")
                continue
            if old == info["value"]:
                continue
            print(f"[FLAG] `{name}`: {old} -> {info['value']}（值已变更）")
            missing = [t for t in FLAGS[name]["affected_tests"] if t not in touched]
            if missing:
                fails.append(
                    f"G3：flag `{name}` 由 {old} 翻为 {info['value']}，"
                    f"但以下受影响测试文件**本次未改动**：\n"
                    + "\n".join(f"         - {t}" for t in missing)
                    + "\n       「提交信息自述已同步测试契约」不可采信 —— 这里只认文件改动事实。"
                )
            else:
                print(f"       ✔ 契约已同步：{', '.join(FLAGS[name]['affected_tests'])}")

    if fails:
        print()
        for f in fails:
            print(f"[FAIL] {f}")
        print(f"\n共 {len(fails)} 项FAIL。")
        return 1

    print(f"[PASS] flag 契约守卫：{len(cur)} 个 flag 登记齐备、值变更均已同步测试契约。")
    return 0


if __name__ == "__main__":
    sys.exit(main())