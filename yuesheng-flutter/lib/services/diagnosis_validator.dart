// ─────────────────────────────────────────────────────────────
// 诊断输出生成校验 — 复刻 services/diagnosis-validator.ts
// 两层校验：
//   1. JSON schema 校验（字段白名单）
//   2. 自然语言校验（V-01/V-02/V-03/V-04）
// V-03（编号泄漏）+ V-04（sensei 糖水词）真拦截；V-01/V-02 仅记录
// ─────────────────────────────────────────────────────────────

import '../config/shared_constants.dart';
import '../services/syndrome_registry.dart';
import '../types/teaching_types.dart';
import 'package:writingcoach/contracts/diagnosis_capability.dart';

export 'package:writingcoach/contracts/diagnosis_capability.dart';

/// 匹配所有 P0xx 格式的症候编号（P000-P099）
final RegExp kSyndromeCodeRe = RegExp(r'P0\d{2}');

/// 匹配所有 A0xx 格式的教学动作编号（A000-A099）
final RegExp kActionCodeRe = RegExp(r'A0\d{2}');

const int _kRewriteThreshold = 80;
const List<String> _kSugaryWords = [
  '加油',
  '真棒',
  '你可以的',
  '已经很好了',
  '没关系',
  '别灰心',
  '继续努力',
];
// 批次4（4.6）：V-02 判定句正则改由共享常量诊断词表构建（防双份维护漂移）
final RegExp _kDecisionRe = RegExp(diagnosisVerdictPhrases.join('|'));

/// 批次4（4.1 O6）：症候互斥对（原为知识库软约束，迁移到代码层防漂移）。
/// 与 syndrome_knowledge_base 手册中的互斥/前置/区分规则对齐：
///   - P006/P021：互斥校验（先排除对方）
///   - P015/P012：铺垫质量前置（无代价预期优先判 P012）
///   - P009/P018：触发信号差异化
const List<List<String>> _kMutexSyndromePairs = [
  ['P006', 'P021'],
  ['P015', 'P012'],
  ['P009', 'P018'],
];

/// 批次4（4.1 O6）：症候互斥代码层校验——互斥对同时命中时返回 warning 提示。
/// warning 级起步（不阻断诊断落库），用于观察误伤率后再决定是否升级为拦截。
List<String> validateSyndromeMutexWarnings(List<String> syndromeIds) {
  final idSet = syndromeIds.toSet();
  final warnings = <String>[];
  for (final pair in _kMutexSyndromePairs) {
    if (idSet.contains(pair[0]) && idSet.contains(pair[1])) {
      warnings.add(
        '症候互斥 ${pair[0]}/${pair[1]} 同时命中（互斥规则见知识库，warning 级仅记录）',
      );
    }
  }
  return warnings;
}

/// 真拦截类型集合：V-03 + V-04
const Set<String> _kBlockingFixTypes = {'V-03', 'V-04'};

/// 校验错误 / JSON schema 校验结果 / 自然语言修复项 / 自然语言校验结果 /
/// 完整校验结果 等 DTO 已上移至 contracts/diagnosis_capability.dart，
/// 本文件经 import 复用，不再重复定义。

/// JSON schema 校验
DiagnosisValidationResult validateDiagnosisSchema(dynamic raw) {
  if (raw is! Map<String, dynamic>) {
    return const DiagnosisValidationResult(
      valid: false,
      errors: [ValidationError(field: '', message: '根对象必须是 JSON 对象')],
    );
  }

  final errors = <ValidationError>[];
  final parsedSyndromeIds = <String>[];

  // syndromes: 非空数组
  final syndromes = raw['syndromes'];
  if (syndromes is! List || syndromes.isEmpty) {
    errors.add(
      const ValidationError(field: 'syndromes', message: 'syndromes 必须为非空数组'),
    );
  } else {
    for (var i = 0; i < syndromes.length; i++) {
      final s = syndromes[i];
      if (s is! Map<String, dynamic>) {
        errors.add(ValidationError(field: 'syndromes[$i]', message: '必须为对象'));
        continue;
      }
      if (s['syndrome_id'] is! String || (s['syndrome_id'] as String).isEmpty) {
        errors.add(
          ValidationError(
            field: 'syndromes[$i].syndrome_id',
            message: '必须为非空字符串',
          ),
        );
      } else {
        parsedSyndromeIds.add(s['syndrome_id'] as String);
        // b11：退役症候不允许出现在诊断输出（预置校验，当前无退役症候不触发）
        if (kRetiredSyndromeIds.contains(s['syndrome_id'])) {
          errors.add(
            ValidationError(
              field: 'syndromes[$i].syndrome_id',
              message: '退役症候 ${s['syndrome_id']} 不允许出现在诊断输出',
            ),
          );
        }
      }
      if (s['name'] is! String || (s['name'] as String).isEmpty) {
        errors.add(
          ValidationError(field: 'syndromes[$i].name', message: '必须为非空字符串'),
        );
      }
      final sev = s['severity'];
      if (sev is! String || !['L1', 'L2', 'L3'].contains(sev)) {
        errors.add(
          ValidationError(
            field: 'syndromes[$i].severity',
            message: '必须为 L1/L2/L3',
          ),
        );
      }
      if (s['evidence'] is! List) {
        errors.add(
          ValidationError(field: 'syndromes[$i].evidence', message: '必须为数组'),
        );
      }
      if (s['explanation'] is! String) {
        errors.add(
          ValidationError(
            field: 'syndromes[$i].explanation',
            message: '必须为字符串',
          ),
        );
      }
    }
  }

  // suggested_actions: string[]
  if (raw['suggested_actions'] is! List ||
      (raw['suggested_actions'] as List).any((a) => a is! String)) {
    errors.add(
      const ValidationError(field: 'suggested_actions', message: '必须为字符串数组'),
    );
  }

  // confidence: 0-1
  final conf = raw['confidence'];
  if (conf is! num || conf < 0 || conf > 1) {
    errors.add(
      const ValidationError(field: 'confidence', message: '必须为 0-1 之间的数字'),
    );
  }

  if (errors.isNotEmpty) {
    return DiagnosisValidationResult(valid: false, errors: errors);
  }
  // 批次4（4.1 O6）：互斥症候 warning 级提示（不阻断，观察误伤率）
  final mutexWarnings = validateSyndromeMutexWarnings(parsedSyndromeIds);
  return DiagnosisValidationResult(
    valid: true,
    errors: const [],
    warnings: mutexWarnings,
    data: raw,
  );
}

/// 自然语言校验
NlValidationResult validateNaturalLanguage(
  String raw, {
  AttitudeLevel? attitude,
}) {
  final fixes = <NlFix>[];
  var cleaned = raw;

  // V-03: 编号泄漏替换
  final codeMatches = <String>[];
  cleaned = cleaned.replaceAllMapped(kSyndromeCodeRe, (match) {
    codeMatches.add(match.group(0)!);
    return '【症候】';
  });
  cleaned = cleaned.replaceAllMapped(kActionCodeRe, (match) {
    codeMatches.add(match.group(0)!);
    return '【动作】';
  });
  if (codeMatches.isNotEmpty) {
    fixes.add(
      NlFix(
        type: 'V-03',
        original: codeMatches.join(', '),
        replacement: '【症候】/【动作】',
      ),
    );
  }

  // V-01: 连续改写检测（仅记录）
  final paragraphs = cleaned
      .split('\n')
      .where((p) => p.trim().isNotEmpty)
      .toList();
  for (final para in paragraphs) {
    if (para.length > _kRewriteThreshold &&
        !para.contains('"') &&
        !para.contains('「') &&
        !para.contains('『')) {
      fixes.add(
        NlFix(
          type: 'V-01',
          original:
              '${para.substring(0, para.length > DiagnosisLimits.rewritePreviewLength ? DiagnosisLimits.rewritePreviewLength : para.length)}...',
          replacement: '（检测到连续改写，已在日志中记录）',
        ),
      );
    }
  }

  // V-04: sensei 档禁止糖水词（真拦截）
  if (attitude == AttitudeLevel.sensei) {
    for (final word in _kSugaryWords) {
      if (cleaned.contains(word)) {
        fixes.add(
          NlFix(
            type: 'V-04',
            original: word,
            replacement: '（sensei 档禁止糖水词，已拦截）',
          ),
        );
      }
    }
  }

  // V-02: 决策句检测（仅记录）
  final decisionMatch = _kDecisionRe.firstMatch(cleaned);
  if (decisionMatch != null) {
    fixes.add(
      NlFix(
        type: 'V-02',
        original: decisionMatch.group(0)!,
        replacement: '（已记录）',
      ),
    );
  }

  return NlValidationResult(
    valid: !fixes.any((f) => _kBlockingFixTypes.contains(f.type)),
    fixes: fixes,
    cleaned: cleaned,
  );
}

/// 完整校验（JSON schema + 自然语言）
FullValidationResult validateDiagnosisOutput(
  String displayContent,
  dynamic diagnosisJson, {
  AttitudeLevel? attitude,
}) {
  final jsonValidation = validateDiagnosisSchema(diagnosisJson);
  final nlValidation = validateNaturalLanguage(
    displayContent,
    attitude: attitude,
  );

  final passed = jsonValidation.valid && nlValidation.valid;

  ParsedDiagnosis? diagnosis;
  if (jsonValidation.valid && jsonValidation.data != null) {
    diagnosis = _mapToParsedDiagnosis(jsonValidation.data!);
  }

  return FullValidationResult(
    passed: passed,
    displayContent: nlValidation.cleaned,
    diagnosis: diagnosis,
    jsonValidation: jsonValidation,
    nlValidation: nlValidation,
  );
}

/// 将通过 schema 校验的 Map 映射为 ParsedDiagnosis
ParsedDiagnosis _mapToParsedDiagnosis(Map<String, dynamic> data) {
  final syndromesRaw = data['syndromes'] as List;
  final syndromes = syndromesRaw.map((s) {
    final m = s as Map<String, dynamic>;
    return Syndrome.fromJson(m);
  }).toList();

  final suggestedActions = (data['suggested_actions'] as List).cast<String>();

  final teachingPlanRaw = data['teaching_plan'];
  final teachingPlan = teachingPlanRaw is Map<String, dynamic>
      ? teachingPlanRaw
      : null;

  String? teachingPlanNextStep;
  if (teachingPlan != null && teachingPlan['next_step'] is String) {
    teachingPlanNextStep = teachingPlan['next_step'] as String;
  }

  final nextFocus = data['next_focus'] as String? ?? teachingPlanNextStep;

  return ParsedDiagnosis(
    syndromes: syndromes,
    suggestedActions: suggestedActions,
    confidence: (data['confidence'] as num).toDouble(),
    rootCauseAnalysis: data['root_cause_analysis'] as String?,
    nextFocus: nextFocus,
    feedbackSummary: data['feedback_summary'] as String?,
    suggestedPhase: TeachingPhase.fromString(
      data['suggested_phase'] as String?,
    ),
    suggestedBeginnerLevel: BeginnerLevel.fromString(
      data['suggested_beginner_level'] as String?,
    ),
    teachingMode: TeachingMode.fromString(data['teaching_mode'] as String?),
    currentTeachingFocusId:
        teachingPlan?['current_teaching_focus_id'] as String?,
    focusReason: teachingPlan?['focus_reason'] as String?,
    styleProfile: _parseStyleProfile(data),
  );
}

/// 解析可选 style_profile（批次53；缺失/非法返回 null，不阻断诊断）
WritingStyleProfile? _parseStyleProfile(Map<String, dynamic> data) {
  final raw = data['style_profile'];
  if (raw is! Map<String, dynamic>) return null;
  try {
    return WritingStyleProfile.fromJson(raw);
  } catch (_) {
    return null; // 缺 summary 等非法结构 → 忽略
  }
}

/// 格式化校验错误信息
String formatValidationErrors(FullValidationResult result) {
  final parts = <String>[];
  if (!result.jsonValidation.valid) {
    parts.add('[JSON 校验] ${result.jsonValidation.errors.length} 个错误:');
    for (final e in result.jsonValidation.errors) {
      parts.add('  - ${e.field}: ${e.message}');
    }
  }
  if (!result.nlValidation.valid) {
    for (final fix in result.nlValidation.fixes) {
      if (fix.type == 'V-03') {
        parts.add('[V-03 编号泄漏] 已替换: ${fix.original} → ${fix.replacement}');
      }
    }
  }
  return parts.join('\n');
}
