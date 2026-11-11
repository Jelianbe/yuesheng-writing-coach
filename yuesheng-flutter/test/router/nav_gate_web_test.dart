// NAV-1 门控（浏览器侧）—— 只在 web 平台跑。
//
// 【这条用例补的是 VM 测试补不了的那一格】VM 版用 `isWeb:` 覆写证明「映射对」，
// 但证明不了**真实运行时 `kIsWeb` 确实是 true**。本用例在浏览器里读真的
// `kIsWeb`，并用**生产签名**（不传参）断言门控为 false —— 这正是设计稿要的
// 运行时判据，且不需要启动 App（无 DB / 无网络依赖）。
//
// 运行：`CHROME_EXECUTABLE=<Edge 路径> flutter test --platform chrome test/router/nav_gate_web_test.dart`
@TestOn('browser')
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/router/nav_gate.dart';

void main() {
  test('真实 web 运行时：kIsWeb=true 且生产门控为 false', () {
    expect(
      kIsWeb,
      isTrue,
      reason: '本文件只应在浏览器平台执行；kIsWeb=false 说明跑错平台（不是被测代码的问题）',
    );
    expect(shouldRenderBottomNav(), isFalse);
  });
}
