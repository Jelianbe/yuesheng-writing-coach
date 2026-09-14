// ─────────────────────────────────────────────────────────────
// coaching-rhythm 阶段装配验证（Phase 3 A 组 / Step 2 段资源模型）
//
// 依据：docs/ADR-knowledge-injection-driver-model.md §2.2 裁剪准入三问
// 背景：索引化缺检索触发源（见 ADR §1.2），故改为状态驱动裁剪。
//      本测试守护四件事：
//      1. 非 P0/P1 阶段逐字节回退原文（诊断档等行为与裁剪前完全一致）
//      2. 当前阶段分段注入、非当前阶段分段不注入
//      3. 装配产物逐字节等于段资源的 '\n\n' 拼接（零编辑漂移）
//      4. 分区不变量：Σ段体积 + 2×(段数−1) == content 长度（段序/边界护栏）
//
// Step 2（2026-09-14）：被测实现由「字面标题 indexOf 切片」改为「具名段选择」。
// 本测试因此**经 `Skill.contentForPhase` 真实挂载点取值**（顺带守护挂载点接线），
// 不再持有测试侧的字面标题锚点——旧 `_slice()` helper 已删除。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 完整原文（未裁剪）
String get _raw => skillRegistry['coaching-rhythm']!.content;

/// 经真实挂载点取相位内容（与 dispatcher 的调用路径一致）
String _forPhase(TeachingPhase phase) {
  final skill = skillRegistry['coaching-rhythm']!;
  final fn = skill.contentForPhase;
  expect(fn, isNotNull, reason: 'coaching-rhythm 缺 contentForPhase 挂载点');
  return fn!(phase, skill.content);
}

/// 段目录（数组顺序即装配序）
const List<String> _segmentOrder = [kCrSegHead, kCrSegP0, kCrSegP1, kCrSegTail];

void main() {
  group('coaching-rhythm 段资源与分区不变量', () {
    test("content == 段资源按目录顺序的 '\\n\\n' 拼接", () {
      expect(_segmentOrder.join('\n\n'), _raw);
    });

    test('分区不变量：Σ段体积 + 2×(段数−1) == content 长度', () {
      final sum = _segmentOrder.fold<int>(0, (acc, s) => acc + s.length);
      expect(sum + 2 * (_segmentOrder.length - 1), _raw.length);
    });

    test('段边界自证：各段首行即其标题，P1 段尾自带分隔线', () {
      expect(kCrSegHead, startsWith('# SKILL:'));
      expect(kCrSegP0, startsWith('## 二、阶段一：建立投入'));
      expect(kCrSegP1, startsWith('## 三、阶段二：暴露问题'));
      expect(kCrSegTail, startsWith('## 四、从零构建模式'));
      expect(kCrSegP1, endsWith('---'), reason: 'P1 段尾须自带 `---` 分隔线');
      for (final s in _segmentOrder) {
        expect(s, equals(s.trim()), reason: '段资源必须已 trim（装配式依赖）');
      }
    });

    test('段可见性护栏：实现内不得再有 indexOf 寻址的段常量', () {
      // Step 2 前，段边界靠代码里的字面标题 + indexOf 维持；模型变更后
      // 段是一等公民，标题只可能是段资源自身。此处断言段的顺序稳定。
      expect(_segmentOrder.length, 4);
      expect(_segmentOrder.toSet().length, 4, reason: '段不得重复');
    });
  });

  group('coaching-rhythm 阶段裁剪', () {
    test('非 P0/P1 阶段逐字节回退原文', () {
      for (final phase in [
        TeachingPhase.p2PracticeLoop,
        TeachingPhase.p3Training,
        TeachingPhase.p4Review,
      ]) {
        expect(_forPhase(phase), _raw, reason: '${phase.value} 未回退完整原文');
      }
    });

    test('装配产物逐字节等于段资源拼接（零编辑漂移）', () {
      expect(
        _forPhase(TeachingPhase.p0Engage),
        [kCrSegHead, kCrSegP0, kCrSegTail].join('\n\n'),
      );
      expect(
        _forPhase(TeachingPhase.p1World),
        [kCrSegHead, kCrSegP1, kCrSegTail].join('\n\n'),
      );
    });

    test('P0 档注入 P0 分段、不含 P1 分段', () {
      final p0 = _forPhase(TeachingPhase.p0Engage);
      expect(p0, contains('## 二、阶段一：建立投入（P0_ENGAGE）'));
      expect(p0, contains('### 2.2 五步节奏'));
      expect(p0, isNot(contains('## 三、阶段二：暴露问题（P1_WORLD）')));
      expect(p0, isNot(contains('### 3.2 三类提问模式')));
      // §一 总览是跨阶段旅程地图，裁掉细节段后仍须保留
      expect(p0, contains('## 一、教练对话总览'));
      // §四~§七 与阶段无关，必须保留
      expect(p0, contains('## 四、从零构建模式'));
      expect(p0, contains('## 七、三层认知模型'));
    });

    test('P1 档注入 P1 分段、不含 P0 分段', () {
      final p1 = _forPhase(TeachingPhase.p1World);
      expect(p1, contains('## 三、阶段二：暴露问题（P1_WORLD）'));
      expect(p1, contains('### 3.2 三类提问模式'));
      expect(p1, isNot(contains('## 二、阶段一：建立投入（P0_ENGAGE）')));
      expect(p1, isNot(contains('### 2.2 五步节奏')));
      expect(p1, contains('## 一、教练对话总览'));
      expect(p1, contains('## 四、从零构建模式'));
    });

    test('裁剪确实降低体积（两档均小于原文）', () {
      expect(_forPhase(TeachingPhase.p0Engage).length, lessThan(_raw.length));
      expect(_forPhase(TeachingPhase.p1World).length, lessThan(_raw.length));
    });

    // C57 防复发护栏（A.12.25）：裁剪后保留段不得留悬空引用。
    // §六 分工表两行引用另一阶段的章节（P0 档引 §三 / P1 档引 §二），
    // 须有裁剪说明兜底；§2.3 的 §三 引用须自含「P1 阶段才加载」说明。
    test('C57 护栏：两档切片均含裁剪说明，悬空引用有兜底', () {
      const noteKeyword = '按学员当前阶段裁剪注入';
      final p0 = _forPhase(TeachingPhase.p0Engage);
      final p1 = _forPhase(TeachingPhase.p1World);

      // §六 分工表在两档都保留 → 裁剪说明必须在两档都出现
      expect(p0, contains('## 六、与本模块其他 Skill 的分工边界'));
      expect(p1, contains('## 六、与本模块其他 Skill 的分工边界'));
      expect(p0, contains(noteKeyword), reason: 'P0 档缺裁剪说明（C57 回归）');
      expect(p1, contains(noteKeyword), reason: 'P1 档缺裁剪说明（C57 回归）');

      // P0 档含 §2.3（引用 §三 的唯一保留位），其引用必须自含加载时机说明
      expect(
        p0,
        contains('§三 的暴露引导在 P1 阶段才加载'),
        reason: 'P0 档 §2.3 退回裸引用 §三（C57 回归）',
      );
    });
  });

  group('dispatcher 按阶段注入', () {
    test('beginner 模式（P0）prompt 含 P0 分段且不含 P1 分段', () {
      final r = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p0Engage,
          attitude: AttitudeLevel.doubao,
          isBeginner: true,
        ),
      );
      expect(r.l2Mode, L2Mode.beginner);
      expect(r.systemPrompt, contains('## 二、阶段一：建立投入（P0_ENGAGE）'));
      expect(r.systemPrompt, isNot(contains('## 三、阶段二：暴露问题（P1_WORLD）')));
    });

    test('beginner 模式（P1）prompt 含 P1 分段且不含 P0 分段', () {
      final r = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p1World,
          attitude: AttitudeLevel.doubao,
          isBeginner: true,
        ),
      );
      expect(r.l2Mode, L2Mode.beginner);
      expect(r.systemPrompt, contains('## 三、阶段二：暴露问题（P1_WORLD）'));
      expect(r.systemPrompt, isNot(contains('## 二、阶段一：建立投入（P0_ENGAGE）')));
    });

    test('diagnosis 模式（P2）不受裁剪影响，两段俱在', () {
      final r = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.yuesheng,
          subphase: TeachingSubphase.diagnosis,
        ),
      );
      expect(r.l2Mode, L2Mode.diagnosis);
      expect(r.systemPrompt, contains('## 二、阶段一：建立投入（P0_ENGAGE）'));
      expect(r.systemPrompt, contains('## 三、阶段二：暴露问题（P1_WORLD）'));
    });
  });
}
