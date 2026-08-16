// ─────────────────────────────────────────────────────────────
// Reviewer Service
// 复刻 yuesheng-android/src/services/reviewer-service.ts
//
// 用 chatCompletion 调 reviewer skill，parse + validate，
// 失败返回 null（严格降级）。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/services/agent_skills.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/reviewer_parser.dart';
import 'package:writingcoach/services/reviewer_validator.dart';

/// 调用 Reviewer Agent 对文本做 PASS/FAIL 二元判决。
///
/// 真源：reviewer-service.ts callReviewer
///
/// 任何失败点（网络/解析/校验）都返回 null，调用方走现有流程。
Future<ReviewerResult?> callReviewer(LlmClient llmClient, String text) async {
  try {
    final userPrompt = '请按审稿步骤审稿以下小说文本，输出 [YS_REVIEW] JSON。\n\n$text';
    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: kReviewerSkillContent),
      ChatMessage(role: 'user', content: userPrompt),
    ];

    final raw = await llmClient.chatCompletion(messages);

    final parsed = parseReviewerReview(raw);
    if (parsed.review == null) return null;

    // parser 已做 schema 校验，service 只做 consistency 校验
    // （修复 P0 bug：原代码传 ReviewerResult 给 validateReviewerOutput，
    //  该函数期望原始 JSON Map，导致 schema 校验恒失败、所有合法输入返回 null）
    final consistency = checkConsistency(parsed.review!);
    if (!consistency.passed) return null;

    return parsed.review;
  } catch (_) {
    return null;
  }
}
