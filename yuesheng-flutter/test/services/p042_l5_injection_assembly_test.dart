// ─────────────────────────────────────────────────────────────
// P042 L5 症候「注入装配面」行为采样 — 补缺口 G8
//
// 缺口真源：.ai/reports/2026-09-17-module-gap-audit.md:96
//   「P042 L5 症候真机行为未采样」→ 建议「L5 注入行为采样」。
//
// 采样口径（与「词条级」锚点互补，不是重复）：
//   test/snapshots/l3_entry_anchor.json 只冻结 getSyndromeContent(['P042']) 的
//   字节指纹；本测试冻结的是「P042 作为教学焦点被选中时，**装配函数实际吐出的
//   注入文本**里那一段」——即把真实装配结果切出来，再与冻结锚点逐字节比对。
//   路径：ActiveSyndromeView(P042) → buildStructuredSyndromeContext(...)
//         → _buildFocusSyndromeSection → getSyndromeContent(['P042'])
//
// 锚点纪律（硬约束）：
//   本文件**只读** test/snapshots/l3_entry_anchor.json（readAsStringSync），
//   绝不写入 / 重生成 / 追加任何快照文件，也不向既有锚点测试加 case。
//
// 术语澄清：P042 词条正文里的 L1 / L2 / L3 是 **severity（严重度）**，
//   不是 SkillLevel；P042 的 SkillLevel 是 l5（syndrome_registry.dart:844）。
//   故本文件不断言词条文本内含「L5」。
//
// 用法：flutter test test/services/p042_l5_injection_assembly_test.dart
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
// FocusSource 在 chat_context_builder 与 focus_resolver 各有一份同名不同定义，
// 故 focus_resolver 走前缀别名，避免撞名。
import 'package:writingcoach/services/focus_resolver.dart' as fr;
import 'package:writingcoach/services/syndrome_skill_types.dart';
import 'package:writingcoach/types/teaching_types.dart';

const String kL3AnchorPath = 'test/snapshots/l3_entry_anchor.json';

/// L3 知识库 header（syndrome_knowledge_base.dart:46-47 的逐字形态）。
const String kKbHeader = '## 活跃症候详细定义（系统注入，学员不可见）';

/// P042 词条三级标题（syndrome_kb_content_manual_6.dart:270）。
const String kP042EntryTitle = '### P042 声线漂移症';

/// P042 词条正文的**尾行**（syndrome_kb_content_manual_6.dart:310）。
const String kP042TailSentence = '**推荐教学动作**：首选 A009 节奏变速，备选 A016 高频词清扫';

/// 词条切出的**完整**右边界：`_extractSyndromeSection`
/// （syndrome_knowledge_base.dart:23-37）只切到下一个 `## ` 标题（此处是
/// 手册的「## 症候类型速查」），故尾行与它之间的 `---` 分隔符**仍留在词条内**。
/// 作为切片右边界时，边界由实际装配文本自己给出，不依赖锚点 len。
const String kP042BlockEnd = '$kP042TailSentence\n\n---';

/// FNV-1a 64 位指纹（与 test/services/l3_entry_anchor_test.dart:39-49 同款）。
int _fnv1a64(String s) {
  // FNV-1a 64 位偏移基数（14695981039346656037）。项目仅发布 Android、不编译 JS，
  // VM 上 int 即 64 位；改用 BigInt 会改变哈希值 ⇒ 锚点快照全量失配，故保留字面量。
  // ignore: avoid_js_rounded_ints
  var h = 0xcbf29ce484222325;
  for (final cu in s.codeUnits) {
    h ^= cu;
    h *= 0x100000001b3;
  }
  return h & 0x7fffffffffffffff;
}

/// 从冻结锚点读 P042 词条的 (len, fnv)。**只读**，不写回。
({int len, String fnv}) _p042Anchor() {
  final stored = jsonDecode(File(kL3AnchorPath).readAsStringSync()) as Map;
  final syndrome = stored['syndrome'] as Map;
  final entry = syndrome['P042'] as Map;
  return (len: entry['len'] as int, fnv: entry['fnv'] as String);
}

/// 从**实际装配结果**里切出注入的 P042 L3 段（KB header 起 → 词条尾行止）。
///
/// 刻意不直接调 getSyndromeContent 当结果——那是同义反复，采不到「装配」这一环。
String _extractInjectedP042Block(String assembled) {
  final start = assembled.indexOf(kKbHeader);
  expect(
    start,
    greaterThanOrEqualTo(0),
    reason: '装配结果未含 L3 KB header（$kKbHeader）',
  );
  final end = assembled.indexOf(kP042BlockEnd, start);
  expect(
    end,
    greaterThanOrEqualTo(0),
    reason: '装配结果未含 P042 词条尾边界锚点（$kP042TailSentence + ---）',
  );
  return assembled.substring(start, end + kP042BlockEnd.length);
}

/// 构造 P042 活跃症候视图（focus 装配面输入）。
ActiveSyndromeView _p042View() => const ActiveSyndromeView(
  syndromeId: 'P042',
  syndromeName: '声线漂移症',
  severity: Severity.l3,
  confirmationStatus: ConfirmationStatus.confirmed,
);

void main() {
  group('P042 L5 症候注入装配采样（只读消费锚点）', () {
    test('正例：P042 为 focus 时装配结果含冻结词条，且与锚点 len/fnv 一致', () {
      final assembled = buildStructuredSyndromeContext(
        [_p042View()],
        activeFocus: const ActiveFocusContext(
          focusId: 'P042',
          source: FocusSource.aiSuggested,
          reason: 'P042 为当前教学焦点（L5 症候装配采样）',
        ),
      );

      // 1) 走的是 focus 完整注入分支（而非非 focus 概览行）
      expect(assembled, contains('### ★ 当前教学焦点 P042 声线漂移症'));
      // 2) 词条本体确实出现在装配结果里
      expect(assembled, contains(kP042EntryTitle));
      // 3) 可选：KB header 形态存在
      expect(assembled, contains(kKbHeader));

      // 4) 把装配结果里的那一段切出来，与冻结锚点逐字节比对
      final block = _extractInjectedP042Block(assembled);
      final anchor = _p042Anchor();
      expect(
        block.length,
        anchor.len,
        reason: '装配出的 P042 段长度与 l3_entry_anchor.json 冻结值不一致',
      );
      expect(
        _fnv1a64(block).toRadixString(16),
        anchor.fnv,
        reason: '装配出的 P042 段 FNV-1a 指纹与 l3_entry_anchor.json 冻结值不一致',
      );
    });

    test('负例 A：focus 换成 P041 时，装配结果不含 P042 词条', () {
      final assembled = buildStructuredSyndromeContext(
        const [
          ActiveSyndromeView(
            syndromeId: 'P041',
            syndromeName: '降智反派症',
            severity: Severity.l3,
            confirmationStatus: ConfirmationStatus.confirmed,
          ),
        ],
        activeFocus: const ActiveFocusContext(
          focusId: 'P041',
          source: FocusSource.aiSuggested,
          reason: '对照组：焦点换成 P041',
        ),
      );

      // 先证明装配确实产出了内容（防「空字符串上的负断言」假绿）
      expect(assembled, contains('### ★ 当前教学焦点 P041 降智反派症'));
      expect(assembled, contains(kKbHeader));
      // 再断言 P042 词条不出现
      expect(assembled, isNot(contains(kP042EntryTitle)));
      expect(assembled, isNot(contains(kP042TailSentence)));
    });

    test('负例 B：症候列表为空时，装配结果不含 P042 词条', () {
      final assembled = buildStructuredSyndromeContext(
        const [],
        activeFocus: const ActiveFocusContext(
          focusId: null,
          source: FocusSource.none,
          reason: '无活跃症候',
        ),
      );

      // 防假绿：空症候也要产出 header
      expect(assembled, contains('## 活跃症候概览（未激活教学焦点）'));
      expect(assembled, isNot(contains(kP042EntryTitle)));
      expect(assembled, isNot(contains(kP042TailSentence)));
    });

    test('L5 链路：resolveTeachingFocus(L5 学员) 选中 P042 → 装配含冻结词条', () {
      final resolved = fr.resolveTeachingFocus(
        fr.ResolveFocusInput(
          problems: [
            const FocusProblem(
              syndromeId: 'P042',
              syndromeName: '声线漂移症',
              severity: Severity.l3,
              confirmationStatus: ConfirmationStatus.confirmed,
              status: 'active',
              confirmedAt: 1,
            ),
          ],
          aiSuggestedFocusId: null,
          userFocusOverride: null,
          subphase: null,
          focusHistory: const [],
          studentSkillLevel: SkillLevel.l5,
        ),
      );

      expect(
        resolved.activatedFocusId,
        'P042',
        reason: 'L5 学员下 fallback 应选中唯一活跃症候 P042（reason=${resolved.reason}）',
      );

      final assembled = buildStructuredSyndromeContext(
        [_p042View()],
        activeFocus: ActiveFocusContext(
          focusId: resolved.activatedFocusId,
          source: FocusSource.fallback,
          reason: resolved.reason,
        ),
      );
      expect(assembled, contains(kP042EntryTitle));
      final block = _extractInjectedP042Block(assembled);
      final anchor = _p042Anchor();
      expect(block.length, anchor.len);
      expect(_fnv1a64(block).toRadixString(16), anchor.fnv);
    });
  });
}
