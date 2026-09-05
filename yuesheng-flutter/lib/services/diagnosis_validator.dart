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
      warnings.add('症候互斥 ${pair[0]}/${pair[1]} 同时命中（互斥规则见知识库，warning 级仅记录）');
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
  final codeResult = _applyCodeReplacement(raw);
  var cleaned = codeResult.text;
  if (codeResult.codes.isNotEmpty) {
    fixes.add(
      NlFix(
        type: 'V-03',
        original: codeResult.codes.join(', '),
        replacement: '【症候】/【动作】',
      ),
    );
  }
  fixes.addAll(_detectRewrites(cleaned));
  fixes.addAll(_detectSugaryWords(cleaned, attitude));
  final decision = _detectDecision(cleaned);
  if (decision != null) fixes.add(decision);
  return NlValidationResult(
    valid: !fixes.any((f) => _kBlockingFixTypes.contains(f.type)),
    fixes: fixes,
    cleaned: cleaned,
  );
}

/// V-03 编号泄漏替换（R-019 拆出：validateNaturalLanguage）。
({String text, List<String> codes}) _applyCodeReplacement(String cleaned) {
  final codes = <String>[];
  var out = cleaned.replaceAllMapped(kSyndromeCodeRe, (match) {
    codes.add(match.group(0)!);
    return '【症候】';
  });
  out = out.replaceAllMapped(kActionCodeRe, (match) {
    codes.add(match.group(0)!);
    return '【动作】';
  });
  return (text: out, codes: codes);
}

/// V-01 连续改写检测（仅记录，R-019 拆出）。
List<NlFix> _detectRewrites(String cleaned) {
  final fixes = <NlFix>[];
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
  return fixes;
}

/// V-04 sensei 档禁止糖水词（真拦截，R-019 拆出）。
List<NlFix> _detectSugaryWords(String cleaned, AttitudeLevel? attitude) {
  final fixes = <NlFix>[];
  if (attitude != AttitudeLevel.sensei) return fixes;
  for (final word in _kSugaryWords) {
    if (cleaned.contains(word)) {
      fixes.add(
        NlFix(type: 'V-04', original: word, replacement: '（sensei 档禁止糖水词，已拦截）'),
      );
    }
  }
  return fixes;
}

/// V-02 决策句检测（仅记录，R-019 拆出）。
NlFix? _detectDecision(String cleaned) {
  final decisionMatch = _kDecisionRe.firstMatch(cleaned);
  if (decisionMatch == null) return null;
  return NlFix(
    type: 'V-02',
    original: decisionMatch.group(0)!,
    replacement: '（已记录）',
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
  // ADR-C64：漂移 warning 合并进既有 jsonValidation.warnings。
  // 不动 valid —— 判错会丢弃整块诊断，与 N5 裁决冲突（见
  // _collectOptionalFieldDrifts 注释）。无漂移时 jsonResult 与
  // jsonValidation 完全等价，既有行为逐字节不变。
  var jsonResult = jsonValidation;
  if (jsonValidation.valid && jsonValidation.data != null) {
    final data = jsonValidation.data!;
    final drifts = _collectOptionalFieldDrifts(data);
    diagnosis = _mapToParsedDiagnosis(data);
    if (drifts.isNotEmpty) {
      jsonResult = DiagnosisValidationResult(
        valid: jsonValidation.valid,
        errors: jsonValidation.errors,
        warnings: [...jsonValidation.warnings, ...drifts],
        data: jsonValidation.data,
      );
    }
  }

  return FullValidationResult(
    passed: passed,
    displayContent: nlValidation.cleaned,
    diagnosis: diagnosis,
    jsonValidation: jsonResult,
    nlValidation: nlValidation,
  );
}

/// 将通过 schema 校验的 Map 映射为 ParsedDiagnosis
ParsedDiagnosis _mapToParsedDiagnosis(Map<String, dynamic> data) {
  final syndromes = _parseSyndromes(data);

  final suggestedActions = (data['suggested_actions'] as List).cast<String>();

  final teaching = _resolveTeachingPlan(data);

  // ADR-C64：以下可选字段 schema **不校验类型**（validateDiagnosisSchema 的
  // 校验在 :154 就结束了，只覆盖 syndromes / suggested_actions / confidence）。
  // 这些字段原本是硬 cast，模型把 next_focus 输出成数字即抛 TypeError；
  // 而抛错点在 validateDiagnosisOutput 返回之前（:268 早于 :273），
  // 会**连带丢掉 validateNaturalLanguage 已算好的清洗结果**——
  // 后果是 V-03 编号泄漏拦截失效、用户直接看到 P012 这类裸编号
  // （ADR-C64 §1.2 实测）。
  //
  // 改安全读取：非 String 一律按缺失处理。漂移本身不静默消失，
  // 由 _collectOptionalFieldDrifts 产出 warning。
  final raw = _readOptionalRawFields(data, teaching.plan);

  // N3-a（ADR-C65）：与 parser 侧同款校验——prompt 三处明写「必须从本轮
  // syndromes 中选取」。两条解析路径必须一致，否则重演 N8（parser 白名单 /
  // validator 不校验）的老问题。越界置 null → 走 focus-resolver fallback，
  // 这是 prompt 自己声明的既有行为，不是新造路径。
  final focusId = _resolveFocusId(syndromes, raw.focusIdRaw);

  return ParsedDiagnosis(
    syndromes: syndromes,
    suggestedActions: suggestedActions,
    confidence: (data['confidence'] as num).toDouble(),
    rootCauseAnalysis: raw.rootCauseRaw is String ? raw.rootCauseRaw : null,
    // 漂移时回退到 teachingPlan.next_step——与 next_focus 缺失时行为一致
    nextFocus: raw.nextFocusRaw is String
        ? raw.nextFocusRaw
        : teaching.nextStep,
    feedbackSummary: raw.feedbackRaw is String ? raw.feedbackRaw : null,
    suggestedPhase: TeachingPhase.fromString(
      raw.phaseRaw is String ? raw.phaseRaw : null,
    ),
    suggestedBeginnerLevel: BeginnerLevel.fromString(
      raw.levelRaw is String ? raw.levelRaw : null,
    ),
    teachingMode: TeachingMode.fromString(
      raw.modeRaw is String ? raw.modeRaw : null,
    ),
    currentTeachingFocusId: focusId,
    focusReason: raw.focusReasonRaw is String ? raw.focusReasonRaw : null,
    styleProfile: _parseStyleProfile(data),
  );
}

/// 可选字段安全读取（ADR-C64：schema 不校验类型，非 String 按缺失处理）。
/// 由 _collectOptionalFieldDrifts 产出 warning（R-019 拆出）。
({
  dynamic nextFocusRaw,
  dynamic rootCauseRaw,
  dynamic feedbackRaw,
  dynamic phaseRaw,
  dynamic levelRaw,
  dynamic modeRaw,
  dynamic focusIdRaw,
  dynamic focusReasonRaw,
})
_readOptionalRawFields(
  Map<String, dynamic> data,
  Map<String, dynamic>? teachingPlan,
) {
  return (
    nextFocusRaw: data['next_focus'],
    rootCauseRaw: data['root_cause_analysis'],
    feedbackRaw: data['feedback_summary'],
    phaseRaw: data['suggested_phase'],
    levelRaw: data['suggested_beginner_level'],
    modeRaw: data['teaching_mode'],
    focusIdRaw: teachingPlan?['current_teaching_focus_id'],
    focusReasonRaw: teachingPlan?['focus_reason'],
  );
}

/// N3-a（ADR-C65）：focus 必须从本轮 syndromes 中选取（R-019 拆出）。
String? _resolveFocusId(List<Syndrome> syndromes, dynamic focusIdRaw) {
  final syndromeIds = syndromes.map((s) => s.syndromeId).toSet();
  return focusIdRaw is String && syndromeIds.contains(focusIdRaw)
      ? focusIdRaw
      : null;
}

/// teaching_plan 安全解析（R-019 拆出：_mapToParsedDiagnosis）。
({Map<String, dynamic>? plan, String? nextStep}) _resolveTeachingPlan(
  Map<String, dynamic> data,
) {
  final plan = data['teaching_plan'] is Map<String, dynamic>
      ? data['teaching_plan'] as Map<String, dynamic>
      : null;
  return (plan: plan, nextStep: _resolveNextStep(plan));
}

/// syndromes 列表解析（R-019 拆出：_mapToParsedDiagnosis）。
List<Syndrome> _parseSyndromes(Map<String, dynamic> data) {
  final syndromesRaw = data['syndromes'] as List;
  return syndromesRaw.map((s) {
    final m = s as Map<String, dynamic>;
    return Syndrome.fromJson(m);
  }).toList();
}

/// teaching_plan.next_step 安全读取（R-019 拆出：_mapToParsedDiagnosis）。
String? _resolveNextStep(Map<String, dynamic>? teachingPlan) {
  if (teachingPlan == null || teachingPlan['next_step'] is! String) return null;
  return teachingPlan['next_step'] as String;
}

/// 可选字段类型漂移检测（ADR-C64）
///
/// `validateDiagnosisSchema` 只校验必填三项，可选字段的类型完全不校验。
/// 这些字段在 `_mapToParsedDiagnosis` 中原为硬 cast，类型漂移会抛 TypeError，
/// 连带丢掉已算好的 NL 清洗结果（V-03 失效，见 ADR-C64 §1.2 实测）。
/// 改安全读取后崩溃消失，但漂移本身不能无声消失。
///
/// **为什么不判为 error**：判错会让 `jsonValidation.valid` 变 false，
/// `validateDiagnosisOutput:267` 的条件不成立 → `diagnosis = null`，
/// 整块诊断被丢弃，放大「输出了但不落库」，与 N5「只观测不拦截」的裁决
/// 同向恶化。故只产出 warning，由调用方决定是否上报。
///
/// 字段清单与 `_mapToParsedDiagnosis` 的安全读取**必须同步修改**——
/// 新增可选字段时两边都要加，否则会出现「静默丢弃且不留痕」。
List<String> _collectOptionalFieldDrifts(Map<String, dynamic> data) {
  final drifts = <String>[];

  void check(String field) {
    final v = data[field];
    if (v != null && v is! String) {
      drifts.add('可选字段 $field 类型漂移（${v.runtimeType}），已按缺失处理');
    }
  }

  check('next_focus');
  check('root_cause_analysis');
  check('feedback_summary');
  check('suggested_phase');
  check('suggested_beginner_level');
  check('teaching_mode');

  final syndromeIdSet = _collectSyndromeDrifts(data, drifts);
  _collectTeachingPlanDrifts(data, drifts, syndromeIdSet);

  return drifts;
}

/// syndromes[].reader_impact 类型漂移 + syndrome_id 收集（R-019 拆出）。
/// 返回本轮 syndromes 的 id 集合，供 N3-a 越界校验使用。
Set<String> _collectSyndromeDrifts(
  Map<String, dynamic> data,
  List<String> drifts,
) {
  final syndromeIdSet = <String>{};
  final syndromesRaw = data['syndromes'];
  if (syndromesRaw is! List) return syndromeIdSet;
  for (var i = 0; i < syndromesRaw.length; i++) {
    if (syndromesRaw[i] is! Map<String, dynamic>) continue;
    final syndrome = syndromesRaw[i] as Map<String, dynamic>;
    final sid = syndrome['syndrome_id'];
    if (sid is String) syndromeIdSet.add(sid);
    final ri = syndrome['reader_impact'];
    if (ri != null && ri is! String) {
      drifts.add(
        '可选字段 syndromes[$i].reader_impact 类型漂移'
        '（${ri.runtimeType}），已按缺失处理',
      );
    }
  }
  return syndromeIdSet;
}

/// teaching_plan 字段漂移 + N3-a 越界校验（R-019 拆出）。
void _collectTeachingPlanDrifts(
  Map<String, dynamic> data,
  List<String> drifts,
  Set<String> syndromeIdSet,
) {
  final teachingPlan = data['teaching_plan'];
  if (teachingPlan is! Map<String, dynamic>) return;

  void checkPlan(String field) {
    final v = teachingPlan[field];
    if (v != null && v is! String) {
      drifts.add(
        '可选字段 teaching_plan.$field 类型漂移'
        '（${v.runtimeType}），已按缺失处理',
      );
    }
  }

  checkPlan('current_teaching_focus_id');
  checkPlan('focus_reason');

  // N3-a（ADR-C65）：类型合法但**越界**（不在本轮 syndromes 中）是另一类
  // 违规——checkPlan 只管类型，管不了成员关系。越界值会被置 null 走向
  // focus-resolver fallback，必须留痕，否则又是「静默丢弃且不留痕」。
  final ctf = teachingPlan['current_teaching_focus_id'];
  if (ctf is String && !syndromeIdSet.contains(ctf)) {
    drifts.add(
      'teaching_plan.current_teaching_focus_id = $ctf 不在本轮 syndromes 中，'
      '已按缺失处理（走 fallback 优先级表）',
    );
  }
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
