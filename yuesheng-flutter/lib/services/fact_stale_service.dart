// ─────────────────────────────────────────────────────────────
// FactStaleService — C78 批次2a「幽灵事实」治理
//
// 病根：character_fact / event_fact 的外键挂在 manuscript_id 上而非章节
// （tables.dart:512 / :548），删章节对它们零连带影响 → 从被删章节抽出的
// 断言变成「幽灵」，继续参与 F05 时序矛盾 / F07 因果链断裂检测，给用户报
// 一些根本不存在的矛盾。
//
// 对策：
//   ① 抽取时记录章节内容指纹 chapterHash（D-6）
//   ② 章节被删（软删/彻底删/硬删/删卷）→ 该章事实标 stale
//   ③ 重诊时旧指纹的事实标 stale
//   ④ 用户可在角色标签页「清除本章旧版断言」（clearStaleChapter，批次3 接线）
//
// 依赖方向（决策1）：本类**只**依赖 AppDatabase（依赖链最底层），不 import
// 任何 repository / service。项目 tool/circular_baseline.json 为空——门禁3
// 是全量卡口，本批必须零新增环；依赖链 chapter_repository → 本类 →
// database.dart 单向，database.dart 不可能反向 import services。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/database/database.dart';
import '../data/database/utils.dart';
import '../types/character_types.dart';

/// 人物/事件事实的 stale（旧版）标记与清理。
class FactStaleService {
  FactStaleService(this._db);

  final AppDatabase _db;

  /// 决策4 并集判据：该断言是否「属于这一章」
  ///
  /// 并集 = (指纹命中) ∪ (章号命中)。理由：CharacterAssertion.chapter 是
  /// **AI 自报值**，写入路径既不校验也不覆写（tryFromJson 直接穿透），只按
  /// 章号匹配会漏掉 AI 报错章号的断言；chapterHash 按章节正文算、与 AI 自报
  /// 无关。两支取并集才补得上。
  static bool belongsToChapter(
    CharacterAssertion a,
    int chapterNo,
    String chapterHash,
  ) {
    return (a.chapterHash != null && a.chapterHash == chapterHash) ||
        a.chapter == chapterNo;
  }

  /// 三元组键：(attribute, value, chapter)——同三元组的断言视为同一条事实。
  static String tripleKey(CharacterAssertion a) {
    return '${a.attribute}\u0000${a.value}\u0000${a.chapter}';
  }

  /// 缺表守卫（C78 批次2a）——复用 [AppDatabase.tableExists]。
  ///
  /// **为何会缺表**：character_fact / event_fact 是 **v16 / v17** 才建的表
  /// （database.dart:467 / :489），而最小 schema 的存量库（迁移测试用的
  /// v23 / v24 库只有 manuscripts / volumes / chapters 三张表）在升级时
  /// `if (from < 16)` 被跳过 → 这两张表**永远补不上**。
  ///
  /// **为何必须守卫而非任其抛出**：钩子是删除动作的**前置步骤**，一抛异常就
  /// 阻断主流程——softDeleteChapter 的 update 根本执行不到，deleteChapter /
  /// purgeChapter 在事务里直接回滚。用户点「删除章节」却因一张辅助表缺失而
  /// 删不掉，是**职责倒置**。缺表时「无事可标」才是正确语义。
  ///
  /// 只认「表不存在」这一种降级；其余异常照常抛出——不用 try/catch 兜一切，
  /// 否则会把 JSON 解析失败之类的真错误一并吞掉（R-028 禁止无痕静默）。
  Future<bool> _hasCharacterTable() => _db.tableExists('character_fact');

  Future<bool> _hasEventTable() => _db.tableExists('event_fact');

  /// 章节删除钩子：把「属于这一章」的断言 + 事件同标 stale。
  ///
  /// 调用方必须在删除/更新动作**之前**调（删完章节行就没了，拿不到
  /// manuscriptId / sortOrder / content 三要素）。
  Future<void> markChapterStale({
    required String manuscriptId,
    required int chapterNo,
    required String chapterHash,
  }) async {
    if (await _hasCharacterTable()) {
      await _markAssertions(manuscriptId, chapterNo, chapterHash, keep: true);
    }
    if (await _hasEventTable()) {
      await (_db.update(_db.eventFacts)..where(
            (t) =>
                t.manuscriptId.equals(manuscriptId) &
                (t.chapterHash.equals(chapterHash) |
                    t.chapter.equals(chapterNo)),
          ))
          .write(
            // event_fact.stale 是 **int**（SQLite 布尔惯例），不是 bool。
            EventFactsCompanion(
              stale: const Value(1),
              updatedAt: Value(nowSec()),
            ),
          );
    }
  }

  /// 清除该章的 stale 事实——**删除**而非取消标记。
  ///
  /// 仅用户发起时调用（批次3 UI「清除本章旧版断言」接线，本批只提供能力）。
  Future<void> clearStaleChapter({
    required String manuscriptId,
    required int chapterNo,
    String? chapterHash,
  }) async {
    if (await _hasCharacterTable()) {
      await _markAssertions(manuscriptId, chapterNo, chapterHash, keep: false);
    }
    if (await _hasEventTable()) {
      await (_db.delete(_db.eventFacts)..where(
            (t) =>
                t.manuscriptId.equals(manuscriptId) &
                t.stale.equals(1) &
                (chapterHash == null
                    ? t.chapter.equals(chapterNo)
                    : t.chapter.equals(chapterNo) |
                          t.chapterHash.equals(chapterHash)),
          ))
          .go();
    }
  }

  /// 重诊路径：把该章**旧指纹**的事件标 stale。
  ///
  /// 与 [markChapterStale] 的删除钩子判据**不同**：删除是「这一章没了」→
  /// 用并集；重诊是「这一章内容变了」→ 只认「章号命中 且 有旧指纹 且 指纹
  /// 已变」。决策2：chapterHash == null 的存量行**不碰**。
  Future<void> markStaleEvents({
    required String manuscriptId,
    required int chapterNo,
    required String chapterHash,
  }) async {
    if (!await _hasEventTable()) return;
    await (_db.update(_db.eventFacts)..where(
          (t) =>
              t.manuscriptId.equals(manuscriptId) &
              t.chapter.equals(chapterNo) &
              t.chapterHash.isNotNull() &
              t.chapterHash.equals(chapterHash).not(),
        ))
        .write(
          EventFactsCompanion(
            stale: const Value(1),
            updatedAt: Value(nowSec()),
          ),
        );
  }

  /// 三元组合并（决策2 / 决策3）——静态纯函数，不碰数据库，便于单测。
  ///
  /// [currentHash] 或 [chapterNo] 为空 → 退化成**旧行为**（按三元组去重、
  /// 先出现者胜，不填指纹、不标 stale）：保护本批未接线的调用点。
  ///
  /// 三条规则（按 (attribute, value, chapter) 三元组比对）：
  ///   (a) 三元组命中 → **用新断言替换旧的，不标 stale**。理由：AI 改写后重新
  ///       抽出同一三元组，说明该断言改写后仍成立；若标旧为 stale 而新断言又
  ///       被去重吃掉，会出现「断言仍在却永远灰显」的错误态。
  ///   (b) 三元组命中且**既有**断言 status=='rejected' 或 source=='user' →
  ///       **保留既有、丢弃 AI 新断言**（R-009 用户主权，最高优先，**优先于
  ///       (a)**）：AI 重复抽取不得复活已被用户拒绝的断言，也不得覆盖用户
  ///       手写值。
  ///   (c) incoming 一律填 chapterHash=[currentHash]——手动补充的断言同理，
  ///       与 AI 断言统一 stale 规则，避免「手写断言永不灰显」的双重标准。
  ///
  /// **决策2（偏离 ADR 字面，刻意如此）**：既有断言 chapterHash == null 的
  /// **一律不标 stale**。若放宽成「null 也标」，v27 升级后第一次重诊会把所有
  /// 存量断言（它们 chapterHash 全是 null）集体误标，用户会看到全部断言一夜
  /// 变灰——误伤代价远大于漏标代价。这是**渐进生效**设计：升级后新抽的断言
  /// 才带 chapterHash，从那时起 stale 机制才开始工作；存量断言靠两条路径
  /// 消化——被新断言按三元组替换（规则 a），或由章节删除钩子标记（决策4）。
  static List<CharacterAssertion> mergeAssertions(
    List<CharacterAssertion> existing,
    List<CharacterAssertion> incoming,
    String? currentHash, {
    int? chapterNo,
  }) {
    final result = <CharacterAssertion>[];
    if (currentHash == null || chapterNo == null) {
      final seen = <String>{};
      for (final a in [...existing, ...incoming]) {
        if (seen.add(tripleKey(a))) result.add(a);
      }
      return result;
    }
    final incomingKeys = incoming.map(tripleKey).toSet();
    final kept = <String>{};
    for (final e in existing) {
      final key = tripleKey(e);
      if (incomingKeys.contains(key)) {
        // (b) 用户裁决优先（保留既有）；否则 (a) 让 incoming 顶替，此处不输出。
        if (e.status == 'rejected' || e.source == 'user') {
          kept.add(key);
          result.add(e);
        }
        continue;
      }
      // stale 必须限定在同章内：否则重诊第 3 章时，第 5 章抽出来的断言
      // （哈希必然是第 5 章的）会被全库误伤。
      final outdated =
          e.chapterHash != null &&
          e.chapterHash != currentHash &&
          e.chapter == chapterNo;
      result.add(outdated ? e.withStaleMark(stale: true) : e);
    }
    for (final a in incoming) {
      if (kept.contains(tripleKey(a))) continue;
      result.add(a.withStaleMark(chapterHash: currentHash, stale: false));
    }
    return result;
  }

  /// 遍历该作品全部人物行，按并集判据处理属于该章的断言。
  ///
  /// [keep] = true → 标 stale（删除钩子）；false → 从列表里删除（用户清除）。
  Future<void> _markAssertions(
    String manuscriptId,
    int chapterNo,
    String? chapterHash, {
    required bool keep,
  }) async {
    final rows = await (_db.select(
      _db.characterFacts,
    )..where((t) => t.manuscriptId.equals(manuscriptId))).get();
    for (final row in rows) {
      final list = _parse(row.assertions);
      if (list.isEmpty) continue;
      var changed = false;
      final next = <CharacterAssertion>[];
      for (final a in list) {
        final hit = chapterHash == null
            ? a.chapter == chapterNo
            : belongsToChapter(a, chapterNo, chapterHash);
        if (hit && (keep ? !a.stale : a.stale)) {
          // 单独记账 changed：keep=true 时是原地标 stale，条目数不变；
          // 不能用「长度变了」来判断是否需要写回。
          changed = true;
          if (keep) next.add(a.withStaleMark(stale: true));
        } else {
          next.add(a);
        }
      }
      if (!changed) continue;
      await (_db.update(
        _db.characterFacts,
      )..where((t) => t.id.equals(row.id))).write(
        CharacterFactsCompanion(
          assertions: Value(jsonEncode(next.map((a) => a.toJson()).toList())),
          updatedAt: Value(nowSec()),
        ),
      );
    }
  }

  static List<CharacterAssertion> _parse(String raw) {
    return parseJsonList<CharacterAssertion>(
      raw,
      const <CharacterAssertion>[],
      CharacterAssertion.fromDbJson,
    ).where((a) => a.attribute.isNotEmpty && a.value.isNotEmpty).toList();
  }
}
