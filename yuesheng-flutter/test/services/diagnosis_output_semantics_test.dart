// ─────────────────────────────────────────────────────────────
// 诊断输出语义消歧护栏（ADR-C68 / 台账 N35 + N36）
//
// 病因（两条同源同法：不是规则写错，是两处规则撞车时没人说怎么办）：
//   N35 —— 「诊断前先确认体裁」(skills_diagnosis_p1 §四) 与
//          「诊断块必附加」(skills_l1_core_p2 §3.9) 撞车：学员贴了文本
//          却没说体裁时，模型不知道 severity 按哪个基准标。
//          关键发现：基准**已在 prompt 里**——§一 容忍度矩阵写着
//          「阈值高于通用标准」，所以体裁未定 ≠ 阈值未定，缺的只是一条接线。
//   N36 —— 「先自然语言 + 再 JSON」的两段缝在同一轮，但输出格式段
//          从未明说两段各受哪套数量规则管：自然说明受教学层「聚焦 1-2 个」
//          约束，JSON 的 syndromes 数组不受约束（全量识别）。
//          ADR-C67 已解决「从未明说」的一半，但说明落在「诊断输出规范」
//          章节（:44-45），距模型逐段遵循的「## 输出格式」（:51+）有 6 行，
//          残留缺口在输出格式段本身。
//
// 本护栏守五条不变量（与 ADR-C68 §5.3 一一对应）：
//   ① 存在性：N35 裁决段落存在，含「通用标准」（与 §一 同词，可交叉检索）
//   ② 生效性：三段说明必须落在**会被注入**的常量 / skill 区间内——
//      N36 的两段不得落进 kSyndromeManualContent（按症候 ID 切片注入，
//      写在那里模型看不到；ADR-C67 §2.4 首轮改动正是踩了这个坑）
//   ③ 就近性：N36 两段必须各自落在对应 `###` 标题之后、下一个标题之前——
//      防止「存在但不再就近」，退化为 ADR-C67 那种 6 行外的旁注
//   ④ 反向断言：既有规则原文不得被改写（只补不删）
//   ⑤ 逐处断言：N36 两段各自独立断言，不求和（AGENTS.md V4.8）
//
// 变异验证（预期）：
//   A 删掉 N35 段落                     → ① 失败
//   B 把 N35 段落挪到 _genreGuide 之外  → ② 失败（① 是存在性判定，本就通过）
//   C 删掉③（JSON 段说明）              → ②③⑤ 失败（⑤ 独立计数，不被②掩盖）
//   D 把②挪到 index 内容最末端          → ③⑤ 失败（仍可注入，但脱离小节 → 由 ③ 管）
//   E 把③挪到「### JSON 数据部分」之前  → ③⑤ 失败
//   F 改掉「不限制问题数量」原文        → ④ 失败
//   G 把「1-2 个」改成「1-3 个」        → ④ 失败（syndrome_count_scope_test 也拦）
//   H 把②挪到「## 输出格式」之前        → ②③⑤ 失败（② 的「## 输出格式」下界生效）
//
// 变异脚本：tool/_c68_mutation.py（7 个变异，全部拦截、无漏网）
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

/// 片段在源码中的出现次数。
///
/// 一律用次数而非 `contains` —— contains 是假判据：同一标识符在多处出现时，
/// 改坏其中一处不改变布尔结果（AGENTS.md V4.7）。
int _count(String src, String needle) => needle.allMatches(src).length;

const String kDiagnosisP1 = 'lib/services/skills_diagnosis_p1.dart';
const String kSyndromeKb = 'lib/services/syndrome_kb_content.dart';

/// ── N35（①）指纹 ──
/// 标题句含「≠」，避开全角/半角引号歧义；「通用标准」是与 §一 容忍度矩阵
/// 同词的交叉检索锚点，单独成一条断言。
const String kN35Head = '体裁未确认 ≠ 不能诊断';
const String kN35BaselineWord = '通用标准';

/// ── N36（②③）指纹 ──
/// 均取不含引号的稳定片段，避免源码里中英文引号混用导致断言脆断。
const String kN36NaturalNote = '本轮聚焦的 1-2 个主要问题';
const String kN36JsonNote = '两段管的是不同事';

/// 输出格式段的两个 `###` 小标题（③ 就近性判据的边界）
const String kH3Natural = '### 自然说明部分';
const String kH3Json = '### JSON 数据部分';

/// 「## 输出格式」标题（② 上边界 B 的锚点，见该处注释）
const String kOutputFormatHeading = '## 输出格式';

/// ④ 的反向基线：既有规则原文，本批只补不删
const Map<String, List<String>> kUntouchedRules = {
  kDiagnosisP1: ['教练在第一次诊断前需要确认学员的作品体裁'],
  kSyndromeKb: [
    '不限制问题数量——识别到多少就报多少',
    kOutputFormatHeading,
    kH3Natural,
    kH3Json,
  ],
};

/// 取 `heading` 之后、下一个 `###` 或 `##` 标题之前的区间文本。
///
/// 若 heading 不存在返回 null，由调用方显式断言（不让 -1 静默通过）。
String? _sectionAfter(String src, String heading) {
  final start = src.indexOf(heading);
  if (start == -1) return null;
  final bodyStart = start + heading.length;
  final rest = src.substring(bodyStart);
  // 注意两处 Dart 正则差异（本批实测踩到）：
  //   1) `#{2,3}` 的 `{` 会被当成字符串插值 → 用字符类 [#]{2,3}；
  //   2) Dart RegExp **不支持** `(?m)` 内联修饰符 → 用 multiLine: 构造参数。
  final m = RegExp(r'^[#]{2,3}\s', multiLine: true).firstMatch(rest);
  final end = m == null ? rest.length : m.start;
  return rest.substring(0, end);
}

void main() {
  group('① 存在性：N35 体裁未确认时 severity 基准裁决', () {
    test('skills_diagnosis_p1.dart 含裁决段落', () {
      final src = _readSrc(kDiagnosisP1);
      expect(
        _count(src, kN35Head),
        1,
        reason:
            '$kDiagnosisP1 中「$kN35Head」应出现 1 次。\n'
            '（ADR-C68 §3.1 改动 ①：体裁未确认时按通用标准标定，不推迟诊断）',
      );
    });

    test('裁决段落使用与 §一 容忍度矩阵同词的「$kN35BaselineWord」', () {
      final src = _readSrc(kDiagnosisP1);

      // 基线词必须在容忍度矩阵里**本来就有**——否则 N35 的「基准早已存在」
      // 这个前提不成立，本批的修法（补接线而非新增概念）也随之失效。
      expect(
        _count(src, kN35BaselineWord),
        greaterThanOrEqualTo(2),
        reason:
            '「$kN35BaselineWord」在 $kDiagnosisP1 中出现次数应 ≥ 2'
            '（§一 容忍度矩阵一处 + N35 裁决一段落一处）。\n'
            '若只剩 1 处，说明容忍度矩阵的基准表述被改掉了——N35 的接线会悬空。',
      );

      // 且必须有一处落在 N35 段落内，而不是只在矩阵里
      final head = src.indexOf(kN35Head);
      expect(head, isNot(-1), reason: 'N35 裁决段落不存在');
      final tail = src.substring(head, head + 400);
      expect(
        tail.contains(kN35BaselineWord),
        isTrue,
        reason: 'N35 裁决段落正文内必须出现「$kN35BaselineWord」，以便交叉检索',
      );
    });
  });

  group('② 生效性：三段说明都落在会被注入的区间内', () {
    test('N35 段落落在 _genreGuide 的 content 区间内', () {
      final src = _readSrc(kDiagnosisP1);

      final genreStart = src.indexOf("Skill(\n  id: 'genre-guide'");
      final fallbackStart = src.indexOf("id: 'genre-guide'");
      final skillStart = genreStart != -1 ? genreStart : fallbackStart;
      expect(
        skillStart,
        isNot(-1),
        reason: '在 $kDiagnosisP1 中找不到 genre-guide 的 Skill 声明',
      );

      final note = src.indexOf(kN35Head);
      expect(note, isNot(-1), reason: 'N35 裁决段落不存在');
      expect(
        note,
        greaterThan(skillStart),
        reason: 'N35 裁决段落必须位于 genre-guide 声明之后（即落在该 skill 内）',
      );

      // 下边界：不得越过 genre-guide 之后的下一个 Skill 声明
      final rest = src.substring(skillStart + 20);
      final m = RegExp(r'^\s*Skill\(', multiLine: true).firstMatch(rest);
      if (m != null) {
        final nextSkill = skillStart + 20 + m.start;
        expect(
          note,
          lessThan(nextSkill),
          reason:
              'N35 裁决段落越过了 genre-guide 的边界，落进下一个 Skill 的 content 里。\n'
              '（genre-guide 经 skill_registry 注册后按整段注入；落在别的 skill 内 '
              '要么不生效，要么污染别的 skill）',
        );
      }
    });

    test('N36 两段落在 kSyndromeIndexContent 区间、不在 kSyndromeManualContent 区间', () {
      final src = _readSrc(kSyndromeKb);

      final idxIndex = src.indexOf('final String kSyndromeIndexContent =');
      final idxManual = src.indexOf('final String kSyndromeManualContent =');
      expect(idxIndex, isNot(-1), reason: '找不到 kSyndromeIndexContent 声明');
      expect(
        idxManual,
        isNot(-1),
        reason: '找不到 kSyndromeManualContent 声明（判据前提，不能静默跳过）',
      );
      expect(idxIndex, lessThan(idxManual));

      final iNatural = src.indexOf(kN36NaturalNote);
      final iJson = src.indexOf(kN36JsonNote);
      expect(iNatural, isNot(-1), reason: 'N36 自然说明段说明不存在');
      expect(iJson, isNot(-1), reason: 'N36 JSON 段说明不存在');

      // 上边界 A：必须在 index 常量声明之后
      expect(
        iNatural,
        greaterThan(idxIndex),
        reason: 'N36 自然说明段说明必须位于 kSyndromeIndexContent 之后',
      );
      expect(
        iJson,
        greaterThan(idxIndex),
        reason: 'N36 JSON 段说明必须位于 kSyndromeIndexContent 之后',
      );

      // 上边界 B（比 A 更紧）：必须在「## 输出格式」标题之后。
      //
      // 只有 A 时存在盲点——把说明插在 `kSyndromeManualContent` 声明**前一行**
      // 也能通过（位置仍 < idxManual），但那里既不在输出格式段内、也不在 index
      // 的正文里，模型同样看不到。变异 D 正是撞在这个盲点上，靠 ③ 兜住的。
      // 用「## 输出格式」做下界后，D 会被 ② 直接命中，不再依赖 ③ 单兜。
      final idxFmt = src.indexOf(kOutputFormatHeading);
      expect(
        idxFmt,
        isNot(-1),
        reason: '找不到「$kOutputFormatHeading」标题（判据前提，不能静默跳过）',
      );
      expect(
        iNatural,
        greaterThan(idxFmt),
        reason:
            'N36 自然说明段说明必须位于「$kOutputFormatHeading」之后。\n'
            '（ADR-C68 §5.2 判据加强：仅判「在 manual 声明之前」留了个盲区，'
            '插在两常量之间也能蒙混）',
      );
      expect(
        iJson,
        greaterThan(idxFmt),
        reason: 'N36 JSON 段说明必须位于「$kOutputFormatHeading」之后',
      );

      // 下边界（关键）：manual 常量按症候 ID 切片注入，写在那里模型看不到
      expect(
        iNatural,
        lessThan(idxManual),
        reason:
            'N36 自然说明段说明落在 kSyndromeManualContent 区间——该常量只按症候 ID '
            '切片注入（_extractSyndromeSection），写在那里模型看不到。\n'
            '（ADR-C67 §2.4：首轮改动正是踩了这个坑，已撤销）',
      );
      expect(
        iJson,
        lessThan(idxManual),
        reason: 'N36 JSON 段说明落在 kSyndromeManualContent 区间，同上，不生效',
      );
    });
  });

  group('③ 就近性：N36 两段各自紧贴对应的 ### 小标题', () {
    test('自然说明段说明落在「$kH3Natural」之后', () {
      final src = _readSrc(kSyndromeKb);
      final section = _sectionAfter(src, kH3Natural);
      expect(section, isNotNull, reason: '找不到小标题「$kH3Natural」');
      expect(
        section!.contains(kN36NaturalNote),
        isTrue,
        reason:
            '「$kH3Natural」正文中找不到「$kN36NaturalNote」。\n'
            '说明被挪到别处后，模型逐段生成时读不到——退化为 ADR-C67 §3.2 指出的 '
            '「说明在 6 行外、不在生成位」的问题。',
      );
    });

    test('JSON 段说明落在「$kH3Json」之后', () {
      final src = _readSrc(kSyndromeKb);
      final section = _sectionAfter(src, kH3Json);
      expect(section, isNotNull, reason: '找不到小标题「$kH3Json」');
      expect(
        section!.contains(kN36JsonNote),
        isTrue,
        reason:
            '「$kH3Json」正文中找不到「$kN36JsonNote」。\n'
            '这条说明的存在意义就在**此处**——模型读完「聚焦 1-2 个」再往下生成 JSON '
            '时，最容易把 syndromes 数组也收敛到 1-2 条（正是 N28 要防的失败模式）。',
      );
    });

    test('就近性判据自身有效（变异 E 回归）', () {
      // 模拟：说明被挪到 JSON 小标题**之前**（变成上一节的尾巴）
      const fake =
          '### 自然说明部分\n'
          '两段管的是不同事\n'
          '### JSON 数据部分\n';
      final section = _sectionAfter(fake, kH3Json);
      expect(section, isNotNull);
      expect(section!.contains(kN36JsonNote), isFalse); // ③ 应判为失败
    });
  });

  group('④ 反向断言：既有规则原文不得被改写（只补不删）', () {
    for (final entry in kUntouchedRules.entries) {
      for (final rule in entry.value) {
        test('${entry.key} :: $rule', () {
          final src = _readSrc(entry.key);
          expect(
            _count(src, rule),
            greaterThanOrEqualTo(1),
            reason:
                '${entry.key} 中原文「$rule」缺失。\n'
                '（ADR-C68 §3：本批只补裁决 / 就近指引，不得改动任何既有规则）',
          );
        });
      }
    }
  });

  group('⑤ 逐处断言：N36 两段各自独立计数，不求和', () {
    test('自然说明段说明出现 1 次', () {
      final src = _readSrc(kSyndromeKb);
      expect(
        _count(src, kN36NaturalNote),
        1,
        reason:
            '$kSyndromeKb 中「$kN36NaturalNote」应出现 1 次。\n'
            '（ADR-C68 §3.2 改动 ②）',
      );
    });

    test('JSON 段说明出现 1 次', () {
      final src = _readSrc(kSyndromeKb);
      expect(
        _count(src, kN36JsonNote),
        1,
        reason:
            '$kSyndromeKb 中「$kN36JsonNote」应出现 1 次。\n'
            '（ADR-C68 §3.2 改动 ③。两段分开计数：若用「两段合计 ≥ 2」，'
            '删掉任一段后另一段重复一次也能蒙混过关——与 AGENTS.md V4.7 同类）',
      );
    });

    test('两段指向不同的数量规则（防止补成了同义反复）', () {
      final src = _readSrc(kSyndromeKb);
      final natural = _sectionAfter(src, kH3Natural) ?? '';
      final json = _sectionAfter(src, kH3Json) ?? '';

      // 自然说明段：必须提到「聚焦」由教学层另定，即承认自己受封顶约束
      expect(
        natural.contains('聚焦'),
        isTrue,
        reason: '自然说明段应提及「聚焦」，表明它受教学层聚焦规则约束',
      );
      // JSON 段：必须提到「全量」/「不限制数量」，即声明自己不受封顶约束
      expect(
        json.contains('全量识别'),
        isTrue,
        reason: 'JSON 段应提及「全量识别」，表明 syndromes 数组不受聚焦约束',
      );
    });
  });
}
