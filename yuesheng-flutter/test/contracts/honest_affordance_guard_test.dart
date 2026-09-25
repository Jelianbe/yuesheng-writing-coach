// ─────────────────────────────────────────────────────────────
// 诚实可供性护栏（交互批 P0-3 · 2026-09-19）
//
// 把 gen_ui_card.dart 文件头写着的哲学红线（「白名单外/占位类型：诚实渲染
// 『暂未支持』，**无假按钮**」）从**注释**升格为**可执行检测**。
// 侦察实证：「假入口」在本仓历史已人肉清理 3 轮（E3 / 批次38 / 批次77），
// 零门禁 ⇒ 本文件即那条缺失的执行点。
//
// 三条断言（缺一不可，防三种复发形态）：
//   ① 假按钮文案（敬请期待/即将上线/开发中）在 lib 全域注释外零命中
//      （2026-09-25 Batch 6 起扫描面从 lib/widgets 扩为 lib 全域：
//       features 领域分层迁移后 UI 主体已不在 widgets/，原范围看守面静默缩水）
//   ② 单行空回调（onTap/onPressed/onChanged: () {}）仅允许白名单那一条
//   ③ ★ 阳性对照：白名单项**必须真的被检出逻辑命中** ——
//      堵「扫描器正则静默失效 ⇒ ①② 以零命中假绿」（§4 系列教训：
//      「零发现 vs 没跑起来」外观相同；本仓 entry_matrix 曾因交替未分组
//      假命中 2618 处而自检全绿，同族反向）
//
// 已知边界（诚实声明，勿当全知）：只匹配**单行**形态；跨行回调体、
// 变量持有的 handler、多行拼接的文案不覆盖 —— 与侦察工具
// `.ai/tools/dead_affordance_scan.py` 同款局限，静态闸只做「不再变坏」。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _fakeLabel = RegExp(r'敬请期待|即将上线|开发中');
final RegExp _emptyCb = RegExp(
  r'(onTap|onPressed|onChanged)\s*:\s*\(\s*\w*\s*\)\s*\{\s*\}\s*,',
);

/// 唯一合法的空回调：点弹层卡片本体时防冒泡到遮罩取消（外层 :140 有正解）。
const String _emptyCbWhitelistFile = 'lib/widgets/ui_overlay_host.dart';

class _ScanResult {
  final List<String> fakeLabels;
  final List<String> emptyCbs;
  _ScanResult(this.fakeLabels, this.emptyCbs);
}

_ScanResult _scanWidgets() {
  final fake = <String>[];
  final empty = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File ||
        !entity.path.endsWith('.dart') ||
        entity.path.endsWith('.g.dart')) {
      continue;
    }
    final rel = entity.path.replaceAll(r'\', '/');
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final s = lines[i].trim();
      if (s.startsWith('//') || s.startsWith('/*') || s.startsWith('*')) {
        continue; // 注释行豁免（历史批次自陈如「移除开发中占位」必须可保留）
      }
      if (_fakeLabel.hasMatch(s)) fake.add('$rel:${i + 1}: $s');
      if (_emptyCb.hasMatch(s)) empty.add('$rel:${i + 1}: $s');
    }
  }
  return _ScanResult(fake, empty);
}

void main() {
  group('诚实可供性护栏（P0-3）', () {
    final scan = _scanWidgets();

    test('① 假按钮文案（敬请期待/即将上线/开发中）零命中', () {
      expect(
        scan.fakeLabels,
        isEmpty,
        reason:
            '按钮/入口文案承诺了不存在的功能 = 误导性可供性（批次79B 同族）。'
            '若确需诚实占位，走「暂未支持」+ 无按钮形态（gen_ui_card 红线）。',
      );
    });

    test('② 单行空回调仅白名单一条（防死按钮复发）', () {
      final unexpected = scan.emptyCbs
          .where((r) => !r.startsWith(_emptyCbWhitelistFile))
          .toList();
      expect(
        unexpected,
        isEmpty,
        reason:
            '新增 `onPressed/onTap: () {}` = 假按钮本体；'
            '白名单仅 ui_overlay_host 的防冒泡写法（有注释自证）。',
      );
    });

    test('③ ★ 阳性对照：检出逻辑必须真的命中白名单那条（堵检测器静默失效）', () {
      expect(
        scan.emptyCbs.any((r) => r.startsWith(_emptyCbWhitelistFile)),
        isTrue,
        reason:
            '连白名单已知正例都扫不到 ⇒ 是**检测器坏了**，不是代码干净；'
            '①② 的「零命中」在读作通过前必须先过这条。',
      );
    });
  });
}
