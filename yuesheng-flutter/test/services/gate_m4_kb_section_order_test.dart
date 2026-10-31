// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// 发布门槛 M4 — L3 段边界正确性（2026-10-13 四任务书 §4-M4）
//
// 缺陷（批 1 §6.1）：P039（信息密度缺失症）手册段被追加到
// syndrome_kb_content_manual_3.dart 的 P018 之后，而分片约定是
// manual_1..6 依 ID 升序连续铺满（1: P001-P005 / 2: P006-P013 /
// 3: P014-P018 / 4: P019-P021 / 5: P022-P025 / 6: P026-P039）。
// 现有四库一致性校验只比条数与名称、不校验段序 ⇒ 错位无人拦截。
//
// 2026-10-14 舰长批准 R-027 修复（D-4 治理批）：P039 段已逐字节
// 迁至 manual_6 的 P038 之后，本门槛**已转绿**（known-fail skip 解除）。
// 迁移自检：EOL 归一后 6 分片拼接总字节不变 + P039 块字节恒等。
//
// 本文件只**读取**知识库源文件做静态断言，不修改任何知识库正文（R-027 安全）。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';

/// 包根定位：从 cwd 向上回溯，直到同时存在 lib/ 与 test/
/// （同 progressive_chunk_syndrome_coverage_test 的口径）。
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

/// 提取一个分片文件内 `### P0XX` 段头出现顺序（保持出现序、不去重）。
List<String> _sectionIds(String src) =>
    RegExp(r'### (P\d{3})').allMatches(src).map((m) => m.group(1)!).toList();

int _idNum(String id) => int.parse(id.substring(1));

void main() {
  group('发布门槛 M4：L3 段边界正确性（2026-10-14 舰长批准 R-027 修复，已转绿）', () {
    test('manual_1..6 各分片内 ### P0XX 段严格升序，且跨分片全局连续升序', () {
      final allIds = <String>[];
      for (var i = 1; i <= 6; i++) {
        final src = _readSrc('lib/services/syndrome_kb_content_manual_$i.dart');
        final ids = _sectionIds(src);
        expect(
          ids,
          isNotEmpty,
          reason: 'manual_$i 不含任何 ### P0XX 段头（分片被清空/改名？）',
        );
        // 分片内单调。
        for (var j = 1; j < ids.length; j++) {
          expect(
            _idNum(ids[j]),
            greaterThan(_idNum(ids[j - 1])),
            reason:
                'manual_$i 段序回跳：${ids[j - 1]} → ${ids[j]}'
                '（分片内应按 ID 升序排列）',
          );
        }
        allIds.addAll(ids);
      }
      // 跨分片全局单调（修复前此处失败：…P018 → P039 → P019…）。
      for (var j = 1; j < allIds.length; j++) {
        expect(
          _idNum(allIds[j]),
          greaterThan(_idNum(allIds[j - 1])),
          reason:
              '跨分片段序错位：${allIds[j - 1]} 之后出现 ${allIds[j]}——'
              '分片铺排约定被破坏，L3 逐段抽取的可读顺序与分片物理顺序脱节'
              '（批 1 §6.1 P039 错位即此形态）',
        );
      }
    });

    test('每段抽取边界不跨段（下一段头即本段终止边界）', () {
      // 与 syndrome_knowledge_base._extractSyndromeSection 同规则的
      // 测试侧复刻（该函数私有），作用在**运行时真源** kSyndromeManualContent
      // （生产检索 getSyndromeContent 的输入串）上——不扫源文件，
      // 源文件拼串会混入 Dart 语法与注释造成假阳性。
      // 规则：段起点 = '### P0XX '，终点 = 下一个 '### ' 或 '## ' 取更早者。
      // 断言每段抽取结果不含任何其他段头（边界不吞下段）且非空。
      final manualSrc = kSyndromeManualContent;
      final ids = _sectionIds(manualSrc).toSet();
      for (final id in ids) {
        final start = manualSrc.indexOf('### $id ');
        expect(start, greaterThanOrEqualTo(0), reason: '$id 段头缺失');
        final nextH3 = manualSrc.indexOf('\n### ', start + 1);
        final nextH2 = manualSrc.indexOf('\n## ', start + 1);
        var end = manualSrc.length;
        if (nextH3 != -1) end = nextH3;
        if (nextH2 != -1 && nextH2 < end) end = nextH2;
        final section = manualSrc.substring(start, end);
        expect(section, isNotEmpty, reason: '$id 段抽取为空');
        for (final other in ids) {
          if (other == id) continue;
          expect(
            section.contains('### $other '),
            isFalse,
            reason: '$id 段抽取结果吞并了 $other 段头（抽取边界跨段）',
          );
        }
      }
    });
  });

  group('M4 配套正向抽取测试（D-4 修复的注入面验证，走生产检索函数）', () {
    // 抽取真源 = syndrome_knowledge_base.getSyndromeContent（生产 L3 注入
    // 同函数）。修复前缺陷形态：P018 抽取丢锚点示例（manual_4 头的孤立段）；
    // P039 抽取吞入 P018 锚点（跨 body3→body4 边界串味）。
    test('getSyndromeContent([P018])：包含 P018 判据与锚点示例，不含 P039 判据', () {
      final s = getSyndromeContent(const ['P018']);
      expect(s, isNotEmpty, reason: 'P018 抽取为空');
      // P018 判据在场。
      expect(s.contains('### P018 重复用词/基础语病'), isTrue);
      expect(s.contains('与 P034 的划界'), isTrue, reason: 'P018 判据正文缺失');
      // 锚点示例已随 P039 迁出自然归属（manual_4 头孤立段回到 P018 抽取内）。
      expect(
        s.contains('**✅ L2 命中（重复用词）**'),
        isTrue,
        reason: 'P018 抽取仍丢失锚点示例——P018→P019 之间被头阻断或示例段被移走',
      );
      expect(s.contains('连续三句以"忽然"起头'), isTrue);
      // 不串味：不含 P039 判据（修复前 P018 抽取止于 P039 段头，不含其正文；
      // 此断言防未来反方向回退）。
      expect(s.contains('### P039'), isFalse);
      expect(s.contains('信息增量链'), isFalse, reason: 'P018 抽取吞入了 P039 判据');
    });

    test('getSyndromeContent([P039])：包含 P039 判据与锚点示例，不含 P018 锚点', () {
      final s = getSyndromeContent(const ['P039']);
      expect(s, isNotEmpty, reason: 'P039 抽取为空');
      // P039 判据在场。
      expect(s.contains('### P039 信息密度缺失'), isTrue);
      expect(s.contains('信息增量链'), isTrue, reason: 'P039 判据正文缺失');
      expect(s.contains('**✅ L2 命中（整段无信息增量）**'), isTrue);
      // 不串味：不含 P018 的锚点示例（修复前 P039 抽取吞入 manual_4 头的
      // P018 孤立示例段 ⇒ 注入面把「重复用词」锚点塞进「信息密度」词条）。
      expect(
        s.contains('**✅ L2 命中（重复用词）**'),
        isFalse,
        reason: 'P039 抽取吞入了 P018 锚点示例（D-1 缺陷形态复发）',
      );
      expect(s.contains('连续三句以"忽然"起头'), isFalse);
      expect(s.contains('### P018'), isFalse);
    });
  });
}
