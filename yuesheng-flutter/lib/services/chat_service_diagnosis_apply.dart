// ─────────────────────────────────────────────────────────────
// chat_service_diagnosis 方法级拆分：chat_service_diagnosis_apply.dart（R-019 ≤300 行）
// 逐字迁移自 chat_service_diagnosis.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'chat_service.dart';

extension ChatServiceDiagnosisApply on ChatService {
  /// 大纲实体提取 + 确认卡写入（批次72/73/74 D4-A 共用）
  ///
  /// 失败/未装配/无大纲块/非章节主引用 → 静默跳过不抛。
  /// 优先使用入参传入的 primaryRef（sendMessage 路径）；
  /// 若未传（commitDiagnosisFromContent 路径）则从 session 的当前引用取。
  Future<void> _applyOutlineEntitiesFromContent({
    required String sessionId,
    required String fullContent,
    ReferenceItem? primaryRef,
  }) async {
    if (_ensureOutlineService() == null) return;
    // 若调用方未传入 primaryRef（D4-A 路径），从 session 装配主引用
    ReferenceItem? pRef = primaryRef;
    if (pRef == null) {
      try {
        final refs = await _referenceRepo.listReferences(sessionId);
        if (refs.isNotEmpty) {
          final items = refs
              .map(
                (r) => ReferenceItem(
                  refType: r.refType,
                  refId: r.refId,
                  title: r.title,
                  isPrimary: r.isPrimary,
                  manuscriptId: r.manuscriptId,
                  excerptRange: r.excerptRange,
                ),
              )
              .toList();
          pRef = items.firstWhere(
            (r) => r.isPrimary == 1,
            orElse: () => items.first,
          );
        }
      } catch (e) {
        debugPrint('[SafeRun] commitOutlineChangeFromContent 引用查询失败: $e');
        return;
      }
    }
    if (pRef?.refType != 'chapter') return;
    try {
      final outlineExtraction = parseOutlineExtraction(fullContent);
      if (outlineExtraction == null || outlineExtraction.entities.isEmpty) {
        return;
      }
      final chapter = await _chapterRepo.getChapter(pRef!.refId);
      if (chapter == null) return;
      final results = await _ensureOutlineService()!.applyOutlineExtraction(
        manuscriptId: chapter.manuscriptId,
        extraction: outlineExtraction,
        sourceChapterId: chapter.id,
        sourceChapterNo: chapter.sortOrder,
      );
      debugPrint(
        '[ChatService] 大纲提取落库 | 实体数=${outlineExtraction.entities.length}',
      );
      for (final r in results) {
        if (r.impressions.isEmpty) continue;
        await insertOutlineConfirmationCard(
          _sessionRepo,
          sessionId,
          OutlineConfirmationPayload(
            confirmationId: generateUuid(),
            entityId: r.entityId,
            entityType: r.entityType,
            entityKey: r.entityKey,
            isNewEntity: r.isNewEntity,
            impressions: r.impressions
                .map(
                  (im) => OutlineImpressionPayload(
                    id: im.id,
                    text: im.text,
                    conflictWith: im.conflictWith,
                  ),
                )
                .toList(),
          ),
        );
      }
    } catch (e) {
      debugPrint('[SafeRun] commitOutlineChangeFromContent 大纲落库失败: $e');
    }
  }

  /// A6：事实提取落库（时序知识图谱写入路径）
  ///
  /// 从 AI 诊断回复中提取 [YS_FACT] 块，将人物/事件/支线事实
  /// upsert 到 character_fact/event_fact/subplot_fact 三表。
  /// 失败/未装配/无事实块/非章节 → 静默跳过不抛。
  /// 优先使用入参 primaryRef（sendMessage 路径）；
  /// 若未传（commitDiagnosisFromContent 路径）则从 session 引用取。
  Future<void> _applyFactExtractionFromContent({
    required String sessionId,
    required String fullContent,
    ReferenceItem? primaryRef,
  }) async {
    // 三表仓储至少一个未装配 → 跳过
    if (_characterFactRepo == null &&
        _eventFactRepo == null &&
        _subplotFactRepo == null) {
      return;
    }

    // 解析 primaryRef（同 _applyOutlineEntitiesFromContent 模式）
    ReferenceItem? pRef = primaryRef;
    if (pRef == null) {
      try {
        final refs = await _referenceRepo.listReferences(sessionId);
        if (refs.isNotEmpty) {
          final items = refs
              .map(
                (r) => ReferenceItem(
                  refType: r.refType,
                  refId: r.refId,
                  title: r.title,
                  isPrimary: r.isPrimary,
                  manuscriptId: r.manuscriptId,
                  excerptRange: r.excerptRange,
                ),
              )
              .toList();
          pRef = items.firstWhere(
            (r) => r.isPrimary == 1,
            orElse: () => items.first,
          );
        }
      } catch (e) {
        debugPrint('[SafeRun] persistTeacherSuggestion 失败: $e');
        return;
      }
    }
    if (pRef?.refType != 'chapter') return;

    try {
      final extraction = parseFactExtraction(fullContent);
      if (extraction == null || extraction.isEmpty) return;

      final chapter = await _chapterRepo.getChapter(pRef!.refId);
      if (chapter == null) return;
      final manuscriptId = chapter.manuscriptId;
      final chapterNo = chapter.sortOrder;
      final now = nowSec();

      // 人物事实 → character_fact
      if (_characterFactRepo != null) {
        for (final c in extraction.characters) {
          await _characterFactRepo.upsertCharacter(
            manuscriptId: manuscriptId,
            name: c.name,
            firstSeenChapter: chapterNo,
            firstSeenAt: now,
            assertions: c.assertions,
          );
        }
      }

      // 事件事实 → event_fact
      // 批次3-D4：两轮写入——先 upsert 全部事件（不带因果边），
      // 再反查 causeEventName 对应 id 填入 cause_event_id
      if (_eventFactRepo != null) {
        // 第一轮：upsert 全部事件
        for (final e in extraction.events) {
          await _eventFactRepo.upsertEvent(
            manuscriptId: manuscriptId,
            name: e.name,
            eventType: e.eventType,
            chapter: e.chapter ?? chapterNo,
            participants: e.participants,
            description: e.description,
          );
        }
        // 第二轮：填因果边（causeEventName → causeEventId）
        for (final e in extraction.events) {
          final causeName = e.causeEventName;
          if (causeName == null) continue;
          final self = await _eventFactRepo.getEvent(manuscriptId, e.name);
          final cause = await _eventFactRepo.getEvent(manuscriptId, causeName);
          if (self != null && cause != null) {
            await _eventFactRepo.updateCauseEventId(self.id, cause.id);
          } else {
            // 批次6（6.11 L5/V10）：因果边反查失败不再静默丢弃——
            // 打日志留痕，便于排查前因名称不一致导致关联未建立
            debugPrint(
              '[FactExtract] 因果边反查失败未关联: 事件="$e.name" '
              '前因="$causeName"（self=${self != null ? '找到' : '缺失'}'
              ' / cause=${cause != null ? '找到' : '缺失'}）',
            );
          }
        }
      }

      // 支线事实 → subplot_fact
      if (_subplotFactRepo != null) {
        for (final s in extraction.subplots) {
          await _subplotFactRepo.upsertSubplot(
            manuscriptId: manuscriptId,
            name: s.name,
            introducedChapter: s.introducedChapter ?? chapterNo,
            resolvedChapter: s.resolvedChapter,
            resolvedAt: s.resolvedChapter != null ? now : null,
            description: s.description,
          );
        }
      }

      debugPrint(
        '[ChatService] A6 事实提取落库 | 人物=${extraction.characters.length} '
        '事件=${extraction.events.length} 支线=${extraction.subplots.length}',
      );
    } catch (e) {
      debugPrint('[SafeRun] 事实提取三表落库失败: $e');
    }
  }

}
