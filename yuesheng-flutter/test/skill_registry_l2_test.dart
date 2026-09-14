// ─────────────────────────────────────────────────────────────
// L2 按需层 skill 注册与组装验证
// 2026-08-08 批次 17：L2 五组内容搬运入 skill_registry（真源 RN skills/*.ts）
//
// 验证目标：
//   1. skillRegistry 注册完整性（L1 9 + 态度 3 + L2 25 = 37；v1 训练三件套已退役）
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

    test('L2 五组 25 个 skill 全部注册（v1 训练三件套已退役）', () {
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
        // training 组（v1 training-loop/training-evaluation/text-surgery 已退役，仅保留 v2 变体）
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
        expect(
          skill!.content,
          contains('| ${s.id} | $name |'),
          reason: '索引缺 ${s.id}',
        );
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

    test('Phase 2：共享本体按组注入 contextHint，且不串组', () {
      final diagnosis = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.yuesheng,
          subphase: TeachingSubphase.diagnosis,
        ),
      );
      // 同一共享本体在 diagnosis 组挂自己的语境指令
      expect(diagnosis.systemPrompt, contains('诊断语境：把症候映射到推荐动作卡'));
      expect(diagnosis.systemPrompt, contains('诊断语境：审视读者视角漏洞'));
      // 其它组的语境指令不应混入
      expect(diagnosis.systemPrompt, isNot(contains('训练语境：动作卡直接执行指引')));
      expect(diagnosis.systemPrompt, isNot(contains('大纲语境：大纲层面的读者体验预判')));

      final training = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.yuesheng,
          subphase: TeachingSubphase.practice,
        ),
      );
      // reader-awareness 同一本体，在 training 组换成训练语境
      expect(training.systemPrompt, contains('训练语境：聚焦反馈恐惧与读者视角的刻意练习'));
      expect(training.systemPrompt, isNot(contains('诊断语境：审视读者视角漏洞')));
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

  // ─────────────────────────────────────────────────────────────
  // Step 3c · 人格块（attitude）不变量守护（2026-09-14）
  //
  // 背景：人格档被建模为「注册表里的一个普通 skill」，但它在装配链里实际是
  // 一个**无条件注入、位置固定、不参与阶段切片**的 pinned block —— 这份契约
  // 此前只存在于 _buildL1Chunks 的实现细节里，没有任何判据守它。
  // 后果：若将来有人把 attitude 挪出 _buildL1Chunks（挪到 L2 之后）、给它挂
  // 上 contentForPhase（被阶段裁剪误伤）、或把它也挂进某个 l2SkillMap 组
  // （重复注入），十二道门禁全绿也不会察觉。
  //
  // 本组把该契约变成可执行判据。判据一律**锚定注入序（生效位置）**，
  // 不锚定注释或文件文本（V4.13：注释不是代码）。
  //
  // ⚠️ 本护栏已做变异验证（V4.7/V4.15 硬要求）：
  //    把 attitude 注入点从 _buildL1Chunks 挪到 _buildL2Chunks 之后 ⇒ 本组必须红。
  // ─────────────────────────────────────────────────────────────
  group('Step 3c · 人格块（attitude）不变量守护', () {
    /// 档位 → 期望注册 id（与 _buildL1Chunks 的 `'attitude-${attitude.value}'` 同源）
    String attitudeId(AttitudeLevel a) => 'attitude-${a.value}';

    /// 六个代表性语境，覆盖 resolveL2Mode 的全部返回值
    /// （none / beginner / diagnosis / training / advanced / outline）。
    List<SkillLoadContext> contextsFor(AttitudeLevel a) => [
      // none：P0 + 非零基础
      SkillLoadContext(phase: TeachingPhase.p0Engage, attitude: a),
      // beginner
      SkillLoadContext(
        phase: TeachingPhase.p0Engage,
        attitude: a,
        isBeginner: true,
      ),
      // diagnosis
      SkillLoadContext(
        phase: TeachingPhase.p2PracticeLoop,
        attitude: a,
        subphase: TeachingSubphase.diagnosis,
      ),
      // training
      SkillLoadContext(
        phase: TeachingPhase.p2PracticeLoop,
        attitude: a,
        subphase: TeachingSubphase.practice,
      ),
      // advanced
      SkillLoadContext(phase: TeachingPhase.p3Training, attitude: a),
      // outline
      SkillLoadContext(
        phase: TeachingPhase.p2PracticeLoop,
        attitude: a,
        isOutlineContext: true,
      ),
    ];

    test('L1 常驻恰好 9 件，且九件套内不含任何人格档（人格块是独立块）', () {
      expect(l1SkillIds.length, 9, reason: '九件套件数变了 ⇒ 人格块位置契约需重审');
      for (final id in l1SkillIds) {
        expect(
          id.startsWith('attitude-'),
          isFalse,
          reason: '$id 不应混入 L1 九件套（人格块应作为独立块在其后）',
        );
      }
    });

    test('恰好注入一次：每轮 loadedSkillIds 中人格块恰好 1 个，且就是当轮档位', () {
      for (final a in AttitudeLevel.values) {
        for (final ctx in contextsFor(a)) {
          final r = buildSystemPromptV2(ctx);
          final injected = r.loadedSkillIds
              .where((id) => id.startsWith('attitude-'))
              .toList();
          expect(
            injected,
            [attitudeId(a)],
            reason:
                '档=$a 模式=${r.l2Mode}：应恰好注入 1 个人格块且为 ${attitudeId(a)}，'
                '实际 $injected',
          );
        }
      }
    });

    test('位置不变量：人格块紧跟 L1 九件套之后、且在全部 L2 之前', () {
      for (final a in AttitudeLevel.values) {
        for (final ctx in contextsFor(a)) {
          final r = buildSystemPromptV2(ctx);
          final ids = r.loadedSkillIds;
          final iAtt = ids.indexOf(attitudeId(a));
          expect(
            iAtt,
            l1SkillIds.length,
            reason:
                '档=$a 模式=${r.l2Mode}：人格块下标应为 ${l1SkillIds.length}'
                '（紧跟九件套），实际 $iAtt',
          );
          // 前 9 位必须逐位是 l1SkillIds（顺序也算契约）
          expect(
            ids.sublist(0, l1SkillIds.length),
            l1SkillIds,
            reason: '档=$a 模式=${r.l2Mode}：L1 九件套前缀或顺序被改变',
          );
          // 人格块之后不得再出现任何 attitude-*（防重复注入 / 混入 L2）
          expect(
            ids
                .sublist(iAtt + 1)
                .where((id) => id.startsWith('attitude-'))
                .toList(),
            isEmpty,
            reason: '档=$a 模式=${r.l2Mode}：人格块在 L2 段重复出现',
          );
        }
      }
    });

    test('装配序全序 = [九件套...] + [人格块] + [L2 已注册项...]', () {
      for (final a in AttitudeLevel.values) {
        for (final ctx in contextsFor(a)) {
          final r = buildSystemPromptV2(ctx);
          // 期望的 L2 段 = getL2SkillIds(mode) 中「已注册」的 id
          //（未注册者被 dispatcher 静默跳过，与 _buildL2Chunks 同源）
          final expectedL2 = getL2SkillIds(r.l2Mode)
              .map((ref) => ref.skillId)
              .where((id) => skillRegistry[id] != null)
              .toList();
          expect(r.loadedSkillIds, [
            ...l1SkillIds,
            attitudeId(a),
            ...expectedL2,
          ], reason: '档=$a 模式=${r.l2Mode}：装配序偏离契约');
        }
      }
    });

    test('人格块不可被切片：三档均无 contentForPhase，且注入串 == content 全文', () {
      for (final a in AttitudeLevel.values) {
        final id = attitudeId(a);
        final skill = skillRegistry[id];
        expect(skill, isNotNull, reason: '缺失人格块 $id');
        expect(
          skill!.contentForPhase,
          isNull,
          reason: '$id 挂了阶段裁剪钩子 ⇒ 人格会被切片机制误伤',
        );
        // 注入串须逐字等于 content（未走任何裁剪路径）
        final r = buildSystemPromptV2(contextsFor(a).first);
        expect(
          r.systemPrompt.contains(skill.content),
          isTrue,
          reason: '$id 注入串不是 content 全文（疑似被裁剪）',
        );
      }
    });

    test('三档人格互斥：不同档位产出的 prompt 各自只含本档正文', () {
      final prompts = <AttitudeLevel, String>{
        for (final a in AttitudeLevel.values)
          a: buildSystemPromptV2(contextsFor(a).first).systemPrompt,
      };
      for (final a in AttitudeLevel.values) {
        for (final b in AttitudeLevel.values) {
          final bBody = skillRegistry[attitudeId(b)]!.content;
          final present = prompts[a]!.contains(bBody);
          expect(
            present,
            a == b,
            reason: a == b ? '档=$a 自身正文缺失' : '档=$a 的 prompt 混入了档=$b 的正文',
          );
        }
      }
    });

    test('位置引导 / 边界声明恒在末尾，且在人格块之后（chunk 序）', () {
      for (final a in AttitudeLevel.values) {
        // outline 模式 L2 最长，最能暴露「末段被 L2 挤走」类劣化
        final prompt = buildSystemPromptV2(contextsFor(a).last).systemPrompt;
        final iPosition = prompt.indexOf('## 内容位置判断（必读）');
        final iBoundary = prompt.lastIndexOf('【边界声明】');
        expect(iPosition, greaterThan(0), reason: '档=$a：位置引导缺失');
        expect(iBoundary, greaterThan(0), reason: '档=$a：边界声明缺失');
        expect(iPosition, lessThan(iBoundary), reason: '档=$a：位置引导应在边界声明之前');
        expect(
          prompt.indexOf(skillRegistry[attitudeId(a)]!.content),
          lessThan(iPosition),
          reason: '档=$a：人格块应位于位置引导之前（不得被挤到末段）',
        );
      }
    });

    test('人格块不参与 L2：三档 id 均不出现在任何 l2SkillMap 组内', () {
      for (final a in AttitudeLevel.values) {
        final id = attitudeId(a);
        for (final entry in l2SkillMap.entries) {
          expect(
            entry.value.map((ref) => ref.skillId),
            isNot(contains(id)),
            reason: '$id 不应挂进 L2 组 ${entry.key}（会重复注入）',
          );
        }
      }
    });
  });
}
