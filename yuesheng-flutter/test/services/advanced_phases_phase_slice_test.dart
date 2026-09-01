// ─────────────────────────────────────────────────────────────
// advanced-phases 阶段裁剪验证（Phase 3 A 组）
//
// 方案：docs/designs/2026-08-28-skill-orthogonal-refactor-plan.md §5
// 背景：索引化缺检索触发源（见 skills_advanced_outline_p7.dart 头注释），
//      故改为状态驱动裁剪。本测试守护三件事：
//      1. 非进阶阶段逐字节回退原文（行为与裁剪前完全一致）
//      2. 当前阶段分段注入、非当前阶段分段不注入
//      3. 切片是原文子串（零编辑漂移，知识未被改写）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 完整原文（未裁剪）
String get _raw => skillRegistry['advanced-phases']!.content;

/// 从原文按标题边界切出片段（与被测实现同一套锚点，验证子串纯正性）
String _slice(String start, String end) {
  final s = _raw.indexOf(start);
  expect(s, greaterThanOrEqualTo(0), reason: '原文缺锚点: $start');
  final e = _raw.indexOf(end, s + start.length);
  return _raw.substring(s, e < 0 ? _raw.length : e).trim();
}

void main() {
  group('advanced-phases 阶段裁剪', () {
    test('非进阶阶段（P0/P1/P2）逐字节回退原文', () {
      for (final phase in [
        TeachingPhase.p0Engage,
        TeachingPhase.p1World,
        TeachingPhase.p2PracticeLoop,
      ]) {
        expect(
          advancedPhasesContentFor(phase),
          _raw,
          reason: '${phase.value} 未回退完整原文',
        );
      }
    });

    test('P3 档注入 P3 分段、不含 P4 分段', () {
      final p3 = advancedPhasesContentFor(TeachingPhase.p3Training);
      expect(p3, contains('### P3 教学重点'));
      expect(p3, contains('### P3 态度策略'));
      expect(p3, contains('### P3 → P4'));
      expect(p3, isNot(contains('### P4 教学重点')));
      expect(p3, isNot(contains('### P4 态度策略')));
      // 已发生的迁移（P2→P3）与不可达段（P5）不注入
      expect(p3, isNot(contains('### P2 → P3')));
      expect(p3, isNot(contains('## P5 持续创作陪伴')));
      // 迁移约束为通用规则，两档都要保留
      expect(p3, contains('### 迁移约束'));
    });

    test('P4 档注入 P4 分段、不含 P3 分段', () {
      final p4 = advancedPhasesContentFor(TeachingPhase.p4Review);
      expect(p4, contains('### P4 教学重点'));
      expect(p4, contains('### P4 态度策略'));
      expect(p4, contains('### P4 → P2（重新开始）'));
      expect(p4, isNot(contains('### P3 教学重点')));
      expect(p4, isNot(contains('### P3 态度策略')));
      expect(p4, isNot(contains('### P3 → P4')));
      expect(p4, contains('### 迁移约束'));
    });

    test('切片为原文子串（零编辑漂移）', () {
      final p3 = advancedPhasesContentFor(TeachingPhase.p3Training);
      final p4 = advancedPhasesContentFor(TeachingPhase.p4Review);
      expect(p3, contains(_slice('### P3 教学重点', '### P3 教学流程')));
      expect(p4, contains(_slice('### P4 教学重点', '### P4 教学流程')));
      expect(p3, contains(_slice('### P3 态度策略', '### P4 态度策略')));
      expect(p4, contains(_slice('### P4 态度策略', '## 阶段迁移规则')));
    });

    test('防复发：P5 幽灵阶段不得回归（C56/ADR-C54 §9-D）', () {
      expect(
        _raw,
        isNot(contains('P5')),
        reason: 'advanced-phases 不得再出现幽灵阶段 P5（C56）',
      );
      expect(
        skillRegistry['writing-style']!.content,
        isNot(contains('P5')),
        reason: 'writing-style 不得再出现幽灵阶段 P5（C56）',
      );
      final p3 = advancedPhasesContentFor(TeachingPhase.p3Training);
      final p4 = advancedPhasesContentFor(TeachingPhase.p4Review);
      expect(p3, isNot(contains('P5')));
      expect(p4, isNot(contains('P5')));
      // P4 唯一出口的动作行必须显式指向 P2（不再有「下一个阶段」的含糊提法）
      expect(p4, contains('"suggested_phase": "P2_PRACTICE_LOOP"'));
    });

    test('防复发：P4 教学流程须带示例标注与数据兜底（C59/C61/C66）', () {
      final p4 = advancedPhasesContentFor(TeachingPhase.p4Review);
      // C61：台词必须标注「示例，不是台词」（B-23 已给 beginner 侧加过，
      // advanced 侧漏加，而这些台词还预设了症候名与解决状态，风险更高）
      expect(p4, contains('示例，不是台词'));
      // C59：五步全都依赖历史数据，必须写明「没有时怎么办」
      expect(p4, contains('数据兜底'));
      expect(p4, contains('没有可比的两稿'));
      expect(p4, contains('没有症候严重度变化记录'));
      // C66：与 V-10（🔴 致命）冲突时 V-10 优先（B-22 家族第 3 次）
      expect(p4, contains('V-10 优先'));
      expect(p4, contains('不产进步'));
    });

    test('防复发：P4 输出要求的示例数值须声明来源（C60）', () {
      final p4 = advancedPhasesContentFor(TeachingPhase.p4Review);
      expect(p4, contains('数值同样是示例'));
      expect(p4, contains('指不出来源的数字不要'));
    });

    test('防复发：P4→P2 迁移信号为 OR 且停留 P4 是正常态（C62）', () {
      final p4 = advancedPhasesContentFor(TeachingPhase.p4Review);
      expect(p4, contains('满足任一即可'));
      expect(p4, contains('停留在 P4 是正常状态'));
      // AND 版三条件不得回归——它每轮判定为假会把学员永久留在 P4
      expect(p4, isNot(contains('仍有 L2 以上的症候需要系统训练')));
    });

    test('防复发：复习调度不得「上限 2」与「一次聚焦一个」并存（B-22 家族第 4 次）', () {
      final p3 = advancedPhasesContentFor(TeachingPhase.p3Training);
      expect(p3, contains('一次聚焦一个到期症候'));
      expect(p3, contains('至多 2 个'));
      // 旧写法把上限与聚焦并列、未说清什么情况下可以用满 2 个
      expect(p3, isNot(contains('不要同时复习超过 2 个到期症候')));
    });

    test('裁剪确实降低体积（两档均小于原文）', () {
      final p3 = advancedPhasesContentFor(TeachingPhase.p3Training);
      final p4 = advancedPhasesContentFor(TeachingPhase.p4Review);
      expect(p3.length, lessThan(_raw.length));
      expect(p4.length, lessThan(_raw.length));
      // 标志文本必须保留（既有测试依赖它判定进阶组已加载）
      expect(p3, contains('进阶阶段指引'));
      expect(p4, contains('进阶阶段指引'));
    });
  });

  group('dispatcher 按阶段注入', () {
    test('advanced 模式（P3）prompt 含 P3 分段且不含 P4 分段', () {
      final r = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p3Training,
          attitude: AttitudeLevel.sensei,
        ),
      );
      expect(r.l2Mode, L2Mode.advanced);
      expect(r.systemPrompt, contains('### P3 教学重点'));
      expect(r.systemPrompt, isNot(contains('### P4 教学重点')));
      expect(r.systemPrompt, contains('进阶阶段指引'));
    });

    test('P4 场景下 P4 档与 L1 常驻层信号同源（V-05 第 7 对 + C63/C64）', () {
      final r = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p4Review,
          attitude: AttitudeLevel.yuesheng,
        ),
      );
      final p = r.systemPrompt;
      // V-05 第 7 对：两处 P4→P2 信号必须同为 OR
      // （此前 L1 常驻侧是 OR、advanced 侧是 AND 三条件，逻辑运算符相反）
      expect(p, contains('满足任一即可'));
      expect(p, contains('学员完成复盘，或携带新的文本'));
      // C63：P4「不引入新训练任务」让位于学员主动提出的目标（R-009 用户主权）
      expect(p, contains('学员主动提出新目标时以学员为准'));
      // C64：§3.6 隐性诊断铁律与 §9.1 自然语言转述的调和说明
      expect(p, contains('与 §9.1'));
      expect(p, contains('暴露内部编号（V-03）'));
    });

    test('非 advanced 模式不受裁剪影响', () {
      final r = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.yuesheng,
          subphase: TeachingSubphase.diagnosis,
        ),
      );
      expect(r.l2Mode, L2Mode.diagnosis);
      expect(r.systemPrompt, isNot(contains('### P3 教学重点')));
    });
  });
}
