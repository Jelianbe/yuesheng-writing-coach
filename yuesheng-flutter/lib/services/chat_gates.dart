// ─────────────────────────────────────────────────────────────
// Chat Gates — Teacher 触发判断 + 持久化
// 复刻 yuesheng-android/src/services/chat-gates.ts
//
// 触发条件（方案 A）：
//   - Editor 分支：pronounced >= 1 或 against >= 2
//   - Diagnosis 分支：命中 L2/L3 或症候总数 >= 3
//
// 持久化：guide/train + training_task 时写入 teacher_suggestion 表
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/services/editor_validator.dart';
import 'package:writingcoach/services/teacher_validator.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 判断 Editor observation 是否满足 Teacher 触发条件。
///
/// 真源：chat-gates.ts shouldTriggerTeacherForEditor
bool shouldTriggerTeacherForEditor(EditorResult observation) {
  if (!TeacherGate.enabled) return false;
  final pronouncedCount = observation.observations
      .where((o) => o.observationVisibility == 'pronounced')
      .length;
  final againstCount = observation.observations
      .where((o) => o.intentAlignment == 'against')
      .length;
  return pronouncedCount >= TeacherGate.editorPronouncedThreshold ||
      againstCount >= TeacherGate.editorAgainstThreshold;
}

/// 判断 Diagnosis syndromes 是否满足 Teacher 触发条件。
///
/// 真源：chat-gates.ts shouldTriggerTeacherForDiagnosis
bool shouldTriggerTeacherForDiagnosis(List<Syndrome> syndromes) {
  if (!TeacherGate.enabled) return false;
  final hasL2Plus = syndromes.any(
    (s) => s.severity == Severity.l2 || s.severity == Severity.l3,
  );
  return hasL2Plus ||
      syndromes.length >= TeacherGate.diagnosisSyndromeCountThreshold;
}

/// 批次59：心流窗口——距上一条用户消息不足该秒数视为「心流中」（延迟反馈）
const int kRapidFireWindowSec = 60;

/// 批次64（B62g）：编辑器活跃窗口——最近该秒数内有编辑输入视为「心流中」
const int kEditorActiveWindowSec = 120;

/// 批次59：同症候反馈去重窗口（窗口内已触发过同症候建议则不再触发）
/// 批次4（4.9 O4）：3600s 过长（同问题一小时内重复提醒间隔过久），缩短至 900s；
/// 密集练习时 15 分钟足以承载新一轮反馈点。
const int kDedupeRecencyWindowSec = 900;

/// 批次62：采纳后冷却窗口——用户已采纳过同症候建议，冷却期内不重复触发；
/// 冷却期过后可触发新的/进阶反馈点（Just-in-Time 三问第 2 问）
const int kAdoptedDedupeWindowSec = 1800;

/// 批次1（O1）：Teacher 升级阀——症候严重度达该阈值（L3 重度）时绕过心流窗口。
/// 持续写作学员「编辑器活跃 120s」恒真 → 建议出不来 → identified 永不前进 →
/// M4-A 永不满足；对重度/慢性症候解除心流抑制，保证建议能输出。
const Severity kFlowBypassMinSeverity = Severity.l3;

/// 批次1（O1）：Teacher 升级阀——症候累计诊断次数达该阈值时绕过心流窗口。
const int kFlowBypassDiagnosisCount = 3;

/// 批次59：Just-in-Time 触发三问第 3 问——心流判定。
///
/// 用户持续快速发送消息（距上一条 < [windowSec] 秒）时视为处于写作心流，
/// 应延迟教学反馈，避免打断创作节奏。
bool isRapidFireSend({
  required int? lastSendAtSec,
  required int nowAtSec,
  int windowSec = kRapidFireWindowSec,
}) {
  if (lastSendAtSec == null) return false;
  return (nowAtSec - lastSendAtSec) < windowSec;
}

/// 批次64（B62g）：编辑器活跃判定——最近 [windowSec] 秒内有编辑输入 → 心流中。
///
/// 用户可能长时间不发言但一直在编辑器写作，此时不应弹出教学反馈打断创作。
bool isEditorActive({
  required int? lastEditorEditAtSec,
  required int nowAtSec,
  int windowSec = kEditorActiveWindowSec,
}) {
  if (lastEditorEditAtSec == null) return false;
  return (nowAtSec - lastEditorEditAtSec) < windowSec;
}

/// 批次64（B62g）：综合心流判定——消息频率心流 或 编辑器活跃 任一命中。
///
/// 批次1（O1）：[bypassFlowWindow] 为 Teacher 升级阀——症候严重度/诊断次数
/// 达阈值时绕过心流窗口（重度/慢性问题不能因心流抑制而永远得不到反馈）。
/// 批次6（6.8 M4）：[helpSignal] 为心流求助信号例外——消息文本含求助关键词
/// （不会/怎么/卡住了/没思路）时视为学员主动求助，绕过心流抑制及时反馈，
/// 与 1.3 升级阀（问题侧）互补（求助侧）。
bool isInFlow({
  required int? lastSendAtSec,
  required int? lastEditorEditAtSec,
  required int nowAtSec,
  bool bypassFlowWindow = false,
  String? helpSignal,
}) {
  if (bypassFlowWindow) return false;
  if (isHelpSeekingText(helpSignal)) return false;
  return isRapidFireSend(lastSendAtSec: lastSendAtSec, nowAtSec: nowAtSec) ||
      isEditorActive(
        lastEditorEditAtSec: lastEditorEditAtSec,
        nowAtSec: nowAtSec,
      );
}

/// 批次6（6.8 M4）：心流求助信号关键词——学员消息含以下任一关键词
/// 视为主动求助（「我不会写」「怎么写」「卡住了」「没思路」），
/// 命中时绕过心流抑制，保证求助能立即得到教学反馈。
const Set<String> kHelpSeekingKeywords = {'不会', '怎么', '卡住了', '没思路'};

/// 判断消息文本是否含求助信号（心流抑制例外）。
/// null / 空文本 → false（无求助信号）。
bool isHelpSeekingText(String? text) {
  if (text == null || text.isEmpty) return false;
  return kHelpSeekingKeywords.any(text.contains);
}

/// FT-22 越界输出抑制关键词——学员消息含以下任一关键词
/// 视为「只诊断不要改/不要建议」的明确边界声明，
/// 命中时跳过 teacher stream 调用与 teacher_suggestion 落库，
/// 避免在学员只想要诊断结论时强行塞入修改建议。
///
/// 设计参考：架构真源 §4.4 FT-22 输出边界控制
/// 触发例：「只诊断就好」「不要给建议」「只要找出问题」「先别改」
const Set<String> kDiagnosisOnlyKeywords = {
  '只诊断',
  '只找问题',
  '只要诊断',
  '不要建议',
  '不要给建议',
  '不要改',
  '先别改',
  '先不改',
  '不用改',
  '不用建议',
};

/// FT-22：判断消息文本是否声明「只要诊断不要建议」边界。
/// null / 空文本 → false（无边界声明，走默认行为）。
bool isDiagnosisOnlyRequest(String? text) {
  if (text == null || text.isEmpty) return false;
  return kDiagnosisOnlyKeywords.any(text.contains);
}

/// 持久化 Teacher suggestion（guide/train 档位且有 training_task 时写入）。
///
/// 真源：chat-gates.ts persistTeacherSuggestion
/// DB 写入失败不影响 Teacher 输出（降级 + 返回 null）。
///
/// 批次59 Just-in-Time 增强（对齐 V2.0 §3.3 触发三问）：
///   - [isRapidFire]：心流中 → 延迟反馈（本次不写入，返回 null）
///   - 同症候去重：窗口内已触发过同症候建议 → 不重复骚扰（返回 null）
Future<String?> persistTeacherSuggestion(
  TeacherSuggestionRepository repo,
  TeacherResult teacherResult,
  String sessionId,
  String messageId,
  String source, {
  bool isRapidFire = false,
  int dedupeRecencyWindowSec = kDedupeRecencyWindowSec,
  int adoptedWindowSec = kAdoptedDedupeWindowSec,
}) async {
  // 只有 guide/train 档位才写入；encourage/defer 不入库
  if (teacherResult.teachingDecision != 'guide' &&
      teacherResult.teachingDecision != 'train') {
    return null;
  }
  final task = teacherResult.trainingTask;
  if (task == null) return null;

  try {
    // 批次59：心流中延迟反馈（第 3 问——用户正在快速创作，不打断）
    if (isRapidFire) return null;

    // 批次59/62：会话内同症候去重（第 2 问——同一问题不反复提示；
    // 批次62 采纳语义：已采纳过且过冷却 → 可触发新反馈点）
    final duplicated = await repo.hasDuplicateSuggestion(
      sessionId,
      task.targetSyndromeId,
      recencyWindowSec: dedupeRecencyWindowSec,
      adoptedWindowSec: adoptedWindowSec,
    );
    if (duplicated) return null;

    return await repo.insertTeacherSuggestion(
      InsertTeacherSuggestionParams(
        sessionId: sessionId,
        messageId: messageId,
        source: source,
        teachingDecision: teacherResult.teachingDecision,
        targetSyndromeId: task.targetSyndromeId,
        targetDimension: task.targetDimension,
        taskType: task.taskType,
        taskDescription: task.taskDescription,
        difficulty: task.difficulty,
        evaluationCriteria: task.evaluationCriteria,
      ),
    );
  } catch (_) {
    return null;
  }
}
