// ─────────────────────────────────────────────────────────────
// TeacherSuggestionCard — Teacher 建议卡片
//
// 记忆硬约束：
//   「Teacher建议必须作为可交互卡片出现在对话流中，
//     显示症候名称而非代号，包含「开始练习」「跳过此建议」「查看详情」三个按钮」
//
// 视觉规范（月色竹青）：
//   - 卡片：#F7F8F6 + 圆角 12 + 左 4dp 竹青色条
//   - 症候名称 chip：竹青淡 #E8F0EE + 深墨竹青字 #2D5A52
//   - 主按钮「开始练习」：竹青底 #2D5A52 + 白字
//   - 次要按钮：描边 + 深灰字
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/teacher_suggestion_repository.dart';
import '../providers/app_providers.dart';
import '../providers/practice_providers.dart';
import '../services/message_card_service.dart';

/// 教学决策文案映射
const Map<String, String> _decisionText = {'guide': '引导练习', 'train': '强化训练'};

/// 任务类型文案映射
const Map<String, String> _taskTypeText = {
  'rewrite': '改写',
  'analyze': '分析',
  'compare': '对比',
  'generate': '生成',
};

/// 难度文案映射
const Map<String, String> _difficultyText = {
  'easy': '入门',
  'medium': '进阶',
  'hard': '挑战',
};

class TeacherSuggestionCard extends ConsumerStatefulWidget {
  final TeacherSuggestionCardPayload payload;

  /// 「开始练习」回调；为空时点击提示"训练功能即将上线"
  final VoidCallback? onStartPractice;

  /// 批次61：「教我原理」回调（参数 = 症候名）；为空时点击提示兜底文案
  final ValueChanged<String>? onTeachPrinciple;

  const TeacherSuggestionCard({
    super.key,
    required this.payload,
    this.onStartPractice,
    this.onTeachPrinciple,
  });

  /// 便利构造：从 Message.content 的 JSON 解析 payload 渲染
  static TeacherSuggestionCard fromMessageContent(
    String content, {
    Key? key,
    VoidCallback? onStartPractice,
    ValueChanged<String>? onTeachPrinciple,
  }) {
    try {
      return TeacherSuggestionCard(
        key: key,
        payload: TeacherSuggestionCardPayload.fromJson(
          jsonDecode(content) as Map<String, dynamic>,
        ),
        onStartPractice: onStartPractice,
        onTeachPrinciple: onTeachPrinciple,
      );
    } catch (_) {
      // 兜底：空建议卡（正常不会触发）
      return TeacherSuggestionCard(
        key: key,
        payload: TeacherSuggestionCardPayload(
          suggestionId: '',
          teachingDecision: 'guide',
          naturalLanguage: '',
          taskType: '',
          taskDescription: '',
          difficulty: '',
          evaluationCriteria: const [],
          source: 'diagnosis',
        ),
        onStartPractice: onStartPractice,
        onTeachPrinciple: onTeachPrinciple,
      );
    }
  }

  @override
  ConsumerState<TeacherSuggestionCard> createState() =>
      _TeacherSuggestionCardState();
}

class _TeacherSuggestionCardState extends ConsumerState<TeacherSuggestionCard> {
  bool _expanded = false;
  bool _dismissed = false;
  bool _showLocations = false;

  @override
  void initState() {
    super.initState();
    // 批次75：跳过持久化——重建时按 DB dismissedAt 过滤，滚动回收不再重现
    _restoreDismissed();
  }

  Future<void> _restoreDismissed() async {
    final id = widget.payload.suggestionId;
    if (id.isEmpty) return;
    try {
      final dismissed = await TeacherSuggestionRepository(
        ref.read(appDatabaseProvider),
      ).isDismissed(id);
      if (dismissed && mounted) setState(() => _dismissed = true);
    } catch (_) {
      // 反查失败保持显示（兜底）
    }
  }

  /// 批次62：采纳回写——「开始练习」时记录 adoptedAt
  Future<void> _markAdopted() async {
    final id = widget.payload.suggestionId;
    if (id.isEmpty) return;
    final db = ref.read(appDatabaseProvider);
    try {
      await TeacherSuggestionRepository(db).markAdopted(id);
    } catch (_) {
      // 落库失败不影响练习启动
    }
  }

  /// 跳过此建议：批次62 起标记 dismissed（用户见过但未采纳）+ 本地隐藏
  Future<void> _dismiss() async {
    final id = widget.payload.suggestionId;
    final db = ref.read(appDatabaseProvider);
    try {
      if (id.isNotEmpty) {
        await TeacherSuggestionRepository(db).markDismissed(id);
      }
    } catch (_) {
      // 落库失败仍本地隐藏（卡片消息仍在，下次拉取可重现）
    }
    if (mounted) setState(() => _dismissed = true);
  }

  /// 开始练习：T3 接入训练系统；批次62 先回写采纳状态
  ///
  /// 优先用外部回调（宿主可自定义），否则从 payload 构造 PracticeTask
  /// 并启动全局练习状态（practiceStoreProvider）。
  void _handleStartPractice() {
    _markAdopted();
    if (widget.onStartPractice != null) {
      widget.onStartPractice!();
      return;
    }
    final p = widget.payload;
    final criteriaText = p.evaluationCriteria.isEmpty
        ? '对照评估标准完成写作练习'
        : '对照评估标准：${p.evaluationCriteria.join('；')}';
    ref
        .read(practiceStoreProvider.notifier)
        .startPractice(
          PracticeTask(
            syndromeId: p.targetSyndromeId,
            syndromeName: p.targetSyndromeName,
            taskDescription: p.taskDescription.isEmpty
                ? '针对「${p.targetSyndromeName ?? '当前问题'}」完成一段针对性写作练习。'
                : p.taskDescription,
            taskGoal: criteriaText,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final p = widget.payload;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xsm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左侧 4dp 竹青主色条
                Container(width: 4, color: AppColors.primary),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(p),
                        const SizedBox(height: 10),
                        _buildDescription(p),
                        const SizedBox(height: 10),
                        _buildButtons(),
                        if (_expanded) ...[
                          const SizedBox(height: 10),
                          _buildDetails(p),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 头部：建议标题 + 症候名称 chip + 难度徽标
  Widget _buildHeader(TeacherSuggestionCardPayload p) {
    final decision = _decisionText[p.teachingDecision] ?? p.teachingDecision;
    final difficulty = p.difficulty.isEmpty
        ? ''
        : (_difficultyText[p.difficulty] ?? p.difficulty);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.l1,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            // 症候名称优先，无则显示决策类型
            p.targetSyndromeName ?? decision,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
        if (difficulty.isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.l2,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              difficulty,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.l2Text,
              ),
            ),
          ),
        ],
        const Spacer(),
        const Text(
          '训练建议',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// 主内容：任务描述
  Widget _buildDescription(TeacherSuggestionCardPayload p) {
    return Text(
      p.taskDescription.isEmpty ? p.naturalLanguage : p.taskDescription,
      style: const TextStyle(
        fontSize: 14,
        height: 1.5,
        color: AppColors.textPrimary,
      ),
    );
  }

  /// 教我原理：向 AI 请求讲解该症候的原理（反馈三层结构「选择」的 D 选项）
  void _handleTeachPrinciple() {
    final name = widget.payload.targetSyndromeName;
    final callback = widget.onTeachPrinciple;
    if (callback != null) {
      callback(name ?? '这个写法问题');
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            name == null ? '原理讲解将随对话展开' : '已记录：「$name」的原理会在后续对话中讲解',
          ),
        ),
      );
    }
  }

  /// 两行按钮：第一行「开始练习 | 跳过此建议」，第二行「查看详情 | 教我原理」
  /// 批次63（B62d）：locationMarks 非空时第二行追加「标注位置」按钮
  Widget _buildButtons() {
    final hasLocations = widget.payload.locationMarks.isNotEmpty;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: _handleStartPractice,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('开始练习'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 34,
                child: OutlinedButton(
                  onPressed: _dismiss,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textDeep,
                    side: const BorderSide(color: AppColors.borderSoft),
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('跳过此建议'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: OutlinedButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textDeep,
                    side: const BorderSide(color: AppColors.borderSoft),
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(_expanded ? '收起详情' : '查看详情'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 34,
                child: OutlinedButton(
                  onPressed: _handleTeachPrinciple,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textDeep,
                    side: const BorderSide(color: AppColors.borderSoft),
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('教我原理'),
                ),
              ),
            ),
            if (hasLocations) ...[
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    onPressed: () =>
                        setState(() => _showLocations = !_showLocations),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: EdgeInsets.zero,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(_showLocations ? '收起位置' : '标注位置'),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (_showLocations && hasLocations) ...[
          const SizedBox(height: 10),
          _buildLocations(widget.payload.locationMarks),
        ],
      ],
    );
  }

  /// 批次63（B62d）：位置清单块——段落位置 + 原文摘录，供学员自查修改（AI 不代改）
  Widget _buildLocations(List<String> locations) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.smx),
      decoration: BoxDecoration(
        color: AppColors.l1,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '问题位置（自查修改，月笙不改写你的正文）：',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < locations.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      locations[i],
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.textDeep,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 详情块：自然语言说明 + 任务类型 + 评估标准
  Widget _buildDetails(TeacherSuggestionCardPayload p) {
    final taskType = p.taskType.isEmpty
        ? ''
        : (_taskTypeText[p.taskType] ?? p.taskType);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.smx),
      decoration: BoxDecoration(
        color: AppColors.l1,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.naturalLanguage.isNotEmpty) ...[
            Text(
              p.naturalLanguage,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textDeep,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (taskType.isNotEmpty)
            Row(
              children: [
                const Text(
                  '任务类型：',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  taskType,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDeep,
                  ),
                ),
              ],
            ),
          if (p.evaluationCriteria.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              '评估标准：',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < p.evaluationCriteria.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${i + 1}.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        p.evaluationCriteria[i],
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.textDeep,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
