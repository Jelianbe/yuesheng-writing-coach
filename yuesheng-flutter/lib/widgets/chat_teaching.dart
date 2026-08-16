// ignore_for_file: invalid_use_of_protected_member
part of 'chat_page.dart';

extension _ChatTeaching on _ChatPageState {

  /// 批次 13 自动诊断：成长页「写作诊断」选章后进入对话页触发（startDiagnosis 语义）
  ///
  /// 对齐 RN sendDiagnosisMessage：读章节 → 长度校验 → 超长走分块
  /// （runProgressiveDiagnosis + commitDiagnosisFromContent），否则回退
  /// 单次诊断 prompt（显式要求 [YS_DIAGNOSIS] 格式）。
  Future<void> _handleAutoDiagnose(String chapterId) async {
    // 清空 pending，避免重复触发（对齐 RN diagnosisStartedRef）
    ref.read(pendingDiagnosisChapterProvider.notifier).state = null;
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    final db = ref.read(appDatabaseProvider);
    final chapter = await ChapterRepository(db).getChapter(chapterId);
    if (chapter == null || !mounted) return;

    // 对齐 RN：内容过短提示先编辑（Alert 语义落为 SnackBar）
    if (chapter.content.trim().length < UILimits.diagnosisWordThreshold) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('章节内容少于 100 字，请先编辑章节')));
      return;
    }

    ref.read(chatStoreProvider.notifier).setStreaming(
          true,
          // 批次49：自动诊断阶段标签（分块/单次均适用）
          stageLabel: '正在诊断本章…',
        );
    try {
      // 1. 超长分块（>4000 字）优先，质量更好（对齐 RN T-011）
      final progressive = await runProgressiveDiagnosis(
        content: chapter.content,
        title: chapter.title,
        llmClient: ref.read(llmClientProvider),
        sessionId: bootstrap.sessionId,
        onContent: (delta) {
          ref.read(chatStoreProvider.notifier).appendStreamingContent(delta);
        },
      );

      if (progressive != null) {
        // 分块链路：解析 + 持久化 + 卡片插入
        await ref
            .read(chatServiceProvider)
            .commitDiagnosisFromContent(
              sessionId: bootstrap.sessionId,
              fullContent: progressive.fullContent,
            );
      } else {
        // 2. 回退：单次诊断 prompt（对齐 RN sendDiagnosisMessage 回退分支）
        final prompt =
            '请对以下章节内容进行写作诊断分析：\n\n'
            '【${chapter.title}】\n\n'
            '${chapter.content}\n\n'
            '---\n'
            '重要：诊断说明后必须输出 [YS_DIAGNOSIS]...[/YS_DIAGNOSIS] 包裹的 JSON 块，'
            '含 syndromes 数组（每条含 syndrome_id/name/severity/evidence/explanation）、'
            'suggested_actions（数组）、confidence（0-1）。'
            '此结构化数据用于驱动后续教学流程，不可缺少。';
        await _handleSend(
          prompt,
          // 批次49：单次诊断回退分支打标
          stageLabel: '正在诊断本章…',
        );
      }
    } catch (_) {
      // 诊断失败不打断页面，错误由 sendMessage 的 onError / finally 复位处理
    } finally {
      if (mounted) {
        ref.read(chatStoreProvider.notifier).setStreaming(false);
        final sessionRepo = SessionRepository(db);
        final messages = await sessionRepo.listMessages(bootstrap.sessionId);
        ref.read(chatStoreProvider.notifier).setMessages(messages);
      }
    }
  }

  /// 批次 18 活跃问题面板：加载当前会话活跃问题列表
  /// 对齐 RN useDiagnosis.loadActiveProblems（listActiveProblems）
  Future<void> _loadActiveProblems(String sessionId) async {
    try {
      final problems = await DiagnosisRepository(
        ref.read(appDatabaseProvider),
      ).listActiveProblems(sessionId);
      if (mounted) {
        setState(() => _activeProblems = problems);
      }
    } catch (_) {
      // 加载失败保持空列表，静默
    }
  }

  /// 批次 18 活跃问题面板：标记症候已完成
  /// 对齐 RN useDiagnosis.handleMarkComplete（resolveProblem + 重载）
  Future<void> _handleMarkComplete(String syndromeId) async {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;
    await DiagnosisRepository(
      ref.read(appDatabaseProvider),
    ).resolveProblem(bootstrap.sessionId, syndromeId);
    await _loadActiveProblems(bootstrap.sessionId);
  }

  /// 批次75：移除活跃问题条目（物理删行 + 重载）。
  /// 与「完成」区分：完成保留 resolved 历史供成长曲线，移除 = 主观不再追踪。
  Future<void> _handleRemoveProblem(String syndromeId) async {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.overlay,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '移除问题',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: const Text(
          '确定要从练习任务中移除这个问题吗？\n移除后需重新诊断才会再次出现。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textPrimary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: const Text('移除', style: TextStyle(color: AppColors.onPrimary)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DiagnosisRepository(
      ref.read(appDatabaseProvider),
    ).removeProblem(bootstrap.sessionId, syndromeId);
    await _loadActiveProblems(bootstrap.sessionId);
  }

  /// 切换 P2 子阶段（对齐 RN handleNextSubphase 循环）：
  /// DIAGNOSIS → PRACTICE → FEEDBACK → DIAGNOSIS，持久化失败回滚
  Future<void> _handleNextSubphase() async {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;
    final prev = _subphase;
    final next = switch (prev) {
      TeachingSubphase.diagnosis => TeachingSubphase.practice,
      TeachingSubphase.practice => TeachingSubphase.feedback,
      TeachingSubphase.feedback => TeachingSubphase.diagnosis,
      null => TeachingSubphase.diagnosis,
    };
    setState(() => _subphase = next);
    try {
      await ref
          .read(chatServiceProvider)
          .setSubphase(bootstrap.sessionId, next);
    } catch (_) {
      if (mounted) setState(() => _subphase = prev);
    }
  }

  Future<void> _handleSend(
    String text, {
    TeachingSubphase? subphase,
    void Function(TrainingResult)? onTrainingResult,
    // 批次49：流式阶段标签（诊断/评估等场景 ThinkingIndicator 阶段化文案）
    String? stageLabel,
  }) async {
    if (text.isEmpty) return;
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    // 解析 @ 引用（对齐 RN handleSend）：引用对象添加为会话附加引用，
    // 发送清理后的文本（引用内容由 chat_context_builder 注入上下文）
    //
    // 批次 39（引用死数据修复）：无主引用时首条 @ 引用自动设为主引用，
    // 使保存到文件/相关对话等依赖主引用的链路可用（对齐批次 4b 决策
    // 「无主引用时首个自动设主」）；同时给出 SnackBar 反馈，让引用可感知。
    var textToSend = text;
    final addedTitles = <String>[];
    // 批次71：@ 引用快照（JSON 数组字符串），随消息落库供气泡徽章展示 + 点击跳转
    String? referencesJson;
    // 批次6（6.2）：记录首条自动设为主引用的引用标题，用于显式 SnackBar 提示
    String? autoPrimaryTitle;
    // 批次7（D2）：自动设主仅对 manuscript/chapter 生效（file 只作次引用）
    var autoPrimaryAssigned = false;
    try {
      final result = await ref.read(mentionParserProvider).parseMentions(text);
      final refRepo = ReferenceRepository(ref.read(appDatabaseProvider));
      final existing = await refRepo.listReferencesOfSession(
        bootstrap.sessionId,
      );
      final hasPrimary = existing.any((r) => r.isPrimary == 1);
      for (var i = 0; i < result.mentions.length; i++) {
        final mention = result.mentions[i];
        // 批次7（D2）：file 允许作次引用（v21 CHECK 已扩），但不可设主
        if (mention.refType == 'file') {
          await refRepo.addReference(
            bootstrap.sessionId,
            mention.refType,
            mention.refId,
            isPrimary: false,
          );
          addedTitles.add(mention.title);
          continue;
        }
        // 无主引用时首条引用自动设主（幂等：后续 @ 均为附加引用）
        final autoPrimary = !hasPrimary && !autoPrimaryAssigned;
        if (autoPrimary) {
          autoPrimaryTitle = mention.title;
          autoPrimaryAssigned = true;
        }
        await refRepo.addReference(
          bootstrap.sessionId,
          mention.refType,
          mention.refId,
          isPrimary: autoPrimary,
        );
        addedTitles.add(mention.title);
      }
      if (result.cleanedText.isNotEmpty) textToSend = result.cleanedText;
      // 批次71：引用快照序列化（气泡徽章展示 + 点击跳转用）
      if (result.mentions.isNotEmpty) {
        referencesJson = jsonEncode([
          for (final m in result.mentions)
            {
              'refType': m.refType,
              'refId': m.refId,
              'manuscriptId': m.manuscriptId,
              'title': m.title,
            },
        ]);
      }
    } catch (_) {
      // 解析失败时直接发送原文本
      textToSend = text;
    }
    if (textToSend.trim().isEmpty) return;

    // @ 引用反馈：让用户感知引用已生效（修复「引用是死数据」的无反馈问题）
    // 批次6（6.2）：自动设主时显式提示主引用归属，避免用户困惑哪个引用被设主
    if (addedTitles.isNotEmpty && mounted) {
      final feedback = autoPrimaryTitle != null
          ? '已引用：${addedTitles.join('、')}（$autoPrimaryTitle 已自动设为主引用）'
          : '已引用：${addedTitles.join('、')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(feedback)),
      );
    }

    ref.read(chatStoreProvider.notifier).setStreaming(
          true,
          stageLabel: stageLabel,
        );

    final chatService = ref.read(chatServiceProvider);
    try {
      await chatService.sendMessage(
        bootstrap.sessionId,
        textToSend,
        SendMessageCallbacks(
          onStream: (delta) {
            ref.read(chatStoreProvider.notifier).appendStreamingContent(delta);
          },
          onComplete: (fullContent, messageId) async {
            final sessionRepo = SessionRepository(
              ref.read(appDatabaseProvider),
            );
            final messages = await sessionRepo.listMessages(
              bootstrap.sessionId,
            );
            ref.read(chatStoreProvider.notifier).setMessages(messages);
            ref.read(chatStoreProvider.notifier).setStreaming(false);
            // 批次 12：发送完成后延迟检查态度建议（对齐 RN）
            _scheduleAttitudeCheck();
          },
          onError: (error) {
            ref.read(chatStoreProvider.notifier).setError(error);
          },
          onTrainingResult: onTrainingResult,
        ),
        SendMessageOptions(
          phase: TeachingPhase.p0Engage,
          attitude: _attitude,
          // 批次7 O1：心流判定叠加编辑器活跃维度（对齐 writing_coach_panel）。
          // 用户刚在写作页编辑后切回对话页发消息，isInFlow 可识别"编辑器活跃"
          // 即时反馈窗口（批次59/64 三问第 3 问触发）。
          lastEditorEditAtSec: ref.read(editorActivityProvider),
          // 批次71：@ 引用快照随消息落库
          referencesJson: referencesJson,
        ),
        subphase: subphase,
      );
    } catch (e) {
      ref.read(chatStoreProvider.notifier).setError(e.toString());
    }
    if (mounted) {
      setState(() => _inputText = '');
    }
  }

  /// T3 训练系统：提交练习作答（复用 _handleSend 链路，强制 subphase=FEEDBACK，
  /// 使 chat_service 步骤 11 的 parseTrainingResult + teaching_history 落库生效）
  Future<void> _submitPractice(String content) async {
    final practiceStore = ref.read(practiceStoreProvider.notifier);
    practiceStore.setSubmitting(true);
    try {
      await _handleSend(
        content,
        subphase: TeachingSubphase.feedback,
        // 批次49：训练评估打标
        stageLabel: '正在评估你的改写…',
        onTrainingResult: (result) {
          practiceStore.setTrainingResult(result);
          _buildEvaluationReportForLastMessage();
        },
      );
    } finally {
      practiceStore.setSubmitting(false);
      practiceStore.submitPractice();
    }
  }

  /// T4 评估报告：训练反馈落库后，为最后一条 assistant 消息构建评估报告
  /// （对齐 RN chat.tsx：训练完成后 buildEvaluationReport 挂到消息）
  Future<void> _buildEvaluationReportForLastMessage() async {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;
    final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
    final messages = await sessionRepo.listMessages(bootstrap.sessionId);
    final lastAssistant = messages
        .where((m) => m.role == 'assistant')
        .lastOrNull;
    if (lastAssistant != null) {
      await ref
          .read(evaluationReportsProvider.notifier)
          .buildEvaluationReport(bootstrap.sessionId, lastAssistant.id);
    }
  }

  /// 批次61：Teacher 建议卡「教我原理」→ 发送原理讲解请求（反馈三层结构 D 选项）
  void _handleTeachPrinciple(String syndromeName) {
    if (ref.read(chatStoreProvider).isStreaming) return;
    setState(() => _inputText = '');
    _handleSend(
      '我想了解「$syndromeName」的原理。请用简单的话给我讲清楚：'
      '它是什么、怎么判断、怎么避免。一次只讲一个点。',
    );
    _scheduleAttitudeCheck();
  }
}
