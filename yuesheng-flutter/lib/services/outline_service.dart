// ─────────────────────────────────────────────────────────────
// OutlineService — 大纲层业务编排（批次72）
//
// 职责：
//   1. 构建「实体索引上下文」注入诊断 prompt（AI 匹配防重复入库的前提）
//   2. 应用 AI 提取结果：实体匹配（matched_id → 别名交集 → 新建）、
//      印象增量追加（不覆盖）、冲突标记（防幻觉 id 校验）
// 所有新写入一律 pending 态，待用户确认后 active（可交互性兜底）。
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';
import '../data/repositories/outline_repository.dart';
import 'outline_parser.dart';

/// 本次落库的单条印象摘要（供确认卡片渲染）
class OutlineImpressionResult {
  final String id;
  final String text;
  final String? conflictWith; // 采信后的冲突目标（可能为 null）
  const OutlineImpressionResult({
    required this.id,
    required this.text,
    this.conflictWith,
  });
}

/// 本次落库的实体摘要（供确认卡片渲染）
class OutlineExtractionResult {
  final String entityId;
  final String entityType; // character | setting | plot
  final String entityKey;
  final bool isNewEntity;
  final List<OutlineImpressionResult> impressions;
  const OutlineExtractionResult({
    required this.entityId,
    required this.entityType,
    required this.entityKey,
    required this.isNewEntity,
    required this.impressions,
  });
}

class OutlineService {
  final OutlineRepository _repo;
  OutlineService(this._repo);

  /// 构建「大纲实体记忆」协议说明（批次74，诊断时无条件注入）
  ///
  /// 首次诊断零实体时也注入 → AI 从首轮即知晓 [YS_ENTITY] 协议，闭环可启动。
  /// 输出顺序强约束（解决：AI 原把 token 全耗在诊断教学建议，实体块被 max_tokens 截断）：
  ///   [YS_DIAGNOSIS] → [YS_ENTITY] → 自然语言说明
  /// 措辞遵循 A1：定位为记忆沉淀工具，非硬性指令；只输出增量。
  String buildEntityProtocolContext() {
    return '## 大纲实体记忆沉淀（必须遵守输出顺序）\n\n'
        '【输出顺序】若同时输出诊断块与实体块，**必须严格按此顺序**，不可调换：\n'
        '  1. [YS_DIAGNOSIS] 症候块（若诊断要求）；\n'
        '  2. [YS_ENTITY] 实体记忆块（**本条为高优先级，宁可压缩自然语言诊断说明也不得省略**）；\n'
        '  3. 之后再写面向学员的自然语言诊断与教学建议。\n\n'
        '若章节内容出现值得长期记住的人物/设定/情节（称呼、身世、关系、关键事件、信物等），'
        '请在回复中附加 [YS_ENTITY] JSON 块，供系统沉淀为作品大纲记忆。'
        '【续写/中段章节必须输出】即使没有新人物，只要已有角色发生了值得记住的状态变化、'
        '关键动作、关系变化、态度转变、出场场景更新，**必须**输出 [YS_ENTITY] 块做增量更新；'
        '严禁因为"没有新人物"而省略该块。'
        '新章节一般期望抽取 2-5 个核心实体（关键人物优先，重要场景/信物/事件视重要性补充），'
        '信息量极少可只抽 1 个，完全无新信息（无状态变化、无新人物、无关键事件）才可不输出该块。\n\n'
        '格式：\n'
        '[YS_ENTITY]\n'
        '{"entities":[{"type":"character|setting|plot","key":"规范名",'
        '"aliases":["别名"],"matched_entity_id":"已有实体 id，新建则不填",'
        '"impressions":[{"text":"印象/梗概片段（每条约 20-60 字，原文可验证的事实）",'
        '"conflict_with":"同实体已有印象 id，无则省略"}]}]}\n'
        '[/YS_ENTITY]\n\n'
        '规则：\n'
        '- 一次只给增量：仅记录当前章节新增或变化的信息，不重复已沉淀的印象\n'
        '- matched_entity_id 仅可引用下方「大纲实体索引」方括号内的实体 id；新实体不填\n'
        '- conflict_with 仅可引用索引内同实体已列出的印象 id（标记与旧认知矛盾，需学员确认）\n'
        '- 印象每条约 20-60 字，以原文可验证的事实为主，避免空泛形容词\n'
        '- **完整性硬约束**：[YS_ENTITY] 包裹的 JSON 必须语法合法、完整闭合，严禁出现以下情况：\n'
        '  · impressions 数组写到一半停住（字符/引号未闭合、缺少 ]/}）；\n'
        '  · 省略 impressions、key、type 等必填字段；\n'
        '  · 在 JSON 中间换行导致字符串或括号不匹配。\n'
        '  如担心篇幅，请压缩自然语言诊断说明以保证实体块完整。max_tokens 配额充足，实体块一定能放下。';
  }

  /// 构建「大纲实体索引」上下文（注入诊断 prompt）
  ///
  /// 列出作品下全部实体及其 active 印象摘要（含印象 id），
  /// 供 AI 自主匹配实体并引用 conflict_with。
  /// 无实体 → 返回 null（首次诊断不注入索引，零 token 成本）。
  /// 措辞遵循 A1 约束：定位为记忆沉淀工具，非硬性指令。
  Future<String?> buildEntityIndexContext(String manuscriptId) async {
    final entities = await _repo.listEntities(manuscriptId);
    if (entities.isEmpty) return null;

    final lines = <String>[];
    for (final entity in entities) {
      final impressions = await _repo.listImpressions(entity.id);
      final active = impressions.where((i) => i.status == 'active').toList();
      final aliases = OutlineRepository.parseAliases(entity.aliases);
      final aliasText = aliases.isEmpty ? '' : '（别名：${aliases.join('、')}）';
      // 印象带 id（[id] 文本），供 AI 填 conflict_with 时引用
      final impText = active.isEmpty
          ? '暂无已确认印象'
          : active.map((i) => '[${i.id}] ${i.impression}').join('；');
      lines.add(
        '- [${entity.id}] ${entity.entityType}「${entity.entityKey}」$aliasText'
        '：$impText',
      );
    }

    return '## 大纲实体索引（供记忆沉淀参考）\n\n'
        '以下是本作品已记录的大纲实体。若当前章节涉及其中实体，'
        '请在回复末尾用 [YS_ENTITY] 块更新其印象（标注 matched_entity_id 为上方方括号内 id），'
        '新实体不填 matched_entity_id。每处仅更新新增信息，不重复已有印象。\n\n'
        '${lines.join('\n')}';
  }

  /// 应用 AI 大纲提取结果（匹配/合并/冲突落库）
  ///
  /// 匹配优先级：
  ///   1. matched_entity_id 且存在于当前作品实体集合（防 AI 幻觉编造 id）
  ///   2. 别名交集匹配（新 key/别名 vs 已有 key/别名）
  ///   3. 新建实体（pending 态）
  /// 印象：同实体同文本跳过（防重复）；conflict_with 仅采信同实体已有印象 id。
  /// 返回本次落库的实体摘要（含新写入的 pending 印象），供写确认卡片。
  Future<List<OutlineExtractionResult>> applyOutlineExtraction({
    required String manuscriptId,
    required OutlineExtraction extraction,
    String? sourceChapterId,
    int? sourceChapterNo,
  }) async {
    // 批次5（5.2）：新印象落库前先清理过期 pending（7 天超时 + 归档作品来源），
    // 防确认卡永居与陈旧印象覆盖当前 active。
    await _repo.cleanupPendingImpressions();

    final results = <OutlineExtractionResult>[];
    final entities = await _repo.listEntities(manuscriptId);
    final knownIds = entities.map((e) => e.id).toSet();
    // 已有匹配键（key + 别名），供别名交集匹配
    final existingKeys = <String, OutlineEntity>{};
    for (final e in entities) {
      existingKeys[e.entityKey] = e;
      for (final alias in OutlineRepository.parseAliases(e.aliases)) {
        existingKeys[alias] = e;
      }
    }

    for (final update in extraction.entities) {
      // 1. matched_entity_id（校验存在性，防幻觉）
      OutlineEntity? target;
      if (update.matchedEntityId != null &&
          knownIds.contains(update.matchedEntityId)) {
        target = await _repo.getEntityById(update.matchedEntityId!);
      }
      // 2. 别名交集匹配
      if (target == null) {
        final probeKeys = {update.key, ...update.aliases};
        for (final key in probeKeys) {
          final hit = existingKeys[key];
          if (hit != null) {
            target = hit;
            break;
          }
        }
      }
      // 3. 新建（pending）
      var isNewEntity = false;
      if (target == null) {
        await _repo.insertEntity(
          manuscriptId: manuscriptId,
          entityType: update.type,
          entityKey: update.key,
          aliases: update.aliases,
        );
        target = await _findByKey(manuscriptId, update.key);
        isNewEntity = true;
      } else {
        await _repo.mergeAliases(target.id, update.aliases);
      }
      if (target == null) continue; // 兜底：极端情况跳过该实体

      // 追加印象（增量，不覆盖）
      final existingImpressions = await _repo.listImpressions(target.id);
      final impressionIds = existingImpressions.map((i) => i.id).toSet();
      final newImpressions = <OutlineImpressionResult>[];
      for (final im in update.impressions) {
        if (await _repo.hasImpression(target.id, im.text)) continue;
        // conflict_with 防幻觉：仅采信同实体已有印象 id
        final conflict =
            im.conflictWith != null && impressionIds.contains(im.conflictWith)
            ? im.conflictWith
            : null;
        final id = await _repo.insertImpression(
          entityId: target.id,
          impression: im.text,
          sourceChapterId: sourceChapterId,
          sourceChapterNo: sourceChapterNo,
          conflictWith: conflict,
        );
        newImpressions.add(
          OutlineImpressionResult(
            id: id,
            text: im.text,
            conflictWith: conflict,
          ),
        );
      }
      results.add(
        OutlineExtractionResult(
          entityId: target.id,
          entityType: target.entityType,
          entityKey: target.entityKey,
          isNewEntity: isNewEntity,
          impressions: newImpressions,
        ),
      );
    }
    return results;
  }

  Future<OutlineEntity?> _findByKey(String manuscriptId, String key) async {
    final entities = await _repo.listEntities(manuscriptId);
    for (final e in entities) {
      if (e.entityKey == key) return e;
    }
    return null;
  }
}
