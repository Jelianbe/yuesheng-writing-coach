// ─────────────────────────────────────────────────────────────
// V-5 回归网：章节状态配色「单一真源 + 统一兜底」
//
// 钉住三层命题（对应本批三项改动，缺一层都会留复发土壤）：
//   ① 值域锁 —— chapterStatusConfig 恰 3 键、标签与 9 色值逐项等于
//      收敛前的 AppColors 令牌（任何人改值域/配色必须过这条显式断言）
//   ② 兜底行为锁 —— 表外状态 ⇒ 详情页章节卡**不渲染徽标**（本批把
//      `?? draft` 编造行为改掉的**唯一线上可见语义变化点**）；
//      配「卡片正常渲染」阳性对照，防「整卡没 build 冒充 findsNothing」假绿
//   ③ 源码对账 meta —— 抽屉不再自持本地表、真源引用在场
//      （防后续批次「复制一份改」重演分叉；File 读法有 V-3/V-4 先例）
//
// 判别性依据（§4-28 纪律）：②的夹具刻意用**表外状态**『paused』——
// 旧实现（?? draft 兜底）与新实现（判空隐藏）在该输入上**必然分叉**；
// 表内状态两种实现渲染相同、零鉴别力，故只作正向回归不作裁决用例。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/config/app_theme.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/features/manuscript/manuscript_detail_chapter_card.dart';

/// 纯数据构造 Chapter（drift 数据类不经 DB，CHECK 约束管不到它 ——
/// 这正是能测「表外状态」分支的原因；DB 路径实测进不来表外值）。
Chapter _fakeChapter({required String status}) => Chapter(
  id: 'ch-1',
  manuscriptId: 'ms-1',
  volumeId: null,
  title: '第一章',
  content: '一' * 1234,
  previousContent: null,
  wordCount: 1234,
  sortOrder: 0,
  status: status,
  lastDiagnosedAt: null,
  createdAt: 0,
  updatedAt: 0,
);

Future<void> _pumpCard(WidgetTester tester, Chapter chapter) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChapterCard(
          chapter: chapter,
          index: 0,
          onTap: () {},
          onLongPress: () {},
          onDelete: () {},
          onRename: () {},
        ),
      ),
    ),
  );
}

void main() {
  group('① 值域锁：chapterStatusConfigFor 逐项对账（P1-6 const 表→palette 驱动函数）', () {
    // P1-6：const Map 改为 chapterStatusConfigFor(AppPalette, status)；light 恒等
    // AppColors（护栏锁）⇒ 逐项断言语义不变；函数对表外状态返回 null（不编造）。
    const p = AppPalette.light;

    test('恰 3 键：表内状态返回配置、表外状态返回 null（加状态须同步两页消费点）', () {
      expect(chapterStatusConfigFor(p, 'draft'), isNotNull);
      expect(chapterStatusConfigFor(p, 'revising'), isNotNull);
      expect(chapterStatusConfigFor(p, 'complete'), isNotNull);
      expect(chapterStatusConfigFor(p, 'paused'), isNull);
      expect(chapterStatusConfigFor(p, ''), isNull);
    });

    test('标签锁定（改文案 = 用户可见变化，必须显式过这里）', () {
      expect(chapterStatusConfigFor(p, 'draft')!.label, '草稿');
      expect(chapterStatusConfigFor(p, 'revising')!.label, '修改中');
      expect(chapterStatusConfigFor(p, 'complete')!.label, '完成');
    });

    test('9 色值锁定 = 收敛前两表的逐字值（等价迁移证明，非新造配色）', () {
      expect(chapterStatusConfigFor(p, 'draft')!.bgColor, AppColors.border);
      expect(chapterStatusConfigFor(p, 'draft')!.textColor, AppColors.textDeep);
      expect(
        chapterStatusConfigFor(p, 'revising')!.bgColor,
        AppColors.warningBg,
      );
      expect(
        chapterStatusConfigFor(p, 'revising')!.textColor,
        AppColors.warning,
      );
      expect(chapterStatusConfigFor(p, 'complete')!.bgColor, AppColors.l1);
      expect(
        chapterStatusConfigFor(p, 'complete')!.textColor,
        AppColors.primary,
      );
    });

    test('★ P1-6 暗色真翻：同键 dark 配色 != light（const 表时代做不到的事）', () {
      const d = AppPalette.dark;
      expect(
        chapterStatusConfigFor(d, 'draft')!.bgColor,
        isNot(chapterStatusConfigFor(p, 'draft')!.bgColor),
      );
      expect(chapterStatusConfigFor(d, 'complete')!.textColor, d.primary);
    });
  });

  group('② 兜底行为锁：详情页章节卡（表外状态不渲染徽标、不编造）', () {
    testWidgets('draft 正例 → 渲染「草稿」徽标', (tester) async {
      await _pumpCard(tester, _fakeChapter(status: 'draft'));
      expect(find.text('草稿'), findsOneWidget);
    });

    testWidgets('revising 正例 → 渲染「修改中」徽标', (tester) async {
      await _pumpCard(tester, _fakeChapter(status: 'revising'));
      expect(find.text('修改中'), findsOneWidget);
    });

    testWidgets('★ 判别用例：表外状态 paused → 三种徽标标签全部不渲染；'
        '阳性对照证明卡片本身已构建（防整卡未渲染冒充 findsNothing 假绿）', (tester) async {
      await _pumpCard(tester, _fakeChapter(status: 'paused'));
      // 阳性对照：标题 + 字数在场 ⇒ build() 确实跑过
      expect(find.text('第一章'), findsOneWidget);
      expect(find.text('1.2千字'), findsOneWidget);
      // 被测命题：不编造任何状态徽标（旧实现 `?? draft` 会显「草稿」⇒ 本条必红）
      expect(find.text('草稿'), findsNothing);
      expect(find.text('修改中'), findsNothing);
      expect(find.text('完成'), findsNothing);
    });
  });

  group('③ 源码对账 meta：单一真源在场、抽屉本地表不得复现', () {
    final drawerSrc = File(
      'lib/widgets/chapter_tree_drawer.dart',
    ).readAsStringSync();

    test('抽屉真源引用在场（读的是那张表，不是自己抄一份）', () {
      expect(
        drawerSrc,
        contains('chapterStatusConfigFor(context.palette, chapter.status)'),
      );
      expect(
        drawerSrc,
        contains('_buildStatusBadge(ChapterStatusConfig status)'),
      );
    });

    test('抽屉不再自持本地表（旧私有类名与三个标签字面量必须绝迹）', () {
      expect(drawerSrc, isNot(contains('_StatusConfig')));
      expect(drawerSrc, isNot(contains("'草稿'")));
      expect(drawerSrc, isNot(contains("'修改中'")));
      expect(drawerSrc, isNot(contains("'完成'")));
    });
  });
}
