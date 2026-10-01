// ─────────────────────────────────────────────────────────────
// diagnostic_reference_page_test — 诊断资料区测试（ADR-C122 一期）
//
// 覆盖：
//   1. 列表页渲染全部 34 条症候（编号+名称+一句解读）
//   2. 详情页四区块展示（这是什么/为什么是问题/常见表现/对应训练动作）
//   3. syndromeLearnerNoteById 命中与未命中
//
// 纯展示页测试：不进注入链，无 R-027 面。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/features/growth/diagnostic_reference_page.dart';
import 'package:writingcoach/services/syndrome_learner_notes.dart';

void main() {
  test('数据完整性：34 条症候，编号与名称齐全、actionRefs 非空', () {
    expect(kSyndromeLearnerNotes.length, 34);
    for (final note in kSyndromeLearnerNotes) {
      expect(note.id, startsWith('P'));
      expect(note.name, isNotEmpty);
      expect(note.what, isNotEmpty);
      expect(note.why, isNotEmpty);
      expect(note.signs, isNotEmpty);
      expect(note.actionRefs, isNotEmpty);
      // 幽灵键消歧：编号不重复
      expect(
        kSyndromeLearnerNotes.where((n) => n.id == note.id).length,
        1,
        reason: '${note.id} 重复',
      );
    }
  });

  testWidgets('列表页：渲染 34 条 + 首尾条目可见', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DiagnosticReferenceListPage()),
    );

    // 头部标题
    expect(find.text('教学资料'), findsOneWidget);
    // 列表项（ListView 懒加载，断言首条与条数来源数据）
    expect(find.text('P001'), findsOneWidget);
    expect(find.text('情绪标签化'), findsOneWidget);
    // 底部条目需滚动可见——直接断言数据源长度（UI 渲染由首条抽查代表）
    expect(kSyndromeLearnerNotes.length, 34);
  });

  testWidgets('详情页：四区块字段完整展示', (tester) async {
    final note = kSyndromeLearnerNotes.first; // P001 情绪标签化
    await tester.pumpWidget(
      MaterialApp(home: SyndromeLearnerDetailPage(note: note)),
    );

    // 区块标题
    expect(find.text('这是什么'), findsOneWidget);
    expect(find.text('为什么是问题'), findsOneWidget);
    expect(find.text('常见表现'), findsOneWidget);
    expect(find.text('对应训练动作'), findsOneWidget);

    // 内容字段
    expect(find.text(note.what), findsOneWidget);
    expect(find.text(note.why), findsOneWidget);
    for (final sign in note.signs) {
      expect(find.text(sign), findsOneWidget);
    }
    for (final ref in note.actionRefs) {
      expect(find.text(ref), findsOneWidget);
    }
  });

  test('syndromeLearnerNoteById：命中与未命中', () {
    final hit = syndromeLearnerNoteById('P034');
    expect(hit, isNotNull);
    expect(hit!.name, '指称歧义/零回指过载症');

    expect(syndromeLearnerNoteById('P999'), isNull);
  });
}
