// ─────────────────────────────────────────────────────────────
// CharacterEditorService — C78 批次3：断言级人工裁决（UI 后端）
//
// 职责：角色详情页的四个写入动作——拒绝 / 修正 / 补充 / 别名编辑。
// 刻意独立成类（真分解，非 part/extension 拆分）：CharacterFactRepository
// 已 285 行，AI 写入路径（upsert）与人工裁决（断言级改写）是两条职责线；
// 与 FactStaleService 同模式（持 AppDatabase 直接操作 character_fact 行）。
//
// 断言同一性判据：[FactStaleService.tripleKey]（attribute+value+chapter）
// + timestamp。仅 tripleKey 会误伤「同章同属性被 AI 先后报过两个不同值、
// 之后又报回旧值」的场景——timestamp 是落库唯一瞬间，组合后唯一。
//
// R-009 边界：修正 / 补充均为**纯手动输入**（属性、值、章节全部由用户填），
// 本服务不提供任何「建议值」；AI 重复抽取不得复活被拒断言——mergeAssertions
// 规则 (b) 已在写入侧兜住（rejected / user 三元组命中即保留既有）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';

import '../data/database/database.dart';
import '../data/database/utils.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/character_fact_repository.dart';
import '../types/character_types.dart';
import 'fact_stale_service.dart';

/// 人物断言的人工裁决服务（拒绝 / 修正 / 补充 / 别名编辑）。
class CharacterEditorService {
  CharacterEditorService(this._db);

  final AppDatabase _db;

  /// 拒绝断言（D-7：理由 chips 可选不强制，[reason] 为 null = 直接拒绝）。
  ///
  /// 被拒断言保留在列表（灰显 + 删除线「已拒绝」），不参与 F05
  /// （detector 只消费 confirmed）；且不会被 AI 重抽复活（merge 规则 b）。
  Future<bool> rejectAssertion({
    required String characterId,
    required CharacterAssertion target,
    String? reason,
  }) {
    return _rewriteAssertions(characterId, (list) {
      return [
        for (final a in list)
          if (_sameAssertion(a, target))
            _withStatus(a, 'rejected', reason: reason)
          else
            a,
      ];
    });
  }

  /// 修正断言（FR-5）：原条标 rejected（留痕）+ 落一条 `source=user` 的新断言。
  ///
  /// 为什么自动拒绝原条：修正 = 用户已裁决该属性值，若原条留在 confirmed，
  /// 同章同属性两个 confirmed 值会立刻成为 F05 幽灵矛盾；拒绝留痕同时保住
  /// 「AI 原判 vs 用户修正」的证据链（D-4 事实可信）。
  Future<bool> correctAssertion({
    required String characterId,
    required CharacterAssertion target,
    required String newValue,
    int? chapter,
  }) async {
    if (newValue.trim().isEmpty) return false;
    final row = await _findById(characterId);
    if (row == null) return false;
    final finalChapter = chapter ?? target.chapter;
    final replaced = await _rewriteAssertions(characterId, (list) {
      return [
        for (final a in list)
          if (_sameAssertion(a, target)) _withStatus(a, 'rejected') else a,
      ];
    });
    if (!replaced) return false;
    return _appendUserAssertion(row, target.attribute, newValue, finalChapter);
  }

  /// 补充断言（FR-5 / R-009：纯手动，无 AI 代填建议值）。
  Future<bool> addUserAssertion({
    required String characterId,
    required String attribute,
    required String value,
    int? chapter,
  }) async {
    if (attribute.trim().isEmpty || value.trim().isEmpty) return false;
    final row = await _findById(characterId);
    if (row == null) return false;
    return _appendUserAssertion(row, attribute.trim(), value.trim(), chapter);
  }

  /// 编辑别名（FR-3 / V-05 #11 引用式副本语义）：整表写回，去重去空。
  ///
  /// 别名参与 F05 匹配（groupByIdentity 按「主名 ∪ 别名」并查集）与事件关联
  /// （filterEventsByIdentity 按 participants 命中），此处只管存储。
  Future<bool> updateAliases({
    required String characterId,
    required List<String> aliases,
  }) async {
    final cleaned = aliases.map((s) => s.trim()).where((s) => s.isNotEmpty);
    final unique = cleaned.toSet().toList();
    final updated =
        await (_db.update(
          _db.characterFacts,
        )..where((t) => t.id.equals(characterId))).write(
          CharacterFactsCompanion(aliases: Value(stringifyJson(unique))),
        );
    return updated > 0;
  }

  // ── 内部 ──

  /// 追加一条用户断言：confirmed / user / 带该章当前指纹（§5.1(c)，
  /// 与 AI 断言统一 stale 规则——手写断言也参与「章节改写 → 灰显」）。
  Future<bool> _appendUserAssertion(
    CharacterFact row,
    String attribute,
    String value,
    int? chapter,
  ) async {
    final hash = await _hashForChapter(row.manuscriptId, chapter);
    return _rewriteAssertions(row.id, (list) {
      return [
        ...list,
        CharacterAssertion(
          attribute: attribute,
          value: value,
          chapter: chapter,
          timestamp: nowSec(),
          status: 'confirmed',
          source: 'user',
          chapterHash: hash,
        ),
      ];
    });
  }

  /// 用户断言的章节指纹（§5.1(c)）；章号空 / 章节不存在 → null（不猜）。
  Future<String?> _hashForChapter(String manuscriptId, int? chapterNo) async {
    if (chapterNo == null) return null;
    final chapter = await ChapterRepository(
      _db,
    ).getChapterByOrder(manuscriptId, chapterNo);
    if (chapter == null) return null;
    return chapterFingerprint(chapter.content);
  }

  /// 读行 → 变换断言 → 写回；行不存在 / 无变化 / 无匹配 → false。
  Future<bool> _rewriteAssertions(
    String characterId,
    List<CharacterAssertion> Function(List<CharacterAssertion>) mutate,
  ) async {
    final row = await _findById(characterId);
    if (row == null) return false;
    final before = CharacterFactRepository.parseAssertions(row.assertions);
    final next = mutate(before);
    if (next.length == before.length && _identicalList(before, next)) {
      return false;
    }
    await (_db.update(
      _db.characterFacts,
    )..where((t) => t.id.equals(characterId))).write(
      CharacterFactsCompanion(
        assertions: Value(stringifyJson(next.map((a) => a.toJson()).toList())),
        updatedAt: Value(nowSec()),
      ),
    );
    return true;
  }

  /// 断言同一性：三元组 + timestamp（见类头注释）。
  bool _sameAssertion(CharacterAssertion a, CharacterAssertion target) {
    return FactStaleService.tripleKey(a) ==
            FactStaleService.tripleKey(target) &&
        a.timestamp == target.timestamp;
  }

  /// 状态改写（拒绝 / 修正留痕共用）。其余字段原样保留。
  CharacterAssertion _withStatus(
    CharacterAssertion a,
    String status, {
    String? reason,
  }) {
    return CharacterAssertion(
      attribute: a.attribute,
      value: a.value,
      chapter: a.chapter,
      timestamp: a.timestamp,
      status: status,
      source: a.source,
      evidence: a.evidence,
      chapterHash: a.chapterHash,
      stale: a.stale,
      rejectReason: reason ?? (status == 'rejected' ? a.rejectReason : null),
    );
  }

  /// 逐字段比较（拒绝等改写会替换对象实例，浅 equal 恒 false 会让
  /// 「重复拒绝同一断言」误判为有变化而空写一次）。
  bool _identicalList(List<CharacterAssertion> a, List<CharacterAssertion> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toJson().toString() != b[i].toJson().toString()) return false;
    }
    return true;
  }

  Future<CharacterFact?> _findById(String id) {
    return (_db.select(
      _db.characterFacts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }
}
