// ─────────────────────────────────────────────────────────────
// ui_overlay_provider_test — 全局 Toast/Dialog 覆盖层队列测试
//
// 覆盖：
//   1. showToast：入队 + 状态暴露
//   2. showToast 超时自动 dismiss（fakeAsync 推进）
//   3. dismissToast 手动移除
//   4. confirm：挂起时 confirm 入状态，resolve(true) → Future=true
//   5. confirm：resolve(false) → Future=false（取消）
//   6. confirm 挂起期间再次 confirm：前者 Future=false，新请求替换
// ─────────────────────────────────────────────────────────────

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/providers/ui_overlay_provider.dart';

void main() {
  late ProviderContainer container;
  late UiOverlayNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(uiOverlayProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  test('showToast：入队 + 状态暴露', () {
    notifier.showToast('已保存');
    notifier.showToast('保存失败', kind: UiToastKind.error);
    final state = container.read(uiOverlayProvider);
    expect(state.toasts.length, 2);
    expect(state.toasts.first.message, '已保存');
    expect(state.toasts.first.kind, UiToastKind.info);
    expect(state.toasts.last.kind, UiToastKind.error);
  });

  test('showToast 超时自动 dismiss（默认 2s）', () {
    fakeAsync((async) {
      notifier.showToast('临时提示');
      expect(container.read(uiOverlayProvider).toasts.length, 1);
      async.elapse(const Duration(milliseconds: 2100));
      expect(container.read(uiOverlayProvider).toasts, isEmpty);
    });
  });

  test('dismissToast 手动移除', () {
    notifier.showToast('A');
    notifier.showToast('B');
    final id = container.read(uiOverlayProvider).toasts.first.id;
    notifier.dismissToast(id);
    final remaining = container.read(uiOverlayProvider).toasts;
    expect(remaining.length, 1);
    expect(remaining.first.message, 'B');
  });

  test('confirm：resolve(true) → Future 返回 true 且状态清除', () async {
    final future = notifier.confirm(
      title: '删除章节？',
      message: '确认删除吗',
      confirmText: '删除',
      cancelText: '取消',
    );
    final state = container.read(uiOverlayProvider);
    expect(state.confirm, isNotNull);
    expect(state.confirm!.title, '删除章节？');
    expect(state.confirm!.confirmText, '删除');

    notifier.resolveConfirm(true);
    expect(await future, isTrue);
    expect(container.read(uiOverlayProvider).confirm, isNull);
  });

  test('confirm：resolve(false) → Future 返回 false（取消）', () async {
    final future = notifier.confirm(title: 'T', message: 'M');
    notifier.resolveConfirm(false);
    expect(await future, isFalse);
    expect(container.read(uiOverlayProvider).confirm, isNull);
  });

  test('confirm 挂起期间再次 confirm：前者 Future=false，新请求替换', () async {
    final first = notifier.confirm(title: '第一个', message: 'M1');
    final second = notifier.confirm(title: '第二个', message: 'M2');
    // 第一个被覆盖 → false
    expect(await first, isFalse);
    expect(container.read(uiOverlayProvider).confirm!.title, '第二个');
    notifier.resolveConfirm(true);
    expect(await second, isTrue);
  });

  test('provider dispose：挂起 confirm 未 resolve → Future=false', () async {
    final future = notifier.confirm(title: 'T', message: 'M');
    container.dispose();
    expect(await future, isFalse);
  });
}
