// ─────────────────────────────────────────────────────────────
// CharacterFactRepository — 人物知识 DAO（批次66 B62i / A6 首步）
// 作品级（manuscript_id 维度），严格复刻 yuesheng schema 惯例
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../services/fact_stale_service.dart';
import '../../types/character_types.dart';
import '../database/database.dart';
import '../database/utils.dart';

/// `character_fact.status` 仅两个取值（tables.dart:521 明列 `active | merged`）。
/// C78 §5.4：合并后的**源行**标 merged——留在库里，但不进列表、不参与检测。
const String _kActiveStatus = 'active';
const String _kMergedStatus = 'merged';

class CharacterFactRepository {
  final AppDatabase _db;
  CharacterFactRepository(this._db);

  /// 写入/更新人物（同作品内按 name 唯一，UNIQUE(manuscript_id, name)）
  ///
  /// 批次3-D2：assertions 增量合并，不覆盖历史断言。
  /// - insert：直接写入新断言
  /// - update：读取现有断言 → 与新断言按 (attribute, value, chapter) 去重合并 → 写回
  ///           firstSeenChapter / firstSeenAt 仅 insert 时设置，update 不覆盖
  ///
  /// C78 批次2a：[chapterHash] + [chapterNo] 同时给出才启用 stale 机制
  /// （填指纹 / 标旧版 / 三元组合并全部委托 [FactStaleService.mergeAssertions]）；
  /// 二者缺一即退化成批次3-D2 的纯三元组去重，保护未接线的调用点。
  Future<void> upsertCharacter({
    required String manuscriptId,
    required String name,
    int? firstSeenChapter,
    int? firstSeenAt,
    List<CharacterAssertion> assertions = const [],
    String? chapterHash,
    int? chapterNo,
  }) async {
    final now = nowSec();
    await _db.transaction(() async {
      final existing = await _findCharacter(manuscriptId, name);
      if (existing == null) {
        await _insertCharacter(
          manuscriptId: manuscriptId,
          name: name,
          firstSeenChapter: firstSeenChapter,
          firstSeenAt: firstSeenAt,
          assertions: assertions,
          chapterHash: chapterHash,
          chapterNo: chapterNo,
          now: now,
        );
      } else {
        await _updateCharacter(
          existing.id,
          name: name,
          existingAssertions: parseAssertions(existing.assertions),
          assertions: assertions,
          chapterHash: chapterHash,
          chapterNo: chapterNo,
          now: now,
        );
      }
    });
  }

  /// 按作品 + 姓名查既有人物（UNIQUE(manuscript_id, name)）。
  /// R-019：由 [upsertCharacter] 抽出（与 event_fact_repository 同构）。
  Future<CharacterFact?> _findCharacter(
    String manuscriptId,
    String name,
  ) async {
    return (_db.select(_db.characterFacts)..where(
          (t) => t.manuscriptId.equals(manuscriptId) & t.name.equals(name),
        ))
        .getSingleOrNull();
  }

  /// 新建人物。R-019：由 [upsertCharacter] 抽出（C78 批次2a）。
  Future<void> _insertCharacter({
    required String manuscriptId,
    required String name,
    required List<CharacterAssertion> assertions,
    required int now,
    int? firstSeenChapter,
    int? firstSeenAt,
    String? chapterHash,
    int? chapterNo,
  }) async {
    final merged = FactStaleService.mergeAssertions(
      const [],
      assertions,
      chapterHash,
      chapterNo: chapterNo,
    );
    await _db
        .into(_db.characterFacts)
        .insert(
          CharacterFactsCompanion.insert(
            id: generateUuid(),
            manuscriptId: manuscriptId,
            name: name,
            firstSeenChapter: Value(firstSeenChapter),
            firstSeenAt: Value(firstSeenAt),
            assertions: Value(_encodeAssertions(merged)),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  /// 更新既有人物（不覆盖 firstSeenChapter / firstSeenAt，保留首次出场信息）。
  /// R-019：由 [upsertCharacter] 抽出（C78 批次2a）。
  Future<void> _updateCharacter(
    String id, {
    required String name,
    required List<CharacterAssertion> existingAssertions,
    required List<CharacterAssertion> assertions,
    required int now,
    String? chapterHash,
    int? chapterNo,
  }) async {
    final merged = FactStaleService.mergeAssertions(
      existingAssertions,
      assertions,
      chapterHash,
      chapterNo: chapterNo,
    );
    await (_db.update(_db.characterFacts)..where((t) => t.id.equals(id))).write(
      CharacterFactsCompanion(
        name: Value(name),
        assertions: Value(_encodeAssertions(merged)),
        updatedAt: Value(now),
      ),
    );
  }

  /// 断言列表 → JSON 字符串。
  /// 填指纹 / 标 stale / 三元组合并全部由 [FactStaleService] 负责，此处只管序列化。
  static String _encodeAssertions(List<CharacterAssertion> list) {
    return jsonEncode(list.map((a) => a.toJson()).toList());
  }

  /// 列出作品下全部人物（按姓名排序）
  ///
  /// C78 §5.4（勘误3：本方法是**改造**不是新增——它本来就存在且已被
  /// `message_injector.dart:771` 调用）：加 [includeMerged] 可选参数，
  /// **默认排除 `status='merged'` 的合并源行**。合并后源行断言已拷进目标行，
  /// 一并取出会让 F05 检测双重计入（ADR §5.4）。
  /// 可选参数的好处：既有 7 处调用点（生产 1 + 测试 6）**零改动**自动获得
  /// 排除语义；要回溯源行时显式传 `true`。
  ///
  /// 注：drift 的 `where` 是 setter 不是追加，两次调用后者覆盖前者——
  /// 故过滤必须写在**同一个表达式**里，不能 if 里再 where 一次。
  Future<List<CharacterFact>> listCharacters(
    String manuscriptId, {
    bool includeMerged = false,
  }) async {
    return (_db.select(_db.characterFacts)
          ..where(
            (t) => includeMerged
                ? t.manuscriptId.equals(manuscriptId)
                : t.manuscriptId.equals(manuscriptId) &
                      t.status.equals(_kActiveStatus),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
  }

  /// 合并人物（C78 §5.4）：把源行并进目标行，事务内三步。
  ///
  /// ① 源行断言并入目标行（[FactStaleService.mergeForTransfer]，保 source）→
  /// ② 源名收进目标 aliases（去重，供 §5.4 事件按「主名 ∪ 别名」匹配）→
  /// ③ 源行置 `status='merged'`。
  ///
  /// **源行为什么是标记而不是物理删**（ADR 未写，按载体实测定的）：
  /// `character_fact` 表**没有** deleted_at / isDeleted 类软删列
  /// （tables.dart:506-534 全列实读），项目软删惯例本就是用 status 列标记
  /// （该列注释明写 `active | merged`，tables.dart:521；章节侧同理走
  /// softDeleteChapter + status）。物理删在此有三个实打实的代价：
  ///   1. 丢首次出场信息（firstSeenChapter / firstSeenAt / createdAt 一并没）；
  ///   2. UNIQUE(manuscript_id, name) 下源名立刻可被 AI 再次抽出重建 →
  ///      刚并上的两行又被拆开，合并功能形同无效，D-1 的别名价值一起没了；
  ///   3. 合并不可撤销——用户误并一次就永久丢数据（R-009）。
  /// 故沿用 D-6 的**标记制**：源行留在库里，只是不进列表、不参与检测。
  ///
  /// 边界防御（R-028）：同行 / 跨作品 / 任一行不存在 → 返回 false 且不落任何写，
  /// **不抛**——合并是辅助动作，不得因 id 失效把主流程打断（与批次2a
  /// 「辅助动作不得阻断主流程」同一条契约）。
  Future<bool> mergeCharacter({
    required String targetId,
    required String sourceId,
  }) async {
    if (targetId == sourceId) return false;
    return _db.transaction(() async {
      final target = await _findById(targetId);
      final source = await _findById(sourceId);
      if (target == null || source == null) return false;
      if (target.manuscriptId != source.manuscriptId) return false;
      final now = nowSec();
      await _mergeIntoTarget(target, source, now);
      await _markSourceMerged(source, now);
      return true;
    });
  }

  /// 获取单个人物
  Future<CharacterFact?> getCharacter(String manuscriptId, String name) async {
    return (_db.select(_db.characterFacts)..where(
          (t) => t.manuscriptId.equals(manuscriptId) & t.name.equals(name),
        ))
        .getSingleOrNull();
  }

  /// 按主键获取人物（批次3 详情页用：列表项携带的是 id，且合并后源行
  /// 可能是 merged 状态，按 name 查会与目标行别名重合）。
  Future<CharacterFact?> getCharacterById(String id) async {
    return (_db.select(
      _db.characterFacts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 解析人物的属性断言列表（JSON 非法 / 脏条目 → 保守跳过，不抛出）
  ///
  /// C78 批次2a：改走 [CharacterAssertion.fromDbJson]（原用 tryFromJson）。
  /// tryFromJson 是 **AI 协议** 解析入口，刻意不读 status / source /
  /// chapterHash / stale；但 DB 回读必须原样还原这些字段，否则 stale 标记
  /// 与用户裁决会在一次读写往返中丢失——批次1 遗留的潜伏缺陷。
  static List<CharacterAssertion> parseAssertions(String json) {
    return parseJsonList<CharacterAssertion>(
      json,
      const <CharacterAssertion>[],
      CharacterAssertion.fromDbJson,
    ).where((a) => a.attribute.isNotEmpty && a.value.isNotEmpty).toList();
  }

  /// 按主键取人物行（合并用：源行可能是 merged 状态，不能走 [getCharacter]
  /// 那种按 name 的查询——源名可能已与目标别名重合）。
  Future<CharacterFact?> _findById(String id) async {
    return (_db.select(
      _db.characterFacts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 合并第①②步：目标行吃进源行断言 + 源名（含源行自己的别名）。
  ///
  /// 断言走 [FactStaleService.mergeForTransfer]——**不是** mergeAssertions，
  /// 后者在合并场景下会丢掉源行里用户手改的断言（该处已实证并留注）。
  /// 别名用 LinkedHashSet 保插入序：先目标行原有的，再源名，再源行别名。
  Future<void> _mergeIntoTarget(
    CharacterFact target,
    CharacterFact source,
    int now,
  ) async {
    final assertions = FactStaleService.mergeForTransfer(
      parseAssertions(target.assertions),
      parseAssertions(source.assertions),
    );
    final aliases = <String>{
      ...parseJsonStringList(target.aliases),
      source.name,
      ...parseJsonStringList(source.aliases),
    }.toList();
    await (_db.update(
      _db.characterFacts,
    )..where((t) => t.id.equals(target.id))).write(
      CharacterFactsCompanion(
        assertions: Value(_encodeAssertions(assertions)),
        aliases: Value(jsonEncode(aliases)),
        updatedAt: Value(now),
      ),
    );
  }

  /// 合并第③步：源行标记为已并入（软删语义，理由见 [mergeCharacter]）。
  ///
  /// 源行断言**不清空**——标记制下它仍在库里，万一合并判据将来修正，
  /// 用户还有后悔药；且 F05 检测按 `listCharacters` 默认排除，不会双重计入。
  Future<void> _markSourceMerged(CharacterFact source, int now) async {
    await (_db.update(
      _db.characterFacts,
    )..where((t) => t.id.equals(source.id))).write(
      CharacterFactsCompanion(
        status: const Value(_kMergedStatus),
        updatedAt: Value(now),
      ),
    );
  }
}
