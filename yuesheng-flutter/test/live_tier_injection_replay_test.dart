// ─────────────────────────────────────────────────────────────
// live_tier_injection_replay_test — tier 是否真能改变教练输出（真实 LLM）
//
// ★ 本文件回答的问题（与另两个测试文件分工）：
//   · diagnosis_tier_bridge_test        → 映射函数对不对（纯函数、零 IO）
//   · diagnosis_tier_injection_verify   → 注入文本变没变（本地数据流）
//   · **本文件**                        → **模型是否真的照那句话做**
//
// ★ 为什么必须真跑（诚实边界）：
//   前两个文件都只能证明「**话传到了**」。注入文本是「请优先给当前层级+1
//   以内的问题做重点反馈」这类**软引导措辞**——模型是否照做、照做的幅度
//   有多大，**无法从代码或本地断言推出**。这是 prompt 行为问题，不是数据
//   结构问题。⇒ 只能实测。
//
// ── 实验设计（单变量对照）──
//   样本：同一段文本（同时含L1 语病 / L4 结构问题）×三档 tier。
//   变量：**只有 tier 不同**（同一消息、同一系统 prompt 集合、同一模型、
//         同一温度），故差异只可能来自 tier。
//   读数：每档 3 票，**逐票全文留痕**（不打分、不抽样）。
//   ⚠️ 「模型是否照做」本身没有 ground truth（教练输出是散文）⇒
//     本文件**只陈述观察到的差异，不下「哪档更好」的结论**。
//
// ── 费用护栏（ADR-C136 §4 范式）──
//   上限 12 次调用（3 档 × 3 票 + 余量），超限即停并如实记录。
//   无 DEEPSEEK_API_KEY 时 markTestSkipped（不破门禁）。
//   Key 仅从环境变量读，**不入库**（本文件不含任何字面量 Key）。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/diagnosis_tier_bridge.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/llm_concurrency_gate.dart';
import 'package:writingcoach/services/llm_usage_monitor.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/syndrome_skill_levels.dart';
import 'package:writingcoach/types/teaching_types.dart';

const _kBaseUrl = 'https://api.deepseek.com';
const _kModel = 'deepseek-v4-flash';

/// 真实调用预算上限（3 档 × 3 票 + 余量）。
const int _kMaxRealCalls = 12;

/// 三档 tier（与 UI `_tiers` 的键一一对应）。
const _tierOrder = ['beginner', 'story', 'full'];

/// 单票样本：**同时含 L1 层语病与 L4 层结构问题**。
///
/// 这是实验设计的核心 —— 样本必须**跨层混合**，否则「只报语病」和「只报结构」
/// 都无法区分是「照做了引导」还是「恰好只发现那一类」。
const _kSample = '''
她很愤怒，转身摔门而去，心里感到一阵难以名状的难过与激动。他的表情很愤怒。
故事里有很多角色，主角是张三，还有李四和王五，他们之间有很多冲突，主角很勇敢。
''';

void main() {
  final bool hasKey = Platform.environment.containsKey('DEEPSEEK_API_KEY');
  int callCount = 0;

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  // ── 常驻自检组：无 Key 也跑，保证门禁不被破，且验证本地链路没退化 ──
  group('tier 注入·本地自检（无 Key 也跑）', () {
    test('S1 三档→ BeginnerLevel 映射稳定（防本地链路退化）', () {
      expect(
        resolveBeginnerLevelFromTier(tier: 'beginner', beginnerLevel: null),
        isNotNull,
      );
      expect(
        resolveBeginnerLevelFromTier(tier: 'story', beginnerLevel: null),
        isNotNull,
      );
      expect(
        resolveBeginnerLevelFromTier(tier: 'full', beginnerLevel: null),
        isNotNull,
      );
      expect(callCount, 0, reason: '自检组不得消耗真实调用预算');
    });
  });

  group('tier 注入·真实 LLM（@live，需 DEEPSEEK_API_KEY）', () {
    LlmClient buildRealClient(LlmUsageMonitor monitor) {
      final cfg = LlmConfigValues(
        apiKey: Platform.environment['DEEPSEEK_API_KEY']!,
        baseUrl: _kBaseUrl,
        model: _kModel,
      );
      return LlmClient(
        null,
        null,
        () async => cfg,
        null,
        LlmConcurrencyGate(),
        monitor.sink,
      );
    }

    MessageInjector buildInjector() {
      final sRepo = SessionRepository(db);
      return MessageInjector(
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
    }

    ///跑一票：注入 tier 对应的层级引导 → 发真实请求 → 返回全文。
    Future<String> runOnce(
      LlmClient client,
      MessageInjector injector,
      String? tier,
    ) async {
      // ★ 走真实解析：与生产 `_prepareTeachingState` 同一入口。
      final lv = resolveBeginnerLevelFromTier(tier: tier, beginnerLevel: null);

      final messages = <ChatMessage>[
        const ChatMessage(
          role: 'system',
          content:
              '你是写作教练。请针对下面文本给出**具体的、可执行**的改进建议。'
              '控制在 200 字以内。',
        ),
      ];
      // 用 injectDiagnosisLock 复现真实注入路径（含层级引导段）。
      await injector.injectDiagnosisLock(
        sessionId: 'live-tier',
        content: _kSample,
        activeProblems: const [],
        currentSubphase: null,
        beginnerLevel: lv,
        messages: messages,
        markStage: (_) {},
      );
      // injectDiagnosisLock 在 activeProblems 为空时早退 ⇒ 手工补注入段，
      // 文本取自 message_injector:2077 的模板（保持与生产逐字一致）。
      if (lv != null) {
        final lvLabel = levelLabelOf(lv);
        messages.add(
          ChatMessage(
            role: 'system',
            content:
                '# 学员技能层级\n\n'
                '学员当前技能层级：$lvLabel。\n'
                '反馈建议：优先给当前层级+1 以内的问题做重点反馈；'
                '若诊断出更高层级的问题可以提及，但作为次要项，'
                '不要一次展开超出学员理解范围的内容。',
          ),
        );
      }
      messages.add(ChatMessage(role: 'user', content: _kSample));

      final buf = StringBuffer();
      await client.streamChat(messages, (resp) {
        if (resp.isDone) return;
        buf.write(resp.content);
      });
      return buf.toString();
    }

    test('R1 三档 × 3 票：逐票全文留痕，观察输出差异', () async {
      if (!hasKey) {
        markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
        return;
      }
      final monitor = LlmUsageMonitor();
      final client = buildRealClient(monitor);
      final injector = buildInjector();

      // 记录注入文本（取证：证明每票真的带了不同的引导）
      final injected = <String, String>{};
      for (final tier in _tierOrder) {
        final lv = resolveBeginnerLevelFromTier(
          tier: tier,
          beginnerLevel: null,
        );
        if (lv == null) continue;
        injected[tier] = levelLabelOf(lv);
        // ignore: avoid_print
        print('[注入对照] tier=$tier → 引导段层级=${injected[tier]}');
      }

      final traces = <String, List<String>>{};
      for (final tier in _tierOrder) {
        traces[tier] = [];
        for (var i = 1; i <= 3; i++) {
          if (callCount >= _kMaxRealCalls) {
            // ignore: avoid_print
            print('已达调用上限 $_kMaxRealCalls，提前停止');
            break;
          }
          callCount++;
          final out = await runOnce(client, injector, tier);
          traces[tier]!.add(out);
          // ignore: avoid_print
          print('--- tier=$tier 第$i 票 ---');
          // ignore: avoid_print
          print(out);
        }
      }

      // 断言只锁「有产出」，**不**断言哪档更好（无 ground truth，见头注）。
      for (final tier in _tierOrder) {
        final got = traces[tier] ?? const <String>[];
        expect(got, isNotEmpty, reason: 'tier=$tier 应至少有一票');
        for (final one in got) {
          expect(one.trim(), isNotEmpty, reason: 'tier=$tier 出现空回复');
        }
      }
      // 打印长度对照（供人工判断差异幅度）
      for (final tier in _tierOrder) {
        final lens = traces[tier]!.map((s) => s.length).toList();
        // ignore: avoid_print
        print('[长度对照] tier=$tier 注入=${injected[tier]} 回复长度=$lens');
      }
    });
  });
}

/// BeginnerLevel → SkillLevel 的标签（供取证打印用）。
///
/// 复用既有换算（`skillLevelForBeginner`），**不在本文件维护第二张映射表**
/// —— 否则两处各改一处就会漂（§4-39 同源纪律）。
/// 取层级标签（复用既有换算，不另建映射）。
String levelLabelOf(BeginnerLevel lv) => _skillOf(lv);

String _skillOf(BeginnerLevel lv) {
  final sl = skillLevelForBeginner(lv);
  return sl == null ? '未映射' : '${sl.value} ${sl.label}';
}
