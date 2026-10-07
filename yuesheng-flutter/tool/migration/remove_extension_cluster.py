"""从 Dart extension 宿主文件里**精确删除**已搬走的成员（含其前置 doc 注释）。

★ 为什么需要它（ADR-0004 步 5 实测得出）：
  ChatServiceSend 拆成 3 个独立类时，簇内成员要按「签名行→大括号配平」精确切除。
  首版脚本从签名行往上扫 `//` 注释，结果把注释跨行的成员（`_injectDiagnosisFor`
  的 doc 有 7 行）算进了**上一个成员体内** ⇒ 区间重叠、删除会切坏代码。

三条硬纪律（都是本脚本内建断言，不符即exit 1 且**不写文件**）：
  1. **成员数量断言**：定位数必须等于配置数，缺一个即中止（防正则漏匹配
     非 `Future` 返回类型 —— `_finalizeSendContext` 返回 `_SendContext` 就栽过）。
  2. **区间无重叠断言**：相邻两段的 end 必须 < 下一段 start。
  3. **目标显式配置**：不靠「猜」哪些成员该删，`TARGETS` 必须逐条写明。

用法：
  1. 编辑下方 TARGETS（簇名 + 成员名单）。
  2. 先备份：``cp lib/services/chat_service.dart /tmp/backup.dart``（**脚本不备份**）。
  3. 干跑：``python tool/migration/remove_extension_cluster.py --dry-run``
  4. 实删：``python tool/migration/remove_extension_cluster.py``
  5. 立即验证：``dart analyze <宿主文件>``（rc 必须为 0 或仅剩预期内的引用错误）。

★ 本脚本只做「切除」，**不改调用点** —— 调用点需手工改（拆簇时通常只有 1~2 处，
  逐个改成调服务实例）。
"""
from __future__ import annotations

import argparse
import io
import os
import re
import sys

# ============ 配置区（每次使用前按实际情况填写）============
HOST_REL = "lib/services/chat_service.dart"
# ★ 默认**空** —— 本工具不预置任何目标：使用者必须按当前要拆的簇显式填写。
#   （ADR-0004 步 5 的三批目标 D/C/B+E 已在 2026-10-07 全部完成，
#     若留在表里会让后人误以为「这些成员还没删」⇒ 用一个断言失败的干跑来暴露。）
TARGETS: list[tuple[str, list[str]]] = [
    # 示例（请按实际填写）：
    # ("某簇名（X 簇）", ["_memberOne", "_memberTwo"]),
]
# ============================================================

# ★ 必须覆盖**非 Future** 返回类型：`_finalizeSendContext` 返回 `_SendContext`
#   （无 Future 前缀）。首版正则漏了它⇒ 断言报「缺 1 个」（脚本按设计 abort、
#   未写文件），此处显式包含 `_\w+` 分支。
SIG = re.compile(
    r"^  (?:Future<[^>]*>|void|String|bool|int|List<[^>]*>|Map<[^>]*>|Duration|_\w+)"
    r"\s+(\w+)\s*\("
)

# 仓根=本文件的上上级（tool/migration/ -> tool/ -> 仓根）
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PATH = os.path.join(REPO_ROOT, HOST_REL)


def find_block_end(lines: list[str], sig_idx: int) -> int:
    """从签名行起按大括号配平找块尾（含尾随 `}` 行）。"""
    depth = 0
    began = False
    i = sig_idx
    while i < len(lines):
        depth += lines[i].count("{") - lines[i].count("}")
        if "{" in lines[i]:
            began = True
        if began and depth == 0:
            # 跳过尾随空行
            j = i
            while j + 1 < len(lines) and lines[j + 1].strip() == "":
                j += 1
            return j
        i += 1
    raise AssertionError(f"sig line {sig_idx + 1} 大括号未配平")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="只打印将删除的区间，不写文件")
    a = ap.parse_args()
    lines = io.open(PATH, encoding="utf-8").read().split("\n")

    # 定位所有 extension 成员签名
    sigs = [(i, SIG.match(lines[i]).group(1))
            for i in range(len(lines)) if SIG.match(lines[i])]

    targets = []
    wanted = {m for _, members in TARGETS for m in members}
    for k, (i, name) in enumerate(sigs):
        if name not in wanted:
            continue
        end = find_block_end(lines, i)
        # 起点：上一成员 end 之后（或文件头之后）第一个非空行，
        # 且必须包含本成员的全部前置注释。
        prev_end = (find_block_end(lines, sigs[k - 1][0])
                    if k > 0 and sigs[k - 1][0] < i else -1)
        s = prev_end + 1
        while s < i and lines[s].strip() == "":
            s += 1
        targets.append((name, s, end))

    # 断言：全部目标均定位 + 区间互不重叠
    expected = [m for _, members in TARGETS for m in members]
    if not expected:
        print("[SKIP] TARGETS 为空 —— 无事可做。请编辑本文件的配置区后重试。")
        return 0
    found = [t[0] for t in targets]
    assert len(targets) == len(expected), (
        f"定位到 {len(targets)} 个，期望 {len(expected)}："
        f"缺 {set(expected) - set(found)}"
    )
    ordered = sorted(targets, key=lambda t: t[1])
    for a, b in zip(ordered, ordered[1:]):
        assert a[2] < b[1], f"区间重叠：{a[0]}({a[1]}..{a[2]}) 与 {b[0]}({b[1]}..{b[2]})"

    total = sum(e - s + 1 for _, s, e in targets)
    print(f"[DRY-RUN] 定位 {len(targets)} 个成员，待删 {total} 行")
    for name, s, e in ordered:
        print(f"  {name:36s} {s + 1:5d}..{e + 1:5d} ({e - s + 1} 行)")

    kill = set()
    for _, s, e in targets:
        kill.update(range(s, e + 1))
    out = [l for i, l in enumerate(lines) if i not in kill]
    io.open(PATH, "w", encoding="utf-8", newline="\n").write("\n".join(out))
    print(f"[WROTE] 删除 {len(kill)} 行，{len(lines)} -> {len(out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())