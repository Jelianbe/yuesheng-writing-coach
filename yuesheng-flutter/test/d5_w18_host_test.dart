// ─────────────────────────────────────────────────────────────
// DiagnosisChainLiveTest — D5 Phase 3 · 真实诊断链采集 harness
//
// 目的：为 D5-3（月笙诊断分类）/ D5-4 右半列（映射矩阵）/ D5-5（五项指标）
//       采集**真实诊断输出**。此前 03/04/05/06 全部自陈「零运行验证」，
//       导致「月笙诊断」这一列恒为 0 条，是 D5 十项里 4 项的硬阻塞。
//
// 链路同构（形态检验）：与 closed_loop_smoke_test 同一条
//   assembleSendContext → parseAndPersist → commitDiagnosis 生产链路，
//   仅把 FakeLlmClient 换成真实 LlmClient（真实 DeepSeek 调用）。
//
// 三轮实跑纪要（2026-10-14）：
//   run1  误用 corpus_* fixture（那是协议回复测试件不是课文）⇒ 全 SKIPPED
//   run2  换盲测批原文后 5 条诊断流成功；但 debugPrintThrottled 丢掉
//         绝大多数 JSON 分块（只剩 D5J|0|/|1|），且 key 中途余额耗尽
//   run3  key 已 402（HTTP 402 = DeepSeek 余额不足）；另暴露
//         rawOutputs/requestSnapshots 错位 RangeError 与「首点必死」
//
// 本版修复：① 按调用打 tag（根治归属漂移 + RangeError）
//           ② 首点无响应时重试（≤2 次）
//           ③ HTTP 402 快速失败（不再每样本空等 240s）
//           ④ 绕过 debugPrintThrottled；快照裁剪（头尾 600 字 + trunc 标记），
//              模型原始输出保持全量
//
// ── W-18 宿主版（2026-10-15）──────────────────────────────────
// 与 integration_test/ 设备版同一套采集逻辑，但跑在**宿主 flutter test**
// （无模拟器/设备）。与设备版的差异：
//   ① 去掉 integration_test 绑定（TestWidgetsFlutterBinding 宿主即起）
//   ② 网络等待段包 tester.runAsync（离开 FakeAsync 用真时钟，HTTP 才能推进）
//   ③ 新增 YS_TEST_ONLY=<样本ID> 单样本冒烟 define
//   ④ 轮次参数 YS_TEST_TEMP（经 shared_constants.streamTemperature 生效）
// 运行（key 不落仓库；输出必须重定向文件）：
//   flutter test test/d5_w18_host_test.dart \
//     --dart-define=YS_TEST_KEY=sk-xxxx [--dart-define=YS_TEST_TEMP=0.3] \
//     [--dart-define=YS_TEST_ONLY=X17] > w18_t07_r1.log 2>&1
// 纪律：只报「误报密度」不报率（批3 §4.5）；控制台绝不打印 key。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/features/writing/writing_coach_panel.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/providers/writing_providers.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/widgets/diagnosis_card.dart';

import '../integration_test/d5_sample_texts.dart';

/// 一次 LLM 调用的完整记录。归属按 [tag]（= 发起时的样本 ID），
/// 不再按窗口下标切片——那会因「在途调用跨样本」而错位（run2/run3 实证）。
class CallRecord {
  final String tag;
  final List<ChatMessage> snapshot;
  final StringBuffer buf = StringBuffer();
  bool done = false;
  String? error;

  CallRecord(this.tag, this.snapshot);
  String get output => buf.toString();
}

class RecordingLlmClient extends LlmClient {
  final List<CallRecord> calls = <CallRecord>[];

  /// 当前样本 ID；每次 tap 前由 harness 设置。
  String currentTag = '';

  RecordingLlmClient(Future<LlmConfigValues?> Function() loader)
    : super(null, null, loader);

  List<CallRecord> callsOf(String tag) =>
      calls.where((c) => c.tag == tag).toList();

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    final rec = CallRecord(currentTag, <ChatMessage>[
      for (final m in messages)
        ChatMessage(
          role: m.role,
          content: m.content,
          contentBlocks: m.contentBlocks,
        ),
    ]);
    calls.add(rec);
    try {
      await super.streamChat(
        messages,
        (r) {
          if (r.content.isNotEmpty) rec.buf.write(r.content);
          callback(r);
        },
        cancelToken: cancelToken,
        extraBody: extraBody,
      );
      rec.done = true;
    } catch (e) {
      rec.error = e.toString();
      rethrow;
    }
  }
}

/// 快照消息裁剪：头 600 + 尾 600 字符 + 显式 trunc 标记。
List<Map<String, dynamic>> trimSnap(List<ChatMessage> snap) =>
    <Map<String, dynamic>>[
      for (final m in snap)
        <String, dynamic>{
          'role': m.role,
          'chars': m.content.length,
          if (m.content.length <= 1300)
            'content': m.content
          else ...<String, dynamic>{
            'content_head': m.content.substring(0, 600),
            'content_tail': m.content.substring(m.content.length - 600),
            'trunc': true,
          },
          if (m.contentBlocks != null && m.contentBlocks!.isNotEmpty)
            'content_blocks': <Map<String, dynamic>>[
              for (final b in m.contentBlocks!) b.toJson(),
            ],
        },
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // 宿主绑定（无设备）
  // T-20261016 W-29 复测批：flutter_test 默认把 HttpClient 换成「永远 400」
  // （p029 负样本 live 组同款处置，其 setUpAll 注释实证）——清掉它真实 HTTP
  // 才能出网。本批 X11 首跑 400 的真根因即此（此前误判为模型/参数被拒）。
  HttpOverrides.global = null;
  // 宿主无 platform channel：mock connectivity_plus（llm_client 网络预检用）。
  // 纯测试侧 mock，生产零影响。
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => ['wifi'],
      );
  // secure_storage：resolver 链 legacy 读取用；read→null = 走 fallback（不炸）
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => null,
      );
  // path_provider：harness 落档用（已有 try/catch，mock 后能真落档更好）
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.createTempSync('w18host').path,
      );

  // ★ 绕过 debugPrintThrottled：run2 实证大流量分块被节流队列静默丢弃。
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) print(message); // ignore: avoid_print
  };

  const key = String.fromEnvironment('YS_TEST_KEY');

  /// live 级 harness 门闩：无 Key（本地全量门禁场景）⇒ 整组 skip 而非 fail
  /// ——该用例需真实 Key 与网络，与 test/live_* 同级，不进常规全量测试。
  final bool w18HasKey =
      const bool.hasEnvironment('YS_TEST_KEY') && key.isNotEmpty;

  late AppDatabase db;
  late ProviderContainer container;
  late RecordingLlmClient llm;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    llm = RecordingLlmClient(
      () async => LlmConfigValues(
        apiKey: key,
        // YS_TEST_BASE_URL：wire 捕获口（指向本地回显服务器抓真实请求体），
        // 缺省走 DeepSeek 真源，跑批不传即逐字节不变。
        baseUrl: const String.fromEnvironment(
          'YS_TEST_BASE_URL',
          defaultValue: 'https://api.deepseek.com',
        ),
        // YS_TEST_MODEL（T-20261016 W-29 复测批新增）：2026-10-16 实测
        // 'deepseek-chat' 对本 key 返回 HTTP 400（W-18 基线 10-15 尚可用），
        // 'deepseek-v4-flash' 可用（p029 live 组同款）⇒ 可经 define 覆盖，
        // 缺省保持 deepseek-chat（W-18 基线可复现）。
        model: const String.fromEnvironment(
          'YS_TEST_MODEL',
          defaultValue: 'deepseek-chat',
        ),
      ),
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llmClientProvider.overrideWithValue(llm),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  // live 级 harness：无 Key ⇒ skip 而非 fail（需真实 Key 与网络，
  // 与 test/live_* 同级，不进常规全量测试）。
  testWidgets('D5 Phase3：真实诊断链逐样本采集', skip: !w18HasKey, (tester) async {
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final manuscriptId = await msRepo.createManuscript(
      title: 'D5 Phase3 实时采集稿',
    );

    final results = <Map<String, dynamic>>[];
    var keyDead = false; // HTTP 402 快速失败

    for (final sample in kD5Samples) {
      if (keyDead) {
        results.add(<String, dynamic>{
          'sample': sample.id,
          'type': sample.type,
          'expect_label': sample.expect,
          'status': 'SKIPPED',
          'reason': 'key 余额不足（前序样本 HTTP 402），快速跳过',
        });
        continue;
      }

      final only = const String.fromEnvironment('YS_TEST_ONLY');
      if (only.isNotEmpty && sample.id != only) {
        results.add(<String, dynamic>{
          'sample': sample.id,
          'type': sample.type,
          'expect_label': sample.expect,
          'status': 'SKIPPED',
          'reason': 'YS_TEST_ONLY=$only 过滤',
        });
        continue;
      }

      // ★ 低于 100 字门槛：直接记录跳过（「诊断本章」有字数门槛，点了也不会触发）
      if (sample.text.length < 100) {
        results.add(<String, dynamic>{
          'sample': sample.id,
          'type': sample.type,
          'expect_label': sample.expect,
          'status': 'TOO_SHORT',
          'manuscript_chars': sample.text.length,
          'manuscript': sample.text,
          'reason': '低于「诊断本章」100 字门槛，未触发诊断',
        });
        print(
          'D5SKIP|${sample.id}|chars=${sample.text.length}',
        ); // ignore: avoid_print
        continue;
      }

      final chapterId = await chRepo.createChapter(
        manuscriptId,
        title: '样本 ${sample.id}',
        content: sample.text,
      );
      await container
          .read(writingStoreProvider(chapterId).notifier)
          .loadChapter();

      llm.currentTag = sample.id;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: WritingCoachPanel(
                chapterId: chapterId,
                manuscriptId: manuscriptId,
                chapterTitle: '样本 ${sample.id}',
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final diagButton = find.text('诊断本章');
      if (diagButton.evaluate().isEmpty) {
        results.add(<String, dynamic>{
          'sample': sample.id,
          'type': sample.type,
          'expect_label': sample.expect,
          'status': 'SKIPPED',
          'reason': '未找到「诊断本章」按钮',
        });
        continue;
      }

      final tapAt = DateTime.now();
      // ★ 首点重试：run2/run3 实证首个面板挂载后的首次 tap 可能不触发流
      //   （无 sendMessage 日志）。每 20s 检查：无卡片且无调用 → 再点一次，≤3 次。
      //   （T-20261016：tap 保持 FakeAsync 区——runAsync 内 tap 命中测试失效
      //   实证；400 真根因是 HttpOverrides，见 main 头注，已清。）
      var taps = 0;
      const maxTaps = 3;
      const pollFor = Duration(seconds: 240);
      final deadline = tapAt.add(pollFor);
      var cardAppeared = false;

      while (DateTime.now().isBefore(deadline) && !cardAppeared && !keyDead) {
        if (taps < maxTaps && diagButton.evaluate().isNotEmpty) {
          await tester.tap(diagButton, warnIfMissed: true);
          taps++;
          print('D5TAP|${sample.id}|attempt=$taps'); // ignore: avoid_print
        }
        // 宿主版：真时钟轮询（runAsync 离开 FakeAsync，真实 HTTP 才能推进）
        await tester.runAsync(() async {
          final segEnd = DateTime.now().add(const Duration(seconds: 20));
          while (DateTime.now().isBefore(segEnd) && !cardAppeared && !keyDead) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            cardAppeared = find.byType(DiagnosisCard).evaluate().isNotEmpty;
            final mine = llm.callsOf(sample.id);
            // 402 快速失败：本样本已有调用且全部以错误结束
            if (mine.isNotEmpty &&
                mine.every((c) => c.done || c.error != null)) {
              final errs = mine.map((c) => c.error ?? '').join(';');
              if (errs.contains('402')) {
                keyDead = true;
                print(
                  'D5FATAL|${sample.id}|HTTP 402 余额不足，快速失败',
                ); // ignore: avoid_print
              }
              break;
            }
          }
        });
        await tester.pump(const Duration(milliseconds: 100));
      }
      final elapsed = DateTime.now().difference(tapAt);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      List<DiagnosisRow>? diagRows;
      List<ActiveProblem>? activeRows;
      await tester.runAsync(() async {
        // 宿主版：真时钟等卡片数据落库（流结束后 commit 有异步尾）
        final tail = DateTime.now().add(const Duration(seconds: 10));
        while (DateTime.now().isBefore(tail)) {
          final sessions = await db.select(db.sessions).get();
          final sid = sessions.isEmpty ? null : sessions.last.id;
          if (sid != null) {
            final dr = await (db.select(
              db.diagnosisResults,
            )..where((t) => t.sessionId.equals(sid))).get();
            if (dr.isNotEmpty) {
              diagRows = dr;
              activeRows = await (db.select(
                db.activeProblems,
              )..where((t) => t.sessionId.equals(sid))).get();
              break;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      });

      final mine = llm.callsOf(sample.id);
      // 宿主版：closure 赋值破坏流分析 → 收敛为局部非空列表
      final diagRowsN = (diagRows ?? <DiagnosisRow>[]);
      final activeRowsN = (activeRows ?? <ActiveProblem>[]);
      final errs = [
        for (final c in mine)
          if (c.error != null) c.error!,
      ];
      final has402 = errs.any((e) => e.contains('402'));

      final record = <String, dynamic>{
        'sample': sample.id,
        'type': sample.type,
        'expect_label': sample.expect,
        'status': cardAppeared
            ? 'OK'
            : has402
            ? 'LLM_ERROR_402'
            : mine.any((c) => c.error != null)
            ? 'LLM_ERROR'
            : 'NO_CARD',
        'tap_attempts': taps,
        'elapsed_seconds': elapsed.inSeconds,
        'llm_errors': errs,
        'manuscript_chars': sample.text.length,
        'manuscript': sample.text,
        'llm_calls_this_sample': mine.length,
        'request_snapshots': <Map<String, dynamic>>[
          for (final c in mine)
            <String, dynamic>{'done': c.done, 'messages': trimSnap(c.snapshot)},
        ],
        'raw_model_outputs': [for (final c in mine) c.output],
        'diagnosis_results': <Map<String, dynamic>>[
          for (final r in diagRowsN)
            <String, dynamic>{
              'status': r.status,
              'confidence': r.confidence,
              'syndromes_raw': r.syndromes,
              'suggested_actions_raw': r.suggestedActions,
              'root_cause_analysis': r.rootCauseAnalysis,
              'next_focus': r.nextFocus,
              'feedback_summary': r.feedbackSummary,
              'current_teaching_focus_id': r.currentTeachingFocusId,
              'focus_reason': r.focusReason,
            },
        ],
        'active_problems': <Map<String, dynamic>>[
          for (final a in activeRowsN)
            <String, dynamic>{
              'syndrome_id': a.syndromeId,
              'syndrome_name': a.syndromeName,
              'severity': a.severity,
              'status': a.status,
              'confirmation_status': a.confirmationStatus,
              'evidence_confidence': a.evidenceConfidence,
              'teaching_state': a.teachingState,
              'resolved_at': a.resolvedAt,
            },
        ],
      };
      results.add(record);

      // ★ 每样本即时回传摘要（JSON 分块即使再丢，映射也保得住）
      // ignore: avoid_print
      print(
        'D5REC|${sample.id}|${record['status']}|calls=${mine.length}'
        '|elapsed=${elapsed.inSeconds}s|taps=$taps'
        '|diagRows=${diagRows?.length ?? 0}|activeRows=${activeRows?.length ?? 0}'
        '|err=${errs.isEmpty ? '无' : errs.first}',
      ); // ignore: avoid_print

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    final payload = <String, dynamic>{
      'collected_at': DateTime.now().toIso8601String(),
      'model': 'deepseek-chat',
      'base_url': 'https://api.deepseek.com',
      'frame': 'boxB-subset（临时框 · 三重标注 · 只报密度不报率）',
      'sample_count': results.length,
      'results': results,
    };

    final jsonText = json.encode(payload);

    // 分块回传（绕过节流后的 print 直写 logcat）
    final chunks = <String>[];
    for (var i = 0; i < jsonText.length; i += 3000) {
      final end = i + 3000 < jsonText.length ? i + 3000 : jsonText.length;
      chunks.add(jsonText.substring(i, end));
    }
    for (var i = 0; i < chunks.length; i++) {
      print('D5J|$i|${chunks[i]}'); // ignore: avoid_print
    }
    // ignore: avoid_print
    print('D5J|END|total=${chunks.length}');
    // ignore: avoid_print
    // ignore: avoid_print
    debugPrint('D5_LIVE_SAMPLES ${results.length}');

    try {
      final dir = await getApplicationDocumentsDirectory();
      final out = File(
        '${dir.path}/yuesheng_d5_live_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await out.writeAsString(jsonText, flush: true);
      debugPrint('D5_LIVE_OUT ${out.path}');
    } catch (e) {
      debugPrint('D5_LIVE_FILE_SKIP $e');
    }
    debugPrint('D5_LIVE_SAMPLES ${results.length}');
    debugPrint('D5_LIVE_LLM_CALLS ${llm.calls.length}');

    if (keyDead) {
      fail(
        'YS_TEST_KEY 余额不足（HTTP 402）——请充值或换 key 后重跑；'
        '本轮已采集 ${results.where((r) => r['status'] == 'OK').length} 条 OK 样本',
      );
    }
    expect(
      results.length,
      kD5Samples.length,
      reason: '每个样本都要有记录（含 SKIPPED），不得中途丢样本',
    );
  });
}
