// ─────────────────────────────────────────────────────────────
// L2 按需层 skill 注册与组装验证
// 2026-08-08 批次 17：L2 五组内容搬运入 skill_registry（真源 RN skills/*.ts）
//
// 验证目标：
//   1. skillRegistry 注册完整性（L1 9 + 态度 3 + L2 30 = 42）
//   2. buildSystemPromptV2 各 L2 模式实际加载断言
//   3. 虚拟索引 skill（syndrome-diagnosis-index / technique-library-index）
//      在 dispatcher 中静默跳过、不报错
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/skill_layers.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('skillRegistry 注册完整性', () {
    test('L1 常驻 9 个核心 skill 已注册', () {
      for (final id in l1SkillIds) {
        expect(skillRegistry[id], isNotNull, reason: '缺失 L1 skill: $id');
      }
    });

    test('3 个态度档位 skill 已注册', () {
      for (final id in [
        'attitude-doubao',
        'attitude-yuesheng',
        'attitude-sensei',
      ]) {
        expect(skillRegistry[id], isNotNull, reason: '缺失态度 skill: $id');
      }
    });

    test('L2 五组 28 个 skill 全部注册（含 v2 变体）', () {
      const expected = {
        // beginner 组
        'beginner-path',
        'gap-detector',
        'coaching-rhythm',
        'narrative-design',
        'plot-design',
        'writer-psychology',
        // diagnosis 组（新增 6；coaching-rhythm/narrative-design/plot-design 与 beginner 共用）
        // 注：v1 coaching-actions 已于 B12 死负载清理中移除，仅保留 v2 变体
        'reader-awareness',
        'genre-guide',
        'writing-style',
        'diagnosis-confirmation',
        'feedback-cognition',
        // training 组
        'training-loop',
        'training-loop-v2',
        'training-templates-index',
        'training-evaluation',
        'training-evaluation-v2',
        'text-surgery',
        'text-surgery-v2',
        'coaching-actions-v2',
        'demonstration',
        'comparison',
        'timed-rewrite',
        'model-rewrite',
        'revision-methodology',
        // advanced 组
        'advanced-phases',
        // outline 组
        'outline-diagnosis',
        // 虚拟索引 skill（2026-08-08 批次 22 步骤②：索引内容注册）
        'syndrome-diagnosis-index',
        'technique-library-index',
      };
      for (final id in expected) {
        expect(skillRegistry[id], isNotNull, reason: '缺失 L2 skill: $id');
      }
      // 批次65：L1 9（含 reply-voice）+ 态度 3 = 12
      expect(skillRegistry.length, 12 + expected.length);
    });

    test('skill 内容非空且非占位', () {
      skillRegistry.forEach((id, skill) {
        expect(skill.content.trim(), isNotEmpty, reason: '$id 内容为空');
        expect(skill.content.length, greaterThan(100), reason: '$id 内容疑似占位');
      });
    });

    test('training-templates-index 教学知识索引覆盖全部症候（b9 批次31 注册表派生）', () {
      final skill = skillRegistry['training-templates-index'];
      expect(skill, isNotNull);
      for (final s in kSyndromeRegistry) {
        final name = s.id == 'P022' ? '重复用词/基础语病症' : s.shortName;
        expect(skill!.content, contains('| ${s.id} | $name |'),
            reason: '索引缺 ${s.id}');
      }
      // 头部声明的症候数为注册表派生计数
      expect(skill!.content, contains('仅含 ${kSyndromeRegistry.length} 条症候'));
    });
  });

  group('buildSystemPromptV2 组装', () {
    test('beginner 模式加载 beginner 组 6 个 skill', () {
      final r = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p0Engage,
          attitude: AttitudeLevel.yuesheng,
          isBeginner: true,
        ),
      );
      expect(r.l2Mode, L2Mode.beginner);
      for (final id in [
        'beginner-path',
        'gap-detector',
        'coaching-rhythm',
        'narrative-design',
        'plot-design',
        'writer-psychology',
      ]) {
        expect(r.loadedSkillIds, contains(id), reason: 'beginner 模式缺 $id');
      }
      expect(r.systemPrompt, contains('零基础教学路径'));
    });

    test('diagnosis 模式加载 diagnosis 组核心 skill', () {
      final r = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.yuesheng,
          subphase: TeachingSubphase.diagnosis,
        ),
      );
      expect(r.l2Mode, L2Mode.diagnosis);
      for (final id in [
        // V2 开关下 coaching-actions 被替换为 coaching-actions-v2（diagnosis 模式同样替换）
        'coaching-actions-v2',
        'reader-awareness',
        'genre-guide',
        'writing-style',
        'diagnosis-confirmation',
        'feedback-cognition',
        'coaching-rhythm',
        'narrative-design',
        'plot-design',
        // 2026-08-08 批次 22 步骤②：索引 skill 注册后不再跳过
        'syndrome-diagnosis-index',
      ]) {
        expect(r.loadedSkillIds, contains(id), reason: 'diagnosis 模式缺 $id');
      }
      // 2026-08-08 批次 22 步骤②：索引 skill 已注册并加载
      expect(r.systemPrompt, contains('教学方法目录'));
    });

    test('training 模式（V2 开关）加载 v2 替换后的 skill', () {
      final r = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.yuesheng,
          subphase: TeachingSubphase.practice,
        ),
      );
      expect(r.l2Mode, L2Mode.training);
      for (final id in [
        'training-loop-v2',
        'training-templates-index',
        'training-evaluation-v2',
        'text-surgery-v2',
        'coaching-actions-v2',
        'demonstration',
        'comparison',
        'timed-rewrite',
        'model-rewrite',
        'revision-methodology',
        'reader-awareness',
        'writer-psychology',
        // 2026-08-08 批次 22 步骤②：技法索引 skill 注册后加载
        'technique-library-index',
      ]) {
        expect(r.loadedSkillIds, contains(id), reason: 'training 模式缺 $id');
      }
      // V2 替换生效：v1 训练 skill 不应加载
      expect(r.loadedSkillIds, isNot(contains('training-loop')));
      expect(r.loadedSkillIds, isNot(contains('text-surgery')));
      expect(r.systemPrompt, contains('训练循环指南'));
    });

    test('advanced 模式加载 advanced-phases', () {
      final r = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p3Training,
          attitude: AttitudeLevel.sensei,
        ),
      );
      expect(r.l2Mode, L2Mode.advanced);
      expect(r.loadedSkillIds, contains('advanced-phases'));
      expect(r.systemPrompt, contains('进阶阶段指引'));
    });

    test('outline 模式加载 outline-diagnosis', () {
      final r = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.yuesheng,
          isOutlineContext: true,
        ),
      );
      expect(r.l2Mode, L2Mode.outline);
      expect(r.loadedSkillIds, contains('outline-diagnosis'));
      expect(r.systemPrompt, contains('大纲结构诊断'));
    });

    test('token 估算在预算内且 validatePrompt 通过', () {
      final r = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.yuesheng,
          subphase: TeachingSubphase.diagnosis,
        ),
      );
      final v = validatePrompt(r.systemPrompt);
      expect(v.valid, isTrue, reason: 'errors: ${v.errors}');
      expect(r.estimatedTokens, greaterThan(1000));
    });
  });
}
