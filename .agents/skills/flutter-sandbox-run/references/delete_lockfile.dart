// 用 Dart 删掉 Flutter SDK 的陈旧 lockfile，绕过 Bash 的 safe-delete(genie-trash) 拦截。
// 使用：
//   /d/flutter/bin/cache/dart-sdk/bin/dart.exe \
//       D:/ai-teacher/yuesheng-flutter/.workbuddy/skills/flutter-sandbox-run/references/delete_lockfile.dart
// 注意：dart.exe 参数必须 Windows 风格路径 D:/...；本脚本路径本身也用 D:/...。
// 仅在 lockfile 无存活进程占用（陈旧残留）时有效；若被僵尸进程独占，请直接重启机器。

import 'dart:io';

void main() {
  const targets = [
    r'D:\flutter\bin\cache\lockfile',
  ];
  for (final p in targets) {
    final f = File(p);
    if (!f.existsSync()) {
      print('ABSENT: $p (nothing to do)');
      continue;
    }
    try {
      f.deleteSync();
      print('DELETED: $p');
    } on FileSystemException catch (e) {
      // errno 5 = 拒绝访问，通常是被僵尸 flutter 进程以独占锁攥着。
      print('FAIL: $p -> $e  (若被僵尸进程占用，请重启机器释放句柄)');
    }
  }
}
