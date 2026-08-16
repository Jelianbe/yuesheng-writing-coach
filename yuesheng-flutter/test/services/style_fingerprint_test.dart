// ─────────────────────────────────────────────────────────────
// style_fingerprint_test — 定量指纹提取 + 声线漂移检测（批次64 B62f）
//
// 覆盖：
//   extractStyleFingerprint:
//     1. 正常文本 → 提取全部指标（句长/段落/对话/句式/标点/修辞/高频词）
//     2. 对话占比正确（引号行/总行）
//     3. 样本不足（过短）→ null
//     4. JSON 往返（toJson/tryFromJson）
//   detectVoiceDrift:
//     5. 句长均值偏离 ≥40% → 提示
//     6. 对话占比偏离 ≥0.15 → 提示
//     7. 无偏离 → 空列表
//     8. 最多 3 条
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/style_fingerprint.dart';

void main() {
  group('extractStyleFingerprint', () {
    test('#1 正常文本 → 提取全部指标', () {
      const text =
          '他推开门，风灌了进来。\n'
          '桌角的信纸被吹落，散了一地。\n'
          '她站在窗边，一言不发。\n'
          '窗外是沉默的雪。\n'
          '他忽然笑了："你说得对。"\n'
          '她回头看他，眼眶有些红。\n'
          '这场雪下得真大……\n'
          '他们都没有再说话。';
      final fp = extractStyleFingerprint(text);
      expect(fp, isNotNull);
      expect(fp!.avgSentenceLength, greaterThan(0));
      expect(fp.sentenceLengthVariance, greaterThanOrEqualTo(0));
      // 对话占比：8 行中 1 行含引号 → 0.125
      expect(fp.dialogueRatio, closeTo(0.125, 0.001));
      expect(fp.narrativeRatio, closeTo(0.875, 0.001));
      expect(
        fp.shortParaRatio + fp.mediumParaRatio + fp.longParaRatio,
        closeTo(1.0, 0.001),
      );
      expect(fp.simpleSentenceRatio, inInclusiveRange(0, 1));
      expect(fp.sentencesCount, greaterThanOrEqualTo(5));
      expect(fp.topWords, isNotEmpty);
      // 省略号密度 > 0
      expect(fp.ellipsisDensity, greaterThan(0));
    });

    test('#2 对话占比：引号行判定', () {
      const text =
          '他说："走吧，雪越下越大了。"\n'
          '她点点头，没有说话。\n'
          '他说："天快黑了，我们该回去了。"\n'
          '两人并肩走在雪地里。\n'
          '他忽然停下脚步。\n'
          '"等等。"他说。';
      final fp = extractStyleFingerprint(text)!;
      // 6 行，3 行含引号 → 0.5
      expect(fp.dialogueRatio, closeTo(0.5, 0.001));
    });

    test('#3 样本不足（过短）→ null', () {
      expect(extractStyleFingerprint('他走了。'), isNull);
      expect(extractStyleFingerprint(''), isNull);
    });

    test('#4 JSON 往返', () {
      const text =
          '雪落在屋檐上，发出细碎的声响。'
          '他坐在窗前，看了一整夜。'
          '天快亮的时候，她回来了。'
          '他说：你终于回来了。'
          '她笑了笑，没有说话。'
          '炉火噼啪作响。'
          '这一夜，好像特别长……';
      final fp = extractStyleFingerprint(text)!;
      final restored = StyleFingerprint.tryFromJson(fp.toJson());
      expect(restored, isNotNull);
      expect(restored!.avgSentenceLength, fp.avgSentenceLength);
      expect(restored.sentencesCount, fp.sentencesCount);
      expect(restored.topWords, fp.topWords);
    });
  });

  group('detectVoiceDrift', () {
    StyleFingerprint fp({
      required double avg,
      required double dialogue,
      double simple = 0.5,
      double exclamation = 0,
      double ellipsis = 0,
      int sentences = 20,
    }) {
      return StyleFingerprint(
        avgSentenceLength: avg,
        sentenceLengthVariance: 10,
        shortParaRatio: 0.5,
        mediumParaRatio: 0.4,
        longParaRatio: 0.1,
        dialogueRatio: dialogue,
        narrativeRatio: 1 - dialogue,
        simpleSentenceRatio: simple,
        metaphorDensity: 0,
        rhetoricalQuestionDensity: 0,
        ellipsisDensity: ellipsis,
        exclamationDensity: exclamation,
        topWords: const {},
        sentencesCount: sentences,
      );
    }

    test('#5 句长均值偏离 ≥40% → 提示（例证式带数字）', () {
      final base = fp(avg: 18, dialogue: 0.3);
      final current = fp(avg: 8, dialogue: 0.3); // 18 → 8，偏离 55%
      final hints = detectVoiceDrift(base, current);
      expect(hints, isNotEmpty);
      expect(hints.first, contains('通常约 18 字'));
      expect(hints.first, contains('平均只有 8 字'));
      expect(hints.first, contains('是刻意加速'));
    });

    test('#6 对话占比偏离 ≥0.15 → 提示', () {
      final base = fp(avg: 15, dialogue: 0.3);
      final current = fp(avg: 15, dialogue: 0.6); // +0.3
      final hints = detectVoiceDrift(base, current);
      expect(hints.any((h) => h.contains('对话和叙述的配比')), true);
    });

    test('#7 无偏离 → 空列表', () {
      final base = fp(avg: 15, dialogue: 0.3);
      final current = fp(avg: 17, dialogue: 0.32); // 偏离 13% < 40%
      final hints = detectVoiceDrift(base, current);
      expect(hints, isEmpty);
    });

    test('#8 感叹号激增 → 提示', () {
      final base = fp(avg: 15, dialogue: 0.3, exclamation: 0.5);
      final current = fp(avg: 15, dialogue: 0.3, exclamation: 8);
      final hints = detectVoiceDrift(base, current);
      expect(hints.any((h) => h.contains('感叹号')), true);
    });

    test('#9 最多 3 条（多维度同时偏离被截断）', () {
      final base = fp(
        avg: 18,
        dialogue: 0.3,
        simple: 0.4,
        exclamation: 0.5,
        ellipsis: 1,
      );
      final current = fp(
        avg: 8, // 句长偏离
        dialogue: 0.6, // 对话偏离
        simple: 0.9, // 句式偏离
        exclamation: 8, // 感叹号
        ellipsis: 12, // 省略号
      );
      final hints = detectVoiceDrift(base, current);
      expect(hints.length, lessThanOrEqualTo(3));
    });
  });
}
