// ─────────────────────────────────────────────────────────────
// 注入源方向冲突护栏（零额度 · 纯静态）
//
// 背景（2026-10-05 侦察取证）：
//   生产 system prompt 由多个注入源拼装，同一 syndrome 的「报/不报」
//   指令可能来自不同段落。L1 边界 _kPromptBoundary 有一句倾向多报：
//     「不要因为它『可能是作者有意的选择』就直接划掉或放过」
//   而 few-shot / L3 手册对具体 ID 写「不得报 PXXX」。
//   两者字面相反 ⇒ 冲突域 = 同时满足
//     ① ID 在 L1 那句的作用域内（该句自限「结构层判断」）
//     ② 该 ID 的知识段落里存在「不得报 / 不要报」类条款
//
// 本护栏的职责：**把冲突域钉成一个显式清单并使其可维护**，
// 而不是替产品做「该报还是不该报」的裁定——那是需要方案裁定的部分。
// 现在钉住清单，是为了让日后任何「新增划界块 / 改作用域 / 改 L1 措辞」
// 都必然触发一条会红的断言，而不是静默漂移。
//
// 判据纪律（对齐项目既有护栏）：
//   - 断言数与清单逐项列出，不写 `greaterThanOrEqualTo`（那会让它失去牙齿）
//   - 每条断言带 reason 说明「变了会怎样」
//   - 作用域从源码解析（不硬编码类型表）⇒ 注册表加类型时测试会提示复核
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/training_few_shot_library.dart';

/// 「倾向不报」类条款的判据词表。
///
/// 为什么要显式列出而不是用正则模糊匹配：本护栏的全部价值在于
/// 「条款被识别到了」这件事可复核。若判据本身是模糊正则，
/// 读者无法判断「这一条为什么没被算进去」。
const List<String> kNoReportMarkers = <String>[
  '不得报', // 「不得报 P029」
  '不要报', // 「不要报 P018」
  '不是 P0', // 「注意不是 P036」
  '不在此列',
];

/// 读取一个注入源的源码文本。
String _src(String path) => File(path).readAsStringSync();

/// 从 few-shot 库源码解析出每个 ID 的正文（按 `'P0XX': r'''...'''` 切段）。
///
/// 为什么不直接用 `kTrainingFewShotLibrary` 的值：值是运行时对象，
/// 而本护栏要同时证明「源码里有划界块」（文案事实）与
/// 「该 ID 属于结构层」（注册表事实）两件事，故源码与注册表分取。
Map<String, String> _parseFewShotSource() {
  final src = _src('lib/services/training_few_shot_library.dart');
  final out = <String, String>{};
  // 以 `'P0XX':` 为段首，以下一个 `'P0XX':` 或 `};` 为段尾。
  final starts = <int>[];
  final re = RegExp("'(P0\\d\\d)':");
  for (final m in re.allMatches(src)) {
    starts.add(m.start);
    out[m.group(1)!] = '';
  }
  for (var i = 0; i < starts.length; i++) {
    final from = starts[i];
    final to = i + 1 < starts.length ? starts[i + 1] : src.length;
    final seg = src.substring(from, to);
    out[re.firstMatch(seg)!.group(1)!] = seg;
  }
  return out;
}

/// 某 ID 段落里是否含「倾向不报」条款。
bool _hasNoReportClause(String body, String id) =>
    kNoReportMarkers.any(body.contains) && body.contains(id);

/// 某 ID 是否属结构层（L1 边界句自限的作用域）。
bool _isStructural(String id) {
  for (final r in kSyndromeRegistry) {
    if (r.id == id) return r.type == SyndromeType.structuralDisorder;
  }
  throw StateError('注册表缺少 $id —— 新增症候后须复核本护栏清单');
}

/// L3 手册某个 ID 段落的切片结果。
class _Seg {
  const _Seg(this.id, this.body);
  final String id;
  final String body;
}

/// 逐段解析 L3 手册（6 个分片），返回每个 `### P0XX ` 段落的正文。
///
/// 段尾规则与 Dart 侧 `_extractSyndromeSection`（syndrome_knowledge_base.dart）
/// **完全一致**：取下一个 `### P0XX ` 与下一个 `## ` 中更早的那个。
/// 两处口径若漂移，本护栏的读数就不能代表生产注入面 —— 故此处照抄规则。
List<_Seg> _manualSegments() {
  final out = <_Seg>[];
  for (var i = 1; i <= 6; i++) {
    final s = _src('lib/services/syndrome_kb_content_manual_$i.dart');
    final marks = RegExp(
      r'^### (P0\d\d) ',
      multiLine: true,
    ).allMatches(s).toList();
    for (var k = 0; k < marks.length; k++) {
      final m = marks[k];
      final tail = s.substring(m.end);
      final n3 = RegExp(r'\n### P0\d\d ').firstMatch(tail);
      final n2 = RegExp(r'\n## ').firstMatch(tail);
      var end = s.length;
      for (final c in <RegExpMatch?>[n3, n2]) {
        if (c != null && m.end + c.start < end) end = m.end + c.start;
      }
      out.add(_Seg(m.group(1)!, s.substring(m.start, end)));
    }
  }
  return out;
}

void main() {
  group('注入源方向冲突 · 作用域与清单', () {
    test('#1 解析器自检：few-shot 源码解析出 37 个 ID（解析器没失效）', () {
      // 本护栏最大风险是「解析器静默失配 ⇒ 清单恒空 ⇒ 假绿」。
      // 故先钉住解析结果规模，再谈清单。
      final parsed = _parseFewShotSource();
      expect(
        parsed.length,
        kTrainingFewShotLibrary.length,
        reason:
            '源码解析出的 ID 数(${parsed.length})须等于运行时库(${kTrainingFewShotLibrary.length})；'
            '不等说明 `_parseFewShotSource` 的正则与源码格式脱节，'
            '此时下面所有清单断言都会假绿',
      );
      expect(parsed.length, 37, reason: 'few-shot 库基线 37 条（ADR-0003 阶段一后）');
    });

    test('#2 L1 边界句存在「倾向多报」措辞（冲突源在位）', () {
      // 若将来 L1 改写去掉了这句，整个冲突域随之消失 ⇒ 本护栏应整体失效。
      // 故先钉住冲突源本身仍在，避免"冲突已解但护栏还在报"或反之。
      final src = _src('lib/services/skill_dispatcher.dart');
      expect(
        src.contains('可能是作者有意的选择'),
        isTrue,
        reason:
            'L1 边界句（_kPromptBoundary）仍含「可能是作者有意的选择」倾向多报措辞；'
            '若已改写，本护栏的冲突域清单须整体复核',
      );
      expect(
        src.contains('对结构层判断'),
        isTrue,
        reason:
            'L1 那句自限作用域为「结构层判断」——这是本护栏划定冲突域的依据；'
            '若作用域被改（如扩到全部类型），冲突域清单须重算',
      );
    });

    test('#3 冲突域清单：18 个结构层 ID，其中 9 个同时含「不得报」条款', () {
      final parsed = _parseFewShotSource();
      final structural = <String>[];
      final withClause = <String>[];

      for (final id in parsed.keys) {
        if (!_isStructural(id)) continue;
        structural.add(id);
        if (_hasNoReportClause(parsed[id]!, id)) withClause.add(id);
      }
      structural.sort();
      withClause.sort();

      expect(
        structural,
        <String>[
          'P002',
          'P003',
          'P004',
          'P005',
          'P010',
          'P011',
          'P012',
          'P013',
          'P014',
          'P015',
          'P016',
          'P017',
          'P022',
          'P023',
          'P027',
          'P033',
          'P034',
          'P037',
        ],
        reason:
            'few-shot 库中属于结构层的 ID 集合。改动 few-shot 库的 key 集合时，'
            '须同步复核本清单——新增结构层 ID 会让本断言变红，这是预期行为',
      );

      expect(
        withClause,
        <String>[
          'P003',
          'P013',
          'P014',
          'P017',
          'P023',
          'P027',
          'P033',
          'P034',
          'P037',
        ],
        reason:
            '★ 真实冲突域（2026-10-05 实测）：这 9 个 ID 既落在 L1「结构层判断」作用域内，'
            '其 few-shot 段落又写了「不得报」。本清单是本护栏的核心产物——'
            '任何一条新增的划界块若落在结构层、或任一结构层 ID 被移出，'
            '都会让本断言变红，从而阻止冲突域静默扩大/缩小',
      );
    });

    test('#4 冲突域的每一项都真实含「不得报 <自身ID>」（排除「张冠李戴」）', () {
      final parsed = _parseFewShotSource();
      const conflict = <String>[
        'P003',
        'P013',
        'P014',
        'P017',
        'P023',
        'P027',
        'P033',
        'P034',
        'P037',
      ];
      for (final id in conflict) {
        final body = parsed[id]!;
        expect(
          body,
          contains('不得报 $id'),
          reason:
              '$id 被列入冲突域的依据是它自己写了「不得报 $id」；'
              '若该措辞变了而清单未变，说明清单已失真',
        );
      }
    });

    test('#5 非结构层的「不得报」条款不算冲突（P029 等属此列）', () {
      // 这一条是本轮的自纠错锚点：2026-10-05 首轮侦察曾把 P029 当作
      // 「L1 与 few-shot 冲突」的例证，但 P029 属 motivationDeficit，
      // 不在 L1 那句自限的「结构层判断」作用域内 ⇒ 不构成冲突。
      // 本断言把该结论钉死，避免下一轮又把它当成冲突案例引用。
      final parsed = _parseFewShotSource();
      for (final id in <String>['P029', 'P025', 'P026', 'P030', 'P036']) {
        expect(
          _hasNoReportClause(parsed[id]!, id),
          isTrue,
          reason: '$id 应含「不得报」条款（其自身划界块存在）',
        );
        expect(
          _isStructural(id),
          isFalse,
          reason:
              '$id 属非结构层 ⇒ 不在 L1「结构层判断」作用域内 ⇒ '
              '其「不得报」条款与 L1 不构成方向冲突',
        );
      }
    });
  });

  group('L3 知识源覆盖（同一 ID 在不同源的方向一致性前提）', () {
    test('#6 L3 训练知识零「不得报」条款（实测：例外条款只存在于 few-shot 与手册）', () {
      // 实测读数（2026-10-05）：training_kb_content*.dart 五个分片里
      // 「不得报」出现次数为 0。若将来开始写入，此断言变红提醒复核
      // 「同一 ID 在三源是否同向」。
      var hits = 0;
      for (final f in <String>[
        'lib/services/training_kb_content.dart',
        'lib/services/training_kb_content_1.dart',
        'lib/services/training_kb_content_2.dart',
        'lib/services/training_kb_content_3.dart',
        'lib/services/training_kb_content_4.dart',
      ]) {
        final s = _src(f);
        for (final m in kNoReportMarkers) {
          hits += m.allMatches(s).length;
        }
      }
      expect(
        hits,
        0,
        reason:
            'L3 训练知识实测 0 处「不得报」条款；'
            '若开始写入，须复核它与 few-shot / 手册的方向是否一致',
      );
    });

    test('#7 L3 手册逐段解析：34 个 ID 段落内含「未命中」负例', () {
      // ★ 判据纪律：必须**逐 ID 段**解析。若只在整文件里搜「未命中」，
      //   则该文件任意一段出现一次就会让全部 ID 都算命中 ⇒ 断言恒真 = 假绿。
      //   本断言的正对照：#7b 反向检查实测**不含**负例的 ID。
      // ★ 本清单由 Python 侧独立复算校对过一次（Dart 跑不起来时的对账手段），
      //   初稿曾误把 P018 列入 —— 实测 P018 段无「未命中」，故不在此列。
      final neg = <String>[];
      for (final seg in _manualSegments()) {
        if (seg.body.contains('未命中')) neg.add(seg.id);
      }
      neg.sort();
      expect(
        neg,
        <String>[
          'P001',
          'P002',
          'P003',
          'P004',
          'P005',
          'P007',
          'P008',
          'P009',
          'P010',
          'P011',
          'P012',
          'P014',
          'P015',
          'P016',
          'P017',
          'P019',
          'P020',
          'P021',
          'P022',
          'P023',
          'P024',
          'P025',
          'P026',
          'P027',
          'P028',
          'P029',
          'P030',
          'P031',
          'P032',
          'P033',
          'P034',
          'P035',
          'P036',
          'P037',
        ],
        reason:
            'L3 手册内含「未命中」负例段的 ID 全集（实测 34 个）。'
            '逐项列出而非只比长度：这样哪一条被增删会直接显示在 diff 里',
      );
    });

    test('#7b 正对照：P013/P018 段落内**不含**「未命中」负例段', () {
      // 给 #7 装一颗正对照：证明解析器确实会区分「有」与「没有」，
      // 而不是在恒真地全判命中。
      final segs = _manualSegments();
      for (final id in <String>['P013', 'P018']) {
        final seg = segs.firstWhere(
          (s) => s.id == id,
          orElse: () => _Seg(id, ''),
        );
        expect(
          seg.body.contains('未命中'),
          isFalse,
          reason:
              '$id 实测不含「未命中」负例段。若此断言变红，说明手册补了该段'
              '——请一并复核 #7 清单',
        );
      }
    });

    test('#8 ★ P018 空例外清单已修（删空标题，「外部佐证」段保留）', () {
      // 【历史】本条最初是**实测发现的真实缺陷探测**（2026-10-05 护栏施工时），
      // 原读数为红，位置：`lib/services/syndrome_kb_content_manual_3.dart` 的
      // `### P018 重复用词/基础语病` 段内 —— 那里写了
      //   「**例外情况**（以下场景通常不是基础语病）：」
      // 而该标题之下**只有一段「外部佐证」**（讲的是判据外部规范来源，
      // A-15/B-8 与 P018 同轴），**没有一条「以下场景不是 P018」的条目**。
      // ⇒ 模型在此被承诺了一份例外清单，实际拿到 0 条；而 few-shot 侧 P018
      //   又写了「不要报 P018」（把问题指给 P034），两侧拼起来是
      //   「有例外但不给内容」。属「规格里写了却不可达」——
      //   与 .ai/DECISIONS.md 记录的「无条件/恰/必须 需附能变红的判据」同类。
      //
      // 【已裁定并落地 2026-10-06】取**选项 2：删掉那个空标题**。
      //   理由：P018 判据已窄（判式是「删掉它是否还成立」），例外清单的边际
      //   价值低于其它 ID；补内容 = 新造一条未验证的判断边界，风险更高。
      //   manual_3.dart 内该标题已删，**「外部佐证」段原样保留**。
      //
      // 【本断言方向已反转】由「标题必须存在且含锚点样例」改为「不得再出现
      //   空承诺标题」。理由：缺陷已修，若仍钉「必须存在」就是拿一条已作废的
      //   判据挡住正确修复（§4-172 同族：退役前须分清守的是事件还是性质）。
      //   但**只钉「标题没了」太弱**——把全仓 37 份标题一起删掉它照样绿，
      //   故必须配**跨分片负对照**。
      final seg = _manualSegments().firstWhere((s) => s.id == 'P018');

      // 正向 1：空承诺标题已删
      expect(
        seg.body.contains('例外情况'),
        isFalse,
        reason:
            'P018 段不应再含「例外情况」标题——它曾承诺一份 0 条的例外清单'
            '（标题之下只有一段讲判据来源的「外部佐证」）。若确为 P018 补上了'
            '带锚点样例（> 原文 / 判定：）的例外条目，请连带恢复标题，'
            '并把本断言改回「标题必须存在且含锚点样例」',
      );

      // 正向 2：删标题不得连带删掉「外部佐证」（判据来源是独立信息）
      expect(
        seg.body.contains('外部佐证'),
        isTrue,
        reason: '删「例外情况」标题时不得连带删掉「外部佐证」段（判据外部来源）',
      );

      // 负对照：跨分片取确实带真实例外清单的两个 ID
      // （P003 在 manual_1、P034 在 manual_6，避免单文件偶然）
      for (final id in const <String>['P003', 'P034']) {
        final other = _manualSegments().firstWhere((s) => s.id == id);
        expect(
          other.body.contains('例外情况'),
          isTrue,
          reason:
              '$id 段含真实的「例外情况」清单。本条是 #8 的负对照：'
              '若把全仓 37 份标题一起删掉，#8 不该变绿',
        );
      }
    });
  });
}
