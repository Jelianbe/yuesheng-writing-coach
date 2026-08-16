// ─────────────────────────────────────────────────────────────
// ProficiencyRing — 熟练度竹青进度环（方案 A）
//
// 视觉规范（月色竹青）:
//   进度环 = #2D5A52（竹青）
//   底环   = #E0E4E0（浅灰）
//   中心文本 = 等级中文标签（不显示百分比，避免 UX 误导）
//
// 进度语义（方案 A）:
//   progress = 等级位置（非 confidence）
//     beginner=0.25 / elementary=0.5 / intermediate=0.75 / advanced=1.0
//   环满 = 满级，符合直觉
//   confidence 仅用于"数据不足"判断（< 0.3 显示"数据不足"，progress=0）
//
// 用 CustomPaint 实现，无第三方图表库
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../types/teaching_types.dart';

/// 熟练度竹青进度环 — 方案 A（progress = 等级位置）
class ProficiencyRing extends StatelessWidget {
  final ProficiencyLevel level;
  final double confidence;
  final double size;

  const ProficiencyRing({
    super.key,
    required this.level,
    required this.confidence,
    this.size = 120,
  });

  static const _progressColor = AppColors.primary;
  static const _trackColor = AppColors.border;
  static const _textColor = AppColors.textPrimary;

  /// 数据不足阈值（confidence < 0.3 视为数据不足）
  static const _insufficientThreshold = 0.3;

  String get _levelLabel {
    switch (level) {
      case ProficiencyLevel.beginner:
        return '新手';
      case ProficiencyLevel.elementary:
        return '入门';
      case ProficiencyLevel.intermediate:
        return '进阶';
      case ProficiencyLevel.advanced:
        return '熟练';
    }
  }

  /// 数据不足判定
  bool get _isInsufficientData => confidence < _insufficientThreshold;

  /// 进度值（方案 A：等级位置）
  double get _progress {
    if (_isInsufficientData) return 0.0;
    switch (level) {
      case ProficiencyLevel.beginner:
        return 0.25;
      case ProficiencyLevel.elementary:
        return 0.5;
      case ProficiencyLevel.intermediate:
        return 0.75;
      case ProficiencyLevel.advanced:
        return 1.0;
    }
  }

  /// 测试用访问器（不对外暴露，仅测试断言用）
  @visibleForTesting
  double get progressForTest => _progress;

  /// strokeWidth 按 size 比例（默认 120/15=8.0）
  double get _strokeWidth => size / 15;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 进度环
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: _progress,
              progressColor: _progressColor,
              trackColor: _trackColor,
              strokeWidth: _strokeWidth,
            ),
          ),
          // 中心文本（仅等级标签，不显示百分比）
          Text(
            _isInsufficientData ? '数据不足' : _levelLabel,
            style: TextStyle(
              fontSize: size * 0.15, // 120 → 18
              fontWeight: FontWeight.w700,
              color: _textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress; // 0.0 - 1.0
  final Color progressColor;
  final Color trackColor;
  final double strokeWidth;

  _RingPainter({
    required this.progress,
    required this.progressColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;

    // 底环
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // 进度环（从 -π/2 开始，顺时针）
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweepAngle = 2 * 3.141592653589793 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.141592653589793 / 2, // 起始角度（12 点方向）
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
