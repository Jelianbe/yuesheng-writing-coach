// ─────────────────────────────────────────────────────────────
// 诊断完成提示（短时 floating SnackBar，不遮挡后续操作）。
//
// 从 `writing_coach_panel_diagnosis_runner.dart` 整体搬出（T-20261025-06 件2）：
// Runner 已顶到 R-019 文件级基线（容差 0），件2 新增位次透传必须同时腾出行数。
// 只被 Runner 使用，搬出后由 Runner import，行为与文案逐字不变。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

void showDiagnosisCompleteSnack(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('诊断完成'),
      duration: Duration(milliseconds: 1200),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
