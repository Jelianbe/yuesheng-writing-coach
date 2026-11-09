// ─────────────────────────────────────────────────────────────
// 源面快照接线牙测（B0c 后半件 · 纯 instrumentation）。
//
// 牙：① 成功落 D2 快照：正文逐字 + user/system 入域、assistant 出域
//     ② 失败 / 挂起 / 超限一律 null，零落盘（不阻断诊断主链）
//     ③ D3 不伪造 + 零行为面静态扫描
//     ④ controller 接线点唯一、在诊断前、且被 unawaited 包裹
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/source_plane_capture.dart';
import 'package:writingcoach/services/source_plane_snapshot.dart';

void main() {
  late Directory temp;
  var seconds = 1000;

  SourcePlaneStore store() =>
      SourcePlaneStore(directory: () async => temp, now: () => seconds++);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('source_plane_capture_test_');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('诊断源面落盘（D2）', () {
    test('正文逐字 + user/system 入域，assistant 回显不入域', () async {
      final s = store();
      final snapshot = await captureDiagnosisSourcePlane(
        chapterText: '弗利西安看向火车的窗外。',
        loader: () async => const <SourcePlaneMessage>[
          SourcePlaneMessage(role: 'system', content: '系统提示词'),
          SourcePlaneMessage(role: 'user', content: '用户线索：窗外'),
          SourcePlaneMessage(role: 'assistant', content: 'AI 回忆：上章伏笔'),
        ],
        store: s,
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.domain, SourcePlaneDomain.d2);
      expect(snapshot.chapterText, '弗利西安看向火车的窗外。');
      expect(snapshot.conversationText, '系统提示词\n用户线索：窗外');
      expect(snapshot.conversationText.contains('AI 回忆'), isFalse);
      expect(snapshot.settingText, '', reason: 'D3 设定无消费通路，不伪造');
      expect(
        snapshot.contentSha,
        sourcePlaneSha(
          chapterText: snapshot.chapterText,
          conversationText: snapshot.conversationText,
          settingText: '',
        ),
      );
      final loaded = await s.load(snapshot.snapshotId);
      expect(loaded, isNotNull);
      expect(loaded!.chapterText, snapshot.chapterText);
      expect(loaded.conversationText, snapshot.conversationText);
    });

    test('会话读取失败 ⇒ null，零落盘（不阻断诊断）', () async {
      final s = store();
      final snapshot = await captureDiagnosisSourcePlane(
        chapterText: '正文',
        loader: () async => throw StateError('db 读取失败'),
        store: s,
      );
      expect(snapshot, isNull);
      expect(await s.listIds(), isEmpty);
    });

    test('会话读取挂起 ⇒ 超时返回 null（挂起 ≠ 成功）', () async {
      final s = store();
      final snapshot = await captureDiagnosisSourcePlane(
        chapterText: '正文',
        loader: () => Completer<List<SourcePlaneMessage>>().future,
        store: s,
        timeout: const Duration(milliseconds: 30),
      );
      expect(snapshot, isNull);
      expect(await s.listIds(), isEmpty);
    });

    test('正文超限 ⇒ 拒绝落盘返回 null（不截断）', () async {
      final s = store();
      final long = '字' * (SourcePlaneStore.kMaxCharsPerDomain + 1);
      final snapshot = await captureDiagnosisSourcePlane(
        chapterText: long,
        loader: () async => const <SourcePlaneMessage>[],
        store: s,
      );
      expect(snapshot, isNull);
      expect(await s.listIds(), isEmpty);
    });

    test('同输入重复落盘 ⇒ 同 sha（R1 复验可对齐）', () async {
      final s = store();
      Future<SourcePlaneSnapshot?> run() => captureDiagnosisSourcePlane(
        chapterText: '同一章正文',
        loader: () async => const <SourcePlaneMessage>[
          SourcePlaneMessage(role: 'user', content: '同一条线索'),
        ],
        store: s,
      );
      final a = await run();
      final b = await run();
      expect(a!.contentSha, b!.contentSha);
      expect(a.snapshotId, isNot(b.snapshotId), reason: '秒计数递增，快照不覆盖');
    });
  });

  group('零行为面（静态扫描牙）', () {
    test('接线源码不触诊断结论 / prompt / 冒充设定', () {
      final src = File(
        'lib/services/source_plane_capture.dart',
      ).readAsStringSync();
      for (final banned in <String>[
        'isWeakEvidence',
        'buildChunkSystemPrompt',
        'chatServiceProvider',
        'buildStoryStructureProfileText',
        '_structureProfileText',
        'settingText:',
      ]) {
        expect(src.contains(banned), isFalse, reason: '接线不得触碰行为面：$banned');
      }
    });

    test('controller 接线恰一次、在诊断前、且被 unawaited 包裹', () {
      final src = File(
        'lib/features/chat/chat_diagnosis_controller.dart',
      ).readAsStringSync();
      expect(
        'captureDiagnosisSourcePlane('.allMatches(src).length,
        1,
        reason: '重复落盘会让 R1 复验对不上号',
      );
      expect(
        RegExp(r'unawaited\(\s*captureDiagnosisSourcePlane\(').hasMatch(src),
        isTrue,
        reason: '必须 unawaited：平台通道挂起不得拖死诊断主链（B13-1）',
      );
      expect(
        src.indexOf('captureDiagnosisSourcePlane('),
        lessThan(src.indexOf('await _runDiagnosis(chapter, bootstrap);')),
        reason: '源面须取诊断发起前，避免混入系统生成的诊断请求消息',
      );
    });
  });
}
