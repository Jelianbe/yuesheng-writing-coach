// ─────────────────────────────────────────────────────────────
// AppStateRepository — 应用状态 key-value DAO + 章节草稿 DAO
// 复刻 yuesheng-android/src/db/dao/basic-dao.ts 的 onboarding 部分
//          + yuesheng-android/src/db/dao/chapter-draft-dao.ts
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:ui' show Offset;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../database/database.dart';
import '../database/utils.dart';
import '../../config/reasoning_tier.dart';
import '../../services/decode_guard.dart';
import '../../services/error_handler.dart';
import '../../types/display_types.dart';
import '../../widgets/punctuation_bar.dart';
import 'chapter_scoped_keys.dart';
import 'repository_write_guard.dart';
import 'version_retention.dart';

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
  Future<void> setOnboardingCompleted(bool completed) =>
      guardRepoWrite('app_state', 'setOnboardingCompleted', () async {
        await _db
            .into(_db.appStates)
            .insertOnConflictUpdate(
              AppStatesCompanion.insert(
                key: 'onboarding_completed',
                value: Value(completed ? 'true' : 'false'),
                updatedAt: Value(nowSec()),
              ),
            );
      });

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
  Future<void> setQuestionnaireCompleted(bool completed) =>
      guardRepoWrite('app_state', 'setQuestionnaireCompleted', () async {
        await _db
            .into(_db.appStates)
            .insertOnConflictUpdate(
              AppStatesCompanion.insert(
                key: 'questionnaire_completed',
                value: Value(completed ? 'true' : 'false'),
                updatedAt: Value(nowSec()),
              ),
            );
      });

  // ════════════ API 配置教学（A3 + 首启/首次使用，2026-09-25） ════════════

  /// 获取「首次使用 API 配置提示」是否已展示（一次性）
  /// key='api_config_hint_seen'；与 onboarding_completed / questionnaire_completed 区分
  Future<bool> getApiConfigHintSeen() async {
    final row = await (_db.select(
      _db.appStates,
    )..where((t) => t.key.equals('api_config_hint_seen'))).getSingleOrNull();
    return row?.value == 'true';
  }

  /// 设置「首次使用 API 配置提示」已展示
  Future<void> setApiConfigHintSeen(bool seen) =>
      guardRepoWrite('app_state', 'setApiConfigHintSeen', () async {
        await _db
            .into(_db.appStates)
            .insertOnConflictUpdate(
              AppStatesCompanion.insert(
                key: 'api_config_hint_seen',
                value: Value(seen ? 'true' : 'false'),
                updatedAt: Value(nowSec()),
              ),
            );
      });

  /// 获取「写作页首次情境提示」是否已展示（一次性，与 onboarding_completed 解耦）
  /// key='writing_intro_seen'
  Future<bool> getWritingIntroSeen() async {
    final row = await (_db.select(
      _db.appStates,
    )..where((t) => t.key.equals('writing_intro_seen'))).getSingleOrNull();
    return row?.value == 'true';
  }

  /// 设置「写作页首次情境提示」已展示
  Future<void> setWritingIntroSeen(bool seen) =>
      guardRepoWrite('app_state', 'setWritingIntroSeen', () async {
        await _db
            .into(_db.appStates)
            .insertOnConflictUpdate(
              AppStatesCompanion.insert(
                key: 'writing_intro_seen',
                value: Value(seen ? 'true' : 'false'),
                updatedAt: Value(nowSec()),
              ),
            );
      });

  // ════════════ 通用 key-value ════════════

  /// 读取 key-value
  Future<String?> getValue(String key) async {
    final row = await (_db.select(
      _db.appStates,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// 写入 key-value（INSERT OR REPLACE 语义）
  Future<void> setValue(String key, String value) =>
      guardRepoWrite('app_state', 'setValue', () async {
        await _db
            .into(_db.appStates)
            .insertOnConflictUpdate(
              AppStatesCompanion.insert(
                key: key,
                value: Value(value),
                updatedAt: Value(nowSec()),
              ),
            );
      });

  // ════════════ 章节草稿（复刻 chapter-draft-dao.ts） ════════════

  /// 获取章节草稿
  /// 复刻 getChapterDraft(chapterId) — key='chapter_draft:`<chapterId>`'
  Future<ChapterDraft?> getChapterDraft(String chapterId) async {
    final row =
        await (_db.select(_db.appStates)
              ..where((t) => t.key.equals(chapterDraftKey(chapterId))))
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
    } catch (e, st) {
      logDecodeFailure(field: 'app_state.chapter_draft', error: e, stack: st);
    }
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
    await setValue(chapterDraftKey(chapterId), jsonEncode(draft));
  }

  /// 清除章节草稿
  /// 复刻 clearChapterDraft(chapterId)
  Future<void> clearChapterDraft(String chapterId) =>
      guardRepoWrite('app_state', 'clearChapterDraft', () async {
        await (_db.delete(
          _db.appStates,
        )..where((t) => t.key.equals(chapterDraftKey(chapterId)))).go();
      });

  /// 是否有章节草稿
  /// 复刻 hasChapterDraft(chapterId)
  Future<bool> hasChapterDraft(String chapterId) async {
    final row =
        await (_db.select(_db.appStates)
              ..where((t) => t.key.equals(chapterDraftKey(chapterId))))
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

  /// P1-5：读取全部会话的全部评估报告（跨会话，按 generatedAt 升序）。
  /// 能力进步曲线数据源——评估报告已按轮次落库，此处只做跨会话聚合。
  Future<List<EvaluationData>> listAllEvaluationReports() async {
    final rows = await (_db.select(
      _db.appStates,
    )..where((t) => t.key.like('eval_report:%'))).get();
    final result = <EvaluationData>[];
    for (final row in rows) {
      final data = EvaluationData.fromJsonString(row.value);
      if (data != null) result.add(data);
    }
    result.sort((a, b) => a.generatedAt.compareTo(b.generatedAt));
    return result;
  }

  /// 删除单条评估报告
  Future<void> deleteEvaluationReport(String sessionId, String messageId) =>
      guardRepoWrite('app_state', 'deleteEvaluationReport', () async {
        await (_db.delete(_db.appStates)
              ..where((t) => t.key.equals('eval_report:$sessionId:$messageId')))
            .go();
      });

  /// 清空会话全部评估报告（会话切换时调用）
  Future<void> clearEvaluationReports(String sessionId) =>
      guardRepoWrite('app_state', 'clearEvaluationReports', () async {
        final prefix = 'eval_report:$sessionId:';
        await (_db.delete(
          _db.appStates,
        )..where((t) => t.key.like('$prefix%'))).go();
        await (_db.delete(
          _db.appStates,
        )..where((t) => t.key.equals('eval_round:$sessionId'))).go();
      });

  // ════════════ 章节版本快照（批次82 P0 四件套之③ 时光机） ════════════
  // 对标橙瓜码字「时光机（每 100 字版本快照）」，本产品取每 200 字。
  // key 规约：chapter_versions:`<chapterId>` → JSON 数组（时间倒序存，最新在前）
  //   [{"savedAt":<unixSec>,"wordCount":<int>,"content":"<全文>"}, ...]

  /// 每章版本快照条数上限（**单一真源在 version_retention.dart**，此处仅为向后兼容的别名）
  /// 分级保留策略见 version_retention.dart。
  static const int maxChapterVersions = kMaxChapterVersions;

  /// 版本快照间隔（每多少字落一次快照）
  static const int chapterVersionInterval = 200;

  /// 写入一章的版本快照（按分级保留策略淘汰：见 version_retention.dart）
  Future<void> addChapterVersion(String chapterId, String content) =>
      guardRepoWrite('app_state', 'addChapterVersion', () async {
        final now = nowSec();
        final versions = await listChapterVersions(chapterId);
        versions.insert(
          0,
          ChapterVersion(
            savedAt: now,
            wordCount: content.length,
            content: content,
          ),
        );
        final kept = retainVersions<ChapterVersion>(
          versions,
          savedAtOf: (v) => v.savedAt,
          bytesOf: (v) => chapterVersionBytes(v.content),
          nowSec: now,
        );
        if (kept.length != versions.length) {
          // R-029：只打计数与 id，禁止打印正文。
          debugPrint(
            '[AppStateRepository] 版本淘汰: chapterId=$chapterId '
            '${versions.length} → ${kept.length}',
          );
        }
        _warnIfOverVersionBytes(chapterId, kept);
        await setValue(
          chapterVersionsKey(chapterId),
          jsonEncode(kept.map((v) => v.toJson()).toList()),
        );
      });

  /// 单章版本快照落库前体积护栏：仅留痕，**不**阻断保存。
  ///
  /// 走到这里时能丢的旧条目已按 [retainVersions] 丢光，仍超 [kMaxChapterVersionBytes]
  /// 意味着**单条即超预算**（典型：一次粘贴数万字的整段正文）。此时保留最新 1 条
  /// 是设计选择（否则时光机会失去「恢复到刚过去状态」的能力），故只记 warn。
  void _warnIfOverVersionBytes(String chapterId, List<ChapterVersion> kept) {
    final bytes = kept.fold<int>(
      0,
      (sum, v) => sum + chapterVersionBytes(v.content),
    );
    if (bytes <= kMaxChapterVersionBytes) return;
    ErrorHandler.instance.captureError(
      level: 'warn',
      category: 'database',
      message: '单章版本快照超体积预算',
      context: <String, dynamic>{
        'repo': 'app_state',
        'op': 'addChapterVersion',
        'chapterId': chapterId,
        'count': kept.length,
        'bytes': bytes,
        'limit': kMaxChapterVersionBytes,
      },
    );
  }

  /// 读取一章的全部版本快照（新→旧）
  Future<List<ChapterVersion>> listChapterVersions(String chapterId) async {
    final json = await getValue(chapterVersionsKey(chapterId));
    if (json == null || json.isEmpty) return [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((e) => ChapterVersion.fromJson(e))
          .toList();
    } catch (e, st) {
      logDecodeFailure(
        field: 'app_state.chapter_versions',
        error: e,
        stack: st,
      );
      return [];
    }
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

  // ════════════ 推理档位（用户可调思考开关） ════════════
  // key 规约：reasoning_tier → 档位 key 字符串（真源见 config/reasoning_tier.dart）
  // 无记录返回 null；消费方按标准档（不干预请求体）处理 ⇒ 旧库零行为变更。

  /// 读取推理档位 key（无记录 → null）
  Future<String?> getReasoningTier() => getValue(kReasoningTierKey);

  /// 保存推理档位（调用方保证 key 属于 [reasoningTierPresets]）
  Future<void> setReasoningTier(String tierKey) =>
      setValue(kReasoningTierKey, tierKey);

  // ════════════ 教练人格（全局默认 attitude） ════════════
  // key='coach_attitude' → 'doubao' | 'yuesheng' | 'sensei'
  // 无记录 = doubao（默认温和）。chat_header 切档时同步写这里。

  /// 读全局教练人格偏好（无记录 = doubao）
  Future<String?> getCoachAttitude() => getValue('coach_attitude');

  /// 写全局教练人格偏好
  Future<void> setCoachAttitude(String a) => setValue('coach_attitude', a);

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
  Future<void> addRecycleBinItem(String content) =>
      guardRepoWrite('app_state', 'addRecycleBinItem', () async {
        final trimmed = content.trim();
        if (trimmed.isEmpty) return;
        final items = await listRecycleBinItems();
        items.insert(0, RecycleBinItem(content: trimmed, deletedAt: nowSec()));
        if (items.length > maxRecycleBinItems) {
          items.removeRange(maxRecycleBinItems, items.length);
        }
        await _writeRecycleBin(items);
      });

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
    } catch (e, st) {
      logDecodeFailure(field: 'app_state.fab_position', error: e, stack: st);
    }
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
    } catch (e, st) {
      logDecodeFailure(
        field: 'app_state.volume_collapsed',
        error: e,
        stack: st,
      );
    }
    return {};
  }

  /// 保存作品下已折叠的卷 key 集合（空集也会写入，保证可清空）
  Future<void> setCollapsedVolumes(
    String manuscriptId,
    Set<String> keys,
  ) async {
    await setValue('volume_collapsed_$manuscriptId', jsonEncode(keys.toList()));
  }

  // ════════════ 诊断偏好（诊断编辑器：用户全局启用集） ════════════
  // key 规约：diagnosis_prefs → JSON
  //   {"disabledIds":["P008",...],"tier":"beginner|story|full",
  //    "genre":"literary|webnovel|setting","customized":bool}
  // 空/缺省 = 全启用（与现状零行为变化）。disabledIds 是关闭列表，不是启用列表——
  // 老用户升级后无记录 = 全启用，不破坏存量诊断行为。

  /// 读取诊断偏好；无记录返回 null（=全启用，走默认）。
  Future<DiagnosisPrefs?> getDiagnosisPrefs() async {
    final json = await getValue('diagnosis_prefs');
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      return DiagnosisPrefs(
        disabledIds: (decoded['disabledIds'] as List? ?? [])
            .whereType<String>()
            .toSet(),
        tier: decoded['tier'] as String?,
        genre: decoded['genre'] as String?,
        customized: decoded['customized'] as bool? ?? false,
      );
    } catch (e, st) {
      logDecodeFailure(field: 'app_state.diagnosis_prefs', error: e, stack: st);
      return null;
    }
  }

  /// 保存诊断偏好。
  Future<void> setDiagnosisPrefs(DiagnosisPrefs prefs) => setValue(
    'diagnosis_prefs',
    jsonEncode({
      'disabledIds': prefs.disabledIds.toList(),
      if (prefs.tier != null) 'tier': prefs.tier,
      if (prefs.genre != null) 'genre': prefs.genre,
      'customized': prefs.customized,
    }),
  );
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

/// 诊断编辑器偏好（用户全局启用集）。
///
/// - [disabledIds]：用户永久关闭（「不适用于我」）的症候 ID 集合。空 = 全启用。
/// - [tier]：写作阶段档（beginner=只 L1 / story=L1-L4 / full=全开）；null=未引导。
/// - [genre]：写作类型（literary=纯文学 / webnovel=连载网文 / setting=设定优先）。
/// - [customized]：用户是否在档基础上手动改过单条（用于 UI 显示「自定义」）。
class DiagnosisPrefs {
  final Set<String> disabledIds;
  final String? tier;
  final String? genre;
  final bool customized;

  const DiagnosisPrefs({
    this.disabledIds = const {},
    this.tier,
    this.genre,
    this.customized = false,
  });

  /// 该症候是否被用户关闭（未配置偏好时 = false，即全启用）。
  bool isDisabled(String syndromeId) => disabledIds.contains(syndromeId);

  /// 运行时真正传给 prompt 的禁用集 = 用户手动关 ∪ 档禁用集。
  Set<String> get effectiveDisabledIds {
    final set = <String>{...disabledIds};
    if (genre == 'setting') {
      set.addAll(_tierAll.difference(_l3));
      return Set.unmodifiable(set);
    }
    switch (tier) {
      case 'beginner':
        set.addAll(_l2.union(_l3).union(_l4).union(_l5));
      case 'story':
        set.addAll(_l5);
    }
    if (genre == 'literary') set.addAll(_commercial);
    return Set.unmodifiable(set);
  }

  static const _l1 = {'P003', 'P007', 'P008', 'P011', 'P022'};
  static const _l2 = {
    'P004',
    'P006',
    'P020',
    'P021',
    'P029',
    'P035',
    'P036',
    'P037',
  };
  static const _l3 = {
    'P009',
    'P010',
    'P018',
    'P019',
    'P031',
    'P034',
    'P039',
    'P040',
    'P041',
  };
  static const _l4 = {
    'P005',
    'P012',
    'P013',
    'P014',
    'P015',
    'P016',
    'P017',
    'P030',
  };
  static const _l5 = {'P042'};
  static const _commercial = {
    'P023',
    'P024',
    'P025',
    'P026',
    'P027',
    'P032',
    'P033',
  };
  static const _tierAll = {
    ..._l1,
    ..._l2,
    ..._l3,
    ..._l4,
    ..._l5,
    ..._commercial,
  };

  DiagnosisPrefs copyWith({
    Set<String>? disabledIds,
    String? tier,
    String? genre,
    bool? customized,
  }) {
    return DiagnosisPrefs(
      disabledIds: disabledIds ?? this.disabledIds,
      tier: tier ?? this.tier,
      genre: genre ?? this.genre,
      customized: customized ?? this.customized,
    );
  }
}
