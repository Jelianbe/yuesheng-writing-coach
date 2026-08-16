part of 'chat_service.dart';

extension ChatServiceObservers on ChatService {
  /// D8 轻量观测：评估顺序（学员自评 → 改前改后对比 → AI 评估）
  /// 约束源为 skill 指令（skill_registry.dart 阶段3 三步评估流程），非代码强制；
  /// 此处仅 debug 级留痕「FEEDBACK 回复是否按顺序走全三步」，不改变任何行为。
  /// 检测标记：自评引导（"你自己觉得改得怎么样"类）→ 改前改后对比（唯一不可省略）
  /// → 评估三档（含"达标"字样）。观测失败不阻断主流程。
  void _observeEvaluationOrder(String reply) {
    if (!kDebugMode) return;
    final hasSelfEval = RegExp(r'你自己(觉得|认为)|你觉得(自己|刚才)?改得').hasMatch(reply);
    final hasContrast = RegExp(
      r'改(之前|以前|前).{0,60}(改(之后|以后|后)|现在.{0,20}(是|变成))',
    ).hasMatch(reply);
    final hasAssessment = reply.contains('达标');
    debugPrint(
      '[D8 评估顺序观测] 自评引导=$hasSelfEval 改前改后对比=$hasContrast '
      '评估三档=$hasAssessment（仅观测不干预）',
    );
  }

  /// 批次50 临时测量：回复长度观测（standard 档是否真超长）
  /// 「回复颗粒度真人感收敛」决策前置——先量化标准档回复长度分布再决定约束方案。
  /// 仅 debug 级留痕（长度 + 分档 + 颗粒度 + 态度 + 子阶段 + 意图），不改变任何行为；
  /// 批次 52 汇成节奏体检报告后按结论决定保留或删除。观测失败不阻断主流程。
  void _observeReplyLength(
    String reply,
    String userInput,
    AttitudeLevel attitude,
    TeachingSubphase? subphase,
  ) {
    if (!kDebugMode) return;
    final len = reply.length;
    String bucket;
    if (len <= 30) {
      bucket = '≤30(一句)';
    } else if (len <= 80) {
      bucket = '31-80(短段)';
    } else if (len <= 160) {
      bucket = '81-160(中段)';
    } else {
      bucket = '>160(长段)';
    }
    final detail = detectReplyDetail(userInput);
    final intent = classifyUserIntent(userInput);
    debugPrint(
      '[批次50 回复长度观测] 长度=$len($bucket) 颗粒度=${detail.value} '
      '态度=${attitude.value} 子阶段=${subphase?.value ?? 'null'} '
      '意图=${intent.value}（仅观测不干预）',
    );
  }

  /// 预加载所有引用的详情到缓存（buildReferencesContext 调用前使用）
  Future<void> _preloadReferenceDetails(List<ReferencedItem> refs) async {
    for (final ref in refs) {
      try {
        if (ref.refType == 'file') {
          final file = await _referenceRepo.getAttachedFile(ref.refId);
          if (file != null) {
            _cachedAttachedFiles[ref.refId] = file;
          }
        } else if (ref.refType == 'chapter') {
          final ch = await _chapterRepo.getChapter(ref.refId);
          if (ch != null) {
            _cachedChapters[ref.refId] = ChapterBrief(
              id: ch.id,
              title: ch.title,
              wordCount: ch.wordCount,
              sortOrder: ch.sortOrder,
              content: ch.content,
            );
          }
        } else if (ref.refType == 'manuscript') {
          final m = await _manuscriptRepo.getManuscript(ref.refId);
          if (m == null) continue;
          final chapters = await _chapterRepo.listChapters(ref.refId);
          final chapterBriefs = chapters
              .map(
                (ch) => ChapterBrief(
                  id: ch.id,
                  title: ch.title,
                  wordCount: ch.wordCount,
                  sortOrder: ch.sortOrder,
                  content: ch.content,
                ),
              )
              .toList();
          _cachedManuscripts[ref.refId] = ManuscriptDetail(
            genre: m.genre,
            description: m.description,
            chapters: chapterBriefs,
          );
        }
      } catch (e) {
        debugPrint('[SafeRun] 单个引用加载失败不阻断整体: $e');
      }
    }
  }
}
