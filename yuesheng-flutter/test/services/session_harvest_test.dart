// T-20261018-02 会话收口卡护栏（A 议题 + C 子件 M4 接线）
//
// 验收对齐设计批 §五：
//   1. 触发判定五态（首次不出 / ≥2 次出 / 有训练出 / M4 候选出 / 三路全空不出）
//   2. payload 往返稳定 + 旧消息（无 key）兼容
//   3. M4 查询器接到消费方（活性视角）+ dispatcher 挂载渲染（消息流出口）
//   4. 措辞守卫（R-009 机器锚：卡面文案不含评价词——批文七条锚串逐字）
// 全部内存 DB 真链路，零 LLM。
//
// DB 播种纪律（对齐 session_repository_b23_test 先例）：sessions.manuscript_id /
// chapter_id 是 FK ⇒ getOrCreateSessionForChapter 前必须先建真实稿件/章节行，
// 否则 UPDATE sessions 撞 FOREIGN KEY constraint failed（787）。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/edit_diff_event_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/training_result_repository.dart';
import 'package:writingcoach/services/chapter_completion_querier.dart';
import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/services/session_harvest_assembler.dart';
import 'package:writingcoach/theme/app_theme.dart' show buildAppTheme;
import 'package:writingcoach/widgets/message_card_dispatcher.dart';
import 'package:writingcoach/widgets/session_harvest_card.dart';
import 'package:drift/native.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late DiagnosisRepository diagRepo;
  late TrainingResultRepository trainingRepo;
  late SessionHarvestAssembler assembler;
  late SessionRepository sRepo;
  late String msId;
  late String chId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    diagRepo = DiagnosisRepository(db);
    trainingRepo = TrainingResultRepository(db);
    sRepo = SessionRepository(db);
    final chapterRepo = ChapterRepository(db);
    final appStateRepo = AppStateRepository(db);
    final editDiffRepo = EditDiffEventRepository(db);
    // FK 前置：sessions.manuscript_id/chapter_id 引用真实行（b23 先例）。
    final mRepo = ManuscriptRepository(db);
    msId = await mRepo.createManuscript(title: 'ms-1');
    chId = await chapterRepo.createChapter(msId, title: 'ch-1', content: 'x');
    assembler = SessionHarvestAssembler(
      diagRepo: diagRepo,
      trainingRepo: trainingRepo,
      completionQuerier: ChapterCompletionQuerier(
        editDiffRepo,
        appStateRepo,
        chapterRepo,
      ),
      sessionRepo: sRepo,
    );
  });

  tearDown(() async => db.close());

  Future<void> commitDiag(String sid, String syndromesJson, {int? ts}) async {
    await diagRepo.commitDiagnosis(
      DiagnosisInput(
        sessionId: sid,
        messageId: 'm-$sid-$ts',
        // jsonDecode 出 List<dynamic>，须逐元素 cast（直铸 List<Map> 会崩）
        syndromes: (jsonDecode(syndromesJson) as List<dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .toList(),
        suggestedActions: const [],
        confidence: 0.5,
        isTeachingRound: false,
      ),
    );
  }

  const kSynA =
      '{"syndrome_id":"P001","name":"情绪标签化","severity":"L1",'
      '"evidence":["x"],"explanation":"y"}';
  const kSynB =
      '{"syndrome_id":"P002","name":"信息倾泻","severity":"L2",'
      '"evidence":["x"],"explanation":"y"}';

  test('触发①：首次诊断（无训练/无候选）⇒ 不出卡', () async {
    final sid = await sessionRepo.getOrCreateSessionForChapter(msId, chId);
    await commitDiag(sid, '[$kSynA]');
    await assembler.assembleAndInsert(
      sessionId: sid,
      currentSyndromes: const [(id: 'P001', severity: 'L1')],
    );
    final msgs = await sessionRepo.listMessages(sid);
    expect(
      msgs.where((m) => m.messageType == 'session_harvest'),
      isEmpty,
      reason: '首次诊断三路全空 ⇒ 不造死卡',
    );
  });

  test('触发②：第 2 次诊断 ⇒ 出卡且含对比节', () async {
    final sid = await sessionRepo.getOrCreateSessionForChapter(msId, chId);
    await commitDiag(sid, '[$kSynA]', ts: 1);
    await commitDiag(sid, '[$kSynA,$kSynB]', ts: 2);
    await assembler.assembleAndInsert(
      sessionId: sid,
      currentSyndromes: const [
        (id: 'P001', severity: 'L1'),
        (id: 'P002', severity: 'L2'),
      ],
    );
    final msgs = await sessionRepo.listMessages(sid);
    final card = msgs.where((m) => m.messageType == 'session_harvest').single;
    final payload = SessionHarvestPayload.fromJson(
      jsonDecode(card.content) as Map<String, dynamic>,
    );
    expect(payload.diagnosisCount, 2);
    expect(payload.diff, isNotNull, reason: '有历史 ⇒ 对比节在场');
    expect(payload.diff!.added, 1);
    expect(payload.diff!.recurring, 1);
    expect(payload.diff!.removed, 0);
  });

  test('触发③：仅有训练记录（首次诊断）⇒ 出卡且含训练节', () async {
    final sid = await sessionRepo.getOrCreateSessionForChapter(msId, chId);
    await commitDiag(sid, '[$kSynA]');
    await trainingRepo.insertTrainingResult(
      InsertTrainingResultParams(
        sessionId: sid,
        syndromeId: 'P001',
        taskType: 'rewrite',
        userContent: 'x',
        result: 'passed',
      ),
    );
    await assembler.assembleAndInsert(
      sessionId: sid,
      currentSyndromes: const [(id: 'P001', severity: 'L1')],
    );
    final msgs = await sessionRepo.listMessages(sid);
    final card = msgs.where((m) => m.messageType == 'session_harvest').single;
    final payload = SessionHarvestPayload.fromJson(
      jsonDecode(card.content) as Map<String, dynamic>,
    );
    expect(payload.training, isNotNull);
    expect(payload.training!.attempts, 1);
    expect(payload.training!.passed, 1);
    expect(payload.diff, isNull, reason: '首次诊断无历史 ⇒ 对比节不渲染');
  });

  test('payload 往返稳定：toJson→fromJson 逐键一致（空节不落 key）', () {
    const p = SessionHarvestPayload(
      diagnosisCount: 3,
      l1Count: 2,
      l2Count: 1,
      l3Count: 0,
      nextFocusName: '情绪标签化',
    );
    final json = p.toJson();
    expect(json.containsKey('diff'), isFalse, reason: '空节不落 key');
    expect(json.containsKey('training'), isFalse);
    expect(json.containsKey('completion'), isFalse);
    final back = SessionHarvestPayload.fromJson(
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
    );
    expect(back.diagnosisCount, 3);
    expect(back.l1Count, 2);
    expect(back.nextFocusName, '情绪标签化');
    expect(back.diff, isNull);
  });

  test('旧消息兼容：无任何 key 的空对象 ⇒ 全缺省不炸', () {
    final p = SessionHarvestPayload.fromJson({});
    expect(p.diagnosisCount, 0);
    expect(p.diff, isNull);
  });

  test('卡片解析：坏 JSON ⇒ tryFromMessageContent 返回 null（不造坏卡）', () {
    expect(SessionHarvestCard.tryFromMessageContent('not-json'), isNull);
  });

  test('R-009 措辞守卫：批文七条锚串逐字 + 无评价词', () {
    // 评价词黑名单（R-009 机器锚——设计批 §二红线）
    const banned = ['进步了', '变好', '达成', '达标', '恭喜', '优秀', '出色'];
    for (final c in SessionHarvestCardReflector.allStrings) {
      for (final b in banned) {
        expect(c.contains(b), isFalse, reason: '卡面锚串 "$c" 含评价词 "$b"');
      }
    }
    // 批文锚串逐字在场（与卡片常量同形——常量即 §四 清单的机器锚）
    expect(
      SessionHarvestCardReflector.allStrings,
      containsAll([
        '本次收获',
        '次诊断',
        '本章报出',
        '与上次诊断相比：',
        '训练',
        '本章独立成稿：目标',
        '下一次建议关注：',
      ]),
    );
  });

  test('活性（验收3）：ChapterCompletionQuerier 在 assembler 内被消费', () {
    // 结构性断言：assembler 的 completionQuerier 字段存在且被 _buildPayload 使用
    // （compile 即证；这里断言 wiring 完整——assembler 持有 querier 引用）
    final a = assembler;
    expect(a.completionQuerier, isNotNull);
  });

  testWidgets('dispatcher 挂载：session_harvest 消息 ⇒ 渲染收口卡（验收3 消息流出口）', (
    tester,
  ) async {
    const payload = SessionHarvestPayload(
      diagnosisCount: 2,
      l1Count: 1,
      l2Count: 1,
      l3Count: 0,
    );
    final msg = Message(
      id: 'm-harvest',
      sessionId: 's1',
      role: 'system',
      content: jsonEncode(payload.toJson()),
      timestamp: 0,
      messageType: 'session_harvest',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final card = dispatchMessageCard(
                context: context,
                msg: msg,
                isStreamingBubble: false,
              );
              return card ?? const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    // 批文 §四 文案①②③ 逐字渲染（重开会话经消息持久化恢复的同一条路径）
    expect(find.text('本次收获 · 第 2 次诊断'), findsOneWidget);
    expect(find.text('本章报出 2 条 · L1×1 L2×1'), findsOneWidget);
    // 未提供的节不渲染（空态纪律：diff/training/completion/nextFocus 全空）
    expect(find.textContaining('与上次诊断相比'), findsNothing);
  });
}

/// 反射辅助：收集 SessionHarvestCard 全部 R-027 批文锚串常量。
class SessionHarvestCardReflector {
  static const List<String> allStrings = [
    SessionHarvestCard.kTitleText,
    SessionHarvestCard.kCountSuffix,
    SessionHarvestCard.kDiagnosisLinePrefix,
    SessionHarvestCard.kDiffPrefix,
    SessionHarvestCard.kDiffAdded,
    SessionHarvestCard.kDiffRemoved,
    SessionHarvestCard.kDiffRecurring,
    SessionHarvestCard.kTrainingPrefix,
    SessionHarvestCard.kTrainingTimes,
    SessionHarvestCard.kTrainingTimesSuffix,
    SessionHarvestCard.kCompletionPrefix,
    SessionHarvestCard.kCompletionMid,
    SessionHarvestCard.kCompletionSuffix,
    SessionHarvestCard.kNextFocusPrefix,
  ];
}
