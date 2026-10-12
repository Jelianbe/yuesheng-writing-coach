// ─────────────────────────────────────────────────────────────
// ADR-0006 D 组：故事结构画像（story_structure_profile）测试
//
// 覆盖三层判据：
//   H-1 覆盖度首行强制（序列化函数保证，非 prompt 请求）
//   H-2 覆盖度低于阈值 ⇒ 整块不注入（宁缺毋滥）
//   C-5 抽取质量自检（事件密度过低 ⇒ lowConfidence 标注）
// 另覆盖：预算闸、密度曲线身份键、因果覆盖率、孤儿事件计数。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/story_structure_profile.dart';

void main() {
  // 覆盖度分母固定 10 章；diagnosedChapterKeys 用 sort_order 字符串键。
  List<StructureProfileEventInput> events(int n, {String? type}) => [
    for (var i = 0; i < n; i++)
      (
        name: '事件$i',
        chapter: i + 1,
        chapterSortOrder: i,
        eventType: type ?? (i % 2 == 0 ? '决定' : '冲突'),
        causeEventId: i % 3 == 0 ? null : 'E0',
        stale: false,
      ),
  ];

  group('H-1 覆盖度首行强制', () {
    test('#1 画像文本首行含覆盖度声明（已诊断 X/Y 章 + 百分比）', () {
      final p = buildStoryStructureProfile(
        events: events(8),
        diagnosedChapterKeys: {'0', '1', '2', '3'},
        totalChapters: 10,
      );
      expect(p.injectable, isTrue);
      final first = p.text!.split('\n').first;
      expect(first, contains('[结构画像]'));
      expect(first, contains('4/10'));
      expect(first, contains('40%'));
      expect(first, contains('未诊断章节不构成判断依据'));
    });

    test('#2 覆盖度 100% 时首行为 10/10（分母 = 非归档章节数）', () {
      final p = buildStoryStructureProfile(
        events: events(10),
        diagnosedChapterKeys: {for (var i = 0; i < 10; i++) '$i'},
        totalChapters: 10,
      );
      expect(p.text!.split('\n').first, contains('10/10'));
    });
  });

  group('H-2 覆盖度阈值', () {
    test('#3 覆盖度低于 30% ⇒ 不注入、skipReason=coverage_low', () {
      final p = buildStoryStructureProfile(
        events: events(6),
        diagnosedChapterKeys: {'0', '1'},
        totalChapters: 10,
      );
      expect(p.injectable, isFalse);
      expect(p.skipReason, 'coverage_low');
      expect(p.text, isNull);
      expect(p.coverage, closeTo(0.2, 0.001));
    });

    test('#4 恰好 30% 边界 ⇒ 注入（判据是「低于」不注入，等于放行）', () {
      final p = buildStoryStructureProfile(
        events: events(6),
        diagnosedChapterKeys: {'0', '1', '2'},
        totalChapters: 10,
      );
      expect(p.injectable, isTrue);
      expect(p.skipReason, isNull);
    });

    test('#5 事件表为空 ⇒ 不注入、skipReason=events_empty', () {
      final p = buildStoryStructureProfile(
        events: const [],
        diagnosedChapterKeys: const {},
        totalChapters: 10,
      );
      expect(p.injectable, isFalse);
      expect(p.skipReason, 'events_empty');
    });

    test('#6 totalChapters=0（防除零）⇒ coverage=0 ⇒ 不注入', () {
      final p = buildStoryStructureProfile(
        events: events(4),
        diagnosedChapterKeys: const {'0'},
        totalChapters: 0,
      );
      expect(p.injectable, isFalse);
      expect(p.skipReason, 'coverage_low');
    });
  });

  group('五组指标', () {
    test('#7 事件类型分布按数量降序列出', () {
      final p = buildStoryStructureProfile(
        events: [
          for (var i = 0; i < 6; i++)
            (
              name: 'e$i',
              chapter: i + 1,
              chapterSortOrder: i,
              eventType: '日常',
              causeEventId: 'E0',
              stale: false,
            ),
          for (var i = 6; i < 9; i++)
            (
              name: 'e$i',
              chapter: i + 1,
              chapterSortOrder: i,
              eventType: '转折',
              causeEventId: 'E0',
              stale: false,
            ),
        ],
        diagnosedChapterKeys: {for (var i = 0; i < 9; i++) '$i'},
        totalChapters: 10,
      );
      final dist = p.text!
          .split('\n')
          .firstWhere((l) => l.startsWith('事件类型分布'));
      expect(dist, contains('日常6'));
      expect(dist, contains('转折3'));
      expect(dist.indexOf('日常'), lessThan(dist.indexOf('转折')));
    });

    test('#8 因果链覆盖只统计关键事件（决定/转折/突发），冲突/日常不计', () {
      final p = buildStoryStructureProfile(
        events: [
          (
            name: 'k1',
            chapter: 1,
            chapterSortOrder: 0,
            eventType: '决定',
            causeEventId: 'E0', // 有因
            stale: false,
          ),
          (
            name: 'k2',
            chapter: 2,
            chapterSortOrder: 1,
            eventType: '转折',
            causeEventId: null, // 无因
            stale: false,
          ),
          (
            name: 'n1',
            chapter: 3,
            chapterSortOrder: 2,
            eventType: '冲突',
            causeEventId: null, // 非关键，不计入分母
            stale: false,
          ),
        ],
        diagnosedChapterKeys: {'0', '1', '2'},
        totalChapters: 10,
      );
      final line = p.text!.split('\n').firstWhere((l) => l.startsWith('因果链覆盖'));
      expect(line, contains('1/2'));
      expect(line, contains('50%'));
    });

    test('#9 密度曲线用 chapterSortOrder（身份键），非 AI 原值 chapter', () {
      final p = buildStoryStructureProfile(
        events: [
          (
            name: 'x',
            chapter: 99, // AI 原值乱标
            chapterSortOrder: 0, // 身份键才是排序依据
            eventType: '决定',
            causeEventId: 'E0',
            stale: false,
          ),
        ],
        diagnosedChapterKeys: {'0'},
        totalChapters: 3,
      );
      final line = p.text!
          .split('\n')
          .firstWhere((l) => l.startsWith('章节事件密度'));
      expect(line, contains('1章×1')); // sortOrder 0 → 第 1 章
      expect(line, isNot(contains('99')));
    });

    test('#10 孤儿关键事件 = 无前因的关键事件数（stale 不计）', () {
      final p = buildStoryStructureProfile(
        events: [
          (
            name: 'a',
            chapter: 1,
            chapterSortOrder: 0,
            eventType: '决定',
            causeEventId: null,
            stale: false,
          ),
          (
            name: 'b',
            chapter: 2,
            chapterSortOrder: 1,
            eventType: '转折',
            causeEventId: null,
            stale: true, // stale 事件整体剔除
          ),
        ],
        diagnosedChapterKeys: {'0', '1'},
        totalChapters: 3,
      );
      final line = p.text!
          .split('\n')
          .firstWhere((l) => l.startsWith('孤儿关键事件'));
      expect(line, contains('1 个'));
    });
  });

  group('C-5 抽取质量自检', () {
    test('#11 每已诊断章节事件数 < 2 ⇒ qualityOk=false 且文本标注低置信', () {
      final p = buildStoryStructureProfile(
        events: events(3), // 3 章 3 事件 = 1.0/章 < 2.0
        diagnosedChapterKeys: {'0', '1', '2'},
        totalChapters: 10,
      );
      expect(p.qualityOk, isFalse);
      expect(p.injectable, isTrue); // 仍注入，但标注低置信
      expect(p.text, contains('低置信'));
    });

    test('#12 密度达标 ⇒ qualityOk=true、无低置信标注', () {
      final p = buildStoryStructureProfile(
        events: events(8), // 4 章 8 事件 = 2.0/章 ≥ 2.0
        diagnosedChapterKeys: {'0', '1', '2', '3'},
        totalChapters: 10,
      );
      expect(p.qualityOk, isTrue);
      expect(p.text, isNot(contains('低置信')));
    });
  });

  group('预算闸（C-2）', () {
    test('#13 超长时总长 ≤ kProfileMaxChars 且首行（覆盖度）不丢', () {
      // 构造超多样本条数逼超预算：长事件名 + 多章节。
      final p = buildStoryStructureProfile(
        events: [
          for (var i = 0; i < 200; i++)
            (
              name: '很长的事件名字$i',
              chapter: i + 1,
              chapterSortOrder: i,
              eventType: '决定',
              causeEventId: null,
              stale: false,
            ),
        ],
        diagnosedChapterKeys: {for (var i = 0; i < 200; i++) '$i'},
        totalChapters: 200,
      );
      expect(p.text!.length, lessThanOrEqualTo(kProfileMaxChars));
      expect(p.text!.split('\n').first, contains('[结构画像]'));
    });
  });
}
