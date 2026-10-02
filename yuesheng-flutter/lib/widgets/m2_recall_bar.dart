// ─────────────────────────────────────────────────────────────
// M2RecallBar — M2「看懂诊断」复述根因入口（ADR-C133 批2）
//
// 背景（ADR-C133 §4.2 / 裁决三件套 §1.2）：
//   M2 门槛事件 = 学员**用自己的话**复述诊断根因（非照抄）+ 教练确认
//   「复述到位」(confirmed)。本组件提供克制的复述入口与教练核对落库触发点：
//
//   idle     → 一个安静的入口「用自己的话复述根因」
//   editing  → 多行输入框（提交复述）
//   picking  → 复述文本只读展示 + 教练核对结果二选一（到位 / 需修正）
//   recorded → 落库成功后的只读留痕（不重复记录）
//
// 设计取舍（写明）：
//   - **本批不把复述自动派发进对话流、也不加 prompt 标记解析**——那会触及
//     批 1b 正在并行施工的实时消息链路，并触发 R-027 UPDATE_SNAPSHOTS 重冻。
//     故教练核对结果由本组件在学员读完教练对话回复后**如实、显式地记录**
//     （confirmed/corrected），是教学交互的 append-only 留痕，而非系统自动判定。
//   - **R-009 红线**：本组件不计算「复述是否照抄/是否到位」的对错——
//     复述文本原样落 afterText，确认结果由教练核对步骤显式选择；
//     组件内无任何学员打分/达标/成败布尔。是否计入 M2 由用户在证据卡裁决。
//
// 复用 C132 anchor_ack 的现场形态：与 _SyndromeConfirmationBar 同为诊断卡
// 症候块底部的轻量交互条，复用父级已解析好的 sessionId/chapterId/messageId。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/app_palette.dart';
import '../theme/app_typography.dart';
import '../data/repositories/edit_diff_event_repository.dart';
import '../providers/app_providers.dart';
import '../services/decode_guard.dart';

/// M2 复述交互条（挂在诊断卡每个症候块底部；无诊断上下文时父级不渲染）。
class M2RecallBar extends ConsumerStatefulWidget {
  /// 被复述根因所属症候（落库关联）。
  final String syndromeId;
  final String syndromeName;

  /// 诊断根因原文（= 症候 explanation「为什么」行）；落库作 beforeText 锚点。
  final String rootCauseText;

  final String sessionId;
  final String chapterId;
  final String? messageId;

  const M2RecallBar({
    super.key,
    required this.syndromeId,
    required this.syndromeName,
    required this.rootCauseText,
    required this.sessionId,
    required this.chapterId,
    this.messageId,
  });

  @override
  ConsumerState<M2RecallBar> createState() => _M2RecallBarState();
}

class _M2RecallBarState extends ConsumerState<M2RecallBar> {
  /// 交互阶段：idle / editing / picking / recorded。
  String _phase = 'idle';
  final _controller = TextEditingController();

  /// 已提交待核对的复述文本（picking 阶段只读展示）。
  String? _recall;

  /// 已落库的确认结果（recorded 阶段；confirmed|corrected）。
  String? _recordedVerdict;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 失败反馈（与 _SyndromeConfirmationBar 同判据：点了就要被告知为什么没成）。
  void _showFailure(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 提交复述：非空校验 → 进入教练核对阶段（此时还不落库，等确认结果）。
  void _submitRecall() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _showFailure('先写两句你自己的理解，再提交');
      return;
    }
    setState(() {
      _recall = text;
      _phase = 'picking';
    });
  }

  /// 教练核对结果落库（confirmed / corrected 二选一；只记不判）。
  Future<void> _commitVerdict(String verdict) async {
    if (_submitting || _recall == null) return;
    setState(() => _submitting = true);
    try {
      await EditDiffEventRepository(
        ref.read(appDatabaseProvider),
      ).recordM2Recall(
        sessionId: widget.sessionId,
        chapterId: widget.chapterId,
        messageId: widget.messageId,
        syndromeId: widget.syndromeId,
        syndromeName: widget.syndromeName,
        recallText: _recall!,
        rootCauseText: widget.rootCauseText,
        verdict: verdict,
      );
      if (mounted) {
        setState(() {
          _recordedVerdict = verdict;
          _phase = 'recorded';
        });
      }
    } catch (e, st) {
      // 落库失败停在 picking（可重试）——留痕，不静默吞。
      logSilentDegrade(operation: 'recordM2Recall', error: e, stack: st);
      _showFailure('复述记录失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.palette.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: switch (_phase) {
        'editing' => _buildEditing(),
        'picking' => _buildPicking(),
        'recorded' => _buildRecorded(),
        _ => _buildIdle(),
      },
    );
  }

  /// idle：安静入口（弱色，不与诊断正文抢注意力）。
  Widget _buildIdle() {
    return InkWell(
      onTap: () => setState(() => _phase = 'editing'),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit_note_outlined,
              size: 15,
              color: context.palette.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              '用自己的话复述根因',
              style: context.text.caption.copyWith(
                color: context.palette.textTertiary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// editing：复述输入框。
  Widget _buildEditing() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '别照抄上面那句，用你自己的话说说：这个问题的根因是什么？',
          style: context.text.caption.copyWith(fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '用自己的理解复述根因……',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _phase = 'idle'),
              style: _smallBtn(),
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _submitRecall,
              style: _smallBtn(),
              child: const Text('提交复述'),
            ),
          ],
        ),
      ],
    );
  }

  /// picking：复述只读展示 + 教练核对结果二选一（教学交互留痕，非学员打分）。
  Widget _buildPicking() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('你的复述', style: context.text.caption.copyWith(fontSize: 12)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: context.palette.l1,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            _recall!,
            style: context.text.subBody.copyWith(height: 1.5),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '对照教练的回复，这次复述：',
          style: context.text.caption.copyWith(fontSize: 12),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _verdictButton(
              label: '需修正',
              color: context.palette.l3Text,
              onTap: _submitting
                  ? null
                  : () => _commitVerdict(M2RecallVerdict.corrected),
            ),
            const SizedBox(width: 8),
            _verdictButton(
              label: '复述到位',
              color: context.palette.primary,
              onTap: _submitting
                  ? null
                  : () => _commitVerdict(M2RecallVerdict.confirmed),
            ),
          ],
        ),
      ],
    );
  }

  /// recorded：落库后只读留痕（不重复记录）。
  Widget _buildRecorded() {
    final ok = _recordedVerdict == M2RecallVerdict.confirmed;
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.edit_outlined,
          size: 15,
          color: ok ? context.palette.primary : context.palette.l2Text,
        ),
        const SizedBox(width: 6),
        Text(
          ok ? '已记录复述（到位）' : '已记录复述（需修正，继续和教练对齐）',
          style: context.text.caption.copyWith(fontSize: 12),
        ),
      ],
    );
  }

  ButtonStyle _smallBtn() => TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  Widget _verdictButton({
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
