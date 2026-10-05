"""ADR-0003 判据 9体积红线的可执行检查（阶段一）。

背景
----
ADR-0003 §5 判据 9 要求「阶段一注入后 diagnosis 组体积实测，**不得回涨到C99 减编前水平**」。
舰长 2026-10-05 裁定：红线 = 「不超当前实测值」，并**认可本阶段必要增量**——
`diagnosis_yuesheng` 由 53,907 → **54,285**（+378，源于三条新症候的索引行自动渲染），
基准上移至 54,285。

⚠️ **为什么必须做成脚本而不是只写进文档**：
   规格里每个「不得 / 必须 / 恰」都要有一条**能变红**的判据，
   否则它只是措辞。本脚本就是判据 9 的执行体。

口径
----
· 权威数据源 = `test/snapshots/skill_prompt_anchor.json` 的 `prompt[*].len`
  （与 ADR 判据 7 的「skill_prompt_anchor 重冻」同一口径）。
· 单位 = **字符数**。
· ⚠️ **只对 diagnosis 组设红线**，不对全项目最大组设 ——
  实测training(68,475) / beginner(64,167) 等组在 ADR 阶段一**之前就已超 53,907**
  （HEAD 值即超），拿它当全局红线会让判据一开局就红、且与本批无关。
  真正的判据语义是「**不得回涨**」（相对变化），不是「绝对值须小于某数」。

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

# 舰长 2026-10-05 裁定的红线（= 阶段一落地后的实测值）
REDLINE = {
    'diagnosis_yuesheng': 54285,
    'diagnosis_p1_yuesheng': 52502,
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

    print('=== diagnosis 组体积（红线来源：舰长 2026-10-05 裁定）===')
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
    print('[OK] diagnosis 组未超红线 %d，且对照组零增长'
          % REDLINE['diagnosis_yuesheng'])
    return 0


# 2026-10-05 实测的 HEAD 值（阶段一动手前）—— 对照组基线
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
