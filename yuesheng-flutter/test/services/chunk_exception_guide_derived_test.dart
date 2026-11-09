// ─────────────────────────────────────────────────────────────
// B4 派生牙测（T-20261109-02 · 舰长「按推荐走」裁甲 B / 乙 Δ=0）。
//
// 报批稿 §四 判据 5：`derivedGuide == 运行时切片 chunkExceptionGuideBlock`。
//
// ★ 自证失效防线（PRACTICES A3c ①）：装配产物本身也由表派生，
//   「派生 vs 切片」是**同源判据** ⇒ 单独用会恒真（改表两边同步平移）。
//   故本文件把它定位为**接线牙**（防「表建了但装配没接上」），
//   另配三条不同源的牙：
//     ① 冻结 fnv 钉值（prompt_const_anchor_test.dart，独立第三方真源，Δ=0 主牙）
//     ② 表注入变异牙：证明派生函数真读传入表，不是读别处/硬编码
//     ③ 静态单源牙：扫源码，防手写第二真源复活
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chunk_exception_guide_data.dart';
import 'package:writingcoach/services/chunk_prompt.dart';

/// 独立的运行时切片口径：不复用锚点测试的 kGuide*Marker，
/// 改用「标题行 → 输出格式段起始」定位，避免两处切片同源。
String _sliceGuideFromPrompt(String prompt) {
  final start = prompt.indexOf(kChunkExceptionGuideLines.first);
  expect(start, greaterThanOrEqualTo(0), reason: '例外表标题行未进装配产物 ⇒ 真源表没接上');
  final end = prompt.indexOf('请输出JSON格式的笔记', start);
  expect(end, greaterThan(start), reason: '输出格式段定位失效');
  final raw = prompt.substring(start, end);
  expect(raw.endsWith('\n\n'), isTrue, reason: '例外表与输出格式段之间的空行分隔符变了');
  return raw.substring(0, raw.length - 2);
}

void main() {
  group('判据 5：派生文本 == 运行时切片（接线牙）', () {
    test('buildChunkExceptionGuide() 与 kChunkSystemPrompt 内注入的例外表逐字相同', () {
      final sliced = _sliceGuideFromPrompt(kChunkSystemPrompt);
      expect(
        buildChunkExceptionGuide(),
        sliced,
        reason: '派生文本与运行时注入切片不一致 ⇒ 装配面仍在用另一份文本',
      );
    });

    test('切片非空且形态完整（标题 + 末条兜底）', () {
      final sliced = _sliceGuideFromPrompt(kChunkSystemPrompt);
      expect(sliced.startsWith(kChunkExceptionGuideLines.first), isTrue);
      expect(sliced.endsWith(kChunkExceptionGuideLines.last), isTrue);
      expect(sliced.split('\n').length, 33);
    });
  });

  group('表注入变异牙（A3c ① · 负向变异只落单侧）', () {
    test('派生函数确实读传入表：注入变异表 ⇒ 输出跟随变', () {
      expect(
        buildChunkExceptionGuide(const <String>['探针行A', '探针行B']),
        '''探针行A
探针行B''',
        reason: '若函数体被改回硬编码常量/读别处，本例必红',
      );
    });

    test('生产默认路径 = 表按换行符拼接，末尾不带换行', () {
      final derived = buildChunkExceptionGuide();
      expect(derived, kChunkExceptionGuideLines.join('\n'));
      expect(derived.endsWith('\n'), isFalse);
    });
  });

  group('表结构牙（meta 30/30/33 口径）', () {
    test('33 行：首行标题 + 31 个 -P 行（30 例外 + P034 判界）+ 末条兜底', () {
      final rows = kChunkExceptionGuideLines;
      expect(rows.length, 33);
      expect(rows.first, '例外情况指引（以下场景通常不应判定为症候）：');
      expect(rows.where((l) => l.startsWith('- P')).length, 31);
      expect(rows.where((l) => RegExp(r'^- P\d{3}例外').hasMatch(l)).length, 30);
      expect(rows.last.contains('上面未列出的症候'), isTrue);
    });

    test('P034 判界在表内；P031例外 全表缺席', () {
      final joined = kChunkExceptionGuideLines.join('\n');
      expect(joined.contains('P034判界'), isTrue);
      expect(joined.contains('P031例外'), isFalse, reason: 'P031 例外已裁撤，不得借派生批复活');
    });
  });

  group('静态单源牙（防手写第二真源复活）', () {
    test('chunk_prompt.dart 不再持有任何例外逐字行 / 三引号手写块', () {
      final src = File('lib/services/chunk_prompt.dart').readAsStringSync();
      for (final banned in <String>[
        "const String _kChunkExceptionGuide = '''",
        '- P001例外',
        '- 上面未列出的症候',
      ]) {
        expect(
          src.contains(banned),
          isFalse,
          reason: 'chunk_prompt.dart 又出现手写例外文本：$banned',
        );
      }
      expect(
        src.contains('buildChunkExceptionGuide()'),
        isTrue,
        reason: '装配面必须引用派生函数',
      );
      expect(
        src.contains(r'$_kChunkExceptionGuide'),
        isTrue,
        reason: '装配模板插值点须保留（模板零改动）',
      );
    });

    test('真源表每条 - Pxxx例外 字面恰好一次；两文件合计只此一份', () {
      final table = File(
        'lib/services/chunk_exception_guide_data.dart',
      ).readAsStringSync();
      final prompt = File('lib/services/chunk_prompt.dart').readAsStringSync();
      final re = RegExp(r"^\s*'- P\d{3}例外", multiLine: true);
      expect(re.allMatches(table).length, 30);
      expect(re.allMatches(prompt).length, 0);
      expect(
        table.contains("const List<String> kChunkExceptionGuideLines"),
        isTrue,
      );
    });
  });
}
