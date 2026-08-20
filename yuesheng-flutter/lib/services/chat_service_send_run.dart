// ─────────────────────────────────────────────────────────────
// chat_service_send 步骤块提取：chat_service_send_run.dart（R-019 ≤300 行）
// 逐字迁移自 chat_service_send.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'chat_service.dart';

extension ChatServiceSendRun on ChatService {
  Future<bool> _runEditorBranch({
    required String sessionId,
    required ReferenceItem? primaryRef,
    required bool reviewerPassed,
    required bool reviewerNeedsEditor,
    required String? chapterContent,
    required bool rapidFire,
    required SendMessageCallbacks callbacks,
    required SendMessageOptions options,
  }) async {
      // 7.1 Editor 分支（Reviewer PASS + needs_editor=true）
      // 真源：chat-service.ts L464-562
      // R1：Editor observation 总是入库（即使 Teacher 未触发），便于审计阈值校准
      // R6：Teacher suggestion 写入抽到 chat_gates.dart，消除两分支重复
      if (reviewerPassed && reviewerNeedsEditor && chapterContent != null) {
        final editorResult = await callEditorStream(
          _llmClient,
          chapterContent,
          callbacks.onStream,
          cancelToken: options.cancelToken,
        );

        // R1：计算 Teacher 触发判断中间状态（pronounced/against 计数 + 触发标志）
        bool teacherTriggered = false;
        int pronouncedCount = 0;
        int againstCount = 0;
        if (editorResult.observation != null) {
          pronouncedCount = editorResult.observation!.observations
              .where((o) => o.observationVisibility == 'pronounced')
              .length;
          againstCount = editorResult.observation!.observations
              .where((o) => o.intentAlignment == 'against')
              .length;
          teacherTriggered = shouldTriggerTeacherForEditor(
            editorResult.observation!,
          );
        }

        // Editor → Teacher 条件触发（追加教学反馈）
        String teacherDisplayContent = '';
        TeacherResult? teacherResult;
        if (teacherTriggered && editorResult.observation != null) {
          try {
            final teacherStream = await callTeacherStream(
              _llmClient,
              TeacherEditorInput(
                editorResult: editorResult.observation!,
                chapterContent: chapterContent,
              ),
              callbacks.onStream,
              cancelToken: options.cancelToken,
            );
            teacherDisplayContent = teacherStream.displayContent;
            teacherResult = teacherStream.teacher;
          } catch (e) {
            debugPrint('[SafeRun] Teacher 失败不影响 Editor 已有输出: $e');
          }
        }

        // 合并 Editor + Teacher 输出
        final combinedContent =
            editorResult.displayContent +
            (teacherDisplayContent.isNotEmpty
                ? '\n\n$teacherDisplayContent'
                : '');

        if (combinedContent.trim().isEmpty) {
          callbacks.onError('AI 返回为空');
          return true;
        }

        final messageId = await _sessionRepo.addMessage(
          sessionId,
          'assistant',
          combinedContent,
        );

        // R1：Editor observation 持久化（总是写入，便于审计阈值）
        if (editorResult.observation != null) {
          try {
            await _editorObservationRepo.insertEditorObservation(
              InsertEditorObservationParams(
                sessionId: sessionId,
                messageId: messageId,
                editorResult: editorResult.observation!,
                teacherTriggered: teacherTriggered,
                pronouncedCount: pronouncedCount,
                againstCount: againstCount,
                targetRefType: primaryRef?.refType,
                targetRefId: primaryRef?.refId,
              ),
            );
          } catch (e) {
            debugPrint('[SafeRun] DB 写入失败不影响 Editor/Teacher 已有输出: $e');
          }
        }

        // R6：Teacher suggestion 写入（两分支复用 persistTeacherSuggestion）
        if (teacherResult != null) {
          await persistTeacherSuggestion(
            _teacherSuggestionRepo,
            teacherResult,
            sessionId,
            messageId,
            'editor',
            isRapidFire: rapidFire,
          );
        }

        await callbacks.onComplete(combinedContent, messageId);
        return true; // Editor 分支提前结束，不走主流 Diagnosis streamChat
      }
    return false;
  }

  Future<({String fullContent, bool inDiagnosisBlock})> _streamLlm({
    required List<ChatMessage> messages,
    required SendMessageCallbacks callbacks,
    required SendMessageOptions options,
  }) async {
      // 8. 流式调用 + 拦截诊断块
      String fullContent = '';
      bool inDiagnosisBlock = false;
      int displayLength = 0;
      int streamChunkCount = 0;

      debugPrint('[ChatService] 步骤8: 开始 streamChat 调用...');
      await _llmClient.streamChat(messages, (response) {
        if (response.isDone) {
          debugPrint('[ChatService] 步骤8: streamChat 收到 [DONE]');
          return;
        }
        if (response.content.isEmpty) return;

        streamChunkCount++;
        fullContent += response.content;
        // 批次6（6.10）：内存上限截断——超限丢弃头部，displayLength 同步左移
        //（已转发内容不受影响，仅服务端解析缓冲降载）
        if (fullContent.length > ChatService._kFullContentMaxLen) {
          final overflow = fullContent.length - ChatService._kFullContentMaxLen;
          fullContent = fullContent.substring(overflow);
          displayLength = (displayLength - overflow).clamp(
            0,
            fullContent.length,
          );
          debugPrint(
            '[ChatService] 步骤8: fullContent 超上限截断头部 $overflow 字符（上限 $ChatService._kFullContentMaxLen）',
          );
        }
        if (streamChunkCount <= 3 || streamChunkCount % 10 == 0) {
          debugPrint(
            '[ChatService] 步骤8: chunk#$streamChunkCount | delta="${response.content.length > 30 ? '${response.content.substring(0, 30)}...' : response.content}" | fullLen=${fullContent.length}',
          );
        }

        if (inDiagnosisBlock) return;

        // 拦截诊断块、大纲记忆块（[YS_ENTITY]）、事实块（[YS_FACT]）：
        // 任一标记出现即从该处起不再转发，避免原始协议 JSON 泄漏到流式展示
        // 批次6（6.3）：O(n²) → O(n)——安全区已转发到 displayLength，标记只可能
        // 出现在末尾 ≤ 最大标记长的窗口内（含跨 chunk 拼接），从窗口起点起搜，
        // 避免每 chunk 对全量 fullContent 做三次 indexOf 扫描。
        final scanStart = displayLength > ChatService._kMaxStreamMarkerLen
            ? displayLength - ChatService._kMaxStreamMarkerLen + 1
            : 0;
        final diagMarkerIndex = fullContent.indexOf(kDiagnosisStart, scanStart);
        final outlineMarkerIndex = fullContent.indexOf(
          kOutlineStart,
          scanStart,
        );
        final factMarkerIndex = fullContent.indexOf(kFactStart, scanStart);
        final genuiMarkerIndex = fullContent.indexOf(kGenuiStart, scanStart);
        final markerIndex = ChatService._earliestMarkerIndex(
          ChatService._earliestMarkerIndex(
            ChatService._earliestMarkerIndex(
              diagMarkerIndex,
              outlineMarkerIndex,
            ),
            factMarkerIndex,
          ),
          genuiMarkerIndex,
        );
        if (markerIndex != -1) {
          final newDisplay = fullContent.substring(displayLength, markerIndex);
          if (newDisplay.isNotEmpty) callbacks.onStream(newDisplay);
          displayLength = markerIndex;
          inDiagnosisBlock = true;
          debugPrint(
            '[ChatService] 步骤8: 检测到协议块标记，切换到拦截模式 | displayLength=$displayLength',
          );
          return;
        }

        final pendingLen = ChatService._blockPendingPrefix(fullContent);
        final safeEnd = pendingLen > 0
            ? fullContent.length - pendingLen
            : fullContent.length;
        if (safeEnd > displayLength) {
          final newDisplay = fullContent.substring(displayLength, safeEnd);
          if (newDisplay.isNotEmpty) callbacks.onStream(newDisplay);
          displayLength = safeEnd;
        }
      }, cancelToken: options.cancelToken);
      debugPrint(
        '[ChatService] 步骤8: streamChat 完成 | 总 chunk=$streamChunkCount | fullContent 长度=${fullContent.length} | inDiagnosisBlock=$inDiagnosisBlock',
      );
    return (fullContent: fullContent, inDiagnosisBlock: inDiagnosisBlock);
  }

}
