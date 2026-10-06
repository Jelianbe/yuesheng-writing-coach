// ─────────────────────────────────────────────────────────────
// diagnosis_tier_injection_verify_test — tier 真能改变注入内容的验证
//
// ★ 与 diagnosis_tier_bridge_test 的分工：
//   那 20 条测「映射函数本身」（纯函数、零IO）。
//   本文件测**真实数据流**：`beginnerLevel` 经 `MessageInjector.injectDiagnosisLock`
//   后，**messages 里真的多出/少了哪一段注入文本** —— 即用户选的那一档
//   到底有没有对教练说出不同的话。
//
// ★ 为什么可以不联网测（关键取舍）：
//   `_injectStudentSkillLevelGuidance`（`message_injector.dart:2069`）是
//   **纯本地**的：只把 `skillLevelForBeginner(beginnerLevel)` 的结果拼成
//   一段 system 文本追加到 messages，**不发任何请求**。
//   ⇒ 注入内容的差异是**确定性可测**的，不需要 API Key。
//   ⚠️ 本文件因此**不验证**「模型是否会照做」—— 那需要真实 Key 与真实
//   文段（`live_*` 测试的职责范围）。本文件只证明「话传到了」。
//
// ★ 边界（诚实声明）：
//   `injectDiagnosisLock` 首行 `if (activeProblems.isEmpty) return null;`
//   ⇒ 必须给一个非空 `activeProblems` 才会走到注入段。故本文件用一个
//   构造的 ActiveProblemView 作「最小触发条件」，**不声称**覆盖真实诊断路径。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:drift/native.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/diagnosis_tier_bridge.dart';
import 'package:writingcoach/services/message_injector.dart';

/// skill level 注入段的定位特征（对齐 message_injector:2078 的标题文本）。
const _kLevelHeading = '# 学员技能层级';

List<String> _systemTexts(List<ChatMessage> msgs) =>
    msgs.where((m) => m.role == 'system').map((m) => m.content).toList();

String? _levelBlock(List<ChatMessage> msgs) {
  for (final t in _systemTexts(msgs)) {
    if (t.contains(_kLevelHeading)) return t;
  }
  return null;
}

void main() {
  late AppDatabase db;
  late MessageInjector injector;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final sRepo = SessionRepository(db);
    injector = MessageInjector(
      sessionRepo: sRepo,
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      manuscriptRepo: ManuscriptRepository(db),
      diagnosisCommitter: DiagnosisCommitter(
        sessionRepo: sRepo,
        stateRepo: TeachingStateRepository(db),
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
      ),
      material: const MaterialCapabilityImpl(),
    );
  });

  tearDown(() async => db.close());

  // 非空 activeProblems 是进入注入段的必要条件（injectDiagnosisLock 首行）。
  final problems = [
    ActiveProblemView(
      syndromeId: 'P001',
      syndromeName: '情绪标签化',
      severity: 'L2',
      confirmationStatus: 'active',
    ),
  ];

  Future<List<ChatMessage>> injectWith(String? tier) async {
    // 走真实解析函数：从 tier 得到 BeginnerLevel（与生产同一入口）。
    final lv = resolveBeginnerLevelFromTier(tier: tier, beginnerLevel: null);
    final msgs = <ChatMessage>[];
    await injector.injectDiagnosisLock(
      sessionId: 's1',
      content: '他很愤怒地摔门而去。',
      activeProblems: problems,
      currentSubphase: null,
      beginnerLevel: lv,
      messages: msgs,
      markStage: (_) {},
    );
    return msgs;
  }

  group('真实数据流：tier →注入文本', () {
    test('F1 「先写顺」⇒ 注入 L1 基础表达', () async {
      final block = _levelBlock(await injectWith('beginner'));
      expect(block, isNotNull, reason: '未选中任何 tier 时应无层级注入（对照 F5）');
      expect(block, contains('L1 基础表达'));
    });

    test('F2「完整故事」⇒ 注入 L3 角色塑造', () async {
      final block = _levelBlock(await injectWith('story'));
      expect(block, isNotNull);
      expect(block, contains('L3 角色塑造'));
      expect(
        block,
        isNot(contains('L1 基础表达')),
        reason: '两档必须产出**不同**文本，否则 tier 仍是装饰',
      );
    });

    test('F3 「想被挑刺」⇒ 注入 L4 情节结构', () async {
      final block = _levelBlock(await injectWith('full'));
      expect(block, isNotNull);
      expect(block, contains('L4 情节结构'));
    });

    test('F0 打印三档实际注入文本（取证用）', () async {
      for (final tier in ['beginner', 'story', 'full']) {
        final block = _levelBlock(await injectWith(tier));
        // ignore: avoid_print
        print('=== tier=$tier ===');
        // ignore: avoid_print
        print(block ?? '(无注入)');
      }
    });

    test('F4 ★三档产出的注入文本两两不同（这是「真生效」的可测形态）', () async {
      final a = _levelBlock(await injectWith('beginner'));
      final b = _levelBlock(await injectWith('story'));
      final c = _levelBlock(await injectWith('full'));
      expect(
        <String?>{a, b, c}.length,
        3,
        reason: '三档文本必须两两不同——相同即说明某一档没有实际差异',
      );
      expect(a, isNot(b));
      expect(b, isNot(c));
      expect(a, isNot(c));
    });

    test('F5 未选 tier（映射为 null）⇒ 不注入层级段（保持原行为）', () async {
      final block = _levelBlock(await injectWith(null));
      expect(block, isNull, reason: 'tier 未设时应完全保持既有行为，不擅自注入层级引导');
    });

    test('F6 注入段含「层级+1」软引导措辞（非硬拦截）', () async {
      final block = _levelBlock(await injectWith('beginner'))!;
      expect(block, contains('当前层级+1'), reason: '须是「优先给+1 以内重点反馈」的软引导，不是屏蔽声明');
      expect(block, contains('作为次要项'), reason: '原模板明确允许提及更高层级——这是软引导的关键语义');
    });

    test('F7 tier 覆盖 beginner_level 后注入随之改变（优先级端到端）', () async {
      // 「冷启动自评= N1（初级）+ tier=想被挑刺」⇒ 注入必须是 L4 而非 L1。
      final lv = resolveBeginnerLevelFromTier(
        tier: 'full',
        beginnerLevel: BeginnerLevel.n1Elements,
      );
      expect(lv, BeginnerLevel.n4Independent);
      final msgs = <ChatMessage>[];
      await injector.injectDiagnosisLock(
        sessionId: 's1',
        content: '测试文本。',
        activeProblems: problems,
        currentSubphase: null,
        beginnerLevel: lv,
        messages: msgs,
        markStage: (_) {},
      );
      expect(_levelBlock(msgs), contains('L4 情节结构'));
    });
  });
}
