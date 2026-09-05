// ─────────────────────────────────────────────────────────────
// 分块诊断路径的症候覆盖护栏（ADR-C69）
//
// 病因：长文本（>4000 字）走独立的 `kChunkSystemPrompt`，其症候清单是
//   **硬编码的 19 条（P003-P021）**，而注册表已有 39 条（P003-P041）。
//   缺失的 P022-P041 共 20 个症候在分块路径下**从未可用**。
//
// 因果链（ADR-C69 §5）：症候体系扩过两次（19 → 29 → 39），每次都同步了
//   「四库」+ skill_registry + skill_layers，**唯独漏了本文件**；
//   而 four_libraries_consistency_test 覆盖的正是那批库，本文件不在「四库」
//   之内 → 扩容后既没同步、也没护栏兜住。
//
// 本护栏守四条不变量：
//   ① 覆盖一致性：kChunkSystemPrompt 必须含注册表**全部**非退役症候 ID
//      ——逐条断言，不求和（V4.8）；总数判据允许「少一个、多一个重复的」蒙混
//   ② 范围说明派生：buildMergePrompt 的范围串必须由同一真源算出
//   ③ 无硬编码回退：源码中不得再现 P003-P027 / 硬编码清单行
//   ④ 兜底句存在：例外指引末条覆盖「未列出的症候」
//   ⑤ 生效性：分块链路真的把 kChunkSystemPrompt 作为 system message 发出
//
// 变异验证（预期）：
//   A 把清单改回硬编码 P003-P021      → ①③ 失败
//   B 把范围改回 P003-P027            → ②③ 失败
//   C 删掉兜底句                      → ④ 失败
//   D 给 analyzeChunk 换成别的 prompt → ⑤ 失败
//   E 注册表新增一个症候后不改代码     → ①②③ 应**仍通过**（派生的意义）
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';
import 'package:writingcoach/services/syndrome_registry.dart';

/// 包根定位：从 cwd 向上回溯，直到同时存在 lib/ 与 test/。
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

int _count(String src, String needle) => needle.allMatches(src).length;

const String kProgressive = 'lib/services/progressive_diagnosis.dart';

/// 注册表内全部未退役症候 ID（升序）——真源，与被测代码同源同法
List<String> activeSyndromeIds() {
  final ids =
      kSyndromeRegistry
          .where((s) => s.retired != true)
          .map((s) => s.id)
          .toList()
        ..sort();
  return ids;
}

/// 期望的范围说明串，形如 `P003-P041`
String expectedIdRange() {
  final ids = activeSyndromeIds();
  return '${ids.first}-${ids.last}';
}

void main() {
  final ids = activeSyndromeIds();

  group('① 覆盖一致性：分块 prompt 含注册表全部症候 ID', () {
    test('注册表自身非空且无退役（判据前提）', () {
      expect(
        ids.length,
        greaterThanOrEqualTo(39),
        reason:
            '注册表非退役症候数应 ≥ 39（ADR-C69 登记时为 39）。\n'
            '当前 ${ids.length} 个。若数量下降，先确认是否有症候被误标退役。',
      );
    });

    test('逐个症候 ID 断言出现在 kChunkSystemPrompt 中', () {
      final missing = ids
          .where((id) => !kChunkSystemPrompt.contains(id))
          .toList();
      expect(
        missing,
        isEmpty,
        reason:
            'kChunkSystemPrompt 缺少 ${missing.length} 个症候：${missing.join(', ')}\n'
            '（ADR-C69 §4：原硬编码清单只到 P021，漏掉后段 20 个。\n'
            ' 逐条断言而非总数判据——总数允许「缺一个、别处重复一个」蒙混过关，'
            '见 AGENTS.md V4.8）',
      );
    });

    test('派生清单的行数与注册表规模一致（防多出重复行）', () {
      // 只取「症候类型参考」与「例外情况指引」之间的清单块。
      // 首版把 prompt 里所有 `- ` 开头的行都算了进来，把 16 条例外指引
      // （形如 `- P003例外：…`）也算成清单行，于是每个 ID 都被判为「出现 2 次」
      // ——与 V4.7 同类的判据过宽问题。
      final startIdx = kChunkSystemPrompt.indexOf('症候类型参考');
      final endIdx = kChunkSystemPrompt.indexOf('例外情况指引');
      expect(startIdx, isNot(-1), reason: '找不到「症候类型参考」小节');
      expect(endIdx, greaterThan(startIdx), reason: '清单块边界异常');
      final block = kChunkSystemPrompt.substring(startIdx, endIdx);

      // 每个 ID 在清单块里**恰好**出现 1 次
      final dup = ids.where((id) => _count(block, id) > 1).toList();
      expect(dup, isEmpty, reason: '以下症候在清单块中重复出现：${dup.join(', ')}');
      // 且清单块非空（防止派生函数返回空串却「零重复」）
      final missingInBlock = ids.where((id) => !block.contains(id)).toList();
      expect(
        missingInBlock,
        isEmpty,
        reason: '清单块缺少：${missingInBlock.join(', ')}',
      );
    });
  });

  group('② 范围说明由同一真源派生', () {
    test('buildMergePrompt 的范围串等于注册表的真实范围', () {
      final prompt = buildMergePrompt(const []);
      expect(
        prompt.contains('症候编号 ${expectedIdRange()}'),
        isTrue,
        reason:
            'buildMergePrompt 应含「症候编号 ${expectedIdRange()}」。\n'
            '（ADR-C69 §4：原硬编码「P003-P027」与注册表不符，会压制后段症候输出）',
      );
    });

    test('范围串不含任何过时的硬编码区间', () {
      final prompt = buildMergePrompt(const []);
      for (final stale in ['P003-P027', 'P003-P021', 'P003-P031']) {
        expect(
          prompt.contains(stale),
          isFalse,
          reason: 'buildMergePrompt 出现了过时范围「$stale」，说明派生被回退了',
        );
      }
    });
  });

  group('③ 无硬编码回退（源码级）', () {
    test('生效位置不得是硬编码范围', () {
      final src = _readSrc(kProgressive);
      // 只盯**生效位置**：「症候编号」后面必须跟插值而非字面量。
      //
      // 首版直接扫全文件里的 'P003-P027'，把 ADR 注释中记录历史的那一句
      // （「原硬编码「P003-P027」」）也判为违规——注释不是代码，属假阳性。
      // 改为锚定生效位置后，既拦得住回退，也不误伤史实注释。
      expect(
        _count(src, '症候编号 P'),
        0,
        reason:
            '$kProgressive 的「症候编号」后面跟了字面量范围。\n'
            '必须写成由 _syndromeIdRange() 派生的插值，不得回退为手写区间。',
      );
      expect(
        _count(src, '症候编号 \${_syndromeIdRange()}'),
        1,
        reason: '「症候编号」应由 _syndromeIdRange() 派生，出现 1 次',
      );
    });

    test('源码不含 RA 移植时的硬编码清单行', () {
      final src = _readSrc(kProgressive);
      // 原硬编码清单首行的特征串（RN 逐字移植时带入）
      expect(
        _count(src, '- P003 情绪标签化'),
        0,
        reason:
            '$kProgressive 出现了硬编码清单行「- P003 情绪标签化」。\n'
            '（ADR-C69 §6.2 方案 A：清单必须由注册表派生，'
            '手写清单会在下次扩容时再次漏同步）',
      );
    });
  });

  group('④ 例外指引的兜底句存在', () {
    test('末条兜底覆盖「未列出的症候」', () {
      expect(
        kChunkSystemPrompt.contains('上面未列出的症候'),
        isTrue,
        reason:
            '例外指引缺少兜底句。\n'
            '（ADR-C69 §6.3：16 条例外只覆盖 P003-P021，注册表扩到 P041 后 '
            '后段症候没有对应例外，需一句通用兜底避免「零例外」导致过度诊断）',
      );
    });
  });

  group('⑤ 生效性：分块链路真的用了 kChunkSystemPrompt', () {
    test('analyzeChunk 的调用处引用该常量', () {
      final src = _readSrc(kProgressive);
      expect(
        _count(
          src,
          'ChatMessage(role: \'system\', content: kChunkSystemPrompt)',
        ),
        1,
        reason:
            '$kProgressive 中 analyzeChunk 应以 kChunkSystemPrompt 作为 system '
            'message，出现 1 次。\n'
            '（ADR-C69 §4：即使清单派生正确，若链路没用上也白搭）',
      );
    });

    test('清单确实比修复前更长（回归哨兵）', () {
      // 修复前是 19 条（P003-P021）。派生后应显著更多，且含后段代表项。
      for (final id in ['P022', 'P028', 'P034', 'P041']) {
        expect(
          kChunkSystemPrompt.contains(id),
          isTrue,
          reason: 'kChunkSystemPrompt 缺少后段症候 $id（修复前这些全都没有）',
        );
      }
    });
  });
}
