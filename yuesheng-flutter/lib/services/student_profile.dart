// ─────────────────────────────────────────────────────────────
// 学员画像 — 主入口（IO 层）
// 复刻 yuesheng-android/src/services/student-profile.ts
//
// 职责：
//   - buildStudentContext：聚合诊断历史 → 结构化 profile + 三步推理文本
//   - buildStrategyEffectiveness：聚合历史教学方式效果
//   - inferCognitiveStyle：基于用户消息推断认知风格
//
// 纯计算逻辑见 student_profile_compute.dart，文本格式化见 student_profile_format.dart。
//
// 简化偏差（与 RN 原版）：
//   - inferCognitiveStyle 仅查询当前 sessionId 的用户消息（RN 原版跨所有 session 全表扫描）
//     原因：Flutter SessionRepository 按 sessionId 隔离，跨会话全表扫描需新增 DAO 方法
//     影响有限：认知风格推断主要依赖近期交互关键词，当前 session 已能反映
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/services/student_profile_compute.dart';
import 'package:writingcoach/services/student_profile_format.dart';
import 'package:writingcoach/types/teaching_types.dart';

const List<String> _analyticalKeywords = [
  '逻辑',
  '结构',
  '因果',
  '框架',
  '规则',
  '分析',
  '合理',
  '层次',
  '关系',
  '对比',
];

const List<String> _intuitiveKeywords = [
  '感觉',
  '体会',
  '画面',
  '共鸣',
  '氛围',
  '情绪',
  '感染',
  '代入',
  '味道',
];

const Map<String, String> _modeLabels = {
  'socratic': '苏格拉底追问',
  'mirror': '镜像反馈',
  'conflict': '认知冲突',
  'direct': '直接告知',
};

const Map<String, String> _effectLabels = {
  'improved': '有效',
  'no_change': '无变化',
  'worsened': '恶化',
};

/// 推断认知风格（基于当前 session 的 user 消息关键词）
///
/// 真源：student-profile.ts inferCognitiveStyle
///
/// 偏差：RN 原版跨所有 session 全表扫描 messages，本实现仅查当前 session
Future<CognitiveStyleInference?> inferCognitiveStyle(
  SessionRepository sessionRepo,
  String sessionId,
) async {
  final messages = await sessionRepo.listMessages(sessionId);
  final userMessages = messages.where((m) => m.role == 'user').toList();
  if (userMessages.length < 2) return null;

  final allText = userMessages.map((m) => m.content).join(' ');
  int analyticalCount = 0;
  int intuitiveCount = 0;

  for (final kw in _analyticalKeywords) {
    analyticalCount += _countOccurrences(allText, kw);
  }
  for (final kw in _intuitiveKeywords) {
    intuitiveCount += _countOccurrences(allText, kw);
  }

  final total = analyticalCount + intuitiveCount;
  if (total == 0) return null;

  final ratio = analyticalCount / (intuitiveCount > 0 ? intuitiveCount : 1);
  CognitiveStyle style;
  double confidence;

  if (ratio >= CognitiveStyleThresholds.analyticalRatio) {
    style = CognitiveStyle.analytical;
    confidence = _min(
      CognitiveStyleThresholds.analyticalMaxConfidence,
      CognitiveStyleThresholds.analyticalBaseConfidence +
          total * CognitiveStyleThresholds.analyticalStepFactor,
    );
  } else if (ratio <= CognitiveStyleThresholds.intuitiveRatio) {
    style = CognitiveStyle.intuitive;
    confidence = _min(
      CognitiveStyleThresholds.analyticalMaxConfidence,
      CognitiveStyleThresholds.analyticalBaseConfidence +
          total * CognitiveStyleThresholds.analyticalStepFactor,
    );
  } else {
    style = CognitiveStyle.mixed;
    confidence = _min(
      CognitiveStyleThresholds.mixedMaxConfidence,
      CognitiveStyleThresholds.mixedBaseConfidence +
          total * CognitiveStyleThresholds.mixedStepFactor,
    );
  }

  return CognitiveStyleInference(style: style, confidence: confidence);
}

int _countOccurrences(String text, String sub) {
  int count = 0;
  int idx = 0;
  while ((idx = text.indexOf(sub, idx)) != -1) {
    count++;
    idx += sub.length;
  }
  return count;
}

/// 构建历史策略效果文本
///
/// 真源：student-profile.ts buildStrategyEffectiveness
Future<String> buildStrategyEffectiveness(
  StudentModelRepository studentModelRepo,
  String sessionId,
) async {
  final history = await studentModelRepo.getTeachingHistory(sessionId);
  final modeRecords = history.where((r) {
    return r['type'] == 'diagnosis' &&
        r['teaching_mode'] != null &&
        r['effectiveness'] != null;
  }).toList();

  if (modeRecords.length < 2) return '';

  // 按 syndromeId 分组
  final grouped = <String, List<_ModeEntry>>{};
  for (final r in modeRecords) {
    final mode = r['teaching_mode'] as String?;
    if (mode == null) continue;
    final syndromes = r['syndromes'];
    if (syndromes is! List) continue;
    final eff = r['effectiveness'] as String;
    for (final sid in syndromes) {
      if (sid is! String) continue;
      final list = grouped.putIfAbsent(sid, () => <_ModeEntry>[]);
      final idx = list.indexWhere((g) => g.mode == mode);
      if (idx >= 0) {
        final existing = list[idx];
        existing.attempts++;
        if (eff != 'no_change') existing.eff = eff;
      } else {
        list.add(_ModeEntry(mode: mode, eff: eff, attempts: 1));
      }
    }
  }

  final lines = <String>[];
  grouped.forEach((sid, entries) {
    final tried = entries.map((e) {
      final modeLabel = _modeLabels[e.mode] ?? e.mode;
      final effLabel = _effectLabels[e.eff] ?? e.eff;
      return '$modeLabel × ${e.attempts} 次（$effLabel）';
    }).toList();
    if (tried.isNotEmpty) {
      final staleModes = entries
          .where((e) => e.attempts >= 2 && e.eff == 'no_change')
          .map((e) => _modeLabels[e.mode] ?? e.mode)
          .toList();
      final tip = staleModes.isNotEmpty
          ? ' ⚠️ ${staleModes.join('、')} 连续无效，建议切换'
          : '';
      lines.add('- $sid：${tried.join('；')}$tip');
    }
  });

  return lines.join('\n');
}

/// 构建学员画像上下文（主入口）
///
/// 真源：student-profile.ts buildStudentContext
Future<ProfileTextResult> buildStudentContext({
  required DiagnosisRepository diagnosisRepo,
  required StudentModelRepository studentModelRepo,
  required SessionRepository sessionRepo,
  String? sessionId,
}) async {
  // M1 修复：诊断查询用 null（跨 session 全局聚合），让 LLM 看到全局画像
  // sessionId 仍用于 onboarding/cognitiveStyle/effectiveness 等会话级数据
  final entries = await diagnosisRepo.getAllDiagnoses(sessionId: null);
  // ADR-C71 §3.2：onboarding 写入是 session 级而问卷用户级只弹一次，
  // 本会话查不到时回退取全库最新有效数据（skipped 过滤不变），
  // 否则第二个会话起初始画像永久失忆。
  OnboardingData? onboarding;
  if (sessionId != null) {
    final raw = await studentModelRepo.getOnboardingData(sessionId);
    if (raw != null) {
      onboarding = OnboardingData.fromJson(raw);
    } else {
      final fallbackRaw = await studentModelRepo.getLatestOnboardingData();
      if (fallbackRaw != null) {
        onboarding = OnboardingData.fromJson(fallbackRaw);
      }
    }
  }
  final effectiveOnboarding = (onboarding != null && !onboarding.skipped)
      ? onboarding
      : null;

  if (entries.isEmpty && effectiveOnboarding == null) {
    return ProfileTextResult(
      text: '',
      profile: StudentProfile(
        proficiency: ProficiencyLevel.beginner,
        confidence: 0,
        syndromeProfile: const {},
        totalSessions: 0,
      ),
    );
  }

  final syndromeProfile = computeSyndromeProfile(entries);

  final allSeverities = syndromeProfile.values
      .expand((agg) => agg.severityHistory)
      .toList();

  final proficiency = effectiveOnboarding != null
      ? ProficiencyInference(
          level: effectiveOnboarding.proficiency,
          confidence: 0.5,
        )
      : inferProficiency(allSeverities);

  CognitiveStyleInference? cognitiveStyle;
  if (effectiveOnboarding != null) {
    cognitiveStyle = CognitiveStyleInference(
      style: effectiveOnboarding.cognitiveStyle,
      confidence: 0.5,
    );
  } else if (sessionId != null) {
    try {
      cognitiveStyle = await inferCognitiveStyle(sessionRepo, sessionId);
    } catch (_) {
      // 认知风格推断失败不阻断主流程
    }
  }

  final allSessionIds = entries.map((e) => e.sessionId).toSet();

  final profile = StudentProfile(
    proficiency: proficiency.level,
    confidence: proficiency.confidence,
    cognitiveStyle: cognitiveStyle,
    syndromeProfile: syndromeProfile,
    totalSessions: allSessionIds.length,
  );

  final stagnation = detectStagnation(syndromeProfile, allSessionIds.length);

  // 合并策略效果到第三步
  String? effectivenessText;
  if (sessionId != null) {
    try {
      effectivenessText = await buildStrategyEffectiveness(
        studentModelRepo,
        sessionId,
      );
    } catch (_) {
      // 效果追踪非关键，失败不阻断
    }
  }

  // M2 修复：读取跨 session 最新写作风格画像，注入 LLM
  String? styleProfileText;
  try {
    final styleProfile = await studentModelRepo.getLatestStyleProfile();
    if (styleProfile != null) {
      styleProfileText = _formatStyleProfile(styleProfile);
    }
  } catch (_) {
    // 风格画像非关键，失败不阻断
  }

  final text = formatProfileText(
    profile,
    stagnation,
    effectivenessText,
    effectiveOnboarding,
  );

  // M2：追加风格画像段落到画像文本末尾
  final fullText = styleProfileText != null
      ? '$text\n\n$styleProfileText'
      : text;

  return ProfileTextResult(text: fullText, profile: profile);
}

double _min(double a, double b) => a < b ? a : b;

/// M2：格式化写作风格画像为 LLM 可读文本
String _formatStyleProfile(WritingStyleProfile p) {
  final lines = <String>[
    '## 写作风格画像（五维坐标）',
    '- 感官偏好：${p.sensory.value}',
    '- 节奏偏好：${p.rhythm.value}',
    '- 叙事距离：${p.narrativeDistance.value}',
    '- 语调质感：${p.toneTexture.value}',
    '- 结构直觉：${p.structure.value}',
  ];
  if (p.summary.isNotEmpty) {
    lines.add('- 风格总结：${p.summary}');
  }
  return lines.join('\n');
}

class _ModeEntry {
  final String mode;
  String eff;
  int attempts;
  _ModeEntry({required this.mode, required this.eff, required this.attempts});
}
