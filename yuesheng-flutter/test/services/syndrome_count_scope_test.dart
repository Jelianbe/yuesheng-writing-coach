// ─────────────────────────────────────────────────────────────
// 症候数量上限「分工说明」护栏（ADR-C67 / 台账 N28）
//
// 病因：无上限侧（症候库「识别到多少就报多少」）与封顶侧（教学层
//   「每轮聚焦 1-2 个症候」）**语义其实可分**——前者管诊断块 JSON 的
//   全量识别，后者管本轮自然语言讲解覆盖几条——但 prompt 从未明说，
//   模型只能猜（台账 2146-2149，gp-13 独立命中同一问题）。
//
// 本护栏守四条不变量：
//   ① 无上限侧有「只约束诊断块 JSON」的分工说明
//   ② 封顶侧三处各有「只约束本轮讲解」的分工说明（按**出现次数**判，
//      不用 contains —— 见 ADR-C66 §4.2 / AGENTS.md V4.7 的假判据教训）
//   ③ 双向成对：任一侧的说明必须提及对向，防止只补一侧
//   ④ 数量规则本身没被偷偷改掉（消歧 ≠ 改规则）
//   ⑤ **生效性**：分工说明必须落在会被注入的 kSyndromeIndexContent 区间内，
//      不得落在 kSyndromeManualContent 区间——后者按症候 ID 切片注入，
//      写在那里模型根本看不到（ADR-C67 §2.4，本批实测过一次）
//
// 变异验证：
//   A 删掉无上限侧分工说明   → ① ③ 失败
//   B 删掉封顶侧任一说明     → ② ③ 失败
//   C 把「1-2 个」改成「1-3 个」→ ④ 失败
//   D 把「不限制问题数量」改成「最多 3 个」→ ④ 失败
//   E 把说明挪到 kSyndromeManualContent 区间 → ⑤ 失败
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

/// 剥掉整行注释后的源码——内容语义计数必须锚定**生效位置**。
///
/// V4.13「注释不是代码，判据要锚定生效位置」：元数据头（2737d292 落的
/// 「L1 常驻补头」）是给协作者看的登记文案，`//` 开头、**不进 prompt**，
/// 但整文件计数会把它们算进去 → 头部补一句，② 的护栏就从 1 跳到 2 而红
/// （2026-09-06 实测，正是本函数存在的原因）。
///
/// 只剥「跳过前导空白后以 `//` 开头」的**整行**，**不剥行内尾注释**——这些
/// 源文件的行内 `//` 多为字符串或代码尾注，粗暴剥离会切掉注入正文，制造
/// 比原问题更隐蔽的假绿。
///
/// 剥离范围已离线核验：四个文件共删 93 行注释，12 项受检判据中仅 attitude
/// 的 1 处落在注释里，其余 11 项剥离前后计数不变（零误伤）。
String _stripCommentLines(String src) {
  return src
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
}

/// 片段在**生效内容**（剥离注释行后）中的出现次数。
///
/// 一律用次数而非 `contains` —— contains 是假判据：同一标识符在多处出现时，
/// 改坏其中一处不改变布尔结果（AGENTS.md V4.7）。
///
/// 计数锚定生效内容而非整文件（V4.25-b）：注释里写一百遍也不算数，模型看
/// 不到——这与 ⑤「说明必须落在 kSyndromeIndexContent 区间」是同一个道理
/// 的两个面：⑤ 管**位置**，这里管**介质**。
int _count(String src, String needle) =>
    needle.allMatches(_stripCommentLines(src)).length;

const String kSyndromeKb = 'lib/services/syndrome_kb_content.dart';
const String kAttitude = 'lib/services/skills_attitude.dart';
const String kL1P1 = 'lib/services/skills_l1_core_p1.dart';
const String kL1P2 = 'lib/services/skills_l1_core_p2.dart';

/// 无上限侧分工说明（ADR-C67 §3 改动 ①）
const String kUncappedScopeNote = '本条只约束诊断块 JSON 的全量识别';

/// 封顶侧三处分工说明（ADR-C67 §3 改动 ③④⑤），按文件对应
const Map<String, String> kCappedScopeNotes = {
  kAttitude: '只约束本轮讲解',
  kL1P1: '只约束本轮讲解，不影响诊断块的全量识别',
  kL1P2: '只约束本轮讲解范围',
};

/// 未被改动的数量规则原文（④ 的基线）
const Map<String, String> kUntouchedRules = {
  kSyndromeKb: '4. 不限制问题数量——识别到多少就报多少',
  kAttitude: '每轮聚焦 1-2 个症候',
  kL1P1: '一次聚焦 1-2 个症候',
  kL1P2: '1-2 个症候',
};

void main() {
  group('① 无上限侧有「只约束诊断块 JSON」的分工说明', () {
    test('syndrome_kb_content.dart', () {
      final src = _readSrc(kSyndromeKb);
      expect(
        _count(src, kUncappedScopeNote),
        1,
        reason:
            '$kSyndromeKb 中「$kUncappedScopeNote」应出现 1 次。\n'
            '（ADR-C67 §3 改动 ①：症候库的"不限制数量"必须声明只约束诊断块）',
      );
    });
  });

  group('② 封顶侧三处各有「只约束本轮讲解」的分工说明', () {
    for (final entry in kCappedScopeNotes.entries) {
      test(entry.key, () {
        final src = _readSrc(entry.key);
        expect(
          _count(src, entry.value),
          1,
          reason:
              '${entry.key} 中「${entry.value}」应出现 1 次。\n'
              '（ADR-C67 §3 改动 ③④⑤：聚焦规则必须声明只约束本轮讲解）',
        );
      });
    }
  });

  group('③ 分工说明双向成对（防止只补一侧）', () {
    test('无上限侧提及「讲解」，封顶侧提及「诊断块」', () {
      final uncapped = _readSrc(kSyndromeKb);
      expect(
        _count(uncapped, '讲解'),
        greaterThanOrEqualTo(1),
        reason: '无上限侧必须提到「讲解」，否则模型无从知道两者是两件事',
      );

      // 逐处断言，不用「总数 >= 处数」——总数判据允许某处缺失被别处重复掩盖，
      // 与 AGENTS.md V4.7 是同一类假判据，只是更隐蔽（实测：变异 B 时 ③ 漏网）。
      for (final file in kCappedScopeNotes.keys) {
        expect(
          _count(_readSrc(file), '诊断块'),
          greaterThanOrEqualTo(1),
          reason: '$file 必须提到「诊断块」，否则单向说明拦不住误读',
        );
      }
    });
  });

  group('④ 数量规则本身未被改动（消歧 ≠ 改规则）', () {
    for (final entry in kUntouchedRules.entries) {
      test(entry.key, () {
        final src = _readSrc(entry.key);
        expect(
          _count(src, entry.value),
          greaterThanOrEqualTo(1),
          reason:
              '${entry.key} 中数量规则原文「${entry.value}」缺失。\n'
              '（ADR-C67 §3：本批只补分工说明，不得改动任何数量规则）',
        );
      });
    }
  });

  group('⑤ 生效性：分工说明落在会被注入的常量区间内', () {
    test('说明在 kSyndromeIndexContent 区间、不在 kSyndromeManualContent 区间', () {
      final src = _readSrc(kSyndromeKb);

      final idxIndex = src.indexOf('final String kSyndromeIndexContent =');
      final idxManual = src.indexOf('final String kSyndromeManualContent =');
      final idxNote = src.indexOf(kUncappedScopeNote);

      expect(idxIndex, isNot(-1), reason: '找不到 kSyndromeIndexContent 声明');
      expect(idxManual, isNot(-1), reason: '找不到 kSyndromeManualContent 声明');
      expect(idxIndex, lessThan(idxManual));
      expect(idxNote, isNot(-1), reason: '分工说明不存在');

      expect(
        idxNote,
        greaterThan(idxIndex),
        reason: '分工说明必须位于 kSyndromeIndexContent 之后（即在该常量内）',
      );
      expect(
        idxNote,
        lessThan(idxManual),
        reason:
            '分工说明落在 kSyndromeManualContent 区间——该常量只按症候 ID '
            '切片注入（_extractSyndromeSection），写在那里模型看不到。\n'
            '（ADR-C67 §2.4：本批首轮改动正是踩了这个坑，已撤销）',
      );
    });

    test('生效性判据自身有效（变异 E 回归）', () {
      // 模拟：说明被挪到 manual 区间之后
      const fake =
          'final String kSyndromeIndexContent = ...\n'
          'final String kSyndromeManualContent = ...\n'
          '本条只约束诊断块 JSON 的全量识别';
      final idxManualFake = fake.indexOf(
        'final String kSyndromeManualContent =',
      );
      final idxNoteFake = fake.indexOf(kUncappedScopeNote);
      expect(idxNoteFake, greaterThan(idxManualFake)); // 应被 ⑤ 判为失败
    });
  });
}
