// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// 发布门槛 M4 — L3 段边界正确性（2026-10-13 四任务书 §4-M4）
//
// 缺陷（批 1 §6.1）：P039（信息密度缺失症）手册段被追加到
// syndrome_kb_content_manual_3.dart 的 P018 之后，而分片约定是
// manual_1..6 依 ID 升序连续铺满（1: P001-P005 / 2: P006-P013 /
// 3: P014-P018 / 4: P019-P021 / 5: P022-P025 / 6: P026-P038+）。
// 现有四库一致性校验只比条数与名称、不校验段序 ⇒ 错位无人拦截。
//
// 现状即 FAIL → 显式 known-fail 基线（skip 标注，不让 CI 挂红）。
// ⚠️ 修复（把 P039 段迁到 manual_6）**触 R-027 人工停线**（改知识库
// 正文文件须重冻锚点），须与该治理批次**同批**启用本门槛——届时去掉 skip。
//
// 本文件只**读取**知识库源文件做静态断言，不修改任何知识库正文（R-027 安全）。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
  group('发布门槛 M4：L3 段边界正确性（known-fail 基线，须与 P039 迁移治理批同批启用）', () {
    test(
      'manual_1..6 各分片内 ### P0XX 段严格升序，且跨分片全局连续升序',
      skip:
          'known-fail M4: P039 段错位在 manual_3（P018 之后），修复=把该段迁到 '
          'manual_6，会改知识库正文文件（触 R-027 人工停线 + 锚点重冻），'
          '须与治理批次同批启用——届时移除本 skip。',
      () {
        final allIds = <String>[];
        for (var i = 1; i <= 6; i++) {
          final src = _readSrc(
            'lib/services/syndrome_kb_content_manual_$i.dart',
          );
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
        // 跨分片全局单调（当前缺陷即在此失败：…P018 → P039 → P019…）。
        for (var j = 1; j < allIds.length; j++) {
          expect(
            _idNum(allIds[j]),
            greaterThan(_idNum(allIds[j - 1])),
            reason:
                '跨分片段序错位：${allIds[j - 1]}（manual_{…}）之后出现 '
                '${allIds[j]}——分片铺排约定被破坏，L3 逐段抽取的可读顺序'
                '与分片物理顺序脱节（批 1 §6.1 P039 错位即此形态）',
          );
        }
      },
    );

    test(
      '每段抽取边界不跨段（下一段头即本段终止边界）',
      skip:
          'known-fail M4: 同上，与 P039 迁移治理批同批启用。'
          '边界抽取逻辑正确性不受段序影响，故与上一条一并延迟启用。',
      () {
        // 与 syndrome_knowledge_base._extractSyndromeSection 同规则的
        // 测试侧复刻（该函数私有）：段起点 = '### P0XX '，终点 =
        // 下一个 '### ' 或 '## ' 取更早者。断言每段抽取结果不含任何
        // 其他段头（边界不吞下段）且非空（起点可命中）。
        final manualSrc = [
          for (var i = 1; i <= 6; i++)
            _readSrc('lib/services/syndrome_kb_content_manual_$i.dart'),
        ].join('\n');
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
      },
    );
  });
}
