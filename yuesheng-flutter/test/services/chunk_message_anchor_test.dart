// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// 分块链 user 消息锚点（T-20261027-05 A2）
//
// 缺口（卡片 §一·缺口 2）：`progressive_diagnosis.dart` 的分块链把**章节正文**
//   直接装进 user 消息（`buildChunkMessages` 最后一条 `content: chunk`），
//   但 `message_sequence_anchor.json` 只覆盖 chat_service 边界 ⇒ 这条链的
//   user 侧体积**没有任何读数**。本测试补运行时实测 + 有序 (len,fnv) 指纹。
//
// 量什么：对固定合成语料，走**生产同一条** `splitContent` → `buildChunkMessages`
//   路径，逐 chunk 记录 user 消息的 (len, fnv)，并记录源文本长度。
//   ⇒ 改分块阈值 / 改切法 / 改装配（正文被前置标签污染）都会现形。
//
// ★ 这些是**形状钉**，不是内容上限：正文长度由用户输入决定（`single_paragraph_*`
//   一例就是「无分隔符长段整段成块」的现有行为，见 `splitContent` 的单段原子性）。
//   真加切分上限属行为变更，须另立卡 —— 本测试把现状钉住，变更时红灯逼重钉。
//
// 用法：
//   flutter test test/services/chunk_message_anchor_test.dart
//   UPDATE_SNAPSHOTS=true flutter test test/services/chunk_message_anchor_test.dart
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';

const String kChunkMsgAnchorPath = 'test/snapshots/chunk_message_anchor.json';

int _fnv1a64(String s) {
  // 同 chat_service_message_sequence_anchor_test.dart：UTF-16 code units，
  // VM 上 int 即 64 位（项目只发布 Android，不编译 JS）。
  // ignore: avoid_js_rounded_ints
  var h = 0xcbf29ce484222325;
  for (final cu in s.codeUnits) {
    h ^= cu;
    h *= 0x100000001b3;
  }
  return h & 0x7fffffffffffffff;
}

/// 合成语料：只有「长度 + 分隔符」两个维度参与分块，字符本身无意义。
String _p(int n) => '风' * n;

class _Case {
  final String name;
  final String content;
  const _Case(this.name, this.content);
}

final List<_Case> _kCases = <_Case>[
  // 常规章节：3 段 × 1199 字 + '\n\n' 分隔 ⇒ 按 3000 阈值切成 2 块。
  _Case(
    'paragraphs_3x1199',
    <String>[_p(1199), _p(1199), _p(1199)].join('\n\n'),
  ),
  // 无分隔符长段：`splitContent` 的既有行为是**整段成一块**（不可再分的原子）。
  _Case('single_paragraph_6000', _p(6000)),
  _Case('single_paragraph_20000', _p(20000)),
];

/// 一个用例的读数：源长 + 块数 + 逐 chunk 的 user 消息 (len, fnv)。
Map<String, Object> _measure(_Case c) {
  final chunks = splitContent(c.content);
  final user = <Map<String, Object>>[];
  for (var i = 0; i < chunks.length; i++) {
    final msgs = buildChunkMessages('锚点语料', chunks[i], i, chunks.length);
    final last = msgs.last;
    // 结构自检：最后一条必须是 user，且**逐字节等于** chunk 本体
    // （H8 之后正文那条不前置标签；若有人把标签拼回正文，这里先红）。
    if (last.role != 'user') {
      fail('[chunk-anchor] ${c.name}[$i] 末条 role=${last.role}，应为 user');
    }
    if (last.content != chunks[i]) {
      fail('[chunk-anchor] ${c.name}[$i] user 正文 ≠ chunk 本体（装配混入其他内容）');
    }
    user.add(<String, Object>{
      'len': last.content.length,
      'fnv': _fnv1a64(last.content).toRadixString(16),
    });
  }
  return <String, Object>{
    'sourceLen': c.content.length,
    'chunkCount': chunks.length,
    'user': user,
  };
}

List<String> _diff(String path, dynamic a, dynamic b) {
  final out = <String>[];
  if (a is Map && b is Map) {
    final keys = <String>{...a.keys.cast<String>(), ...b.keys.cast<String>()};
    for (final k in keys) {
      out.addAll(_diff('$path.$k', a[k], b[k]));
    }
  } else if (a is List && b is List) {
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      out.addAll(
        _diff(
          '$path[$i]',
          i < a.length ? a[i] : null,
          i < b.length ? b[i] : null,
        ),
      );
    }
    if (a.length != b.length) {
      out.add('$path.length: ${a.length} → ${b.length}');
    }
  } else if (a != b) {
    out.add('$path: ${a ?? '∅'} → ${b ?? '∅'}');
  }
  return out;
}

void main() {
  test('分块链 user 消息：逐 chunk (len,fnv) 不变（T-20261027-05 A2）', () {
    final updating = (Platform.environment['UPDATE_SNAPSHOTS'] ?? '') == 'true';
    final file = File(kChunkMsgAnchorPath);
    final exists = file.existsSync();

    if (!exists && !updating) {
      fail(
        '[chunk-anchor] 锚点快照缺失：$kChunkMsgAnchorPath\n'
        '  ★ 缺失 = 事故，不是常态（不自动重建 —— 那等于用当前行为重写判据）。\n'
        '  重建：UPDATE_SNAPSHOTS=true flutter test '
        'test/services/chunk_message_anchor_test.dart',
      );
    }

    final current = <String, Object>{
      'meta': {'note': '分块链 user 消息锚点（T-20261027-05 A2）'},
    };
    for (final c in _kCases) {
      final m = _measure(c);
      final user = (m['user']! as List).cast<Map<String, Object>>();
      if (user.isEmpty) fail('[chunk-anchor] ${c.name} 零块 ⇒ 判据面为空（空扫不是通过）');
      for (final u in user) {
        if ((u['len']! as int) < 1) {
          fail('[chunk-anchor] ${c.name} 出现空 user 消息（len<1）');
        }
      }
      current[c.name] = m;
    }

    if (updating) {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(current)}\n',
        );
      final reread = jsonDecode(file.readAsStringSync());
      final written = reread is Map<String, dynamic>
          ? reread
          : const <String, dynamic>{};
      expect(
        written.keys.where((k) => k != 'meta').toSet(),
        {for (final c in _kCases) c.name},
        reason: '回读键集必须与 _kCases 相等（写到一半 = 半截基线）',
      );
      print(
        '[chunk-anchor][告警] UPDATE_SNAPSHOTS=true ⇒ 已重写 $kChunkMsgAnchorPath'
        '（${_kCases.length} 例；本次**未做比对**，这不是校验通过）',
      );
      return;
    }

    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      fail('[chunk-anchor] 快照结构非法：顶层应为 JSON 对象，实际 ${decoded.runtimeType}');
    }
    final stored = decoded;

    // 双向键集合：少键 = 覆盖缩水；多键 = 已删用例残留（判据面混入不存在对象）。
    final expectedNames = <String>{for (final c in _kCases) c.name};
    final storedNames = stored.keys.toSet()..remove('meta');
    final missing = expectedNames.difference(storedNames).toList()..sort();
    final extra = storedNames.difference(expectedNames).toList()..sort();
    if (missing.isNotEmpty || extra.isNotEmpty) {
      fail(
        '[chunk-anchor] 基线用例键集合与 _kCases 不相等（双向判据）：\n'
        '  缺少 ${missing.length} 个：$missing\n'
        '  多出 ${extra.length} 个：$extra\n'
        '  确需重建：UPDATE_SNAPSHOTS=true flutter test '
        'test/services/chunk_message_anchor_test.dart',
      );
    }

    final diffs = <String>[];
    for (final c in _kCases) {
      diffs.addAll(_diff(c.name, stored[c.name], current[c.name]));
    }
    if (diffs.isNotEmpty) {
      print('[chunk-anchor] 检测到 ${diffs.length} 处分块链漂移：');
      for (final d in diffs.take(40)) {
        print('  - $d');
      }
      fail('分块链 user 消息漂移（${diffs.length} 处），见上方 diff。');
    }
    print('[chunk-anchor] 比对通过：分块链 user 消息与基线一致 ✓');
    expect(diffs, isEmpty);
  });
}
