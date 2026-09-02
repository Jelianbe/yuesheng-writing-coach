// ─────────────────────────────────────────────────────────────
// 诊断字数门槛常量化护栏（ADR-C66 / 台账 N10）
//
// 背景：诊断字数门槛此前分裂为「常量 + 阈值硬编码 + 文案硬编码」三套真相，
//   详见 ADR-C66 §2.2。修复后**输出逐字不变**（常量插值与字面量等价），
//   因此运行时无法断言「文案里的数字来自常量」——只能以源码文本扫描
//   守住这条不变量。
//
// 三条断言：
//   ① 常量取值：五个门槛常量各自等于设计值（防手滑改值）
//   ② 引用正确：每个门槛点的阈值与文案都引用 UILimits 常量、且是插值写法
//   ③ 无裸数字：上述文件的**非注释**代码中不再出现「数字 + 字」字面量
//
// 变异验证（新护栏必须能失败）：
//   A 文案改回字面量 '请至少输入 100 字后再提交诊断'
//     → ② 插值断言失败 + ③ 裸数字断言失败（双重捕获）
//   B 阈值改回字面量（如 `text.length < 20`）
//     → ② 常量引用断言失败
//   C 改动任一常量取值（如 diagnosisWordThreshold 100 → 150）
//     → ① 取值断言失败
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';

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

/// 单个门槛文件的护栏规格。
class _Gate {
  const _Gate(
    this.relPath, {
    required this.occurrences,
    required this.snippets,
  });

  final String relPath;

  /// 常量名 → 期望出现次数。
  ///
  /// 计法：**阈值处 1 次 + 每处文案插值 1 次**。
  /// 只断言「出现过」不够——变异 B（阈值改回字面量、文案仍插值）会让文件
  /// 名义上仍含该常量名而蒙混过关，实测已验证（详见文件头「变异验证」）。
  final Map<String, int> occurrences;

  /// 必须出现的插值文案片段（防文案脱钩）。
  final List<String> snippets;
}

/// 门槛点护栏表（ADR-C66 §2.2 四处 + 顺带纳入的两处）。
const List<_Gate> kThresholdGates = [
  // ── 诊断门槛（N10 主体）：两处整章 + 两处选段 ──
  _Gate(
    'lib/widgets/chat_teaching.dart',
    occurrences: {'UILimits.diagnosisWordThreshold': 2}, // 阈值 + 文案
    snippets: [r"'章节内容少于 ${UILimits.diagnosisWordThreshold} 字，请先编辑章节'"],
  ),
  _Gate(
    'lib/widgets/diagnosis_picker_sheet.dart',
    occurrences: {'UILimits.diagnosisWordThreshold': 2},
    snippets: [r"'章节内容少于 ${UILimits.diagnosisWordThreshold} 字，请先编辑章节'"],
  ),
  _Gate(
    'lib/widgets/writing_coach_panel_teaching.dart',
    occurrences: {
      // minLength 两档各 1 次 + 对应文案各 1 次
      'UILimits.diagnosisSelectionWordThreshold': 2,
      'UILimits.diagnosisWordThreshold': 2,
      // 快速观察：阈值 + 文案
      'UILimits.quickObservationWordThreshold': 2,
    },
    snippets: [
      r"'请至少选择 ${UILimits.diagnosisSelectionWordThreshold} 字以上的文本进行诊断'",
      r"'请至少输入 ${UILimits.diagnosisWordThreshold} 字后再提交诊断'",
      r"'请至少写 ${UILimits.quickObservationWordThreshold} 字后再快速观察'",
    ],
  ),
  _Gate(
    'lib/widgets/writing_page_selection_ai.dart',
    occurrences: {
      'UILimits.diagnosisSelectionWordThreshold': 2, // 阈值 + 文案
      'UILimits.selectionAiWordThreshold': 2,
    },
    snippets: [
      r"'请至少选择 ${UILimits.diagnosisSelectionWordThreshold} 字以上的文本进行诊断'",
      r"'请至少选择 ${UILimits.selectionAiWordThreshold} 字以上的文本'",
    ],
  ),
];

void main() {
  group('① 常量取值（ADR-C66 §3.1）', () {
    test('诊断门槛两档取值不变', () {
      expect(UILimits.diagnosisWordThreshold, 100);
      expect(UILimits.diagnosisSelectionWordThreshold, 20);
    });

    test('顺带纳入的两个门槛取值不变（ADR-C66 新发现-a）', () {
      expect(UILimits.quickObservationWordThreshold, 50);
      expect(UILimits.selectionAiWordThreshold, 10);
    });
  });

  group('② 各门槛点阈值与文案均取自常量', () {
    for (final gate in kThresholdGates) {
      test(gate.relPath, () {
        final src = _readSrc(gate.relPath);

        // ②-a 出现次数：阈值处 1 次 + 每处文案插值 1 次。
        // 只判「含不含」会让「阈值写死、文案仍插值」蒙混过关（变异 B）。
        for (final entry in gate.occurrences.entries) {
          final actual = entry.key.allMatches(src).length;
          expect(
            actual,
            entry.value,
            reason:
                '${gate.relPath} 中 ${entry.key} 出现 $actual 次，'
                '期望 ${entry.value} 次（阈值 1 + 每处文案 1）\n'
                '（ADR-C66：门槛数字必须来自 UILimits 常量，不得字面写死）',
          );
        }

        // ②-b 文案必须是插值写法，而非字面量数字
        for (final snippet in gate.snippets) {
          expect(
            src.contains(snippet),
            isTrue,
            reason:
                '${gate.relPath} 缺少插值文案：$snippet\n'
                '（ADR-C66：提示文案中的数字须与阈值同源）',
          );
        }
      });
    }
  });

  group('③ 非注释代码中无裸数字门槛', () {
    // 「数字 + 可选空格 + 字」，且前面不是标识符 / $ / } —— 后者是插值写法
    // （如 `${UILimits.diagnosisWordThreshold} 字`），属合规。
    final bareDigit = RegExp(r'(?<![\w$}])\d+\s*字');

    for (final gate in kThresholdGates) {
      test(gate.relPath, () {
        final code = _stripLineComments(_readSrc(gate.relPath));
        final hits = bareDigit
            .allMatches(code)
            .map((m) => code.substring(m.start, m.end).trim())
            .toList();
        expect(
          hits,
          isEmpty,
          reason:
              '${gate.relPath} 存在硬编码字数门槛：${hits.join(' / ')}\n'
              '（ADR-C66：应改为 UILimits 常量插值）',
        );
      });
    }
  });

  group('④ 护栏自检（锚点：确保扫描真的命中了目标文件）', () {
    test('四个门槛文件均可读且非空', () {
      for (final gate in kThresholdGates) {
        expect(
          _readSrc(gate.relPath).length,
          greaterThan(100),
          reason: '${gate.relPath} 读取异常（空或过短），扫描可能失效',
        );
      }
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
