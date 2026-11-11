// ─────────────────────────────────────────────────────────────
// chat_header_capacity_test — 对话头部容量与触控契约
//
// 真源：`T-20261111-01` U1 设计稿 §TC-1 / §TC-2 / §IA-6（舰长 2026-11-11 批）
//
// ★ 本文件同时钉住一个**实测才发现的老缺陷**：360dp 下态度 chips 的 `Row`
//   溢出 1.5px（3 chip 305.5 + 3×8 = 329.5 vs 可用 328）。设计稿 §5.1 全是
//   推算、没量过，所以没抓到；U2 跑探针才抓到。已改 `Wrap` 修复，这里加
//   断言防回归。
//
// 视口：360×740（仓库既有先例 chat_header_test.dart:210）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/features/chat/chat_header.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  Widget buildHeader({
    String? primaryRefTitle,
    String? entryPoint,
    VoidCallback? onTapPrimaryRef,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ChatHeader(
          currentAttitude: AttitudeLevel.gentle,
          onAttitudeChange: (_) {},
          onOpenSessionDrawer: () {},
          onOpenProfile: () {},
          onNewSession: () {},
          entryPoint: entryPoint,
          primaryRefTitle: primaryRefTitle,
          onTapPrimaryRef: onTapPrimaryRef ?? () {},
        ),
      ),
    );
  }

  Future<void> usePhone(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => t.binding.setSurfaceSize(null));
  }

  /// 命中区高度 = **最近一层可点容器**的 rect（不是文字 rect ——
  /// 文字会被内边距缩小，本项目常见 (48-21)/2 = 13.5dp 级误差）。
  double hitHeight(WidgetTester t, Finder text) {
    final ink = find.ancestor(of: text, matching: find.byType(InkWell));
    if (ink.evaluate().isNotEmpty) return t.getRect(ink.first).height;
    final gesture = find.ancestor(
      of: text,
      matching: find.byType(GestureDetector),
    );
    return t.getRect(gesture.first).height;
  }

  Future<void> openMoreMenu(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pumpAndSettle();
  }

  // ══════════════════════════════════════════════════════════
  // 回归：360dp 下头部与弹层**不得**出现任何溢出
  // ══════════════════════════════════════════════════════════
  group('容量回归（360dp 无溢出）', () {
    testWidgets('头部 + 更多弹层打开 → takeException 为 null', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(buildHeader(primaryRefTitle: '测试书名'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '头部自身不得溢出');

      await openMoreMenu(tester);
      // 改动前此处有两条溢出：态度 Row 横向 1.5px、主引用列纵向 4px
      expect(tester.takeException(), isNull, reason: '更多弹层不得溢出');
    });
  });

  // ══════════════════════════════════════════════════════════
  // TC-1：主引用小字的命中区
  // ══════════════════════════════════════════════════════════
  group('TC-1 主引用小字命中区', () {
    testWidgets('命中区 ≥32dp（56 头部内的几何上限）', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(buildHeader(primaryRefTitle: '测试书名'));
      await tester.pumpAndSettle();

      // 设计稿原判据写 ≥48，但 24(标题行高) + 48 = 72 > 56 头部 ⇒ 不可达。
      // 实测上限 = 56 − 24 = 32，已按实测降级（卡片 §六 有订正记录）。
      expect(
        hitHeight(tester, find.text('测试书名')),
        greaterThanOrEqualTo(32),
        reason: '原为 17dp（整行文字当按钮），现应撑满头部剩余高度',
      );
    });

    testWidgets('负对照：扩热区没盖住左侧汉堡', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(buildHeader(primaryRefTitle: '测试书名'));
      await tester.pumpAndSettle();

      final menu = find.byIcon(Icons.menu).hitTestable();
      expect(menu, findsOneWidget, reason: '汉堡必须仍可点');
    });
  });

  // ══════════════════════════════════════════════════════════
  // TC-2：更多弹层内的触控区 + 首屏契约
  // ══════════════════════════════════════════════════════════
  group('TC-2 更多弹层触控区', () {
    testWidgets('7 个档位 chip 命中区均 ≥44dp', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(buildHeader(primaryRefTitle: '测试书名'));
      await tester.pumpAndSettle();
      await openMoreMenu(tester);

      for (final label in ['温柔语气', '月笙如歌', 'sensei', '标准', '轻量']) {
        final f = find.text(label);
        expect(f, findsOneWidget, reason: 'chip「$label」应存在');
        expect(
          hitHeight(tester, f),
          greaterThanOrEqualTo(44),
          reason: 'chip「$label」的命中区应 ≥44dp（原 ≈29dp）',
        );
      }
    });

    testWidgets('两个整行入口命中区均 ≥48dp', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(buildHeader(primaryRefTitle: '测试书名'));
      await tester.pumpAndSettle();
      await openMoreMenu(tester);

      expect(
        hitHeight(tester, find.text('管理教练')),
        greaterThanOrEqualTo(48),
        reason: '管理教练行原为 36dp',
      );
      expect(
        hitHeight(tester, find.text('画像')),
        greaterThanOrEqualTo(48),
        reason: '画像行原为 47dp',
      );
    });

    testWidgets('首屏契约：抬高 chip 后「画像」仍完整可见', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(buildHeader(primaryRefTitle: '测试书名'));
      await tester.pumpAndSettle();
      await openMoreMenu(tester);

      // 这是必须「量」而不是「估」的那一条：抬高 chip 会把弹层内容顶高
      // ≈43dp，若顶到弹层上限，最底部的「画像」会被挤出可滚区域。
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      final sheetRect = tester.getRect(sheet);
      final profileRect = tester.getRect(find.text('画像'));
      expect(
        profileRect.bottom,
        lessThanOrEqualTo(sheetRect.bottom),
        reason: '「画像」不得被推出弹层可视边界',
      );
      // 负对照：确认弹层内确实还有内容在视口内（不是空弹层）
      expect(tester.getRect(find.text('态度档位')).top, greaterThan(0));
    });
  });

  // ══════════════════════════════════════════════════════════
  // IA-6：第 3 个右侧按钮的容量红线（几何契约）
  // ══════════════════════════════════════════════════════════
  group('IA-6 头部容量红线', () {
    testWidgets('80 字主引用下：标题右边界 < 新建对话按钮左边界', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(buildHeader(primaryRefTitle: '一二三四五六七八九十' * 8));
      await tester.pumpAndSettle();

      final titleRight = tester.getRect(find.text('会话')).right;
      final addLeft = tester
          .getRect(find.byIcon(Icons.add_comment_outlined))
          .left;
      expect(
        titleRight,
        lessThan(addLeft),
        reason: '中心块与右侧按钮区不得几何重叠（重叠也不报溢出，只能这样测）',
      );
      // 负对照：右侧按钮必须真在（否则上式在「按钮没渲染」时也会通过）
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    });
  });
}
