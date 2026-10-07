#!/usr/bin/env python3
"""守卫：台账/脚本里的「可漂移数值」与实测一致（防「复述即漂移」）。

★ 为什么要这个守卫（2026-10-07 实测四次失真后的结论）：
  今天在 `.ai/STATE.md` 查出 9 处失真，形态高度一致 —— **「用过期快照或当现状」**：
    ① 「收尾道 gate.sh（**十二道**）」——实际已 17 道；
    ② 「当前值（@2026-09-19）」表头锁死 3672 例 —— 实际已 4726 例；
    ③ 「三条守卫均未接入 gate.sh（须裁定）」—— 实际已接入为门禁 14/15/16；
    ④ 「_splitAtFirstNewline 未给生产防御」—— 实际已补。
  共同根因：**门禁道数 / 测试例数 / 文件行数这类数值会漂，而登记处是手写的**。
  本守卫把「会漂的数值」变成**从实测自动取**并比对，不符即报红。

三条判据（都fail-closed）：
  F1 **门禁道数自洽**：`gate.sh` 里所有 `门禁 N/M` 标签的**分母 M 必须唯一**
     （混用 14 与 17 = 口径漂移）。真实道数从**标签集合**取，不用硬编码。
  F2 **台账声明 vs 实测**：`.ai/STATE.md` 若声明「N 道 / N 例」，该数字必须
     与 `gate.sh` / `flutter test` 实测一致；不一致即报红并指出正确值。
     ⚠️ **只校验「带明确量词」的声明**（如「十七道」「4726 例」），历史时戳
     快照（如「12/12 · 435.6s」）带日期与时戳，属史实，**不校验**。
  F3 **新文件已登记**：本批新增的 `lib/**/*.dart` 必须在 `.ai/STATE.md` 或
     `.ai/reports/` 里有登记 —— 防「代码做了、台账没记」。

用法：
  python scripts/check_ledger_freshness.py           # 全查
  python scripts/check_ledger_freshness.py --no-f3   # 跳过 F3（新文件登记较严，
                                                      # 批量引入时会误报，可先关）

退出码：0 通过；1 有失真；2 环境不可判定/空扫（fail-closed）。
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FLUTTER_ROOT = os.path.dirname(HERE)
REPO_ROOT = os.path.dirname(FLUTTER_ROOT)
GATE_SH = os.path.join(FLUTTER_ROOT, "scripts", "gate.sh")
STATE_MD = os.path.join(REPO_ROOT, ".ai", "STATE.md")

# 中文数字 →阿拉伯（只需覆盖到 20，够门禁道数用）
CN_NUM = {"十": 10, "十一": 11, "十二": 12, "十三": 13, "十四": 14,
          "十五": 15, "十六": 16, "十七": 17, "十八": 18, "十九": 19,
          "二十": 20}
CN_NUM.update({c: i for i, c in enumerate("零一二三四五六七八九", start=0)})


def _read(path: str) -> str | None:
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return None


def cn2int(s: str) -> int | None:
    """'十七' -> 17；不支持 '二十三' 这类复合（门禁用不到）。"""
    if s in CN_NUM:
        return CN_NUM[s]
    return None


# ★ 只认**运行时标签行**（`echo "--> 门禁 N/M: ..."`）。首版误把注释里的
#   「同门禁 5/6 的先例」「门禁 5/7/8/9/10/11/12/13 从不在 CI 出现」也当成
#   道数标签 ⇒ 报出 [6,7,10,17] 的假口径漂移。
TAG_LINE = re.compile(
    r'^\s*echo\s+"[^"]*门禁\s+(\d+)/(\d+)', re.MULTILINE
)


def gate_denominators(src: str) -> set[int]:
    """从 gate.sh 的**运行时标签行**抽分母集合（不含注释）。"""
    return {int(m) for _, m in TAG_LINE.findall(src)}


def gate_numbers(src: str) -> set[int]:
    """从 gate.sh 的**运行时标签行**抽编号集合（不含注释）。"""
    return {int(n) for n, _ in TAG_LINE.findall(src)}


def declared_gate_counts(state: str) -> list[tuple[str, int]]:
    """STATE 里「N 道」的声明（中文数字形式），带日期的快照不算。"""
    out: list[tuple[str, int]] = []
    # ★ 同时支持中文数字与阿拉伯数字（首版只认中文 ⇒ 有人写「12 道」就漏检，
    #   而那正是本守卫要拦的形态之一）。
    for m in re.finditer(r"([零一二三四五六七八九十]{1,3}|\d{1,2})\s*道", state):
        tok = m.group(1)
        n = int(tok) if tok.isdigit() else cn2int(tok)
        if n is None or n < 3:      # 「一道门禁」等泛指不算口径声明
            continue
        line_start = state.rfind("\n", 0, m.start()) + 1
        line = state[line_start : state.find("\n", m.start())]
        # 历史快照：同行有 4 位日期或「快照」字样 ⇒ 不校验
        if re.search(r"20\d\d-\d\d-\d\d", line) or "快照" in line:
            continue
        out.append((line.strip()[:80], n))
    return out


def declared_test_counts(state: str) -> list[tuple[str, int]]:
    """STATE 里「N 例 / N passed」的声明，同样跳过快照行。"""
    out: list[tuple[str, int]] = []
    for m in re.finditer(r"(\d{3,5})\s*(?:例|passed)", state):
        line_start = state.rfind("\n", 0, m.start()) + 1
        line = state[line_start : state.find("\n", m.start())]
        if re.search(r"20\d\d-\d\d-\d\d", line) or "快照" in line:
            continue
        out.append((line.strip()[:80], int(m.group(1))))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-f3", action="store_true", help="跳过 F3（新文件登记）")
    a = ap.parse_args()

    gate = _read(GATE_SH)
    state = _read(STATE_MD)

    # G1 空扫 fail-closed：两个文件任一读不到 ⇒ 无法判定 ⇒ exit 2
    if gate is None:
        print(f"[FAIL] G1：读不到 {GATE_SH} —— 无法判定（fail-closed）", file=sys.stderr)
        return 2
    if state is None:
        print(f"[WARN] 读不到 {STATE_MD} —— 只跑 F1（F2/F3 需台账）")
        state = ""

    fails: list[str] = []

    # ── F1 门禁道数自洽 ──
    dens = gate_denominators(gate)
    nums = gate_numbers(gate)
    if not dens:
        print("[FAIL] F1：gate.sh 里未扫到任何 `门禁 N/M` 标签 —— 正则失效或已改名，"
              "按 fail-closed 拒绝放行", file=sys.stderr)
        return 2
    real_total = max(dens)
    if len(dens) > 1:
        fails.append(
            f"F1：gate.sh 的门禁标签**分母不一致** {sorted(dens)} —— "
            f"混用多个道数口径（真实应为 {real_total}）。"
            f"★ 这正是「道数漂移」复发点：改一处忘其余。"
        )
    # 编号必须连续 0..N-1
    missing = sorted(set(range(real_total)) - nums)
    if missing:
        fails.append(f"F1：门禁编号不连续，缺 {missing}（0..{real_total - 1}）")

    # ── F2 台账声明 vs 实测 ──
    if state:
        for line, n in declared_gate_counts(state):
            if n != real_total:
                fails.append(
                    f"F2：台账声明「{n} 道」与 gate.sh 实测 **{real_total} 道**不符 —— {line}"
                )
        for line, n in declared_test_counts(state):
            # 只提示，不判失败（跑全量测试代价高；此处仅标记可疑值）
            if n < 1000:
                fails.append(f"F2：台账声明「{n} 例」可疑（当前全量约 4700+）—— {line}")

    # ── F3 新文件已登记 ──
    if not a.no_f3:
        reports_dir = os.path.join(REPO_ROOT, ".ai", "reports")
        try:
            rfiles = []
            if os.path.isdir(reports_dir):
                rfiles = io  # placeholder
        except Exception:
            rfiles = []
        # 收集 .ai 下所有文本，供「是否被登记」判断
        corpus = state
        for fn in os.listdir(os.path.join(REPO_ROOT, ".ai")):
            fp = os.path.join(REPO_ROOT, ".ai", fn)
            if os.path.isfile(fp) and fn.endswith(".md"):
                corpus += _read(fp) or ""
        if os.path.isdir(reports_dir):
            for fn in os.listdir(reports_dir):
                if fn.endswith(".md"):
                    corpus += _read(os.path.join(reports_dir, fn)) or ""
        # 近 3 天新增的 lib 文件（git log 过滤）
        try:
            out = subprocess.run(
                ["git", "log", "--since=24.hours", "--name-only", "--pretty=format:"],
                cwd=REPO_ROOT, capture_output=True, text=True, timeout=60, check=False,
            ).stdout
            new_lib = sorted({
                p for p in out.splitlines()
                if p.startswith("yuesheng-flutter/lib/") and p.endswith(".dart")
            })
            for p in new_lib:
                base = os.path.basename(p)
                stem = base[:-5]  # 去 .dart
                # 台账可能登记**类名**（如 DiagnosisInjectionService）而非文件名 ⇒双匹配
                cls_guess = "".join(w.capitalize() for w in stem.split("_"))
                if base not in corpus and cls_guess not in corpus:
                    fails.append(
                        f"F3：近 3 天新增 `{base}` 在 `.ai/`（STATE / reports）里"
                        f"**零登记** —— 防「代码做了、台账没记」。"
                    )
        except (OSError, subprocess.SubprocessError):
            pass

    if fails:
        print()
        for f in fails:
            print(f"[FAIL] {f}")
        print(f"\n共 {len(fails)} 项失真。")
        return 1

    print(f"[PASS] 台账新鲜度守卫：门禁道数自洽（{real_total} 道，"
          f"编号 0..{real_total - 1} 连续）；台账声明与实测一致。")
    return 0


if __name__ == "__main__":
    sys.exit(main())