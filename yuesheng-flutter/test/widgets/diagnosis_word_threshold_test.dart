// ─────────────────────────────────────────────────────────────
// 诊断字数门槛常量化护栏（ADR-C66 / 台账 N10）
//
// 背景：诊断字数门槛此前分裂为「常量 + 阈值硬编码 + 文案硬编码」三套真相，
//   详见 ADR-C66 §2.2。修复后**输出逐字不变**（常量插值与字面量等价），
//   因此运行时无法断言「文案里的数字来自常量」——只能以源码文本扫描
//   守住这条不变量。
//
// ⚠️ 锚定方式（2026 伪拆分清偿后）：
//   已从「硬编码文件路径」改为「**全 lib 语义自适应发现 + 引用总量守恒**」。
//   原因：本仓库正在把 part + extension 形态的超长文件真分解为独立类，
//   文件会被**搬迁、改名、拆分**；硬编码具体文件路径一旦被搬走，测试即炸
//   （假红）。现改为按语义（引用了任一门槛常量）自动发现文件集，并用
//   「全 lib 引用总数守恒」作为核心护栏——搬文件不改变引用总数，所以护栏抗
//   搬迁，但**门槛点新增/删除/改字面量**仍会被捕获。
//
// 三条断言：
//   ① 常量取值：门槛常量各自等于设计值（防手滑改值）
//   ② 引用正确：门槛常量全 lib 引用总数守恒 + 每个门槛文件至少引用 1 次
//      + 四处门槛文案仍为常量插值写法（防文案返祖为字面量）
//   ③ 无裸数字：自适应发现的门槛文件**非注释**代码中无「数字 + 字」字面量
//
// 变异验证（新护栏必须能失败）：
//   A 文案改回字面量 '请至少输入 100 字后再提交诊断'
//     → ② 插值断言失败 + ③ 裸数字断言失败（双重捕获）
//   B 阈值改回字面量（如 `text.length < 20`）
//     → ② 全 lib 引用总数断言失败（总数 6/4/2 掉 1）
//   C 改动任一常量取值（如 diagnosisWordThreshold 100 → 150）
//     → ① 取值断言失败
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';

/// 门槛常量清单（全 lib 引用扫描目标）。
const List<String> kThresholdConstants = [
  'UILimits.diagnosisWordThreshold',
  'UILimits.diagnosisSelectionWordThreshold',
  'UILimits.quickObservationWordThreshold',
];

/// 各门槛常量在全 lib 的**引用总数守恒基准**（阈值点 1 + 每处文案插值 1）。
///
/// ⚠️ 维护说明：**新增门槛点属正常演进**。若本值需要上调，请务必同步确认
/// **新点位走的是 UILimits 常量插值**（而非字面量硬编码），再更新此值。
/// 若本值**下调** → 有门槛点被删除、或阈值/文案被改回字面量（回归，必须排查）。
///
/// 基准（2026 负债清偿前实测）：
///   diagnosisWordThreshold          : chat_teaching(2) + diagnosis_picker_sheet(2)
///                                     + writing_coach_panel_teaching(2) = 6
///   diagnosisSelectionWordThreshold : writing_coach_panel_teaching(2)
///                                     + writing_page_selection_ai(2) = 4
///   quickObservationWordThreshold   : writing_coach_panel_teaching(2) = 2
const Map<String, int> kExpectedTotalRefs = {
  'UILimits.diagnosisWordThreshold': 6,
  'UILimits.diagnosisSelectionWordThreshold': 4,
  'UILimits.quickObservationWordThreshold': 2,
};

/// 自适应发现的「门槛文件」数量基准。
///
/// 数量变化说明门槛点新增/删除，需人工确认后同步此值（并核对 ② 的总量守恒）。
const int kExpectedThresholdFileCount = 4;

/// 必须存在的插值文案片段（全 lib 范围搜索，防文案脱钩返祖为字面量）。
const List<String> kRequiredSnippets = [
  r"'章节内容少于 ${UILimits.diagnosisWordThreshold} 字，请先编辑章节'",
  r"'请至少选择 ${UILimits.diagnosisSelectionWordThreshold} 字以上的文本进行诊断'",
  r"'请至少输入 ${UILimits.diagnosisWordThreshold} 字后再提交诊断'",
  r"'请至少写 ${UILimits.quickObservationWordThreshold} 字后再快速观察'",
];

/// 包根定位：从 cwd 向上回溯，直到同时存在 lib/ 与 test/。
///
/// 不依赖 Platform.script —— flutter test 下它未必指向源文件。
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

final Directory _root = _findPackageRoot();

String _readSrc(String relPath) {
  final f = File('${_root.path}/$relPath');
  if (!f.existsSync()) {
    throw StateError('源文件不存在：$relPath（root=${_root.path}）');
  }
  return f.readAsStringSync();
}

/// lib/ 下全部 .dart 的相对路径（正斜杠、排序稳定），**排除生成文件**
/// （`*.g.dart` / `*.freezed.dart`）。
List<String> _listLibDartFiles() {
  final libDir = Directory('${_root.path}/lib');
  return libDir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.dart'))
      .where((p) => !p.endsWith('.g.dart') && !p.endsWith('.freezed.dart'))
      .map((p) => p.substring(_root.path.length + 1).replaceAll('\\', '/'))
      .toList()
    ..sort();
}

/// 自适应发现：引用了**任一门槛常量**的文件（相对路径，排序稳定）。
///
/// 这是「抗文件搬迁」的关键——不再硬编码具体文件路径，而是按语义发现。
List<String> _discoverThresholdFiles() =>
    _listLibDartFiles()
        .where(
          (rel) => kThresholdConstants.any((c) => _readSrc(rel).contains(c)),
        )
        .toList()
      ..sort();

/// 只扫描一次（顶层 final 惰性初始化），避免多次全 lib 读盘。
final List<String> _thresholdFiles = _discoverThresholdFiles();

/// 去掉整行注释后的正文。
///
/// 裸数字检测只针对实际代码——文件头 / 行内注释里写「≥20 字」「>4000 字」
/// 是正常的说明文字，不算缺陷。
String _stripLineComments(String src) => src
    .split('\n')
    .where((line) {
      final t = line.trimLeft();
      return !(t.startsWith('//') || t.startsWith('*') || t.startsWith('/*'));
    })
    .join('\n');

void main() {
  group('① 常量取值（ADR-C66 §3.1）', () {
    test('诊断门槛两档取值不变', () {
      expect(UILimits.diagnosisWordThreshold, 100);
      expect(UILimits.diagnosisSelectionWordThreshold, 20);
    });

    test('顺带纳入的两个门槛取值不变（ADR-C66 新发现-a）', () {
      expect(UILimits.quickObservationWordThreshold, 50);
    });
  });

  group('② 各门槛点阈值与文案均取自常量（全 lib 自适应发现）', () {
    test('门槛常量全 lib 引用总数守恒', () {
      final all = _thresholdFiles.map(_readSrc).join('\n');
      for (final entry in kExpectedTotalRefs.entries) {
        final actual = entry.key.allMatches(all).length;
        expect(
          actual,
          entry.value,
          reason:
              '全 lib 中 ${entry.key} 出现 $actual 次，期望 ${entry.value} 次。\n'
              '变多 → 有新增门槛点：请确认新点位引用 UILimits 常量（勿字面写死），'
              '并同步更新 kExpectedTotalRefs。\n'
              '变少 → 有门槛点被删除、或阈值/文案被改回字面量（回归，必须排查）。',
        );
      }
    });

    test('自适应发现的每个门槛文件至少引用 1 次门槛常量', () {
      expect(_thresholdFiles, isNotEmpty, reason: '未发现任何引用门槛常量的文件');
      for (final rel in _thresholdFiles) {
        final src = _readSrc(rel);
        final total = kThresholdConstants
            .map((c) => c.allMatches(src).length)
            .fold<int>(0, (acc, n) => acc + n);
        expect(
          total,
          greaterThanOrEqualTo(1),
          reason: '$rel 未引用任何门槛常量（自适应发现逻辑或源码异常）',
        );
      }
    });

    test('四处门槛文案仍为常量插值写法（全 lib 范围）', () {
      final all = _thresholdFiles.map(_readSrc).join('\n');
      for (final snippet in kRequiredSnippets) {
        expect(
          all.contains(snippet),
          isTrue,
          reason:
              '全 lib 缺少插值文案：$snippet\n'
              '（ADR-C66：提示文案中的数字须与阈值同源，不得字面写死）',
        );
      }
    });
  });

  group('③ 自适应发现的门槛文件：非注释代码中无裸数字门槛', () {
    // 「数字 + 可选空格 + 字」，且前面不是标识符 / $ / } —— 后者是插值写法
    // （如 `${UILimits.diagnosisWordThreshold} 字`），属合规。
    final bareDigit = RegExp(r'(?<![\w$}])\d+\s*字');

    test('每个门槛文件的非注释代码无「数字 + 字」字面量', () {
      for (final rel in _thresholdFiles) {
        final code = _stripLineComments(_readSrc(rel));
        final hits = bareDigit
            .allMatches(code)
            .map((m) => code.substring(m.start, m.end).trim())
            .toList();
        expect(
          hits,
          isEmpty,
          reason:
              '$rel 存在硬编码字数门槛：${hits.join(' / ')}\n'
              '（ADR-C66：应改为 UILimits 常量插值）',
        );
      }
    });
  });

  group('④ 护栏自检（确保自适应扫描真的命中了目标）', () {
    test('自适应发现的文件数 == $kExpectedThresholdFileCount', () {
      expect(
        _thresholdFiles.length,
        kExpectedThresholdFileCount,
        reason:
            '自适应发现 ${_thresholdFiles.length} 个门槛文件（期望 $kExpectedThresholdFileCount）：\n'
            '${_thresholdFiles.join('\n')}\n'
            '（数量变化说明门槛点新增/删除，需人工确认后同步基准，勿硬编码凑数）',
      );
    });

    test('裸数字正则能命中字面量、且不误伤插值写法', () {
      final bareDigit = RegExp(r'(?<![\w$}])\d+\s*字');
      // 变异 A 回归：字面量必须被捕获
      expect(bareDigit.hasMatch("'请至少输入 100 字后再提交诊断'"), isTrue);
      // 插值写法不得被误伤
      expect(
        bareDigit.hasMatch(
          "'请至少输入 \${UILimits.diagnosisWordThreshold} 字后再提交诊断'",
        ),
        isFalse,
      );
    });

    test('出现次数判据自身有效（变异 B 回归）', () {
      // 模拟「阈值写死 + 文案仍插值」的源码：计数应低于 2
      final mutated =
          "if (text.length < 20) {}\n"
          "Text('请至少选择 \${UILimits.diagnosisSelectionWordThreshold} 字以上')";
      expect(
        'UILimits.diagnosisSelectionWordThreshold'.allMatches(mutated).length,
        1,
      );
      // 正规则样本：阈值 + 文案各 1 次
      final correct =
          "if (text.length < UILimits.diagnosisSelectionWordThreshold) {}\n"
          "Text('请至少选择 \${UILimits.diagnosisSelectionWordThreshold} 字以上')";
      expect(
        'UILimits.diagnosisSelectionWordThreshold'.allMatches(correct).length,
        2,
      );
    });
  });
}
