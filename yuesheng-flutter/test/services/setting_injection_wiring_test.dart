// ─────────────────────────────────────────────────────────────
// setting_injection_wiring_test — ADR-C106 设定注入接线修复护栏
//
// 覆盖（先补测试再施工，施工前本组应为红）：
//   A3  「参与诊断」开关接线：勾选参与诊断的设定真正进诊断轮 system 上下文；
//       未接线 / 未勾选 → 不进（修复前 _settingEntryRepo 恒 null ⇒ 永不注入）。
//   A7  userText 接通：用户在对话里点名（未在本章正文出现）的人物，L1 命中层
//       开始命中（修复前 userText 恒 '' ⇒ 退化为只匹配本章正文）；
//       近轮热度名片开始注入（修复前 recent 恒 [] ⇒ 永不注入）。
//       ★ 热度用例发送 content 必须含诊断 marker「写作诊断分析」，否则 C4 守卫致早退。
//   C4  四法（participating/pinned/hot/negative）诊断轮在、纯教学轮不在
//       （修复前四者无 marker 守卫，纯教学轮也注入）。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/setting_entry_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/types/character_types.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 章节正文（刻意不含任何测试人物名，确保 L1 只能靠本轮 userText 命中）
const String _chapterContent =
    '他站在窗前，望着远处连绵的山峦。\n'
    '夜色渐深，街灯次第亮起。\n'
    '她合上那封信，转身走向书桌。\n'
    '窗外的风停了。\n';

/// 捕获注入 messages 的 Fake LLM
class _CaptureLlmClient extends LlmClient {
  List<String> systemContents = [];

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    systemContents = messages
        .where((m) => m.role == 'system')
        .map((m) => m.content)
        .toList();
    callback(const LlmStreamResponse(content: '收到，开始诊断。', isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late String sessionId;
  late String chapterId;
  late String manuscriptId;
  late CharacterFactRepository factRepo;
  late SettingEntryRepository settingRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    sessionId = await sessionRepo.createBlankSession();
    factRepo = CharacterFactRepository(db);
    settingRepo = SettingEntryRepository(db);

    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final refRepo = ReferenceRepository(db);
    manuscriptId = await msRepo.createManuscript(title: '测试稿');
    chapterId = await chRepo.createChapter(
      manuscriptId,
      title: '第一章',
      content: _chapterContent,
    );
    await refRepo.addReference(
      sessionId,
      'chapter',
      chapterId,
      isPrimary: true,
    );
  });

  tearDown(() async => db.close());

  DiagnosisCommitter committer() => DiagnosisCommitter(
    sessionRepo: sessionRepo,
    stateRepo: TeachingStateRepository(db),
    diagnosisRepo: DiagnosisRepository(db),
    studentModelRepo: StudentModelRepository(db),
    referenceRepo: ReferenceRepository(db),
    chapterRepo: ChapterRepository(db),
  );

  MessageInjector makeInjector(LlmClient llm, {bool wireSettingRepo = true}) {
    return MessageInjector(
      sessionRepo: sessionRepo,
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      manuscriptRepo: ManuscriptRepository(db),
      diagnosisCommitter: committer(),
      characterFactRepo: factRepo,
      settingEntryRepo: wireSettingRepo ? settingRepo : null,
      material: const MaterialCapabilityImpl(),
    );
  }

  ChatService makeService(LlmClient llm, {bool wireSettingRepo = true}) {
    final injector = makeInjector(llm, wireSettingRepo: wireSettingRepo);
    return ChatService(
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      referenceRepo: ReferenceRepository(db),
      llmClient: llm,
      messageInjector: injector,
      diagnosisFlowHandler: DiagnosisFlowHandler(
        sessionRepo: sessionRepo,
        stateRepo: TeachingStateRepository(db),
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
        teacherSuggestionRepo: TeacherSuggestionRepository(db),
        llmClient: llm,
        messageInjector: injector,
        diagnosisCommitter: committer(),
        diagnosis: const DiagnosisCapabilityImpl(),
        genUi: const GenUiParser(),
      ),
    );
  }

  SendMessageCallbacks cb() => SendMessageCallbacks(
    onStream: (_) {},
    onComplete: (_, _) {},
    onError: (_) {},
  );

  SendMessageOptions opts() => const SendMessageOptions(
    phase: TeachingPhase.p1World,
    attitude: AttitudeLevel.gentle,
  );

  /// 诊断请求（含 marker「写作诊断分析」）
  String diag(String body) => '请对以下内容进行写作诊断分析：\n\n$body';

  Future<void> send(String content, LlmClient llm) async {
    await makeService(llm).sendMessage(sessionId, content, cb(), opts());
  }

  /// 种一条 participate=true 的自定义设定
  Future<void> seedParticipatingEntry({bool participate = true}) async {
    final id = await settingRepo.createEntry(
      manuscriptId: manuscriptId,
      category: '阵法',
      name: '聚灵阵',
      description: '聚灵之阵，方圆十里灵气汇聚',
    );
    await settingRepo.setParticipate(id, participate);
  }

  /// 种人物「林晚」：一条 confirmed 断言（名片展开用）。
  /// 章节正文与默认诊断文案均不含「林晚」——L1 只能靠本轮 userText 命中。
  Future<void> seedLinwan({bool pin = false}) async {
    await factRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚',
      firstSeenChapter: 1,
      assertions: const [
        CharacterAssertion(
          attribute: '身份',
          value: '女捕快',
          chapter: 1,
          timestamp: 1,
          status: 'confirmed',
        ),
      ],
    );
    if (pin) {
      final rows = await factRepo.listCharacters(manuscriptId);
      final row = rows.firstWhere((r) => r.name == '林晚');
      await factRepo.setPinned(row.id, pinned: true);
    }
  }

  // ── A3：参与诊断接线 ─────────────────────────────────────────
  test('A3 勾选参与诊断 + 已接线 ⇒ 自定义设定段进诊断轮', () async {
    await seedParticipatingEntry();
    final llm = _CaptureLlmClient();
    await send(diag('第一章的开头写得怎么样？'), llm);
    final joined = llm.systemContents.join('\n');
    expect(joined, contains('【作品自定义设定（用户勾选参与诊断）】'));
    expect(joined, contains('聚灵阵'));
  });

  test('A3 未接线 settingEntryRepo ⇒ 自定义设定段不进（反证接线）', () async {
    await seedParticipatingEntry();
    final llm = _CaptureLlmClient();
    await makeService(
      llm,
      wireSettingRepo: false,
    ).sendMessage(sessionId, diag('第一章的开头写得怎么样？'), cb(), opts());
    final joined = llm.systemContents.join('\n');
    expect(joined.contains('【作品自定义设定（用户勾选参与诊断）】'), false);
  });

  test('A3 已接线但未勾选 participate=0 ⇒ 不进（勾选才进语义）', () async {
    await seedParticipatingEntry(participate: false);
    final llm = _CaptureLlmClient();
    await send(diag('第一章的开头写得怎么样？'), llm);
    final joined = llm.systemContents.join('\n');
    expect(joined.contains('【作品自定义设定（用户勾选参与诊断）】'), false);
  });

  // ── A7：userText 接通（L1 用户点名命中）─────────────────────
  test('A7 用户在本轮消息点名（正文未出现）⇒ L1 命中人物展开段', () async {
    await seedLinwan();
    final llm = _CaptureLlmClient();
    // 本章正文不含「林晚」；本轮 content 点名「林晚」——修复前 userText 恒空
    // ⇒ 只匹配正文，不命中；修复后 userText=content ⇒ 命中。
    await send(diag('帮我看看林晚这个人物立不立得住。'), llm);
    final joined = llm.systemContents.join('\n');
    expect(joined, contains('## 设定资料库（正文命中展开）'));
    expect(joined, contains('林晚'));
  });

  // ── A7：热度名片（content 必须含 marker，否则 C4 守卫早退）────
  test('A7 近轮反复提及 ⇒ 热度名片段注入（修复前 recent 恒空）', () async {
    await seedLinwan();
    final llm = _CaptureLlmClient();
    // 前两轮普通消息反复提及「林晚」（无 marker，不触发诊断注入，只落历史）
    await send('今天写林晚和沈砚的对手戏，林晚拔刀的动作我总觉得不够利落。', llm);
    await send('林晚这个人物再想想，林晚的动机还得再磨一磨。', llm);
    // 第三轮诊断请求（不含「林晚」⇒ L1 不命中 ⇒ 走热度退化层）
    await send(diag('帮我诊断一下这章的节奏。'), llm);
    final joined = llm.systemContents.join('\n');
    expect(joined, contains('## 设定资料库（近几轮常被提及）'));
    expect(joined, contains('林晚'));
  });

  // ── C4：诊断轮在 / 纯教学轮不在 ─────────────────────────────
  test('C4 诊断轮 ⇒ participating + pinned 段在', () async {
    await seedParticipatingEntry();
    await seedLinwan(pin: true);
    final llm = _CaptureLlmClient();
    await send(diag('帮我诊断一下这章的节奏。'), llm);
    final joined = llm.systemContents.join('\n');
    expect(joined, contains('【作品自定义设定（用户勾选参与诊断）】'));
    expect(joined, contains('## 设定资料库（学员钉选）'));
  });

  test('C4 纯教学轮（无 marker）⇒ participating + pinned 段不在', () async {
    await seedParticipatingEntry();
    await seedLinwan(pin: true);
    final llm = _CaptureLlmClient();
    await send('今天写得有点卡，不知道怎么往下接。', llm);
    final joined = llm.systemContents.join('\n');
    expect(joined.contains('【作品自定义设定（用户勾选参与诊断）】'), false);
    expect(joined.contains('## 设定资料库（学员钉选）'), false);
  });
}
