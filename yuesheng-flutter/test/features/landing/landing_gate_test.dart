// 「web 端面」与「首访首屏」门控（VM 侧）—— `§4-498` + `§4-499`。
//
// 【为什么单独一个文件】与 `test/router/nav_gate_test.dart` 同源纪律：
// `kIsWeb` 在 VM 测试里恒 `false` ⇒ 判定若写成内联三元，「web 走门面」这一支
// 在 `flutter test` 里**永远走不到**，判据恒绿。抽出 `isWeb` 覆写参数后两端可断言。
//
// 【正对照是必需项】只写「web ⇒ true」的话，`bool shouldShowLanding(...) => true;`
// 这种最省事的实现也会全绿。故必须同时断言非 web ⇒ false。
//
// 【`§4-499` 起本文件守两个函数】`isWebSurface`（web 端面）与 `shouldShowLanding`
// （首访首屏）。两者当前取值一致，但**分开断言** —— 否则将来有人把其中一个写死，
// 另一个会替它遮住红。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/features/landing/landing_gate.dart';

void main() {
  group('web 端面判定（isWebSurface）', () {
    test('web ⇒ true', () {
      expect(isWebSurface(isWeb: true), isTrue);
    });

    test('正对照：非 web ⇒ false（防实现恒返回 true）', () {
      expect(isWebSurface(isWeb: false), isFalse);
    });

    test('生产调用不传参 ⇒ 取编译期 kIsWeb（VM 下为 false）', () {
      expect(isWebSurface(), isFalse);
    });
  });

  group('首访首屏门控（shouldShowLanding）', () {
    test('web ⇒ 展示试用介绍页（替代应用内引导）', () {
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
