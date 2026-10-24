// ─────────────────────────────────────────────────────────────
// B3a 护栏（T-20261025-02 / DECISIONS §4-263）
//
// 目的：给 B3a 的三处 prompt 文本改动各钉一条**能变红**的回归断言，
// 防后续批次把「可判形态」改回「意图自证」，或把协议外字段写回 prompt。
//
// 三处受护改动（施工报告 .ai/reports/2026-10-25-B3a施工.md）：
//   ① skills_diagnosis_p3.dart:69  P017 撤销条件 → 三问可判（替换，非追加）
//   ② skills_diagnosis_p3.dart:71  P016 刻意省略条款（表末新增行）
//   ③ syndrome_kb_content.dart:72  诊断输出规范第 7 条续行「理由不得复用症候名」
//   ④ syndrome_kb_content_manual_3.dart:123  删除与上一行逐字重复的一行
//
// ★ 判据形态：每条判据都写成**纯函数** `_guardXxx(String src)`，
//   既对真实源文件跑，也在内存内对**变异串**跑（必须抛）。
//   ⇒ 「断言恒绿」这类失效在这里当场可见（每个 guard 都有一条反向用例）。
//   ⇒ 判据读的是文件全文，不做行号断言（行号会漂移，见 §4-263② 的教训）。
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

final Directory _root = _findPackageRoot();

String _readSrc(String relPath) {
  final f = File('${_root.path}/$relPath');
  if (!f.existsSync()) {
    throw StateError('源文件不存在：$relPath（root=${_root.path}）');
  }
  return f.readAsStringSync();
}

/// 三个受护源文件（均为 prompt 常量宿主，不含业务逻辑）。
const String kP3Host = 'lib/services/skills_diagnosis_p3.dart';
const String kIndexHost = 'lib/services/syndrome_kb_content.dart';
const String kManual3Host = 'lib/services/syndrome_kb_content_manual_3.dart';

// ───────────────────────── 纯判据 ─────────────────────────

/// 取「以 `|` 开头的表格行」中**唯一**命中 [marker] 的那一行。
/// 命中 0 条或多条一律抛：0 = 行被删，多条 = 复制漂移。
String _tableRow(String src, String marker) {
  final hits = src
      .split('\n')
      .where((l) => l.trimLeft().startsWith('|') && l.contains(marker))
      .toList();
  if (hits.length != 1) {
    throw StateError('表格行 marker="$marker" 命中 ${hits.length} 条（应恰好 1）');
  }
  return hits.single;
}

/// 把**唯一**命中 [marker] 的表格行整行替换成 [newRow]（用于构造变异串）。
String _replaceRow(String src, String marker, String newRow) {
  final lines = src.split('\n');
  var n = 0;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimLeft().startsWith('|') && lines[i].contains(marker)) {
      lines[i] = newRow;
      n++;
    }
  }
  if (n != 1) {
    throw StateError('替换目标 marker="$marker" 命中 $n 条（应恰好 1）');
  }
  return lines.join('\n');
}

/// 删掉**唯一**命中 [marker] 的表格行（用于构造「P016 行被删」的变异串）。
String _removeRow(String src, String marker) {
  final lines = src.split('\n');
  final kept = <String>[];
  var n = 0;
  for (final l in lines) {
    if (l.trimLeft().startsWith('|') && l.contains(marker)) {
      n++;
      continue;
    }
    kept.add(l);
  }
  if (n != 1) {
    throw StateError('删除目标 marker="$marker" 命中 $n 条（应恰好 1）');
  }
  return kept.join('\n');
}

/// ① P017：三问可判要素齐备、旧「意图自证」串与协议外字段零残留。
void _guardP017(String src) {
  final row = _tableRow(src, 'P017 跳跃叙事');
  const required = <String>[
    '200 字内', // 问一：可指认的窗口
    '回指', // 问二：后文回收
    '≥2 次', // 问三：同型计数
    '三问全过才不报', // 撤销通道的边界条件（缺它 ⇒ 三问无出口）
  ];
  for (final n in required) {
    if (!row.contains(n)) {
      throw StateError('P017 行缺可判要素「$n」——撤销通道退回不可判形态');
    }
  }
  const forbidden = <String>[
    '跳跃是否有设计', // 旧串（意图自证）
    '标 pending', // 协议外字段（短链无此字段 ⇒ 制造漏报）
    '输出 uncertain', // 同上
  ];
  for (final b in forbidden) {
    if (row.contains(b)) {
      throw StateError('P017 行含旧串/协议外字段「$b」');
    }
  }
}

/// ② P016：新增的刻意省略条款在位，且带「时空锚」判定条件、不带「症」后缀。
void _guardP016(String src) {
  final row = _tableRow(src, 'P016 过渡生硬');
  const required = <String>['时空锚', '三样皆无', '不得判 P016'];
  for (final n in required) {
    if (!row.contains(n)) {
      throw StateError('P016 行缺可判要素「$n」——刻意省略无法与过渡生硬分离');
    }
  }
  if (row.contains('症')) {
    throw StateError('P016 行含「症」后缀——违反 T-20261024-07 去症口径');
  }
}

/// ③ 输出规范：P⑤「理由不得复用症候名」在位、且晚于第 7 条；
/// 全文件不得出现 `pending` / `uncertain`（短链 [YS_DIAGNOSIS] 协议无此字段）。
void _guardOutputSpec(String src) {
  const marker = '不得复用症候名';
  final iMarker = src.indexOf(marker);
  if (iMarker < 0) {
    throw StateError('输出规范缺「$marker」——理由可复用症候名 ⇒ 只认形态未认代价');
  }
  final iRule7 = src.indexOf('说明判断理由');
  if (iRule7 < 0) {
    throw StateError('找不到第 7 条「说明判断理由」——条号基线变了，须复核本护栏');
  }
  if (iMarker < iRule7) {
    throw StateError('「$marker」位于第 7 条之前——它会脱离「说明判断理由」而失去作用域');
  }
  for (final field in ['pending', 'uncertain']) {
    if (src.contains(field)) {
      throw StateError(
        '输出规范宿主出现「$field」——该字段不在短链协议内，'
        '模型被要求输出不存在的字段时会「先别报」⇒ 制造漏报。'
        '若协议真的要加，须先改协议并同步本护栏（R-025/R-026）',
      );
    }
  }
}

/// ④ 手册：不得存在**逐字相邻重复行**（空行与纯空白行不计）。
void _guardNoAdjacentDuplicate(String src, {String label = 'src'}) {
  final lines = src.split('\n');
  for (var i = 1; i < lines.length; i++) {
    final prev = lines[i - 1].trim();
    final cur = lines[i].trim();
    if (prev.isNotEmpty && prev == cur) {
      throw StateError(
        '$label 第 ${i + 1} 行与上一行逐字重复（${cur.substring(0, cur.length > 30 ? 30 : cur.length)}…）',
      );
    }
  }
}

// ───────────────────────── 用例 ─────────────────────────

void main() {
  group('① P017 撤销条件为三问可判形态', () {
    test('真实源：三问要素齐备、旧串与协议外字段零残留', () {
      _guardP017(_readSrc(kP3Host));
    });

    test('负向自检：整行改回旧写法 ⇒ 判据必须抛', () {
      final mutated = _replaceRow(
        _readSrc(kP3Host),
        'P017 跳跃叙事',
        '| 跳跃叙事 | P017 跳跃叙事 | 跳跃是否有设计（埋线索/留白）？ |',
      );
      expect(
        () => _guardP017(mutated),
        throwsA(isA<StateError>()),
        reason: '判据恒绿则本断言失败 —— 说明护栏没有牙齿',
      );
    });

    test('负向自检：写回协议外字段 ⇒ 判据必须抛', () {
      final src = _readSrc(kP3Host);
      final row = _tableRow(src, 'P017 跳跃叙事');
      final mutated = src.replaceFirst(row, '$row 无 ⇒ 标 pending 不得据此不报。');
      expect(() => _guardP017(mutated), throwsA(isA<StateError>()));
    });
  });

  group('② P016 刻意省略条款在位', () {
    test('真实源：新增行存在且含时空锚三样判据、无「症」后缀', () {
      _guardP016(_readSrc(kP3Host));
    });

    test('负向自检：删掉该行 ⇒ 判据必须抛（防「改回没有这条」）', () {
      final mutated = _removeRow(_readSrc(kP3Host), 'P016 过渡生硬');
      expect(() => _guardP016(mutated), throwsA(isA<StateError>()));
    });

    test('负向自检：写回「症」后缀 ⇒ 判据必须抛', () {
      final src = _readSrc(kP3Host);
      final row = _tableRow(src, 'P016 过渡生硬');
      final mutated = src.replaceFirst(
        row,
        row.replaceFirst('P016 过渡生硬', 'P016 过渡生硬症'),
      );
      expect(() => _guardP016(mutated), throwsA(isA<StateError>()));
    });
  });

  group('③ 输出规范「理由不得复用症候名」在位且无协议外字段', () {
    test('真实源：P⑤ 在位、晚于第 7 条、pending/uncertain 计数为 0', () {
      _guardOutputSpec(_readSrc(kIndexHost));
    });

    test('负向自检：删掉该条 ⇒ 判据必须抛', () {
      final mutated = _readSrc(kIndexHost).replaceFirst('不得复用症候名', '简要说明');
      expect(() => _guardOutputSpec(mutated), throwsA(isA<StateError>()));
    });

    test('负向自检：写回「输出 uncertain」⇒ 判据必须抛', () {
      final mutated = _readSrc(
        kIndexHost,
      ).replaceFirst('该条不得报出', '输出 uncertain 后该条不得报出');
      expect(() => _guardOutputSpec(mutated), throwsA(isA<StateError>()));
    });
  });

  group('④ manual_3 无逐字相邻重复行', () {
    test('真实源：相邻重复计数为 0', () {
      _guardNoAdjacentDuplicate(_readSrc(kManual3Host), label: kManual3Host);
    });

    test('负向自检：把任一行复制一份紧贴其下 ⇒ 判据必须抛', () {
      final src = _readSrc(kManual3Host);
      final lines = src.split('\n');
      final i = lines.indexWhere((l) => l.trim().isNotEmpty);
      final mutated = [...lines]..insert(i + 1, lines[i]);
      expect(
        () => _guardNoAdjacentDuplicate(mutated.join('\n')),
        throwsA(isA<StateError>()),
      );
    });
  });
}
