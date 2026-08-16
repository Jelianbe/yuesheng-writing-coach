// ─────────────────────────────────────────────────────────────
// 大纲层 prompt 端到端验证（live）— 批次74 真实链路
//
// 验证 4 件事（对照 B74 交付目标）：
//   1. 5.1.8 无条件注入协议说明（零实体时也应注入）
//   2. 真实 LLM 输出 [YS_ENTITY] 实体记忆块（schema 合规）
//   3. 9.1 正确落库 pending 实体 + 印象 → 写确认卡
//   4. assistant 消息已剥离 [YS_ENTITY] 原始 JSON，无泄漏
//
// 运行方式（API key 只经环境变量传入，严禁写入源码）：
//   $env:DEEPSEEK_API_KEY="sk-xxx"
//   flutter test --tags live test/live_outline_entity_test.dart
//
// 保护机制：
//   - 无 DEEPSEEK_API_KEY 时自动 markTestSkipped，不影响四闸
//   - @Tags(['live']) 标识，便于只跑真实链路
//   - 关键信息 print 到 stdout，便于肉眼审阅提取质量
// ─────────────────────────────────────────────────────────────

@Tags(['live'])
library;

// ignore_for_file: avoid_print
// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

const String _kBaseUrl = 'https://api.deepseek.com';
const String _kModel = 'deepseek-v4-flash';
const MethodChannel _kConnectivityChannel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);
const MethodChannel _kSecureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// 捕获真实发给 LLM 的 system messages，并规避官方 SSE 偶发断连：
/// streamChat 内部改走 chatCompletion 非流式，整段一次性回推（onStream + onDone）。
/// ChatService 的协议解析/9.1 落库/展示剥离逻辑完全兼容。
class _RecordingLlmClient extends LlmClient {
  final Dio _dio = Dio();
  final List<List<String>> allSystemCalls = [];
  final List<String> allResponses = [];
  final String _apiKey;
  _RecordingLlmClient(this._apiKey);

  /// 首次调用（主 sendMessage 的 LLM 调用）system message 列表
  List<String> get firstSystemContents =>
      allSystemCalls.isEmpty ? const <String>[] : allSystemCalls.first;

  /// 完整原始回包（取主流程那次：allResponses 首项）
  String get firstRawResponse => allResponses.isEmpty ? '' : allResponses.first;

  int get totalCalls => allSystemCalls.length;

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    dynamic cancelToken,
  }) async {
    final sys = messages
        .where((m) => m.role == 'system')
        .map((m) => m.content)
        .toList();
    allSystemCalls.add(sys);
    // Live 测试层直接打官方非流式，强制 max_tokens=8192 兜底
    // （深求索默认短输出 + 诊断 + 双协议块共需大量输出，不强制会截断）
    try {
      final r = await _dio.post<dynamic>(
        '$_kBaseUrl/chat/completions',
        data: jsonEncode({
          'model': _kModel,
          'messages': messages.map((m) => m.toJson()).toList(),
          'stream': false,
          'temperature': LlmConfig.chatTemperature,
          'max_tokens': 8192,
        }),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
          },
          sendTimeout: const Duration(minutes: 3),
          receiveTimeout: const Duration(minutes: 3),
        ),
      );
      final data = r.data is String
          ? jsonDecode(r.data as String) as Map<String, dynamic>
          : r.data as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      final raw = choices.isNotEmpty
          ? ((choices[0] as Map<String, dynamic>)['message']
                        as Map<String, dynamic>)['content']
                    as String? ??
                ''
          : '';
      allResponses.add(raw);
      print(
        '[LIVE DEBUG] chatCompletion 调用#${allResponses.length} 返回长度=${raw.length}，'
        'max_tokens=8192，system=${sys.length} 条',
      );
      if (raw.isEmpty) throw Exception('chatCompletion 空返回');
    } catch (e, st) {
      print('[LIVE DEBUG] chatCompletion 异常: $e\n$st');
      rethrow;
    }
    final resp = allResponses.last;
    callback(LlmStreamResponse(content: resp, isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bool hasKey = Platform.environment.containsKey('DEEPSEEK_API_KEY');

  setUpAll(() {
    HttpOverrides.global = null;
    final key = Platform.environment['DEEPSEEK_API_KEY'];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, (call) async {
      if (call.method == 'check') return <String>['wifi'];
      return null;
    });
    final storageValues = <String, String>{
      if (key != null && key.isNotEmpty) 'yuesheng_api_key': key,
      'yuesheng_api_base_url': _kBaseUrl,
      'yuesheng_api_model': _kModel,
    };
    messenger.setMockMethodCallHandler(_kSecureStorageChannel, (call) async {
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'read':
          return storageValues[args['key']];
        case 'write':
          storageValues[args['key'] as String] = args['value'] as String;
          return true;
        case 'delete':
          storageValues.remove(args['key']);
          return true;
      }
      return null;
    });
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, null);
    messenger.setMockMethodCallHandler(_kSecureStorageChannel, null);
  });

  // 章节内容（2 个人物 + 情节，短而信息密度高——便于 SSE 快速完成、降低断连概率）
  const _chapterTitle = '第一章：巷口';
  const _chapterContent = '''
王建国站在巷口，夜色沉沉。他想起母亲临终前那句"不要报仇"，攥紧了拳头。王叔是他父亲的老部下，在这条巷子里守了三十年，左眼的一道疤从上到下，是王建国十岁那年替他挡一刀留下的。王叔压低声音说："里面有三个人，都带着家伙。"
王建国没回头，只问了一句："我爸的笔记拿到了吗？"王叔把一个油纸包递到他手上："藏在你外婆旧屋的房梁上。"
林小芸从二楼窗户往下看了一眼，手里攥着那把银色的小手枪——是她父亲生前留给她的。她看到王建国的身影出现在巷口，心里一松，又立刻紧了起来。
''';

  test(
    '大纲层 prompt 端到端：协议注入 + AI 提取 + 落库 + 剥离',
    () async {
      if (!hasKey) {
        markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
        return;
      }

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        final sessionRepo = SessionRepository(db);
        final outlineRepo = OutlineRepository(db);
        final msRepo = ManuscriptRepository(db);
        final chRepo = ChapterRepository(db);
        final refRepo = ReferenceRepository(db);

        final sessionId = await sessionRepo.createBlankSession();
        final manuscriptId = await msRepo.createManuscript(title: '巷口');
        final chapterId = await chRepo.createChapter(
          manuscriptId,
          title: _chapterTitle,
          content: _chapterContent,
        );
        await refRepo.addReference(
          sessionId,
          'chapter',
          chapterId,
          isPrimary: true,
        );

        final key = Platform.environment['DEEPSEEK_API_KEY'] ?? '';
        final llm = _RecordingLlmClient(key);
        final service = ChatService(
          sessionRepo: sessionRepo,
          stateRepo: TeachingStateRepository(db),
          diagnosisRepo: DiagnosisRepository(db),
          studentModelRepo: StudentModelRepository(db),
          referenceRepo: refRepo,
          chapterRepo: chRepo,
          manuscriptRepo: msRepo,
          llmClient: llm,
          teacherSuggestionRepo: TeacherSuggestionRepository(db),
          editorObservationRepo: EditorObservationRepository(db),
          outlineRepo: outlineRepo,
        );

        // 对齐 UI 层诊断触发（写作诊断分析 + 章节名/内容 + [YS_DIAGNOSIS] 输出指令）
        final userPrompt =
            '请对以下写作内容进行写作诊断分析：\n\n'
            '【$_chapterTitle】\n\n'
            '$_chapterContent\n\n'
            '---\n'
            '重要：\n'
            '1. 诊断说明后必须输出 [YS_DIAGNOSIS]...[/YS_DIAGNOSIS] 包裹的 JSON 块，'
            '含 syndromes 数组（每条含 syndrome_id/name/severity/evidence/explanation）、'
            'suggested_actions（数组）、confidence（0-1）。\n'
            '2. 必须输出 [YS_ENTITY]...[/YS_ENTITY] 实体记忆块，且 JSON 必须语法合法、完整闭合：'
            '开篇人物王建国、王叔、林小芸 + 关键信物父亲的笔记，四个实体每人/物至少写 1 条事实型印象；'
            '省略字段、引号不闭合、数组不完整一律视为不合格。'
            'max_tokens 充足，宁可压缩后续自然语言说明的篇幅，也必须保证 [YS_ENTITY] 块写完、写全。';

        String? finalDisplay;
        await service.sendMessage(
          sessionId,
          userPrompt,
          SendMessageCallbacks(
            onStream: (_) {},
            onComplete: (display, _) => finalDisplay = display,
            onError: (e) => throw Exception('onError: $e'),
          ),
          const SendMessageOptions(
            phase: TeachingPhase.p1World,
            attitude: AttitudeLevel.doubao,
          ),
        );

        // ═══════════════════════════════════════════════════════════
        // 验证 1：协议说明注入（零实体也应注入）
        // ═══════════════════════════════════════════════════════════
        final sysList = llm.firstSystemContents;
        final joinedSystem = sysList.join('\n===SYSTEM-SPLIT===\n');
        print(
          '\n┌─────────────────────────────────────────────────────────\n'
          '│ [DEBUG] LLM 总调用次数=${llm.totalCalls}；主调用 system 条数=${sysList.length}，总长度=${joinedSystem.length}\n'
          '│ [DEBUG] 是否包含 大纲实体记忆沉淀 = ${joinedSystem.contains('大纲实体记忆沉淀')}\n'
          '│ [DEBUG] 每条 system 消息前 80 字：\n',
        );
        for (var i = 0; i < sysList.length; i++) {
          final s = sysList[i];
          print(
            '│   #$i [${s.length} 字] ${s.substring(0, s.length > 80 ? 80 : s.length).replaceAll("\n", "\\n")}\n',
          );
        }
        print('└─────────────────────────────────────────────────────────');
        expect(
          joinedSystem.contains('大纲实体记忆沉淀'),
          true,
          reason: '5.1.8 应无条件注入协议说明',
        );
        expect(
          joinedSystem.contains('[YS_ENTITY]'),
          true,
          reason: '协议说明应包含 [YS_ENTITY] 标记',
        );
        print(
          '\n┌─────────────────────────────────────────────────────────\n'
          '│ [V1] 协议说明注入：OK（大纲实体记忆沉淀 + [YS_ENTITY] 都存在）\n'
          '└─────────────────────────────────────────────────────────',
        );

        // ═══════════════════════════════════════════════════════════
        // 验证 2：AI 原始回包是否输出 [YS_ENTITY]（肉眼审阅提取质量）
        // ═══════════════════════════════════════════════════════════
        final rawResp = llm.firstRawResponse;
        final hasEntityBlock =
            rawResp.contains('[YS_ENTITY]') && rawResp.contains('[/YS_ENTITY]');
        print(
          '\n┌─────────────────────────────────────────────────────────\n'
          '│ [V2] AI 完整回包全文（${rawResp.length} 字）：\n'
          '├─────────────────────────────────────────────────────────\n'
          '│ ${rawResp.replaceAll('\n', '\n│ ')}\n'
          '├─────────────────────────────────────────────────────────\n'
          '│ [V2] 是否含 [YS_ENTITY]：${rawResp.contains('[YS_ENTITY]') ? "是" : "否"}；是否含 [YS_DIAGNOSIS]：${rawResp.contains('[YS_DIAGNOSIS]') ? "是" : "否"}\n'
          '└─────────────────────────────────────────────────────────',
        );

        // ═══════════════════════════════════════════════════════════
        // 验证 3：落库 + 确认卡
        // ═══════════════════════════════════════════════════════════
        final entities = await outlineRepo.listEntities(manuscriptId);
        print(
          '\n┌─────────────────────────────────────────────────────────\n'
          '│ [V3] 落库实体数：${entities.length}\n'
          '├─────────────────────────────────────────────────────────',
        );
        for (final e in entities) {
          final aliases = OutlineRepository.parseAliases(e.aliases);
          final imps = await outlineRepo.listImpressions(e.id);
          print(
            '│ · [${e.status}] ${e.entityType}「${e.entityKey}」'
            '${aliases.isNotEmpty ? ' 别名=${aliases.join("、")}' : ''}  印象数=${imps.length}',
          );
          for (final i in imps) {
            final cf = i.conflictWith != null ? '（冲突→${i.conflictWith}）' : '';
            print('│     - [${i.status}] ${i.impression}$cf');
          }
        }
        print('└─────────────────────────────────────────────────────────');

        final cards = (await sessionRepo.listMessages(
          sessionId,
        )).where((m) => m.messageType == 'outline_confirmation').toList();
        print(
          '\n┌─────────────────────────────────────────────────────────\n'
          '│ [V3] 确认卡数：${cards.length}\n'
          '└─────────────────────────────────────────────────────────',
        );

        // 弱断言：若有实体，必 pending、必写确认卡
        if (entities.isNotEmpty) {
          expect(
            entities.every((e) => e.status == 'pending'),
            true,
            reason: '新实体未经用户确认应为 pending',
          );
          expect(cards.isNotEmpty, true, reason: '有 pending 实体印象 → 应写确认卡');
        }

        // ═══════════════════════════════════════════════════════════
        // 验证 4：assistant 落库内容剥离（无 YS_ENTITY 原始 JSON）
        // ═══════════════════════════════════════════════════════════
        final msgs = await sessionRepo.listMessages(sessionId);
        final assistantMsgs = msgs.where((m) => m.role == 'assistant').toList();
        expect(assistantMsgs.isNotEmpty, true, reason: '应有 assistant 消息');
        expect(finalDisplay, isNotNull, reason: 'onComplete 应返回展示内容');
        expect(
          finalDisplay!.contains('[YS_ENTITY]'),
          false,
          reason: 'onComplete 返回的展示内容不得含实体块',
        );
        for (final a in assistantMsgs) {
          expect(
            a.content.contains('[YS_ENTITY]'),
            false,
            reason: 'assistant 消息不得泄漏 [YS_ENTITY] 原始 JSON',
          );
          expect(
            a.content.contains('[/YS_ENTITY]'),
            false,
            reason: 'assistant 消息不得泄漏 [/YS_ENTITY] 标记',
          );
        }
        final firstAssistant = assistantMsgs.first.content;
        print(
          '\n┌─────────────────────────────────────────────────────────\n'
          '│ [V4] assistant 展示内容（前 200 + 后 200 字）：\n'
          '├─────────────────────────────────────────────────────────\n'
          '│ ${firstAssistant.substring(0, firstAssistant.length > 200 ? 200 : firstAssistant.length).replaceAll('\n', '\n│ ')}\n'
          '│ ...\n'
          '│ ${firstAssistant.substring(firstAssistant.length > 200 ? firstAssistant.length - 200 : 0).replaceAll('\n', '\n│ ')}\n'
          '│ \n'
          '│ [V4] 剥离验证：${firstAssistant.contains('[YS_ENTITY]') ? "失败 ❌" : "通过 ✅"}（展示/落库无原始 JSON）\n'
          '└─────────────────────────────────────────────────────────',
        );

        // ═══════════════════════════════════════════════════════════
        // 验证 5（强断言）：若 AI 真输出了实体块 → 必被识别 + 落库
        // ═══════════════════════════════════════════════════════════
        if (hasEntityBlock) {
          expect(
            entities.isNotEmpty,
            true,
            reason: 'AI 已输出 [YS_ENTITY] 完整块 → 解析器应识别并落库实体',
          );
        }

        // ═══════════════════════════════════════════════════════════
        // 【A4 增量更新验证准备】模拟用户全量"接受"首轮 4 条印象 → 实体/印象全 active
        // ═══════════════════════════════════════════════════════════
        final Map<String, String> r1EntityKeyToId = {};
        final Map<String, List<(String impressionId, String text)>>
        r1ImpressionsByKey = {};
        for (final e in entities) {
          r1EntityKeyToId[e.entityKey] = e.id;
          final imps = await outlineRepo.listImpressions(e.id);
          r1ImpressionsByKey[e.entityKey] = imps
              .map((i) => (i.id, i.impression))
              .toList();
          for (final i in imps) {
            await outlineRepo.approveImpression(i.id);
          }
        }
        // 验证首轮 active 化生效
        final activeEntities = await outlineRepo.listEntities(manuscriptId);
        expect(
          activeEntities.every((e) => e.status == 'active'),
          true,
          reason: 'A4 准备：首轮 approve 后实体应全 active',
        );
        for (final e in activeEntities) {
          final imps = await outlineRepo.listImpressions(e.id);
          expect(
            imps.every((i) => i.status == 'active'),
            true,
            reason: 'A4 准备：首轮 approve 后印象应全 active',
          );
        }
        print(
          '\n┌─────────────────────────────────────────────────────────\n'
          '│ [A4-准备] 首轮实体/印象已 approve → ${activeEntities.length} 实体已 active\n'
          '├─────────────────────────────────────────────────────────',
        );
        r1EntityKeyToId.forEach((k, id) {
          final imps = r1ImpressionsByKey[k]!;
          print(
            '│ · $k → entity=$id  首轮印象数=${imps.length}：${imps.map((x) => x.$1.substring(0, 8)).join(", ")}',
          );
        });
        print('└─────────────────────────────────────────────────────────');

        // ═══════════════════════════════════════════════════════════
        // 【A4 第二轮诊断】补一段同章节"延续文本"迫使 AI 对同一人物更新认知
        //  （林小芸从窗口下楼；王建国决定冲进去；王叔挡在前面 → 必然触发 matched_entity_id
        //   + 至少一次增量印象）
        // ═══════════════════════════════════════════════════════════
        const _chapterContentV2 = '''
王建国没有犹豫，一脚踹开院门，油纸包往怀里一塞。
王叔挡在他前面，疤脸在院灯下泛着白光："等等，建国。你娘说过不要报仇。"
"我不听。"王建国拨开他的手，却被王叔死死拽住手腕——那只三十年守门的手，力气比他想的大。
楼上，林小芸已经握着银色手枪从二楼台阶跑下来，她不再是远远观望的那一个；她冲到王建国身边，把枪口对准了院子里那三个人的方向。
''';
        final userPromptV2 =
            '请对以下续写内容进行写作诊断分析：\n\n'
            '【$_chapterTitle · 续写段落】\n\n'
            '$_chapterContentV2\n\n'
            '---\n'
            '重要：\n'
            '1. 诊断说明后必须输出 [YS_DIAGNOSIS]...[/YS_DIAGNOSIS] 包裹的 JSON 块，'
            '含 syndromes 数组（每条含 syndrome_id/name/severity/evidence/explanation）、'
            'suggested_actions（数组）、confidence（0-1）。\n'
            '2. **必须输出 [YS_ENTITY]...[/YS_ENTITY] 实体记忆增量块**：'
            '续写中王建国/王叔/林小芸均有新的关键动作与状态变化，请为已有实体引用 matched_entity_id '
            '（参考注入的「大纲实体索引」中方括号内实体 id），并以增量方式写 impressions；'
            '如有与旧印象明显矛盾的新认知，用 conflict_with 引用旧印象 id。\n'
            '两个结构化 JSON 块都不可缺少。';

        final cards1Count = cards.length;
        String? finalDisplayV2;
        await service.sendMessage(
          sessionId,
          userPromptV2,
          SendMessageCallbacks(
            onStream: (_) {},
            onComplete: (display, _) => finalDisplayV2 = display,
            onError: (e) => throw Exception('onError V2: $e'),
          ),
          const SendMessageOptions(
            phase: TeachingPhase.p1World,
            attitude: AttitudeLevel.doubao,
          ),
        );

        // ═══════════════════════════════════════════════════════════
        // A4-V5 第二轮索引注入（协议说明 + buildEntityIndexContext 实体索引 + 印象带 id）
        // ═══════════════════════════════════════════════════════════
        // 找最后一次包含「大纲实体记忆沉淀」的调用（即 ChatService 主调用的系统注入），
        // 而非 TeacherDecision 补自然语言单条 system。
        final sysMatches = <int>[];
        for (var i = 0; i < llm.allSystemCalls.length; i++) {
          if (llm.allSystemCalls[i].any((s) => s.contains('大纲实体记忆沉淀'))) {
            sysMatches.add(i);
          }
        }
        expect(
          sysMatches.isNotEmpty,
          true,
          reason: 'A4-V5 第二轮应有 ChatService 主调用（含协议说明）',
        );
        final r2CallIdx = sysMatches.last;
        final r2Sys = llm.allSystemCalls[r2CallIdx];
        final r2Joined = r2Sys.join('\n===SYSTEM-SPLIT===\n');
        final r2Resp = llm.allResponses[r2CallIdx];
        expect(r2Joined.contains('大纲实体记忆沉淀'), true, reason: 'A4-V5 第二轮仍注入协议说明');
        // 索引文本中应出现首轮实体 key 之一（王建国/王叔/林小芸/父亲的笔记），
        // 以及 `[印象id]` 前缀（buildEntityIndexContext 带 id 格式）
        final r2HasEntityIndex = r1EntityKeyToId.keys.any(
          (k) => r2Joined.contains(k),
        );
        // buildEntityIndexContext 实际格式：`[实体uuid] 实体（别名）：[印象uuid] 文本；[印象uuid2] 文本`
        final r2HasImpressionIdMarker = RegExp(
          r'\[[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\]',
        ).hasMatch(r2Joined);
        print(
          '\n┌─────────────────────────────────────────────────────────\n'
          '│ [A4-V5] 第二轮（调用#${r2CallIdx + 1}）system：含实体索引=$r2HasEntityIndex；含「[uuid]」格式标记=$r2HasImpressionIdMarker\n'
          '│ 命中实体：${r1EntityKeyToId.keys.where((k) => r2Joined.contains(k)).join("、")}\n'
          '└─────────────────────────────────────────────────────────',
        );
        expect(r2HasEntityIndex, true, reason: 'A4-V5 第二轮应注入实体索引（命中首轮实体名）');

        // ═══════════════════════════════════════════════════════════
        // A4-V6 第二轮回包完整性 + 审阅增量
        // ═══════════════════════════════════════════════════════════
        final hasEntityV2 =
            r2Resp.contains('[YS_ENTITY]') && r2Resp.contains('[/YS_ENTITY]');
        print(
          '\n┌─────────────────────────────────────────────────────────\n'
          '│ [A4-V6] 第二轮回包 ${r2Resp.length} 字：是否实体块=$hasEntityV2；是否诊断块=${r2Resp.contains('[YS_DIAGNOSIS]') && r2Resp.contains('[/YS_DIAGNOSIS]')}\n'
          '│ 【第二轮 [YS_ENTITY] 块原文】：\n',
        );
        final eStart = r2Resp.indexOf('[YS_ENTITY]');
        final eEnd = r2Resp.indexOf('[/YS_ENTITY]');
        if (eStart != -1 && eEnd != -1) {
          print(
            '│ ${r2Resp.substring(eStart, eEnd + '[/YS_ENTITY]'.length).replaceAll('\n', '\n│ ')}',
          );
        } else {
          print('│ （未检测到完整 [YS_ENTITY] 块，跳过块原文打印）');
        }
        print('└─────────────────────────────────────────────────────────');
        expect(hasEntityV2, true, reason: 'A4-V6 第二轮续写仍应输出 [YS_ENTITY] 增量块');

        // ═══════════════════════════════════════════════════════════
        // A4-V7 落库：matched_entity_id 命中 → 不建新实体；新增印象挂到旧实体
        // ═══════════════════════════════════════════════════════════
        final entitiesV2 = await outlineRepo.listEntities(manuscriptId);
        final impsV2ById = <String, List<OutlineImpression>>{};
        for (final e in entitiesV2) {
          impsV2ById[e.id] = await outlineRepo.listImpressions(e.id);
        }
        final totalImpressionsV2 = impsV2ById.values.fold<int>(
          0,
          (a, b) => a + b.length,
        );
        print(
          '\n┌─────────────────────────────────────────────────────────\n'
          '│ [A4-V7] 第二轮后实体数=${entitiesV2.length}（首轮=${entities.length}）；总印象数=$totalImpressionsV2（首轮=${entities.length}）\n'
          '├─────────────────────────────────────────────────────────',
        );
        for (final e in entitiesV2) {
          final aliases = OutlineRepository.parseAliases(e.aliases);
          final imps = impsV2ById[e.id]!;
          print(
            '│ · [${e.status}] ${e.entityType}「${e.entityKey}」${aliases.isNotEmpty ? ' 别名=${aliases.join("、")}' : ''} 印象数=${imps.length}（首轮 ${(r1ImpressionsByKey[e.entityKey] ?? []).length}）',
          );
          for (final i in imps) {
            final cf = i.conflictWith != null ? '（冲突→${i.conflictWith}）' : '';
            print(
              '│     - [${i.status}] ${i.impression.substring(0, i.impression.length > 60 ? 60 : i.impression.length)}…$cf',
            );
          }
        }
        print('└─────────────────────────────────────────────────────────');
        // 强：实体数不增加（AI 通过 matched_entity_id 命中首轮实体不造新 key）
        // 弱：至少一条实体印象数 > 1（增量追加成功）
        expect(
          entitiesV2.length,
          entities.length,
          reason: 'A4-V7 增量命中：实体数应与首轮一致（matched_entity_id 命中不应建新实体）',
        );
        final anyIncrement = impsV2ById.values.any((l) => l.length > 1);
        expect(anyIncrement, true, reason: 'A4-V7 续写应给至少一个已有实体追加增量印象（印象数>首轮1）');

        // ═══════════════════════════════════════════════════════════
        // A4-V8 确认卡：新增 pending 印象 → 写卡（新卡数应严格 > 首轮卡数）
        // ═══════════════════════════════════════════════════════════
        final cards2 = (await sessionRepo.listMessages(
          sessionId,
        )).where((m) => m.messageType == 'outline_confirmation').toList();
        print(
          '\n┌─────────────────────────────────────────────────────────\n'
          '│ [A4-V8] 确认卡总数=${cards2.length}；首轮=$cards1Count → 新增=${cards2.length - cards1Count} 张\n'
          '└─────────────────────────────────────────────────────────',
        );
        expect(
          cards2.length > cards1Count,
          true,
          reason: 'A4-V8 第二轮新增印象应再写确认卡，数量严格大于首轮',
        );

        // ═══════════════════════════════════════════════════════════
        // A4-V9 剥离：第二轮 assistant 展示无协议泄漏，非空兜底不走
        // ═══════════════════════════════════════════════════════════
        expect(finalDisplayV2, isNotNull);
        expect(finalDisplayV2!, isNot(contains('[YS_ENTITY]')));
        expect(finalDisplayV2!, isNot(contains('[YS_DIAGNOSIS]')));
        expect(
          finalDisplayV2!.trim(),
          isNot('诊断完成。'),
          reason: 'A4-V9 第二轮有自然语言诊断说明，不应走空兜底文案',
        );
      } finally {
        await db.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
    tags: ['live'],
  );
}
