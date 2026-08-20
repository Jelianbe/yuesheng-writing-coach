// ─────────────────────────────────────────────────────────────
// 消息卡片服务 — 确定性触发机制
// 复刻 yuesheng-android/src/services/message-card-service.ts
//
// 解决 AUDIT-REF-5：卡片触发不再依赖 AI 自然语言输出中的标记，
// 而是由系统事件确定性地插入消息卡片到消息流中。
//
// 已实现卡片类型：
//   - insertDiagnosisResultCard（诊断结果卡片）
//   - insertTeacherSuggestionCard（Teacher 建议卡片，D6）
//   - insertReferenceChangeCard / insertPhaseUpgradeCard（批次 9）
//   - partial_agreement / phase_summary / diagnosis_failed（批次 17，渲染层
//     三卡由 message_list 分派 + fromMessageContent 构造）
//   - insertOutlineConfirmationCard（大纲记忆确认卡片，批次73）
// 未实现卡片类型（implicit_user）延后到需要时再补。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/services/genui_parser.dart';

part 'message_card_service_diagnosis.dart';
part 'message_card_service_teaching.dart';
part 'message_card_service_system.dart';
