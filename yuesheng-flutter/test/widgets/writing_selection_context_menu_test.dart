// ─────────────────────────────────────────────────────────────
// writing_selection_context_menu 单元测试（2026-11-22）
//
// 判据：新交互「复制/粘贴/引用诊断/存入设定库」统一菜单的纯函数行为——
//   ① 系统项（copy/paste/selectAll）原样保留；
//   ② 自定义项「引用诊断」始终存在且点击触发回调；
//   ③ 「存入设定库」按回调有无条件渲染；
//   ④ 回调可触发（能变红：若 onPressed 未接线则断言失败）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/features/writing/writing_selection_context_menu.dart';

void main() {
  group('buildSelectionMenuItems 统一选择菜单', () {
    final systemCopy = ContextMenuButtonItem(
      type: ContextMenuButtonType.copy,
      onPressed: () {},
    );
    final systemPaste = ContextMenuButtonItem(
      type: ContextMenuButtonType.paste,
      onPressed: () {},
    );
    final systemSelectAll = ContextMenuButtonItem(
      type: ContextMenuButtonType.selectAll,
      onPressed: () {},
    );

    test('系统复制/粘贴/全选项原样保留在最前', () {
      final items = buildSelectionMenuItems(
        systemItems: [systemCopy, systemPaste, systemSelectAll],
        onDiagnose: () {},
      );

      expect(items.take(3).toList(), [
        systemCopy,
        systemPaste,
        systemSelectAll,
      ]);
    });

    test('「引用诊断」项始终存在，label 正确', () {
      final items = buildSelectionMenuItems(
        systemItems: const [],
        onDiagnose: () {},
      );

      final diagnose = items.where(
        (i) => i.label == kSelectionMenuDiagnoseLabel,
      );
      expect(diagnose, hasLength(1));
      expect(diagnose.single.type, ContextMenuButtonType.custom);
    });

    test('点击「引用诊断」触发 onDiagnose（回调接线可验证）', () {
      var called = 0;
      final items = buildSelectionMenuItems(
        systemItems: const [],
        onDiagnose: () => called++,
      );

      items
          .firstWhere((i) => i.label == kSelectionMenuDiagnoseLabel)
          .onPressed!
          .call();

      expect(called, 1);
    });

    test('onSaveToLibrary 非空 → 渲染「存入设定库」且点击触发', () {
      var saved = 0;
      final items = buildSelectionMenuItems(
        systemItems: const [],
        onDiagnose: () {},
        onSaveToLibrary: () => saved++,
      );

      final save = items.where(
        (i) => i.label == kSelectionMenuSaveToLibraryLabel,
      );
      expect(save, hasLength(1));
      save.single.onPressed!.call();
      expect(saved, 1);
    });

    test('onSaveToLibrary 为 null → 不渲染该项', () {
      final items = buildSelectionMenuItems(
        systemItems: const [],
        onDiagnose: () {},
      );

      expect(
        items.any((i) => i.label == kSelectionMenuSaveToLibraryLabel),
        isFalse,
      );
    });
  });
}
