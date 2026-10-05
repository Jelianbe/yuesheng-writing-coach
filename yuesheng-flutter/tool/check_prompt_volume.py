"""ADR-0003 判据 9体积红线的可执行检查（阶段一）。

背景
----
ADR-0003 §5 判据 9 原文：「阶段一注入后 diagnosis 组体积实测，**不得回涨到C99 减编前水平**」。

⚠️ **2026-10-05 判据 9 措辞已改写（原措辞不可执行）**：
   原句的「C99 减编前水平」经查 `docs/ADR-C99-diagnosis-skill-pruning.md` §4
   只记「diagnosis 组常驻 tokens 从 ~12k → ~8k」，**没有任何字符数**；
   而本脚本量的是快照 `prompt[*].len`（**整条 system prompt**，当前 5.5万）。
   两者口径差 **4.5 倍**（12,000 vs 54,285）⇒ 照字面判，**注入前就已"超了 4.5 倍"**，
   该判据恒红且无意义。
   ⇒ 改写为：**「不得超本脚本 `REDLINE` 常量」**，并在此把 REDLINE 的来源钉死。
   这是 `DECISIONS §4-155` 的实例：规格里的「不得回涨到 X」若X 是**另一口径的
   估计值**，它只是措辞、不是约束。

红线沿革（红线的每次变更都须有舰长裁定 + 逐键对账）
------------------------------------------------
· 2026-10-05 第一次：舰长裁「不超当前实测 53,907」→ 实测三条新症候索引行
  自动渲染致 54,285（+378）→ 二次请裁 → 「认可增量，基准上移至 54,285」。
· 2026-10-05 第二次（A2/A3 批）：舰长批准五块注入（裁定 2/4/5/6/7），
  预估 +1,058 → **实测 +1,077**（diagnosis 两组同增）⇒ 基准上移至 55,362 /
  53,579。
· 2026-10-05 第三次（判据 8 自查批）：**下调 1 字符**至 55,361 / 53,578。
  ⚠️ **方向是「修缺陷导致的回落」，不是新增预算**
  —— 修 `buildSyndromeIndexContent` 的既有拼接缺陷后，
  diagnosis 两组各**降 1 字符**（数据行末尾与 footer 首行之间补了
  显式换行 ⇒ 少一个重复的 `\n`）。
· 2026-10-05 第四次（判据 8 补修批）：**上调 1 字符**至 55,362 / 53,579。
  方向：补修 **同型第二处接缝**（`footer ↔ADR 块`）——上一批只修了「数据行 ↔ footer」，遗漏下游接缝。
  ⚠️ 本次上调**不是新增预算**，而是修一个**已存在的格式错误**；但纪律不因此放宽：**读数变了红线就贴回实测值**。

⚠️ **红线必须贴住实测值，不留余量**（2026-10-05 判据 8 自查批实证）：
  若沿用 55,362 / 53,579，红线会比实测**高 1**，
  等于免费送出 1 字符预算 —— 下次有人加 1 个字符，
  门禁照样绿。**判据只有在「恰好贴线」时才具备牙齿**；
  留任何余量都会让判据退化成「小于某个更大的数」。
  ⇒ 纪律：红线变更**无论增减**都要重贴实测值，
  且必须写明方向与理由。

⚠️ **为什么必须做成脚本而不是只写进文档**：
   规格里每个「不得 / 必须 / 恰」都要有一条**能变红**的判据，
   否则它只是措辞。本脚本就是判据 9 的执行体。

口径
----
· 权威数据源 = `test/snapshots/skill_prompt_anchor.json` 的 `prompt[*].len`
  （与 ADR 判据 7 的「skill_prompt_anchor 重冻」同一口径）。
· 单位 = **字符数**。
· ⚠️ **只对 diagnosis 组设红线**，不对全项目最大组设——
  实测training(68,475) / beginner(64,167) 等组在 ADR 阶段一**之前就已超 53,907**
  （HEAD 值即超），拿它当全局红线会让判据一开局就红、且与本批无关。
  真正的判据语义是「**不得回涨**」（相对变化），不是「绝对值须小于某数」。
· **受控组 vs 对照组**：`MUST_NOT_GROW` 是「本批不该动」的组；
  `REDLINE` 是「本批允许增长但有上限」的组。

force 分支的覆盖缺口（A2 批补上）
--------------------------------
`_kDiagnosisSceneFirst` 的注入条件是
`l2Mode == diagnosis || ctx.forceDiagnosisSceneFirst`，而该 flag 由
「用户消息措辞是否触发诊断协议」决定（`chat_service.dart:1255`）、**与 l2Mode 无关**
⇒ 非 diagnosis 组也会注入它。
★ 原 13 个快照用例**全不带**该 flag ⇒ 该路径**零体积基线覆盖**。
A2 批已补 `beginner_p3_yuesheng_forceSceneFirst`（66,237 = 65,628 + 609），
并列入 `REDLINE` 受控（给它上限，而不是当对照组 —— 它本来就该随该块增长）。

用法
----
    python tool/check_prompt_volume.py            # 读数 + 判定
    python tool/check_prompt_volume.py --json     # 机器可读
退出码：0 = 通过；1 = 超红线。
"""

import io
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANCHOR = os.path.join(ROOT, 'test', 'snapshots', 'skill_prompt_anchor.json')

# 舰长 2026-10-05 裁定的红线（= A2/A3 批落地后的实测值）
REDLINE = {
    'diagnosis_yuesheng': 55362,
    'diagnosis_p1_yuesheng': 53579,
    # ★ A2 批新增：force=true 用例。609 = _kDiagnosisSceneFirst 全块长度
    # （66,237 − 65,628），是 A2 批实测的「该块在非 diagnosis 组里的真实体积」。
    'beginner_p3_yuesheng_forceSceneFirst': 66237,
}
# 对照组：这些组本批不应增长（beginner 组不涉及新症候）
MUST_NOT_GROW = [
    'beginner_gentle', 'beginner_yuesheng', 'beginner_sensei',
    'beginner_p1_yuesheng', 'beginner_p3_yuesheng', 'beginner_p4_yuesheng',
    'none_p0_yuesheng',
]


def main():
    if not os.path.exists(ANCHOR):
        print('[FAIL] 锚点快照不存在：%s' % ANCHOR)
        print('       先跑 UPDATE_SNAPSHOTS=true flutter test '
              'test/services/skill_prompt_anchor_test.dart')
        return 1

    d = json.load(io.open(ANCHOR, encoding='utf-8'))
    prompt = d.get('prompt')
    if not isinstance(prompt, dict) or not prompt:
        print('[FAIL] 快照里没有 prompt 组 —— 口径变了？先核实再改本脚本')
        return 1

    #正对照：至少能读到若干组，且都带int len
    lens = {k: v.get('len') for k, v in prompt.items()}
    bad = [k for k, v in lens.items() if not isinstance(v, int)]
    if bad:
        print('[FAIL] 这些组缺 int型 len：%s' % bad)
        return 1
    if len(lens) < 5:
        print('[FAIL] 只读到 %d 组 ⇒ 扫描面过窄（正对照未过）' % len(lens))
        return 1

    out = {'redline': REDLINE, 'actual': {}, 'violations': []}

    print('=== 受控组（允许增长·有上限；上限来源：舰长裁定）===')
    for k, lim in sorted(REDLINE.items()):
        act = lens.get(k)
        if act is None:
            print('  %-24s ★快照中无此组' % k)
            out['violations'].append('%s: 快照缺该组' % k)
            continue
        out['actual'][k] = act
        ok = act <= lim
        print('  %-24s %6d  红线 %6d  余量 %+6d  %s'
              % (k, act, lim, lim - act, 'OK' if ok else '★超红线'))
        if not ok:
            out['violations'].append('%s: %d > 红线 %d（超 %d）'
                                     % (k, act, lim, act - lim))

    print('\n=== 对照组（本批不应增长）===')
    for k in MUST_NOT_GROW:
        act = lens.get(k)
        if act is None:
            print('  %-24s ★快照中无此组' % k)
            continue
        # 这些组的红线取「阶段一之前的 HEAD 值」——
        # 用 2026-10-05 实测的 HEAD 读数钉住，避免本脚本自己漂移。
        base = MUST_NOT_GROW_BASE.get(k)
        if base is None:
            print('  %-24s %6d  （无基线，仅读数）' % (k, act))
            continue
        ok = act <= base
        print('  %-24s %6d  基线 %6d  %+6d  %s'
              % (k, act, base, act - base, 'OK' if ok else '★增长'))
        if not ok:
            out['violations'].append('%s: %d > 基线 %d（增长 %d）'
                                     % (k, act, base, act - base))

    if '--json' in sys.argv:
        print('\n' + json.dumps(out, ensure_ascii=False, indent=2))

    print('')
    if out['violations']:
        print('[FAIL] %d 项超限：' % len(out['violations']))
        for v in out['violations']:
            print('  - ' + v)
        return 1
    print('[OK] 受控组均未超红线，且对照组零增长')


# 对照组基线 = 2026-10-05 A2/A3 批**动手前**的 HEAD 实测值。
# ⚠️ 刻意**不**因A2/A3 批上移：实测那6 个 beginner 组 + none_p0 **逐个不变**
#   （扩写的 _kDiagnosisSceneFirst 只在 `force=true` 时进入非 diagnosis 组，
#   而对照组 6 个用例都没设该 flag）⇒ 上移反而会**放松**对照，属越界。
MUST_NOT_GROW_BASE = {
    'beginner_gentle': 64167,
    'beginner_yuesheng': 64154,
    'beginner_sensei': 64022,
    'beginner_p1_yuesheng': 63845,
    'beginner_p3_yuesheng': 65628,
    'beginner_p4_yuesheng': 65628,
    'none_p0_yuesheng': 29812,
}


if __name__ == '__main__':
    sys.exit(main())
