// ─────────────────────────────────────────────────────────────
// app_version_consistency_test — 版本号单一真源守卫
//
// ★ 为什么需要这条（ADR-C74 教训：上一版发版时「关于页版本号」要人工同步，
//   0.4.1 那批就漏改过一处，靠人眼发现）：
//   pubspec.yaml 的 `version:` 与 settings_page.dart 的 `_appVersion`
//   是**同一个版本号的两个副本**，人工同步必然漂。⇒ 用测试钉住。
//
// ★ 为什么从 pubspec 读而不是硬编码期望值：
//   硬编码会变成「每次发版必须记得改的第三个地方」——正是要消灭的模式。
//   改为**从pubspec 解析** ⇒ 版本号只有pubspec 一个真源。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // pubspec 形如 `version: 0.5.0+2014`
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final m = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  final pubspecVersion = m?.group(1);
  final short = pubspecVersion?.split('+').first;

  test('pubspec 能解析出版本号（守卫自身的前提）', () {
    expect(
      pubspecVersion,
      isNotNull,
      reason: 'pubspec.yaml 缺 version: 行或格式变了⇒ 守卫失效',
    );
    expect(
      pubspecVersion,
      matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')),
      reason: '版本号格式应为 `X.Y.Z+build`，实际 `$pubspecVersion`',
    );
  });

  test('关于页显示的版本号与 pubspec 一致（防漂移）', () {
    final page = File(
      'lib/features/app_settings/settings_page.dart',
    ).readAsStringSync();
    final a = RegExp(r"_appVersion\s*=\s*'([^']+)'").firstMatch(page);
    expect(a, isNotNull, reason: 'settings_page.dart 里找不到 _appVersion 定义');
    expect(
      a!.group(1),
      short,
      reason:
          '关于页显示 ${a.group(1)} ≠ pubspec $short'
          ' ⇒ 人工同步漏了一处（上一版就发生过）',
    );
  });

  test('versionCode 递增不回退（本版 ≥ 2014）', () {
    final build = int.parse(pubspecVersion!.split('+').last);
    expect(
      build,
      greaterThanOrEqualTo(2014),
      reason: 'versionCode 必须 ≥ 2014（0.5.0+2014），回退会让 Android 拒装升级包',
    );
  });
}
