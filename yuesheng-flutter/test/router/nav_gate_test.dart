// NAV-1 门控（VM 侧）—— `T-20261111-01` · 舰长 2026-11-11 19:27 裁。
//
// 【为什么要这个文件】`kIsWeb` 在 VM 测试里恒 `false` ⇒ 若判定写成内联三元，
// 「web 隐藏底栏」这一支在 `flutter test` 里**永远走不到** —— 判据恒绿。
// 抽出 `isWeb` 覆写参数后，两个分支都能断言。
//
// 【正对照是必需项，不是锦上添花】只写「web ⇒ false」的话，
// `bool shouldRenderBottomNav(...) => false;` 这种最省事的实现也会全绿。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/router/nav_gate.dart';

void main() {
  group('NAV-1 底部导航门控（VM）', () {
    test('web ⇒ 不渲染底栏', () {
      expect(shouldRenderBottomNav(isWeb: true), isFalse);
    });

    test('正对照：非 web ⇒ 渲染底栏（防实现恒返回 false）', () {
      expect(shouldRenderBottomNav(isWeb: false), isTrue);
    });

    test('生产调用不传参 ⇒ 取编译期 kIsWeb（VM 下为 false ⇒ 渲染）', () {
      expect(shouldRenderBottomNav(), isTrue);
    });
  });
}
