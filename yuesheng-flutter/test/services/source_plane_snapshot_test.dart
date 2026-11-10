// ─────────────────────────────────────────────────────────────
// 源面落盘牙测（B0c 前半件 · 纯 instrumentation）。
//
// 牙：① D2 拼接排除 assistant 回显（负向对照：助手文本不得出现）
//     ② 序列化往返逐字一致 + sha 负向变异（改一字节必变）
//     ③ save/load 真实文件往返 + 体积超限拒绝保存（不截断）
//     ④ 保留期棘轮：>50 份只留最近 50
//     ⑤ 零行为面：本文件不引用任何诊断/provider/prompt 符号（静态扫描牙）
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/source_plane_snapshot.dart';

void main() {
  group('D2 会话上下文拼接（E5 已验证口径）', () {
    test('只收 user/system， assistant 回显不进证据面', () {
      final text = assembleConversationText(const <SourcePlaneMessage>[
        SourcePlaneMessage(role: 'system', content: '系统提示词'),
        SourcePlaneMessage(role: 'user', content: '用户线索：窗外'),
        SourcePlaneMessage(role: 'assistant', content: 'AI 回忆：上章有伏笔'),
      ]);
      expect(text.contains('系统提示词'), isTrue);
      expect(text.contains('用户线索：窗外'), isTrue);
      expect(
        text.contains('AI 回忆：上章有伏笔'),
        isFalse,
        reason: '回忆不等于证据（D2 域声明逐字）',
      );
      expect(text.contains('assistant'), isFalse);
    });
  });

  group('逐字锚与序列化', () {
    test('相同输入同 sha；改一字必变（负向变异）', () {
      final a = sourcePlaneSha(
        chapterText: '窗外桦树林',
        conversationText: '用户线索',
        settingText: '',
      );
      final same = sourcePlaneSha(
        chapterText: '窗外桦树林',
        conversationText: '用户线索',
        settingText: '',
      );
      final changed = sourcePlaneSha(
        chapterText: '窗外桦树森',
        conversationText: '用户线索',
        settingText: '',
      );
      expect(a.length, 16);
      expect(same, a);
      expect(changed, isNot(a), reason: 'sha 恒同 ⇒ 逐字复验无牙');
    });

    test('toJson/fromJson 往返逐字一致（三域 + 计数 + 域）', () {
      const snapshot = SourcePlaneSnapshot(
        snapshotId: 'sp-1-abcd',
        createdAt: 1,
        domain: SourcePlaneDomain.d3,
        chapterText: '正文\n第二行',
        conversationText: '用户消息',
        settingText: '设定：城市',
        contentSha: 'abcd',
      );
      final decoded = SourcePlaneSnapshot.fromJson(snapshot.toJson());
      expect(decoded.snapshotId, snapshot.snapshotId);
      expect(decoded.domain, SourcePlaneDomain.d3);
      expect(decoded.chapterText, '正文\n第二行');
      expect(decoded.conversationText, '用户消息');
      expect(decoded.settingText, '设定：城市');
      expect(decoded.contentSha, 'abcd');
      expect(snapshot.toJson()['chapterChars'], 6);
    });
  });

  group('存储（真实文件 IO · 临时目录）', () {
    late Directory temp;
    var fakeSeconds = 1000;

    SourcePlaneStore store() =>
        SourcePlaneStore(directory: () async => temp, now: () => fakeSeconds++);

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('source_plane_test_');
    });
    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('save → load 往返逐字一致；文件不存在 ⇒ null', () async {
      final s = store();
      final saved = await s.save(
        domain: SourcePlaneDomain.d2,
        chapterText: '弗利西安看向火车的窗外。',
        messages: const <SourcePlaneMessage>[
          SourcePlaneMessage(role: 'user', content: '用户线索'),
          SourcePlaneMessage(role: 'assistant', content: 'AI 回显'),
        ],
      );
      expect(saved.domain, SourcePlaneDomain.d2);
      expect(saved.conversationText, '用户线索');

      final loaded = await s.load(saved.snapshotId);
      expect(loaded, isNotNull);
      expect(loaded!.chapterText, saved.chapterText);
      expect(loaded.conversationText, '用户线索');
      expect(loaded.contentSha, saved.contentSha);
      expect(await s.load('不存在的-id'), isNull, reason: '不猜、不回退');
    });

    test('单域超限 ⇒ 拒绝落盘（不截断、目录无文件）', () async {
      final s = store();
      final long = '字' * (SourcePlaneStore.kMaxCharsPerDomain + 1);
      expect(
        () => s.save(domain: SourcePlaneDomain.d1, chapterText: long),
        throwsA(isA<StateError>()),
      );
      expect(await s.listIds(), isEmpty, reason: 'fail-closed：超限零落盘');
    });

    test('保留期棘轮：55 份 ⇒ 只剩最近 50（负向对照：最旧被删）', () async {
      final s = store();
      final ids = <String>[];
      for (var i = 0; i < SourcePlaneStore.kMaxSnapshots + 5; i++) {
        final saved = await s.save(
          domain: SourcePlaneDomain.d1,
          chapterText: '正文-$i',
        );
        ids.add(saved.snapshotId);
      }
      final kept = await s.listIds();
      expect(kept.length, SourcePlaneStore.kMaxSnapshots);
      expect(kept.contains(ids.first), isFalse, reason: '最旧 5 份已删');
      expect(kept.contains(ids.last), isTrue, reason: '最新 1 份仍在');
    });
  });

  group('零行为面（静态扫描牙）', () {
    test('组件源码不含诊断/prompt/provider 引用', () {
      // T-20261031-03 裁 2：组件拆成「门面 + core + io/web」四个文件 ⇒
      // 扫描面**跟着实现一起搬**（否则门面化会让本护栏退化成空断言）。
      final src = [
        'lib/services/source_plane_snapshot.dart',
        'lib/services/source_plane_snapshot_core.dart',
        'lib/services/source_plane_snapshot_io.dart',
        'lib/services/source_plane_snapshot_web.dart',
      ].map((rel) => File(rel).readAsStringSync()).join('\n');
      for (final banned in <String>[
        'syndrome_registry',
        'buildChunkSystemPrompt',
        'isWeakEvidence',
        'chatServiceProvider',
      ]) {
        expect(src.contains(banned), isFalse, reason: '源面快照不得触碰行为面：$banned');
      }
    });
  });
}
