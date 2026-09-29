// ─────────────────────────────────────────────────────────────
// 两个运行时修复的回归测试
//
// Bug1（上传即诊断拿不到内容）：waitForDiagnosableChapter ——
//   章节正文未落盘时不发空诊断，等落盘后才返回可诊断章节。
//
// Bug2（暂停后用户原因与旧诊断流混在一起）：ChatStore 流式缓冲 ——
//   「停止生成」必须清空待渲染增量，新一轮从干净缓冲开始，新旧不拼接。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/features/chat/chat_diagnosis_controller.dart';
import 'package:writingcoach/providers/chat_store.dart';

Chapter _chapter({required String id, String? content}) {
  // 默认正文 ~200 字，稳过 diagnosisWordThreshold(=100)
  final body = content ?? '这是足够长的章节正文内容，用来模拟落盘后可诊断的章节正文。' * 8;
  return Chapter(
    id: id,
    manuscriptId: 'ms-1',
    title: '第一章',
    content: body,
    wordCount: body.length,
    sortOrder: 1,
    status: 'draft',
    volumeId: null,
    createdAt: 1700000000,
    updatedAt: 1700000000,
    previousContent: null,
    lastDiagnosedAt: null,
  );
}

void main() {
  group('Bug1 waitForDiagnosableChapter（上传即诊断等待落盘）', () {
    test('正文已就绪 → 立即返回章节，不发空诊断', () async {
      final ready = _chapter(id: 'c1');
      var calls = 0;
      final result = await waitForDiagnosableChapter(
        fetch: () async {
          calls++;
          return ready;
        },
        // 测试里用极短间隔，不拖慢 CI
        delay: const Duration(milliseconds: 1),
      );
      expect(result.chapter, same(ready));
      expect(result.tooShort, isFalse);
      expect(calls, 1); // 第一次就拿到，无需多轮轮询
    });

    test('章节稍后才落盘 → 轮询到就绪后返回（不静默拿空）', () async {
      final ready = _chapter(id: 'c1');
      var calls = 0;
      final result = await waitForDiagnosableChapter(
        fetch: () async {
          calls++;
          // 前 2 次模拟导入事务尚未对读连接可见
          if (calls < 3) return null;
          return ready;
        },
        delay: const Duration(milliseconds: 1),
      );
      expect(result.chapter, same(ready));
      expect(calls, greaterThanOrEqualTo(3));
    });

    test('章节一直不存在 → 返回 null 且 tooShort=false（提示未就绪，不发诊断）', () async {
      var calls = 0;
      final result = await waitForDiagnosableChapter(
        fetch: () async {
          calls++;
          return null;
        },
        maxAttempts: 5,
        delay: const Duration(milliseconds: 1),
      );
      expect(result.chapter, isNull);
      expect(result.tooShort, isFalse);
      expect(calls, 5);
    });

    test('章节存在但正文不足门槛 → tooShort=true（走「先编辑」提示，不发空诊断）', () async {
      final short = _chapter(id: 'c1', content: '太短');
      final result = await waitForDiagnosableChapter(
        fetch: () async => short,
        maxAttempts: 5,
        delay: const Duration(milliseconds: 1),
      );
      expect(result.chapter, isNull);
      expect(result.tooShort, isTrue);
    });
  });

  group('Bug2 ChatStore 暂停清空缓冲，新一轮不与旧输出拼接', () {
    test('旧诊断流累加内容 → cancelStreaming 立即清空，isStreaming 复位', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(chatStoreProvider.notifier);

      store.setStreaming(true, stageLabel: '正在诊断本章…');
      store.appendStreamingContent('旧诊断结果片段一');
      store.appendStreamingContent('旧诊断结果片段二');
      expect(
        container.read(chatStoreProvider).streamingContent,
        contains('旧诊断结果'),
      );
      expect(container.read(chatStoreProvider).isStreaming, isTrue);

      // 用户点「停止生成」
      store.cancelStreaming();

      expect(container.read(chatStoreProvider).isStreaming, isFalse);
      expect(container.read(chatStoreProvider).streamingContent, '');
    });

    test('暂停后新一轮流式只含新内容，不含旧诊断残留', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(chatStoreProvider.notifier);

      // 上一轮：诊断流输出旧内容
      store.setStreaming(true, stageLabel: '正在诊断本章…');
      store.appendStreamingContent('旧的诊断输出');
      // 暂停
      store.cancelStreaming();

      // 新一轮：用户回答「原因」，从干净缓冲开始
      store.setStreaming(true, stageLabel: '正在思考…');
      expect(container.read(chatStoreProvider).streamingContent, '');
      store.appendStreamingContent('新的原因回答');
      store.appendStreamingContent('新的后续');

      final bubble = container.read(chatStoreProvider).streamingContent;
      expect(bubble, '新的原因回答新的后续');
      expect(
        bubble.contains('旧的诊断输出'),
        isFalse,
        reason: '旧诊断流的缓冲必须被清空，不能拼进新气泡',
      );
    });

    test('两段式：Teacher 阶段切换标签不清空已显示内容，取消后才清空', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(chatStoreProvider.notifier);

      store.setStreaming(true, stageLabel: '正在诊断本章…');
      store.appendStreamingContent('诊断正文');
      // 进入 Teacher 段：保留诊断正文，仅切标签
      store.updateStreamingStageLabel('正在生成教学建议…');
      expect(container.read(chatStoreProvider).streamingContent, '诊断正文');

      // 用户暂停 Teacher → 缓冲立即清空
      store.cancelStreaming();
      expect(container.read(chatStoreProvider).streamingContent, '');
      expect(container.read(chatStoreProvider).isStreaming, isFalse);
    });
  });
}
