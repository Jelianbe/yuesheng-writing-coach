// ─────────────────────────────────────────────────────────────
// 分块诊断路径的症候覆盖护栏（ADR-C69）
//
// 病因：长文本（>4000 字）走独立的 `kChunkSystemPrompt`，其症候清单是
//   **硬编码的 19 条（P001-P017）**，而注册表已有 39 条（P001-P029）。
//   缺失的 P018-P029 共 20 个症候在分块路径下**从未可用**。
//
// 因果链（ADR-C69 §5）：症候体系扩过两次（19 → 29 → 39），每次都同步了
//   「四库」+ skill_registry + skill_layers，**唯独漏了本文件**；
//   而 four_libraries_consistency_test 覆盖的正是那批库，本文件不在「四库」
//   之内 → 扩容后既没同步、也没护栏兜住。
//
// 本护栏守四条不变量（★ 2026-10-23 ADR-C155 起 ① 升级为两节结构）：
//   ① 覆盖一致性：kChunkSystemPrompt 必须含注册表**全部**非退役症候 ID
//      ——逐条断言，不求和（V4.8）；总数判据允许「少一个、多一个重复的」蒙混
//      ★ ADR-C155：全覆盖现由**两节**共同完成——「症候判定要点」（27 条可片内
//        判定）+「跨章依赖判据」（6 条读数批实测退化者，点名留痕 + uncertain
//        指引）。两节各自守「恰 1 次、不重复、不静默不选」（B4）。
//      ★ T-20261031-11 件①：覆盖集在此基础上再减 [kNonDiagnosableSyndromeIds]
//        （P031 = 判据对象在创作前提层，两链都**不报**，与「退化者走 uncertain」不同类）。
//   ② 范围说明派生：buildMergePrompt 的范围串必须由同一真源算出
//   ③ 无硬编码回退：源码中不得再现 P001-P020 / 硬编码清单行
//   ④ 兜底句存在：例外指引末条覆盖「未列出的症候」
//   ⑤ 生效性：分块链路真的把 kChunkSystemPrompt 作为 system message 发出
//
// 变异验证（预期）：
//   A 把清单改回硬编码 P001-P017      → ①③ 失败
//   B 把范围改回 P001-P020            → ②③ 失败
//   C 删掉兜底句                      → ④ 失败
//   D 给 analyzeChunk 换成别的 prompt → ⑤ 失败
//   E 注册表新增一个症候后不改代码     → ①②③ 应**仍通过**（派生的意义）
//   F（C155 新增）把 6 条退化者从留痕节删掉 → ① 留痕节断言失败（防静默不选）
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
// T-20261025-06 件2：单块 messages 装配按 R-019 职责级分解到 chunk_messages.dart，
// ⑤ 的源码级断言必须跟随生效位置（否则扫不到 `? kChunkSystemPrompt` 恒红）。
const String kChunkMessages = 'lib/services/chunk_messages.dart';

/// 注册表内全部未退役症候 ID（升序）——真源，与被测代码同源同法
List<String> activeSyndromeIds() {
  final ids = kSyndromeRegistry.map((s) => s.id).toList()..sort();
  return ids;
}

/// 期望的范围说明串，形如 `P001-P029`
String expectedIdRange() {
  final ids = activeSyndromeIds();
  return '${ids.first}-${ids.last}';
}

void main() {
  final ids = activeSyndromeIds();

  group('① 覆盖一致性：分块 prompt 含注册表全部症候 ID', () {
    test('注册表自身非空（判据前提，0.3.6+9 聚类去重后活跃 33 条）', () {
      // 0.3.6+9 聚类去重：14 个症候按 b11 退役（记录保留、mergedInto 指向保留症候），
      // 活跃症候由 47 收敛为 33。此处只要求活跃集合非空且维持在合理规模。
      expect(
        ids.length,
        greaterThanOrEqualTo(30),
        reason:
            '注册表活跃症候数应 ≥ 30。\n'
            '当前 ${ids.length} 个。聚类去重后若再骤降，先确认是否有误标退役。',
      );
    });

    test('逐个症候 ID 断言出现在 kChunkSystemPrompt 中', () {
      // ★ T-20261031-11 件① B1：前提层不可诊（P031）已退出两链注入面 ⇒ 覆盖集
      //   改为「活跃 − kNonDiagnosableSyndromeIds」，与装配点同一真源。
      final missing = ids
          .where((id) => !kNonDiagnosableSyndromeIds.contains(id))
          .where((id) => !kChunkSystemPrompt.contains(id))
          .toList();
      expect(
        missing,
        isEmpty,
        reason:
            'kChunkSystemPrompt 缺少 ${missing.length} 个症候：${missing.join(', ')}\n'
            '（ADR-C69 §4：原硬编码清单只到 P017，漏掉后段 20 个。\n'
            ' 逐条断言而非总数判据——总数允许「缺一个、别处重复一个」蒙混过关，'
            '见 AGENTS.md V4.8）',
      );
    });

    test('件① 反向牙：P031 两行都不得进分块链 prompt（排除只发生在注入点）', () {
      // 顺序有意义：阳控在最前 —— prompt 若被整体删空，先红的是「要点块不见了」，
      // 而不是「P031 是否还在」，否则失败信息会把人引到错方向。
      expect(
        kChunkSystemPrompt,
        contains('- P032 '),
        reason: '阳性对照：要点块不在 ⇒ 下面三条负断言都是空集上的真命题',
      );
      expect(
        kChunkSystemPrompt,
        isNot(contains('- P031 ')),
        reason: 'P031 要点行仍在分块链 prompt ⇒ B1 的 .where 被绕过',
      );
      expect(
        kChunkSystemPrompt,
        isNot(contains('P031例外')),
        reason: 'P031 例外行仍在 ⇒ B2 的逐字删除被回退',
      );
      // 无差别兜底：P031 以**任何形式**出现都算越界（含将来的判读说明 / JSON 示例 /
      // 「本窗不判 P031」这类看似无害的提示）。这是**有意红线**，不是过紧 ——
      // 件① 的语义是前提层症候连提都不该提。若将来某个批次确实需要提，那个批次
      // 必须带 R-027 报批稿来改本条，不许顺手放宽。
      expect(
        kChunkSystemPrompt,
        isNot(contains('P031')),
        reason: 'P031 以任何形式出现在分块 prompt（有意红线，见注释）',
      );
      // ★ 上面第三条（无差别兜底）是**三段之外唯一**能挡住「将来有人用 `P031例外` 之外
      //   的措辞把 P031 写回 prompt」的断言 —— 删掉它**没有任何机器会报警**。
      //   「三段之外」= 自证探针段 / 例外指引段 / 输出格式段；「症候判定要点」与
      //   「跨章依赖判据」两节另有 N4 双向牙看守（N4 的右边界止于「片段窗口边界」）。
      //   要删必须先在本卡 / 台账留下「为什么这条可以不要」的理由。
      // 注册表本体仍在（防「顺手删库」）：排除发生在装配点，不在数据源。
      expect(
        kSyndromeRegistry.map((s) => s.id),
        contains('P031'),
        reason: '注册表条目不得因退出注入面而被删除',
      );
    });

    test('N4 双向牙：P031 既不进要点节、也不进「跨章依赖判据」节', () {
      // 只断「要点节不含 P031」防不住把它塞进退化节（那等于改成 uncertain，语义错）；
      // 只断「退化节不含 P031」防不住它被错标成退化判据。⇒ 两个方向都要。
      final startIdx = kChunkSystemPrompt.indexOf('症候判定要点');
      final midIdx = kChunkSystemPrompt.indexOf('跨章依赖判据');
      final endIdx = kChunkSystemPrompt.indexOf('片段窗口边界');
      expect(startIdx, isNot(-1), reason: '找不到「症候判定要点」小节');
      expect(midIdx, greaterThan(startIdx), reason: '清单块边界异常');
      expect(endIdx, greaterThan(midIdx), reason: '留痕节右边界异常');

      final criteriaBlock = kChunkSystemPrompt.substring(startIdx, midIdx);
      final degradedSection = kChunkSystemPrompt.substring(midIdx, endIdx);
      expect(
        criteriaBlock,
        isNot(contains('P031')),
        reason: '要点节仍含 P031 ⇒ 分块链还在报它（应为不报）',
      );
      expect(
        degradedSection,
        isNot(contains('P031')),
        reason: 'P031 被错标成退化判据（走 uncertain）——它的前提层语义是「不报」',
      );
    });

    test('派生要点清单的行数与注册表规模一致（防多出重复行）', () {
      // 只取「症候判定要点」与「跨章依赖判据」之间的清单块。
      // 首版把 prompt 里所有 `- ` 开头的行都算了进来，把 16 条例外指引
      // （形如 `- P001例外：…`）也算成清单行，于是每个 ID 都被判为「出现 2 次」
      // ——与 V4.7 同类的判据过宽问题。
      // ★ ADR-C155（2026-10-23）：标题由「症候类型参考」改为「症候判定要点」，
      //   且清单收窄为「注册表 − kChunkDegradedCriteriaIds」——6 条退化者
      //   移入「跨章依赖判据」节（仍点名，见下一组断言）。
      final startIdx = kChunkSystemPrompt.indexOf('症候判定要点');
      final endIdx = kChunkSystemPrompt.indexOf('跨章依赖判据');
      expect(startIdx, isNot(-1), reason: '找不到「症候判定要点」小节');
      expect(endIdx, greaterThan(startIdx), reason: '清单块边界异常');
      final block = kChunkSystemPrompt.substring(startIdx, endIdx);

      // 每个**非退化且可诊**症候 ID 在要点块里恰好出现 1 次
      final dup = ids
          .where((id) => !kChunkDegradedCriteriaIds.contains(id))
          .where((id) => !kNonDiagnosableSyndromeIds.contains(id))
          .where((id) => _count(block, id) > 1)
          .toList();
      expect(dup, isEmpty, reason: '以下症候在要点块中重复出现：${dup.join(', ')}');
      // 且非退化可诊症候全部在块内（防「收窄」被误做成「静默漏同步」）
      final missingInBlock = ids
          .where((id) => !kChunkDegradedCriteriaIds.contains(id))
          .where((id) => !kNonDiagnosableSyndromeIds.contains(id))
          .where((id) => !block.contains(id))
          .toList();
      expect(
        missingInBlock,
        isEmpty,
        reason: '要点块缺少：${missingInBlock.join(', ')}',
      );
    });

    test('ADR-C155：6 条退化判据在「跨章依赖判据」节点名留痕（防静默不选）', () {
      // 读数批（.ai/reports/2026-10-23-分块链读数.md §三）：P011/P012/P019/
      // P020/P022/P033 分块下 uncertain 率 33%–100% ⇒ 从要点清单排除，但必须
      // **显式留痕**（B4：不能静默不选）。留痕节 = 点名 + uncertain 指引。
      // ⚠️ 节边界截到「片段窗口边界」：其后的例外指引里 P011 等也有条目
      // （「- P011例外：…」），不截会把例外指引的点名算成留痕节重复。
      final degradedIdx = kChunkSystemPrompt.indexOf('跨章依赖判据');
      expect(
        degradedIdx,
        isNot(-1),
        reason: '「跨章依赖判据」节缺失——6 条退化判据被静默排除了（违反 B4）',
      );
      final boundaryIdx = kChunkSystemPrompt.indexOf('片段窗口边界');
      expect(boundaryIdx, greaterThan(degradedIdx), reason: '留痕节边界异常');
      final tail = kChunkSystemPrompt.substring(degradedIdx, boundaryIdx);
      for (final id in kChunkDegradedCriteriaIds) {
        expect(tail.contains(id), isTrue, reason: '退化判据 $id 未在留痕节点名');
        expect(_count(tail, id), 1, reason: '退化判据 $id 在留痕节重复出现');
      }
      expect(
        tail.contains('"uncertain": true'),
        isTrue,
        reason: '留痕节缺 uncertain 指引句（丙为先：明示片内不可判时直接标 uncertain）',
      );
    });

    test('ADR-C155：退化判据不得出现在要点块（收窄的实质）', () {
      final startIdx = kChunkSystemPrompt.indexOf('症候判定要点');
      final endIdx = kChunkSystemPrompt.indexOf('跨章依赖判据');
      final block = kChunkSystemPrompt.substring(startIdx, endIdx);
      final leaked = kChunkDegradedCriteriaIds
          .where((id) => block.contains(id))
          .toList();
      expect(
        leaked,
        isEmpty,
        reason:
            '以下退化判据仍出现在要点块：${leaked.join(', ')}\n'
            '（ADR-C155 裁定 = 乙形态收窄：片内不可自证的判据不注入判定要点）',
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
            '（ADR-C69 §4：原硬编码「P001-P020」与注册表不符，会压制后段症候输出）',
      );
    });

    test('范围串不含任何过时的硬编码区间', () {
      final prompt = buildMergePrompt(const []);
      for (final stale in ['P001-P020', 'P001-P017', 'P001-P023']) {
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
      // 首版直接扫全文件里的 'P001-P020'，把 ADR 注释中记录历史的那一句
      // （「原硬编码「P001-P020」」）也判为违规——注释不是代码，属假阳性。
      // 改为锚定生效位置后，既拦得住回退，也不误伤史实注释。
      expect(
        _count(src, '症候编号 P'),
        0,
        reason:
            '$kProgressive 的「症候编号」后面跟了字面量范围。\n'
            '必须写成由 _syndromeIdRange() 派生的插值，不得回退为手写区间。',
      );
      expect(
        _count(src, r'症候编号 ${_syndromeIdRange(disabledSyndromeIds)}'),
        1,
        reason: '「症候编号」应由 _syndromeIdRange() 派生，出现 1 次',
      );
    });

    test('源码不含 RA 移植时的硬编码清单行', () {
      final src = _readSrc(kProgressive);
      // 原硬编码清单首行的特征串（RN 逐字移植时带入）
      expect(
        _count(src, '- P001 情绪标签化'),
        0,
        reason:
            '$kProgressive 出现了硬编码清单行「- P001 情绪标签化」。\n'
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
            '（ADR-C69 §6.3：16 条例外只覆盖 P001-P017，注册表扩到 P029 后 '
            '后段症候没有对应例外，需一句通用兜底避免「零例外」导致过度诊断）',
      );
    });

    test('P034 判界存在（C123：防诊断分块轮把指称过载误路由 P018/P023）', () {
      // 诊断分块 prompt 只给 LLM 紧凑目录（ID+名称）+ 本例外指引，不注入 manual 正文。
      // 故 P034 与 P018/P023 的划界规则必须写进本指引，LLM 才会把「他骂了他」
      // 报成 P034 而非按字面「重复」归 P018。
      expect(
        kChunkSystemPrompt.contains('P034判界'),
        isTrue,
        reason: '例外指引缺 P034判界——诊断分块轮会把指称过载误路由到 P018/P023',
      );
      expect(kChunkSystemPrompt.contains('他骂了他一顿'), isTrue);
      expect(kChunkSystemPrompt.contains('必须报 P034'), isTrue);
    });
  });

  group('⑤ 生效性：分块链路真的用了 kChunkSystemPrompt', () {
    test('analyzeChunk 的调用处引用该常量', () {
      final src = _readSrc(kChunkMessages);
      // 诊断编辑器：空集时走全启用默认 kChunkSystemPrompt，非空时运行时构造。
      expect(
        _count(src, '? kChunkSystemPrompt'),
        1,
        reason:
            '$kChunkMessages 中 analyzeChunk 应以 kChunkSystemPrompt 作为 system '
            'message 的空集默认分支，出现 1 次。\n'
            '（ADR-C69 §4：即使清单派生正确，若链路没用上也白搭）',
      );
    });

    test('清单确实比修复前更长（回归哨兵）', () {
      // 修复前是 19 条（P001-P017）。派生后应显著更多，且含后段代表项。
      for (final id in ['P018', 'P021', 'P025', 'P029']) {
        expect(
          kChunkSystemPrompt.contains(id),
          isTrue,
          reason: 'kChunkSystemPrompt 缺少后段症候 $id（修复前这些全都没有）',
        );
      }
    });
  });
}
