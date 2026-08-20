// ─────────────────────────────────────────────────────────────
// chat_service_send 步骤块提取：chat_service_send_parse.dart（R-019 ≤300 行）
// 逐字迁移自 chat_service_send.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'chat_service.dart';

extension ChatServiceSendParse on ChatService {
  Future<({bool aborted, String displayContent, ParsedDiagnosis? diagnosis, TeacherResult? teacherResult, String messageId, String finalContent, List<GenUiComponent>? genuiComponents})> _parseAndPersist({
    required String sessionId,
    required String fullContent,
    required bool inDiagnosisBlock,
    required ReferenceItem? primaryRef,
    required String? chapterContent,
    required SendMessageCallbacks callbacks,
    required SendMessageOptions options,
  }) async {
      // 9. 解析 + 第二层后置校验
      final rawParse = _diagnosis.parseDiagnosis(fullContent);
      debugPrint(
        '[ChatService] 步骤9: parseDiagnosis | displayContent 长度=${rawParse.displayContent.length} | diagnosis=${rawParse.diagnosis != null ? "有(${rawParse.diagnosis!.syndromes.length} 症候)" : "无"}',
      );

      String displayContent = rawParse.displayContent;
      ParsedDiagnosis? diagnosis = rawParse.diagnosis;

      // 步骤 9.1：大纲提取落库（批次72，独立 OUTLINE 块，失败/未装配不阻断）
      // 批次73：落库后为含 pending 印象的实体写入确认卡片
      await _applyOutlineEntitiesFromContent(
        sessionId: sessionId,
        fullContent: fullContent,
        primaryRef: primaryRef,
      );

      // 步骤 9.2：A6 事实提取落库（时序知识图谱写入路径，失败不阻断）
      await _applyFactExtractionFromContent(
        sessionId: sessionId,
        fullContent: fullContent,
        primaryRef: primaryRef,
      );

      if (diagnosis != null) {
        // 提取诊断块原始 JSON 供 validator 用
        final startIndex = fullContent.indexOf(kDiagnosisStart);
        final endIndex = fullContent.indexOf(
          kDiagnosisEnd,
          startIndex + kDiagnosisStart.length,
        );
        if (startIndex != -1 && endIndex != -1) {
          final jsonStr = fullContent
              .substring(startIndex + kDiagnosisStart.length, endIndex)
              .trim();
          try {
            final rawJson = jsonDecode(jsonStr);
            final validation = _diagnosis.validateDiagnosisOutput(
              rawParse.displayContent,
              rawJson,
              attitude: options.attitude,
            );
            displayContent = validation.displayContent;
            diagnosis = validation.diagnosis;
          } catch (e) {
            debugPrint('[SafeRun] JSON 解析失败沿用 rawParse: $e');
          }
        }
      }

      // 批次74：剥离 [YS_ENTITY] 协议块（诊断缺块时 displayContent 会含原始 JSON，
      // 校验回填也可能重新引入），确保展示/落库内容不含协议原文
      displayContent = stripOutlineBlock(displayContent);
      // A6：剥离 [YS_FACT] 协议块（事实提取块，与实体块并列独立）
      displayContent = stripFactBlock(displayContent);
      // B-1：剥离 [YS_GENUI] 协议块（GenUI 组件块，独立于诊断/事实）
      displayContent = stripGenuiBlock(displayContent);
      // B-1：解析 GenUI 组件（用于后续确定性插入 genui 卡片）
      final genuiComponents = _genUi.parseGenuiBlock(fullContent);

      // B1：诊断成败记录 → 连续失败达阈值插诊断失败卡。
      // attempted 仅当 AI 确实输出了 [YS_DIAGNOSIS] 块（inDiagnosisBlock），
      // 普通聊天解析为 null 不计入，避免误触发「诊断失败」卡。
      await _recordDiagnosisOutcome(
        sessionId,
        attempted: inDiagnosisBlock,
        success: diagnosis != null,
      );

      // Diagnosis → Teacher 条件触发（C3）
      // 真源：chat-service.ts L626-655
      String teacherDisplayContent = '';
      TeacherResult? teacherResult;
      if (diagnosis != null &&
          shouldTriggerTeacherForDiagnosis(diagnosis.syndromes)) {
        try {
          final teacherStream = await callTeacherStream(
            _llmClient,
            TeacherDiagnosisInput(
              diagnosis: diagnosis,
              chapterContent: chapterContent ?? '',
            ),
            callbacks.onStream,
            cancelToken: options.cancelToken,
          );
          teacherDisplayContent = teacherStream.displayContent;
          teacherResult = teacherStream.teacher;
        } catch (e) {
          debugPrint('[SafeRun] Teacher 失败不影响 Diagnosis 已有输出: $e');
        }
      }

      // 合并 Diagnosis + Teacher 输出（RN L657-660）
      // 注意：不修改 displayContent，保留原始值供 parseTrainingResult 使用（RN L767 注释）
      final combinedContent =
          displayContent +
          (teacherDisplayContent.isNotEmpty
              ? '\n\n$teacherDisplayContent'
              : '');

      // 10. 写入 assistant 消息
      // 批次74：仅大纲装配的章节诊断才放宽空判断：
      //   - diagnosis 解析成功 或 已落库实体 → 说明可能被协议块（YS_DIAGNOSIS/YS_ENTITY）
      //     占据首位，拦截器 displayLength=0 导致 combinedContent 空 → 给默认文案「诊断完成。」继续。
      //   - 无大纲装配 或 三空齐发（说明空+诊断空+实体空）→ 维持 RN 原语义，onError。
      bool treatAsValid = false;
      if (combinedContent.trim().isEmpty &&
          _ensureOutlineService() != null &&
          primaryRef?.refType == 'chapter') {
        if (diagnosis != null) {
          treatAsValid = true;
        } else {
          final c = await _readOutlineEntityCount(primaryRef!.refId);
          if (c > 0) treatAsValid = true;
        }
      }
      if (combinedContent.trim().isEmpty && !treatAsValid) {
        debugPrint('[ChatService] 步骤10: combinedContent 为空，触发 onError');
        callbacks.onError('AI 返回为空');
        return (
          aborted: true,
          displayContent: displayContent,
          diagnosis: diagnosis,
          teacherResult: teacherResult,
          messageId: '',
          finalContent: '',
          genuiComponents: genuiComponents,
        );
      }
      final finalContent = combinedContent.trim().isEmpty
          ? '诊断完成。'
          : combinedContent;

      // P0 机器回执态（2026-08-18，ADR-P0）：教练不替用户执行「保存/导出/应用/修改」
      // 等副作用动作；若回复自称「已X」但本回合无真实机器回执，降级为「建议X」，
      // 避免「我已替你做过」的虚假承诺。receipts 仅依据本次 service 实际落库构造：
      // 诊断结构化数据已在步骤 11 commitDiagnosisWithHistory 落库，故允许「已保存」。
      final performedActions = <ReceiptAction>{
        if (diagnosis != null) ReceiptAction.saved,
      };
      final receiptResult = ReplyReceiptGuard.sanitize(
        finalContent,
        receipts: performedActions,
      );
      final assistantContent = receiptResult.text;

      final messageId = await _sessionRepo.addMessage(
        sessionId,
        'assistant',
        assistantContent,
      );
      debugPrint(
        '[ChatService] 步骤10: assistant 消息已写入 | messageId=$messageId | contentLen=${assistantContent.length}'
        "${receiptResult.status == ReceiptStatus.humanReviewPending ? ' | 回执降级: ${receiptResult.downgraded.map((a) => a.claimPhrase).join('、')}' : ''}",
      );
    return (
      aborted: false,
      displayContent: displayContent,
      diagnosis: diagnosis,
      teacherResult: teacherResult,
      messageId: messageId,
      finalContent: finalContent,
      genuiComponents: genuiComponents,
    );
  }

}
