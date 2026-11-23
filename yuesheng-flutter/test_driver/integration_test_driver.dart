// ─────────────────────────────────────────────────────────────
// integration_test_driver — 只为取回真机截图 PNG
//
// 为什么需要它
// ------------
// `IntegrationTestWidgetsFlutterBinding.takeScreenshot()` 在 `flutter test -d`
// 直跑模式下**取不回 PNG**（本批实测报错：
// `Bad state: Call convertFlutterSurfaceToImage() before taking a screenshot`，
// 补上那一步之后仍需 driver 才有回传通道）。
// 只有 `flutter drive --driver=... --target=...` 才会把 PNG 写到主机。
//
// 用途仅一个：`T-20261119-01` 的 `closes` 第 1 要件要求「真机走查截图」。
// 图落盘到 `outputs/screenshots/`，**不进版本库**（该目录已被忽略）。
//
// 用法
// ----
//   flutter drive \
//     --driver=test_driver/integration_test_driver.dart \
//     --target=integration_test/syn_practice_screenshot_test.dart \
//     -d emulator-5554
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final outDir = Directory('outputs/screenshots');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          final file = File('${outDir.path}/$name.png');
          file.writeAsBytesSync(bytes);
          // ignore: avoid_print
          print('DRIVER-saved=${file.path} bytes=${bytes.length}');
          return true;
        },
  );
}
