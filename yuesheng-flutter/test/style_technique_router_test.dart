// ─────────────────────────────────────────────────────────────
// 文笔画像 → 技法旁路路由测试（2026-08-18 批次）
// 设计：docs/2026-08-18-style-technique-bypass-routing-design.md §5 验证计划
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/style_technique_router.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/types/teaching_types.dart';

WritingStyleProfile _profile({
  SensoryPreference sensory = SensoryPreference.balanced,
  RhythmPreference rhythm = RhythmPreference.alternating,
  NarrativeDistance narrativeDistance = NarrativeDistance.fluid,
  ToneTexture toneTexture = ToneTexture.spare,
  StructureInstinct structure = StructureInstinct.linear,
}) {
  return WritingStyleProfile(
    sensory: sensory,
    rhythm: rhythm,
    narrativeDistance: narrativeDistance,
    toneTexture: toneTexture,
    structure: structure,
    summary: '测试画像',
  );
}

ActiveSyndromeView _view(String id, String name, Severity severity) =>
    ActiveSyndromeView(syndromeId: id, syndromeName: name, severity: severity);

ActiveProblemView _problem(String id, {String? teachingState}) =>
    ActiveProblemView(
      syndromeId: id,
      syndromeName: '症候$id',
      severity: 'L1',
      confirmationStatus: 'confirmed',
      teachingState: teachingState,
    );

void main() {
  group('kTechniqueLayers 完备性', () {
    test('31 个技法全部有 layer 标签', () {
      expect(kTechniqueLayers.keys.toSet(), kTechniqueShortNames.keys.toSet());
    });

    test('映射表引用的技法 ID 全部存在', () {
      for (final m in kStyleDimensionTechniques) {
        for (final t in m.techniqueIds) {
          expect(
            kTechniqueShortNames.containsKey(t),
            isTrue,
            reason: '${m.dimensionKey} 引用了不存在的技法 $t',
          );
        }
      }
    });

    test('五维非健康值全部有映射（健康/中性值不进映射）', () {
      // 非健康值全集（与设计 §3.2 一致）
      const expectedKeys = {
        'rhythm:long',
        'rhythm:short',
        'rhythm:repetitive',
        'sensory:visual',
        'sensory:auditory',
        'sensory:kinesthetic',
        'toneTexture:poetic',
        'narrativeDistance:intimate',
        'narrativeDistance:editorial',
        'structure:fragmented',
      };
      final actualKeys = kStyleDimensionTechniques
          .map((m) => m.dimensionKey)
          .toSet();
      expect(actualKeys, expectedKeys);

      // 健康/中性值不得出现在映射表
      const healthyKeys = {
        'rhythm:alternating',
        'sensory:balanced',
        'narrativeDistance:fluid',
        'narrativeDistance:observational',
        'toneTexture:spare',
        'toneTexture:elegant',
        'toneTexture:colloquial',
        'structure:linear',
        'structure:circular',
        'structure:divergent',
      };
      for (final k in healthyKeys) {
        expect(actualKeys.contains(k), isFalse, reason: '健康值 $k 不应进映射');
      }
    });

    test('唯一跨层条目 structure:fragmented 显式标注 crossLayer', () {
      final cross = kStyleDimensionTechniques
          .where((m) => m.crossLayer)
          .toList();
      expect(cross.length, 1);
      expect(cross.single.dimensionKey, 'structure:fragmented');
      expect(
        kTechniqueLayers[cross.single.techniqueIds.single],
        TechniqueLayer.content,
      );
    });
  });

  group('routeStyleTechniques 门控', () {
    test('门控1：画像未沉淀 → 空', () {
      final s = routeStyleTechniques(
        styleProfile: null,
        activeProblems: const [],
      );
      expect(s.isEmpty, isTrue);
      expect(s.gatedBy, 'no_profile');
    });

    test('健康画像（全中性值）→ 无候选', () {
      final s = routeStyleTechniques(
        styleProfile: _profile(),
        activeProblems: const [],
      );
      expect(s.isEmpty, isTrue);
      expect(s.gatedBy, '');
    });

    test('rhythm=long 无活跃症候 → T023 候选', () {
      final s = routeStyleTechniques(
        styleProfile: _profile(rhythm: RhythmPreference.long),
        activeProblems: const [],
      );
      expect(s.candidates.map((c) => c.techniqueId), ['T023']);
      expect(s.gatedBy, '');
    });

    test('门控2：L3 内容层症候活跃（P006）→ 不抢占', () {
      final s = routeStyleTechniques(
        styleProfile: _profile(rhythm: RhythmPreference.long),
        activeProblems: [_view('P006', '节奏停滞', Severity.l3)],
      );
      expect(s.isEmpty, isTrue);
      expect(s.gatedBy, 'content_priority');
    });

    test('门控2：L1 症候不拦截（轻症不阻塞文笔候选）', () {
      final s = routeStyleTechniques(
        styleProfile: _profile(rhythm: RhythmPreference.long),
        activeProblems: [_view('P006', '节奏停滞', Severity.l1)],
      );
      expect(s.isEmpty, isFalse);
      expect(s.candidates.single.techniqueId, 'T023');
    });

    test('门控2：L2 文笔层主导症候（P007 句式节奏）活跃 → 不拦截', () {
      final s = routeStyleTechniques(
        styleProfile: _profile(sensory: SensoryPreference.visual),
        activeProblems: [_view('P007', '句式节奏单一', Severity.l2)],
      );
      expect(s.isEmpty, isFalse);
      expect(s.candidates.single.techniqueId, 'T002');
    });

    test('门控3：焦点症候技法已含文笔层（P003）→ 不重复', () {
      final s = routeStyleTechniques(
        styleProfile: _profile(rhythm: RhythmPreference.long),
        activeProblems: const [],
        focusSyndromeId: 'P003',
      );
      expect(s.isEmpty, isTrue);
      expect(s.gatedBy, 'focus_covers_prose');
    });

    test('门控3：内容层焦点症候（P006）→ 旁路照常供给', () {
      final s = routeStyleTechniques(
        styleProfile: _profile(rhythm: RhythmPreference.long),
        activeProblems: const [],
        focusSyndromeId: 'P006',
      );
      expect(s.candidates.single.techniqueId, 'T023');
    });

    test('门控4：mastered 技法被过滤', () {
      final s = routeStyleTechniques(
        styleProfile: _profile(rhythm: RhythmPreference.long),
        activeProblems: const [],
        masteredTechniqueIds: {'T023'},
      );
      expect(s.isEmpty, isTrue);
    });

    test('门控4：多维度非健康 → 最多 2 条候选且去重', () {
      final s = routeStyleTechniques(
        styleProfile: _profile(
          rhythm: RhythmPreference.repetitive,
          sensory: SensoryPreference.auditory,
          toneTexture: ToneTexture.poetic,
        ),
        activeProblems: const [],
      );
      expect(s.candidates.length, 2);
      expect(s.candidates.map((c) => c.techniqueId).toSet().length, 2);
    });

    test('structure=fragmented → 跨层候选 T029 且带标注', () {
      final s = routeStyleTechniques(
        styleProfile: _profile(structure: StructureInstinct.fragmented),
        activeProblems: const [],
      );
      final c = s.candidates.single;
      expect(c.techniqueId, 'T029');
      expect(c.crossLayer, isTrue);
    });
  });

  group('deriveMasteredTechniqueIds（症候级 mastered → 技法集合派生）', () {
    test('mastered 症候 → 派生其全部映射技法（P007 → T019/T023/T025）', () {
      final ids = deriveMasteredTechniqueIds([
        _problem('P007', teachingState: TeachingState.mastered.value),
      ]);
      expect(ids, {'T019', 'T023', 'T025'});
    });

    test('非 mastered 状态（identified/in_progress/consolidating）→ 不派生', () {
      for (final s in TeachingState.values) {
        if (s == TeachingState.mastered) continue;
        final ids = deriveMasteredTechniqueIds([
          _problem('P007', teachingState: s.value),
        ]);
        expect(ids, isEmpty, reason: '${s.value} 不应派生技法');
      }
    });

    test('teachingState 为 null（历史症候未写教学态）→ 不派生', () {
      final ids = deriveMasteredTechniqueIds([_problem('P007')]);
      expect(ids, isEmpty);
    });

    test('未知症候 mastered（映射表无此症候）→ 空集合不崩', () {
      final ids = deriveMasteredTechniqueIds([
        _problem('s1', teachingState: TeachingState.mastered.value),
      ]);
      expect(ids, isEmpty);
    });

    test('组合：mastered 派生的集合传入路由 → 候选被排除', () {
      final ids = deriveMasteredTechniqueIds([
        _problem('P007', teachingState: TeachingState.mastered.value),
      ]);
      final s = routeStyleTechniques(
        styleProfile: _profile(rhythm: RhythmPreference.long),
        activeProblems: const [],
        masteredTechniqueIds: ids,
      );
      // rhythm=long 候选 T023 已被 P007 mastered 派生覆盖 → 无候选
      expect(s.isEmpty, isTrue);
    });
  });

  group('formatStyleTechniqueSection', () {
    test('无候选 → null（零注入成本）', () {
      expect(
        formatStyleTechniqueSection(const StyleTechniqueSuggestion()),
        isNull,
      );
    });

    test('有候选 → 含旁路标题/技法名/不并行教学约束', () {
      final s = routeStyleTechniques(
        styleProfile: _profile(rhythm: RhythmPreference.long),
        activeProblems: const [],
      );
      final text = formatStyleTechniqueSection(s)!;
      expect(text, contains('✒️ 文笔精修候选'));
      expect(text, contains('T023 句速控制法'));
      expect(text, contains('节奏偏好=长句型'));
      expect(text, contains('不与当前教学焦点并行教学'));
      expect(text, contains('不暴露编号'));
    });
  });

  group('buildStructuredSyndromeContext 旁路段接入', () {
    test('传 styleTechniqueSection → 追加在症候段之后', () {
      final text = buildStructuredSyndromeContext([
        _view('P007', '句式节奏单一', Severity.l1),
      ], styleTechniqueSection: '### ✒️ 文笔精修候选（画像旁路）\n- T023 句速控制法');
      expect(text, contains('P007'));
      expect(text, contains('✒️ 文笔精修候选'));
      expect(text.indexOf('P007'), lessThan(text.indexOf('✒️')));
    });

    test('不传（null）→ 行为与旧版一致，无旁路段', () {
      final text = buildStructuredSyndromeContext([
        _view('P006', '节奏停滞', Severity.l2),
      ]);
      expect(text, contains('P006'));
      expect(text, isNot(contains('✒️')));
    });
  });
}
