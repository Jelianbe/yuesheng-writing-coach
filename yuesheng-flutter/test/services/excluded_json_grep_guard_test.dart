// ─────────────────────────────────────────────────────────────
// excluded_json_grep_guard_test — ADR-0012 引用点守卫（机器闸）
//
// 防「教学注入面误读历史 excluded 进注入 prompt」：drift 列字段名 `excludedJson`
// 在 lib/ 全树**只允许出现在三处**：
//   ① lib/data/database/tables.dart               （列定义本体）
//   ② lib/data/database/database.g.dart           （build_runner 生成物，不手改）
//   ③ lib/data/repositories/diagnosis_repository.dart
//      （commitDiagnosis 写入 + _parseExcludedList/excludedOf 读回——唯一 sanctioned 消费点）
// 其余任何文件（重点：message_injector.dart:2235 读 listDiagnosisHistory 的注入装配面）
// 出现 excludedJson ⇒ 红（历史排除记录被读进教学注入 prompt 的第一道机器闸）。
//
// ★ 可红判据：在 lib/ 白名单外任一文件加一行含 `excludedJson` 的代码 ⇒ 本用例红。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory _findPackageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (Directory('${dir.path}/lib').existsSync() &&
        Directory('${dir.path}/test').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  throw StateError('找不到包根目录（cwd=${Directory.current.path}）');
}

/// 白名单：excludedJson 允许出现的 lib/ 文件（归一化正斜杠相对路径）。
const Set<String> _allowed = {
  'lib/data/database/tables.dart',
  'lib/data/database/database.g.dart',
  'lib/data/repositories/diagnosis_repository.dart',
};

void main() {
  test('excludedJson 引用点只在白名单三文件出现（防注入面误读）', () {
    final root = _findPackageRoot();
    final hits = <String>{};
    for (final entity in Directory(
      '${root.path}/lib',
    ).listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll(r'\', '/');
      final idx = normalized.indexOf('/lib/');
      final rel = normalized.substring(idx + 1);
      if (File(entity.path).readAsStringSync().contains('excludedJson')) {
        hits.add(rel);
      }
    }

    expect(
      hits,
      _allowed,
      reason:
          'excludedJson 被白名单外文件引用 ⇒ 疑似把历史排除记录读进'
          '教学注入面（message_injector 装配 prompt），红',
    );
  });
}
