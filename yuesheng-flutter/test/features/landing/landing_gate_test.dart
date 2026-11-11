// 站点门面门控（VM 侧）—— `§4-498` · 舰长 2026-11-11 21:59 裁「留」。
//
// 【为什么单独一个文件】与 `test/router/nav_gate_test.dart` 同源纪律：
// `kIsWeb` 在 VM 测试里恒 `false` ⇒ 判定若写成内联三元，「web 走门面」这一支
// 在 `flutter test` 里**永远走不到**，判据恒绿。抽出 `isWeb` 覆写参数后两端可断言。
//
// 【正对照是必需项】只写「web ⇒ true」的话，`bool shouldShowLanding(...) => true;`
// 这种最省事的实现也会全绿。故必须同时断言非 web ⇒ false。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/features/landing/landing_gate.dart';

void main() {
  group('站点门面门控（VM）', () {
    test('web ⇒ 展示站点门面（替代应用内引导）', () {
      expect(shouldShowLanding(isWeb: true), isTrue);
    });

    test('正对照：非 web ⇒ 走应用内引导（防实现恒返回 true）', () {
      expect(shouldShowLanding(isWeb: false), isFalse);
    });

    test('生产调用不传参 ⇒ 取编译期 kIsWeb（VM 下为 false ⇒ 不展示）', () {
      expect(shouldShowLanding(), isFalse);
    });
  });
}
