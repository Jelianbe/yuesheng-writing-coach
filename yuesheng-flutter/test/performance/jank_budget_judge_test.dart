// ─────────────────────────────────────────────────────────────
// jank_budget_judge_test.dart — 帧时预算判据的**离线单测**（验「判据真的会红」）
//
// 为什么这个能放 `test/`：它验的是**纯函数** `judgeFrameBudget`，不需要真实帧时。
// 真实帧时那条断言必须放 `integration_test/`（`test/` 下 addTimingsCallback 收 0 帧，
// 见 jank_budget_assert_test.dart 文件头注释 —— 此为实测结论，非推断）。
//
// 本文档的作用 = 让判据**在无设备环境也能被验证**。
// 否则「判据有没有生效」只能靠真机手跑，等于判据本身不可测。
//
// 逐条断言必须**各自独立守一处**（已用三次单侧变异验过，见 DECISIONS §4-599）：
// 删 L1 门槛 ⇒ 只有②红；删 L2 判定 ⇒ 只有③红（其余仍绿）。
// 这证明断言之间没有互相掩护 —— 一组里若只有一条真在起拦截作用，其余就是凑数。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

// 判据核心在 integration_test/ 下（不在 lib/，因为只有那里能在真设备取帧时）。
// 用相对路径 import —— `package:writingcoach/../integration_test/...` 不合法（实测编译失败）。
import '../../integration_test/jank_budget.dart'
    show frameStats, judgeFrameBudget, kMaxJankPct, kMinFrames;

void main() {
  group('judgeFrameBudget — 判据必须真的会红', () {
    test('① 阳性：jank 在预算内 ⇒ 通过（不误报）', () {
      // median=6.2ms, max=22.3ms, jankPct=3.2% —— 取自 5000 字真机实测值
      const stats = [3.8, 6.2, 22.3, 3.2];
      final v = judgeFrameBudget(stats, frameCount: 1077);
      expect(v, isNull, reason: '实测 3.2% 在 10% 预算内，不应报错，实际：$v');
    });

    test('② 负向 L1：采样不足 ⇒ 必须报（防「采不到=通过」）', () {
      // 即使 stats 显示完美，采样不够也必须拒判
      const stats = [2.9, 5.2, 13.4, 0.0];
      final v = judgeFrameBudget(stats, frameCount: kMinFrames - 1);
      expect(v, isNotNull, reason: 'L1 采样门槛失效：frames=${kMinFrames - 1} 竟然通过了');
      expect(v, contains('L1'), reason: '失败信息须能归因到 L1，实际：$v');
    });

    test('③ 负向 L2：jank 占比超预算 ⇒ 必须报', () {
      // 取自 10 万字真机实测值 jankPct=54.8%
      const stats = [2.8, 18.3, 33.6, 54.8];
      final v = judgeFrameBudget(stats, frameCount: 1075);
      expect(v, isNotNull, reason: 'L2 占比判定失效：实测 54.8% 竟然通过了');
      expect(v, contains('L2'), reason: '失败信息须能归因到 L2，实际：$v');
    });

    test('④ 边界：jankPct 恰等于预算 ⇒ 通过（判据用 > 不用 >=）', () {
      final stats = [3.0, 6.0, 20.0, kMaxJankPct];
      final v = judgeFrameBudget(stats, frameCount: 1000);
      expect(v, isNull, reason: '边界值应视为达标（判据用 > 不用 >=），实际：$v');
    });

    test('⑤ 空帧统计不崩且不误判为通过（frames=0 必须被 L1 拦住）', () {
      final s = frameStats(const []);
      expect(s, [0, 0, 0, 0], reason: '空列表须返回零值而非抛异常');
      final v = judgeFrameBudget(s, frameCount: 0);
      expect(v, isNotNull, reason: '空输入必须被 L1 拦住，否则「没采到」会被当成「完美」');
      expect(v, contains('L1'), reason: '空输入应归因到 L1，实际：$v');
    });
  });
}
