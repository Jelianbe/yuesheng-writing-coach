// ─────────────────────────────────────────────────────────────
// AppStateRepository — 应用状态 key-value DAO + 章节草稿 DAO
// 复刻 yuesheng-android/src/db/dao/basic-dao.ts 的 onboarding 部分
//          + yuesheng-android/src/db/dao/chapter-draft-dao.ts
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:ui' show Offset;
import 'package:drift/drift.dart';
import '../database/database.dart';
import '../database/utils.dart';
import '../../types/display_types.dart';
import '../../widgets/punctuation_bar.dart';

class AppStateRepository {
  final AppDatabase _db;
  AppStateRepository(this._db);

  // ════════════ Onboarding ════════════

  /// 获取引导轮播完成状态（用户级）
  /// 复刻 getOnboardingCompleted() — key='onboarding_completed'
  Future<bool> getOnboardingCompleted() async {
    final row = await (_db.select(
      _db.appStates,
    )..where((t) => t.key.equals('onboarding_completed'))).getSingleOrNull();
    return row?.value == 'true';
  }

  /// 设置引导轮播完成状态（用户级）
  /// 复刻 setOnboardingCompleted(completed)
  Future<void> setOnboardingCompleted(bool completed) async {
    await _db
        .into(_db.appStates)
        .insertOnConflictUpdate(
          AppStatesCompanion.insert(
            key: 'onboarding_completed',
            value: Value(completed ? 'true' : 'false'),
            updatedAt: Value(nowSec()),
          ),
        );
  }

  /// 获取问卷完成状态（用户级）— 批次1-8 波6
  /// key='questionnaire_completed'，与 onboarding_completed 区分：
  ///   - onboarding_completed：引导轮播（3页功能介绍）是否看过
  ///   - questionnaire_completed：写作偏好问卷（4级文本示例+提升方向+学习偏好）是否提交
  Future<bool> getQuestionnaireCompleted() async {
    final row = await (_db.select(
      _db.appStates,
    )..where((t) => t.key.equals('questionnaire_completed'))).getSingleOrNull();
    return row?.value == 'true';
  }

  /// 设置问卷完成状态（用户级）— 批次1-8 波6
  Future<void> setQuestionnaireCompleted(bool completed) async {
    await _db
        .into(_db.appStates)
        .insertOnConflictUpdate(
          AppStatesCompanion.insert(
            key: 'questionnaire_completed',
            value: Value(completed ? 'true' : 'false'),
            updatedAt: Value(nowSec()),
          ),
        );
  }

  // ════════════ 通用 key-value ════════════

  /// 读取 key-value
  Future<String?> getValue(String key) async {
    final row = await (_db.select(
      _db.appStates,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// 写入 key-value（INSERT OR REPLACE 语义）
  Future<void> setValue(String key, String value) async {
    await _db
        .into(_db.appStates)
        .insertOnConflictUpdate(
          AppStatesCompanion.insert(
            key: key,
            value: Value(value),
            updatedAt: Value(nowSec()),
          ),
        );
  }

  // ════════════ 章节草稿（复刻 chapter-draft-dao.ts） ════════════

  /// 获取章节草稿
  /// 复刻 getChapterDraft(chapterId) — key='chapter_draft:`<chapterId>`'
  Future<ChapterDraft?> getChapterDraft(String chapterId) async {
    final row =
        await (_db.select(_db.appStates)
              ..where((t) => t.key.equals('chapter_draft:$chapterId')))
            .getSingleOrNull();
    if (row == null) return null;

    try {
      final decoded = jsonDecode(row.value);
      if (decoded is Map<String, dynamic>) {
        return ChapterDraft(
          chapterId: decoded['chapterId'] as String? ?? chapterId,
          title: decoded['title'] as String? ?? '',
          content: decoded['content'] as String? ?? '',
          savedAt: decoded['savedAt'] as int? ?? row.updatedAt,
        );
      }
    } catch (_) {}
    return null;
  }

  /// 保存章节草稿
  /// 复刻 saveChapterDraft(chapterId, title, content)
  Future<void> saveChapterDraft(
    String chapterId,
    String title,
    String content,
  ) async {
    final draft = {
      'chapterId': chapterId,
      'title': title,
      'content': content,
      'savedAt': nowSec(),
    };
    await setValue('chapter_draft:$chapterId', jsonEncode(draft));
  }

  /// 清除章节草稿
  /// 复刻 clearChapterDraft(chapterId)
  Future<void> clearChapterDraft(String chapterId) async {
    await (_db.delete(
      _db.appStates,
    )..where((t) => t.key.equals('chapter_draft:$chapterId'))).go();
  }

  /// 是否有章节草稿
  /// 复刻 hasChapterDraft(chapterId)
  Future<bool> hasChapterDraft(String chapterId) async {
    final row =
        await (_db.select(_db.appStates)
              ..where((t) => t.key.equals('chapter_draft:$chapterId')))
            .getSingleOrNull();
    return row != null;
  }

  // ════════════ 评估报告持久化（批次4-M3） ════════════
  // key 规约：
  //   eval_round:`<sessionId>`           → 当前评估轮次（int 字符串）
  //   eval_report:`<sessionId>`:`<messageId>` → 单条评估报告 JSON

  /// 读取会话的当前评估轮次（无记录返回 0）
  Future<int> getEvaluationRound(String sessionId) async {
    final row = await (_db.select(
      _db.appStates,
    )..where((t) => t.key.equals('eval_round:$sessionId'))).getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? 0;
  }

  /// 写入会话的当前评估轮次
  Future<void> setEvaluationRound(String sessionId, int round) async {
    await setValue('eval_round:$sessionId', round.toString());
  }

  /// 保存单条评估报告（按 sessionId+messageId 唯一）
  Future<void> saveEvaluationReport(
    String sessionId,
    String messageId,
    EvaluationData data,
  ) async {
    await setValue('eval_report:$sessionId:$messageId', data.toJsonString());
  }

  /// 读取单条评估报告（无记录返回 null）
  Future<EvaluationData?> getEvaluationReport(
    String sessionId,
    String messageId,
  ) async {
    final json = await getValue('eval_report:$sessionId:$messageId');
    return EvaluationData.fromJsonString(json);
  }

  /// 读取会话全部评估报告（key 前缀匹配 eval_report:`<sessionId>`:）
  Future<Map<String, EvaluationData>> listEvaluationReports(
    String sessionId,
  ) async {
    final prefix = 'eval_report:$sessionId:';
    final rows = await (_db.select(
      _db.appStates,
    )..where((t) => t.key.like('$prefix%'))).get();
    final result = <String, EvaluationData>{};
    for (final row in rows) {
      final messageId = row.key.substring(prefix.length);
      final data = EvaluationData.fromJsonString(row.value);
      if (data != null) result[messageId] = data;
    }
    return result;
  }

  /// 删除单条评估报告
  Future<void> deleteEvaluationReport(
    String sessionId,
    String messageId,
  ) async {
    await (_db.delete(
      _db.appStates,
    )..where((t) => t.key.equals('eval_report:$sessionId:$messageId'))).go();
  }

  /// 清空会话全部评估报告（会话切换时调用）
  Future<void> clearEvaluationReports(String sessionId) async {
    final prefix = 'eval_report:$sessionId:';
    await (_db.delete(
      _db.appStates,
    )..where((t) => t.key.like('$prefix%'))).go();
    await (_db.delete(
      _db.appStates,
    )..where((t) => t.key.equals('eval_round:$sessionId'))).go();
  }

  // ════════════ 章节版本快照（批次82 P0 四件套之③ 时光机） ════════════
  // 对标橙瓜码字「时光机（每 100 字版本快照）」，本产品取每 200 字。
  // key 规约：chapter_versions:`<chapterId>` → JSON 数组（时间倒序存，最新在前）
  //   [{"savedAt":<unixSec>,"wordCount":<int>,"content":"<全文>"}, ...]

  /// 每章版本快照上限（超出丢弃最旧）
  static const int maxChapterVersions = 50;

  /// 版本快照间隔（每多少字落一次快照）
  static const int chapterVersionInterval = 200;

  /// 写入一章的版本快照（超出上限丢弃最旧）
  Future<void> addChapterVersion(String chapterId, String content) async {
    final versions = await listChapterVersions(chapterId);
    versions.insert(
      0,
      ChapterVersion(
        savedAt: nowSec(),
        wordCount: content.length,
        content: content,
      ),
    );
    if (versions.length > maxChapterVersions) {
      versions.removeRange(maxChapterVersions, versions.length);
    }
    await setValue(
      'chapter_versions:$chapterId',
      jsonEncode(versions.map((v) => v.toJson()).toList()),
    );
  }

  /// 读取一章的全部版本快照（新→旧）
  Future<List<ChapterVersion>> listChapterVersions(String chapterId) async {
    final json = await getValue('chapter_versions:$chapterId');
    if (json == null || json.isEmpty) return [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((e) => ChapterVersion.fromJson(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ════════════ 灵感随笔（批次84-1 灵感随笔） ════════════
  // 对标橙瓜「灵感随笔」：随手记不跳出写作上下文。
  // key 规约：inspirations → JSON 数组（时间倒序存，最新在前）
  //   [{"id":"<uuid>","content":"<文本>","manuscriptId":"<可选>",
  //     "chapterId":"<可选>","createdAt":<unixSec>}, ...]

  /// 灵感上限（超出丢弃最旧）
  static const int maxInspirations = 100;

  /// 写入一条灵感（最新在前，超出上限丢弃最旧）
  Future<void> addInspiration({
    required String content,
    String? manuscriptId,
    String? chapterId,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final inspirations = await listInspirations();
    inspirations.insert(
      0,
      WritingInspiration(
        id: generateUuid(),
        content: trimmed,
        manuscriptId: manuscriptId,
        chapterId: chapterId,
        createdAt: nowSec(),
      ),
    );
    if (inspirations.length > maxInspirations) {
      inspirations.removeRange(maxInspirations, inspirations.length);
    }
    await setValue(
      'inspirations',
      jsonEncode(inspirations.map((v) => v.toJson()).toList()),
    );
  }

  /// 读取全部灵感（新→旧）
  Future<List<WritingInspiration>> listInspirations() async {
    final json = await getValue('inspirations');
    if (json == null || json.isEmpty) return [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((e) => WritingInspiration.fromJson(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 删除一条灵感（批次87-4：灵感列表行尾删除）
  Future<void> removeInspiration(String id) async {
    final inspirations = await listInspirations();
    inspirations.removeWhere((e) => e.id == id);
    await setValue(
      'inspirations',
      jsonEncode(inspirations.map((v) => v.toJson()).toList()),
    );
  }

  // ════════════ 快捷短语（批次85-3 快捷短语） ════════════
  // 对标起点/笔落/灯果「快捷短语/常用语」：常用语管理 + 光标一键插入。
  // key 规约：quick_phrases → JSON 字符串数组（插入顺序，新加在末尾）
  //   ["短语1","短语2",...]

  /// 快捷短语上限（超出丢弃最早）
  static const int maxQuickPhrases = 30;

  /// 新增快捷短语（去重：已存在则忽略）
  Future<void> addQuickPhrase(String phrase) async {
    final trimmed = phrase.trim();
    if (trimmed.isEmpty) return;
    final phrases = await listQuickPhrases();
    if (!phrases.contains(trimmed)) {
      phrases.add(trimmed);
    }
    if (phrases.length > maxQuickPhrases) {
      phrases.removeRange(0, phrases.length - maxQuickPhrases);
    }
    await setValue('quick_phrases', jsonEncode(phrases));
  }

  /// 读取全部快捷短语（添加顺序）
  Future<List<String>> listQuickPhrases() async {
    final json = await getValue('quick_phrases');
    if (json == null || json.isEmpty) return [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return [];
      return decoded.whereType<String>().toList();
    } catch (_) {
      return [];
    }
  }

  /// 删除一条快捷短语
  Future<void> removeQuickPhrase(String phrase) async {
    final phrases = await listQuickPhrases();
    phrases.remove(phrase);
    await setValue('quick_phrases', jsonEncode(phrases));
  }

  // ════════════ 智能标点开关（批次87-4 低成本小项打包） ════════════
  // key 规约：smart_punctuation_enabled → '1'/'0'（默认开）

  /// 读取智能标点开关（默认开）
  Future<bool> getSmartPunctuationEnabled() async {
    final raw = await getValue('smart_punctuation_enabled');
    return raw != '0';
  }

  /// 保存智能标点开关
  Future<void> setSmartPunctuationEnabled(bool on) async {
    await setValue('smart_punctuation_enabled', on ? '1' : '0');
  }

  // ════════════ 写作菜单高度（批次96-7 拖拽调整篇幅） ════════════
  // key 规约：editor_menu_height → '0.55'（字符串小数，默认 0.55，clamp 0.30-0.85）
  // 写作页 ⋮ 更多菜单 DraggableScrollableSheet 拖拽调整后的高度占比（用户级记忆）

  /// 菜单高度阈值（与 WritingMenuSheet 三档吸附一致）
  static const double minEditorMenuHeight = 0.30;
  static const double maxEditorMenuHeight = 0.85;
  static const double defaultEditorMenuHeight = 0.55;

  /// 读取写作菜单高度占比（默认 0.55，范围 0.30-0.85）
  Future<double> getEditorMenuHeight() async {
    final raw = await getValue('editor_menu_height');
    if (raw == null) return defaultEditorMenuHeight;
    final v = double.tryParse(raw);
    if (v == null) return defaultEditorMenuHeight;
    return v.clamp(minEditorMenuHeight, maxEditorMenuHeight);
  }

  /// 保存写作菜单高度占比
  Future<void> setEditorMenuHeight(double value) async {
    final clamped = value.clamp(minEditorMenuHeight, maxEditorMenuHeight);
    await setValue('editor_menu_height', clamped.toStringAsFixed(2));
  }

  // ════════════ 回收板（批次86-1 回收板） ════════════
  // 对标写作天下「回收板」：删除/剪切的长文本找回，防误删（敢大胆删改不心疼）。
  // key 规约：recycle_bin → JSON 数组（时间倒序存，最新在前）
  //   [{"content":"<文本>","deletedAt":<unixSec>}, ...]
  // 批次87-2：recycle_bin_remove_on_restore → '1'/'0'（恢复后自动移除该条开关）

  /// 回收板条数上限（超出丢弃最旧）
  static const int maxRecycleBinItems = 20;

  /// 回收板保留时长（超过 30 天自动清理）
  static const int recycleBinMaxAgeDays = 30;

  /// 读取「恢复后自动移除」开关（默认关：恢复后条目保留，可手动删）
  Future<bool> getRecycleBinRemoveOnRestore() async {
    final raw = await getValue('recycle_bin_remove_on_restore');
    return raw == '1';
  }

  /// 保存「恢复后自动移除」开关
  Future<void> setRecycleBinRemoveOnRestore(bool on) async {
    await setValue('recycle_bin_remove_on_restore', on ? '1' : '0');
  }

  /// 写入一条回收文本（最新在前，先清超龄，超出上限丢弃最旧）
  Future<void> addRecycleBinItem(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final items = await listRecycleBinItems();
    items.insert(0, RecycleBinItem(content: trimmed, deletedAt: nowSec()));
    if (items.length > maxRecycleBinItems) {
      items.removeRange(maxRecycleBinItems, items.length);
    }
    await _writeRecycleBin(items);
  }

  /// 读取全部回收文本（新→旧；顺带清理超龄条目）
  Future<List<RecycleBinItem>> listRecycleBinItems() async {
    final json = await getValue('recycle_bin');
    if (json == null || json.isEmpty) return [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return [];
      final items = decoded
          .whereType<Map<String, dynamic>>()
          .map((e) => RecycleBinItem.fromJson(e))
          .toList();
      final kept = _filterFresh(items);
      if (kept.length != items.length) {
        await _writeRecycleBin(kept);
      }
      return kept;
    } catch (_) {
      return [];
    }
  }

  /// 过滤超龄条目（保留时长内）
  List<RecycleBinItem> _filterFresh(List<RecycleBinItem> items) {
    final cutoff = nowSec() - recycleBinMaxAgeDays * 24 * 3600;
    return [
      for (final it in items)
        if (it.deletedAt >= cutoff) it,
    ];
  }

  /// 写入回收板数组
  Future<void> _writeRecycleBin(List<RecycleBinItem> items) async {
    await setValue(
      'recycle_bin',
      jsonEncode(items.map((v) => v.toJson()).toList()),
    );
  }

  /// 删除一条回收文本（按列表下标，新→旧）
  Future<void> removeRecycleBinItemAt(int index) async {
    final items = await listRecycleBinItems();
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    await _writeRecycleBin(items);
  }

  /// 清空回收板
  Future<void> clearRecycleBin() async {
    await setValue('recycle_bin', '[]');
  }

  // ════════════ 标点栏配置（批次86-2 自定义工具栏） ════════════
  // 对标笔落/灯果「自定义工具栏」：标点栏按用户习惯隐藏/排序。
  // key 规约：punctuation_bar_config → JSON 字符串数组（可见项的有序 id）
  //   ["comma","period","question",...]

  /// 读取标点栏可见项 id 顺序（null = 未配置，用默认全部）
  Future<List<String>?> getPunctuationBarConfig() async {
    final json = await getValue('punctuation_bar_config');
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return null;
      return decoded.whereType<String>().toList();
    } catch (_) {
      return null;
    }
  }

  /// 保存标点栏可见项 id 顺序
  Future<void> setPunctuationBarConfig(List<String> ids) async {
    await setValue('punctuation_bar_config', jsonEncode(ids));
  }

  // ════════════ 标点栏自定义项（批次88-5 可编辑互动） ════════════
  // 用户在排版设置里增删自定义标点/短语。
  // key 规约：punctuation_custom_items → JSON 数组
  //   [{"id":"custom_1","display":"…","insert":"…"}, ...]

  /// 读取自定义标点项（默认空）
  Future<List<PunctuationItem>> getPunctuationCustomItems() async {
    final json = await getValue('punctuation_custom_items');
    if (json == null || json.isEmpty) return [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(
            (e) => PunctuationItem(
              e['id'] as String? ?? '',
              e['display'] as String? ?? '',
              e['insert'] as String? ?? '',
            ),
          )
          .where((it) => it.id.isNotEmpty && it.display.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存自定义标点项
  Future<void> setPunctuationCustomItems(List<PunctuationItem> items) async {
    await setValue(
      'punctuation_custom_items',
      jsonEncode(
        items
            .map((e) => {'id': e.id, 'display': e.display, 'insert': e.insert})
            .toList(),
      ),
    );
  }

  // ════════════ 对话按钮（批次88-2 可移动/隐藏） ════════════
  // key 规约：
  //   fab_visible  → '1'/'0'（默认 '1'，显示）
  //   fab_position → JSON {"dx":..,"dy":..}（FAB 左上角在编辑区内的位置）

  /// 读取对话按钮（FAB）可见性（默认显示）
  Future<bool> getFabVisible() async {
    final raw = await getValue('fab_visible');
    return raw != '0';
  }

  /// 保存对话按钮可见性
  Future<void> setFabVisible(bool on) async {
    await setValue('fab_visible', on ? '1' : '0');
  }

  /// 读取对话按钮位置（null = 未自定义，用右下角默认）
  Future<Offset?> getFabPosition() async {
    final json = await getValue('fab_position');
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        final dx = decoded['dx'];
        final dy = decoded['dy'];
        if (dx is num && dy is num) {
          return Offset(dx.toDouble(), dy.toDouble());
        }
      }
    } catch (_) {}
    return null;
  }

  /// 保存对话按钮位置
  Future<void> setFabPosition(Offset offset) async {
    await setValue(
      'fab_position',
      jsonEncode({'dx': offset.dx, 'dy': offset.dy}),
    );
  }

  /// 清除对话按钮位置（恢复右下角默认）
  Future<void> clearFabPosition() async {
    await setValue('fab_position', '');
  }

  // ════════════ 卷折叠状态（批次96-2 持久化） ════════════
  // key 规约：volume_collapsed_{manuscriptId} → JSON array（折叠的卷 id / 'unassigned'）

  /// 读取作品下已折叠的卷 key 集合（无记录 = 空集）
  Future<Set<String>> getCollapsedVolumes(String manuscriptId) async {
    final raw = await getValue('volume_collapsed_$manuscriptId');
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toSet();
      }
    } catch (_) {}
    return {};
  }

  /// 保存作品下已折叠的卷 key 集合（空集也会写入，保证可清空）
  Future<void> setCollapsedVolumes(
    String manuscriptId,
    Set<String> keys,
  ) async {
    await setValue('volume_collapsed_$manuscriptId', jsonEncode(keys.toList()));
  }
}

/// 章节版本快照（批次82 时光机）
class ChapterVersion {
  final int savedAt; // unix 秒
  final int wordCount;
  final String content;

  const ChapterVersion({
    required this.savedAt,
    required this.wordCount,
    required this.content,
  });

  Map<String, dynamic> toJson() => {
    'savedAt': savedAt,
    'wordCount': wordCount,
    'content': content,
  };

  static ChapterVersion fromJson(Map<String, dynamic> json) {
    return ChapterVersion(
      savedAt: json['savedAt'] as int? ?? 0,
      wordCount: json['wordCount'] as int? ?? 0,
      content: json['content'] as String? ?? '',
    );
  }
}

/// 章节草稿（复刻 ChapterDraft 类型）
class ChapterDraft {
  final String chapterId;
  final String title;
  final String content;
  final int savedAt;
  ChapterDraft({
    required this.chapterId,
    required this.title,
    required this.content,
    required this.savedAt,
  });
}

/// 灵感随笔（批次84-1）
class WritingInspiration {
  final String id;
  final String content;

  /// 来源作品（写作页记灵感时带上；null = 随手记未关联作品）
  final String? manuscriptId;
  final String? chapterId;
  final int createdAt; // unix 秒

  const WritingInspiration({
    required this.id,
    required this.content,
    this.manuscriptId,
    this.chapterId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'manuscriptId': manuscriptId,
    'chapterId': chapterId,
    'createdAt': createdAt,
  };

  static WritingInspiration fromJson(Map<String, dynamic> json) {
    return WritingInspiration(
      id: json['id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      manuscriptId: json['manuscriptId'] as String?,
      chapterId: json['chapterId'] as String?,
      createdAt: json['createdAt'] as int? ?? 0,
    );
  }
}

/// 回收板条目（批次86-1 回收板）
class RecycleBinItem {
  final String content;
  final int deletedAt; // unix 秒

  const RecycleBinItem({required this.content, required this.deletedAt});

  Map<String, dynamic> toJson() => {'content': content, 'deletedAt': deletedAt};

  static RecycleBinItem fromJson(Map<String, dynamic> json) {
    return RecycleBinItem(
      content: json['content'] as String? ?? '',
      deletedAt: json['deletedAt'] as int? ?? 0,
    );
  }
}
