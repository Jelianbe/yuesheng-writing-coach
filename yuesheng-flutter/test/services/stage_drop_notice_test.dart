// ─────────────────────────────────────────────────────────────
// stage_drop_notice_test — S1（R2）知情截断提示
//
// 覆盖：
//   1. X-040 素材缺失提示**逐字**回归（文案自 chat_service.dart
//      _logBudgetOutcome 逐字迁入 StageDropNotice，迁移纪律 = 逐字不动，
//      本组精确断言即冻结锚点）
//   2. ruleDetectors 观察线索缺失提示（新增；条数明示 = 知情截断，Q0）
//   3. 优先级：素材阶段与观察段同时被裁 → 素材提示优先（架构 §4.1 alt）
//   4. 无关阶段 / 空输入 → null（无需提示）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/token_budget_table.dart';
import 'package:writingcoach/services/stage_drop_notice.dart';

void main() {
  group('X-040 素材缺失提示（逐字回归锚点）', () {
    test('单素材阶段（references）→ 文案逐字一致', () {
      final notice = StageDropNotice.build([BudgetStageNames.references])!;
      expect(
        notice,
        '# 素材缺失提示（X-040 PHI）\n\n'
        '由于本轮 token 预算超限，已裁掉以下用户素材：'
        '${BudgetStageNames.references}。\n'
        '回复时：\n'
        '1. 不得假定素材内容直接给出诊断结论；\n'
        '2. 若回复需这些内容支撑，明确告知用户需重新提供或简化提供；\n'
        '3. 可基于现有上下文（活跃症候 + 历史对话）做方向性引导。',
      );
    });

    test('多素材阶段 → 按传入顺序 join（、），标题逐字不变', () {
      final notice = StageDropNotice.build([
        BudgetStageNames.fact,
        BudgetStageNames.attachedFiles,
      ])!;
      expect(notice, startsWith('# 素材缺失提示（X-040 PHI）\n\n'));
      expect(
        notice,
        contains(
          '已裁掉以下用户素材：'
          '${BudgetStageNames.fact}、${BudgetStageNames.attachedFiles}。',
        ),
      );
    });

    test('素材阶段与 ruleDetectors 同时被裁 → 素材提示优先（§4.1 alt）', () {
      final notice = StageDropNotice.build(
        [BudgetStageNames.ruleDetectors, BudgetStageNames.references],
        countByStage: {BudgetStageNames.ruleDetectors: 2},
      )!;
      expect(notice, startsWith('# 素材缺失提示（X-040 PHI）'));
      expect(notice, isNot(contains('观察线索')));
    });
  });

  group('ruleDetectors 观察线索缺失提示（新增，Q0 知情截断）', () {
    test('仅观察段被裁 → 明示让路条数（取自 countByStage）', () {
      final notice = StageDropNotice.build(
        [BudgetStageNames.ruleDetectors],
        countByStage: {BudgetStageNames.ruleDetectors: 3},
      )!;
      expect(notice, startsWith('# 观察线索缺失提示（预算让路）\n\n'));
      expect(notice, contains('规则观察段（3 条检测线索）已整体让路给教学主链路'));
      expect(notice, contains('本轮请勿假设存在矛盾/设定不一致/因果断裂/支线未收束/文法问题等观察线索'));
      expect(notice, contains('请说明本轮预算受限，引导其稍后重试或缩小诊断范围'));
    });

    test('countByStage 未提供该阶段 → 条数兜底 0（不崩、不省略括号）', () {
      final notice = StageDropNotice.build([BudgetStageNames.ruleDetectors])!;
      expect(notice, contains('规则观察段（0 条检测线索）'));
    });
  });

  group('无需提示 → null', () {
    test('被裁阶段均为非素材 / 非观察段 → null', () {
      expect(
        StageDropNotice.build([
          BudgetStageNames.studentProfile,
          BudgetStageNames.l3Structure,
        ]),
        isNull,
      );
    });

    test('空列表 → null', () {
      expect(StageDropNotice.build(const []), isNull);
    });
  });
}
