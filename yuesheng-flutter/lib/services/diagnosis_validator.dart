// ─────────────────────────────────────────────────────────────
// 诊断输出生成校验 — 复刻 services/diagnosis-validator.ts
// 两层校验：
//   1. JSON schema 校验（字段白名单）
//   2. 自然语言校验（V-01/V-02/V-03/V-04）
// V-03（编号泄漏）真回填；V-04（sensei 糖水词）阻断；
// V-01/V-02（C123 任务4，R-009）由「仅记录」升级为「真降级 cleaned」——
//   因 .fixes/.valid 无运行路径消费，照 V-03 模式直接改写 displayContent 才生效。
// ─────────────────────────────────────────────────────────────

import '../config/shared_constants.dart';
import '../types/teaching_types.dart';
import 'package:writingcoach/contracts/diagnosis_capability.dart';
import 'decode_guard.dart';
import 'skill_registry.dart';
import 'syndrome_id_pattern.dart';
import 'syndrome_registry.dart';
import 'technique_knowledge_base.dart';

export 'package:writingcoach/contracts/diagnosis_capability.dart';

/// 匹配所有 P0xx 格式的症候编号（P000-P099）
///
/// ⚠️ 模式由 [`kAnySyndromeIdRe`] 提供（`syndrome_id_pattern.dart`）——
/// **勿在此硬编码 `P0\d{2}`**：新开编号段时这里是「编号泄漏回填」的第一道
/// 防线，硬编码会让新段编号原样到达学员眼前（ADR-0003 甲-1 · S1 批）。
final RegExp kSyndromeCodeRe = kAnySyndromeIdRe;

/// 匹配所有 A0xx 格式的教学动作编号（A000-A099）
final RegExp kActionCodeRe = RegExp(r'A0\d{2}');

/// 匹配所有 T0xx 格式的**技法**编号（T000-T099）。
///
/// ADR-C105 A9：技法编号**确实会进 prompt**——`kTechniqueIndexContent`
/// （`technique_kb_content.dart:9`）的首列即裸编号，且 `_l2AltColumn`
/// （`technique_knowledge_base.dart:265`）对 P004/P005/P006/P007/P009
/// 直接输出 `T017/T018/T022`（**无技法名**）。该表经
/// `skill_registry.dart:214`（'technique-library-index'）→
/// `skill_layers.dart:96` 注入。此前 V-03 只覆盖 P0xx/A0xx ⇒ 模型回显裸
/// 技法编号时会**原样到达学员眼前**（prompt 自己声明「不暴露编号」）。
final RegExp kTechniqueCodeRe = RegExp(r'T0\d{2}');

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

// ── R-009（C123 任务4）：V-01/V-02 由「仅记录」升级为「真降级 cleaned」──────
// 背景：V-01/V-02 命中后只造 NlFix，而全 lib 无运行路径消费 .fixes/.valid
// （formatValidationErrors 无人调；flow_handler 只取 displayContent=cleaned）。
// 故照 V-03 模式直接改写 cleaned——该路才是真被消费的那一路。
// 精度原则：只拦「确定性违规」，宁漏勿伤。
//  V-01：整段 >80 字、无引号、且无教练元话语 = 替学员成文（ghostwrite）。
//  V-02：句首裸指令（你应该/你务必…）或 同句「全局量词+全局贬判」= 替下结论。

/// V-01 教练元话语标记：段落命中即说明在「点评学员文本」而非「替学员成文」→ 不拦。
///
/// 指示词用明确复合形式（这句/这段/这里…），**不裸匹配「这一」**——否则
/// 叙述里的「这一次/这一刻」会被误判成点评（C123 实测 P1 误伤）。
final RegExp _kCoachMetaMarkers = RegExp(
  r'这里|这[一]?句|这[一]?段|这[一]?章|上文|原文|你的|你写的|'
  r'问题(?:在于|是)|因为|所以|对比|建议|可以(?:再|试着|多|少)|'
  r'为什么|节奏|动机|镜头感|比喻|铺垫|转折',
);

/// V-02b 全局量词：整篇/通篇/整体而言等「覆盖全篇」的措辞。
final RegExp _kGlobalQuantifier = RegExp(r'整篇|全文|通篇|全篇|整个(?:故事|章节|小说)?|整体而言');

/// V-02b 全局贬判词：须与 [_kGlobalQuantifier] 同句共现才拦（局部点评不算）。
/// 与 verdictDangerousWords 语义相近但不合并：后者对任一出现即拦（editor/teacher
/// hard-limit）；本表专司「全局定性」，且含 很差/不知所云/毫无逻辑 等前者没有的词。
final RegExp _kGlobalVerdict = RegExp(
  r'很差|太烂|平庸|失败|拖沓|空洞|毫无(?:亮点|逻辑|意义)|'
  r'完全(?:失败|不行|垮掉)|一无是处|不知所云|没救了',
);

/// V-01 降级文案（R-009 合规）：不替学员落笔、不贴标签，改为邀请其自己写。
const String _kV01Downgrade = '（这段我不替你落笔：这一段请你自己先写一稿，写完我们一起逐句回看。）';

/// V-02 降级文案（R-009 合规）：不替学员下结论，改为邀请一起逐段定位。
const String _kV02Downgrade = '（这个判断我先不下：我们把这一段拆开，一起看它具体卡在哪里。）';

/// 批次4（4.1 O6）：症候互斥对（原为知识库软约束，迁移到代码层防漂移）。
/// 与 syndrome_knowledge_base 手册中的互斥/前置/区分规则对齐：
///   - P004/P017：互斥校验（先排除对方）
///   - P013/P010：铺垫质量前置（无代价预期优先判 P010）
///   - P007/P015：触发信号差异化
const List<List<String>> _kMutexSyndromePairs = [
  ['P004', 'P017'],
  ['P013', 'P010'],
  ['P007', 'P015'],
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

/// syndromes 字段整体校验（必须是数组 + 逐项，R-019 拆出）。
/// 允许空数组：零症候诊断（clean / insufficient 档）合法，下游由 diagnosis_card
/// 渲染「本次未发现显著问题」兜底（D04 / ADR-C102）。
void _validateSyndromesField(
  dynamic syndromes,
  List<ValidationError> errors,
  List<String> parsedSyndromeIds,
) {
  if (syndromes is! List) {
    errors.add(
      const ValidationError(field: 'syndromes', message: 'syndromes 必须为数组'),
    );
    return;
  }
  for (var i = 0; i < syndromes.length; i++) {
    _validateSyndromeEntry(syndromes[i], i, errors, parsedSyndromeIds);
  }
}

/// 单项 syndrome 校验（R-019 拆出）。
void _validateSyndromeEntry(
  dynamic s,
  int i,
  List<ValidationError> errors,
  List<String> parsedSyndromeIds,
) {
  if (s is! Map<String, dynamic>) {
    errors.add(ValidationError(field: 'syndromes[$i]', message: '必须为对象'));
    return;
  }
  if (s['syndrome_id'] is! String || (s['syndrome_id'] as String).isEmpty) {
    errors.add(
      ValidationError(field: 'syndromes[$i].syndrome_id', message: '必须为非空字符串'),
    );
  } else {
    parsedSyndromeIds.add(s['syndrome_id'] as String);
  }
  if (s['name'] is! String || (s['name'] as String).isEmpty) {
    errors.add(
      ValidationError(field: 'syndromes[$i].name', message: '必须为非空字符串'),
    );
  }
  final sev = s['severity'];
  if (sev is! String || !['L1', 'L2', 'L3'].contains(sev)) {
    errors.add(
      ValidationError(field: 'syndromes[$i].severity', message: '必须为 L1/L2/L3'),
    );
  }
  if (s['evidence'] is! List) {
    errors.add(
      ValidationError(field: 'syndromes[$i].evidence', message: '必须为数组'),
    );
  }
  if (s['explanation'] is! String) {
    errors.add(
      ValidationError(field: 'syndromes[$i].explanation', message: '必须为字符串'),
    );
  }
}

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

  // syndromes: 数组（允许为空，零症候合法；逐项校验拆至 _validateSyndromesField）
  _validateSyndromesField(raw['syndromes'], errors, parsedSyndromeIds);

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
        replacement: '已回填症候/动作名',
      ),
    );
  }
  // V-01 R-009：代写段整段降级（照 V-03 真改写 cleaned）
  final v01 = _applyGhostRewriteGuard(cleaned);
  cleaned = v01.text;
  fixes.addAll(v01.fixes);
  fixes.addAll(_detectSugaryWords(cleaned, attitude));
  // V-02 R-009：判决句整句降级（句首裸指令 / 全局定性）
  final v02 = _applyVerdictSentenceGuard(cleaned);
  cleaned = v02.text;
  fixes.addAll(v02.fixes);
  return NlValidationResult(
    valid: !fixes.any((f) => _kBlockingFixTypes.contains(f.type)),
    fixes: fixes,
    cleaned: cleaned,
  );
}

/// V-03 编号泄漏回填（R-019 拆出：validateNaturalLanguage）。
///
/// P0'-3（2026-09-30）：原实现把编号抹成 `【症候】/【动作】` 空壳，而**全仓没有
/// 反向渲染器**（`【症候】` 的出现点只有本文件这一处产生它）⇒ 用户直接读到占位符
/// （2026-09-30 取证实测 68 处，见 docs/audits/2026-09-30-0.3.5诊断质量取证.md §6）。
/// 改为**回填名称**：
///   `P007` → `「角色空心化」`（精确匹配优先；LLM 偶发旧编号经 mergeMap 归一）
///   `A001` → `「缩小范围」`
///   `T017` → `「悬念伏笔法」`（ADR-C105 A9 新增第三族）
/// 查不到名的编号（越界/拼错，如 P099）仍退化为占位符——"编号不外泄"这条底线不破。
({String text, List<String> codes}) _applyCodeReplacement(String cleaned) {
  final codes = <String>[];
  var out = cleaned.replaceAllMapped(kSyndromeCodeRe, (match) {
    final code = match.group(0)!;
    codes.add(code);
    final name = syndromeNameOf(code);
    return name == null ? '【症候】' : '「$name」';
  });
  out = out.replaceAllMapped(kActionCodeRe, (match) {
    final code = match.group(0)!;
    codes.add(code);
    final name = actionNameOf(code);
    return name == null ? '【动作】' : '「$name」';
  });
  // ADR-C105 A9：技法编号同款回填（`T017` → 「悬念伏笔法」）。
  // 查不到名（越界/拼错，如 T099）仍退化为占位符——「编号不外泄」底线不破。
  out = out.replaceAllMapped(kTechniqueCodeRe, (match) {
    final code = match.group(0)!;
    codes.add(code);
    final name = techniqueNameOf(code);
    return name == null ? '【技法】' : '「$name」';
  });
  return (text: out, codes: codes);
}

/// V-01 R-009 代写段守卫（真降级：改写 cleaned）。
///
/// 判据（同时满足才拦，宁漏勿伤）：
///   1. 段落 >80 字（沿用 _kRewriteThreshold）；
///   2. 无引号（"「『）—— 引用学员原文/例句不算代写；
///   3. 无教练元话语（[_kCoachMetaMarkers]）—— 长段点评学员文本不算代写。
/// 命中即把整段替换为 [_kV01Downgrade]，并产出 V-01 fix 供观测。
({String text, List<NlFix> fixes}) _applyGhostRewriteGuard(String cleaned) {
  final fixes = <NlFix>[];
  final out = cleaned
      .split('\n')
      .map((line) {
        final para = line.trim();
        if (para.length <= _kRewriteThreshold) return line;
        if (para.contains('"') || para.contains('「') || para.contains('『')) {
          return line;
        }
        if (_kCoachMetaMarkers.hasMatch(para)) return line;
        fixes.add(
          NlFix(
            type: 'V-01',
            original: para.length > DiagnosisLimits.rewritePreviewLength
                ? '${para.substring(0, DiagnosisLimits.rewritePreviewLength)}...'
                : para,
            replacement: _kV01Downgrade,
          ),
        );
        return _kV01Downgrade;
      })
      .join('\n');
  return (text: out, fixes: fixes);
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

/// V-02 R-009 判决句守卫（真降级：改写 cleaned）。
///
/// 按句切分后逐句判两类（命中即整句替换为 [_kV02Downgrade]）：
///   - V-02a 句首裸指令：trim 后以 diagnosisVerdictPhrases 之一开头
///     （引号包裹的教学例句句首是引号，天然豁免）；
///   - V-02b 全局定性：同句内 [_kGlobalQuantifier] 与 [_kGlobalVerdict] 共现。
({String text, List<NlFix> fixes}) _applyVerdictSentenceGuard(String cleaned) {
  final fixes = <NlFix>[];
  final out = cleaned.splitMapJoin(
    RegExp(r'(?<=[。！？；\n])'),
    onMatch: (_) => '',
    onNonMatch: (sentence) {
      final tailMatch = RegExp(r'\s*$').firstMatch(sentence);
      final tail = tailMatch?.group(0) ?? '';
      final body = sentence.substring(0, sentence.length - tail.length);
      final trimmed = body.trim();
      String? phrase;
      for (final p in diagnosisVerdictPhrases) {
        if (trimmed.startsWith(p)) {
          phrase = p;
          break;
        }
      }
      final global =
          _kGlobalQuantifier.hasMatch(trimmed) &&
          _kGlobalVerdict.hasMatch(trimmed);
      if (phrase == null && !global) return sentence;
      fixes.add(
        NlFix(
          type: 'V-02',
          original: phrase ?? '（全局定性）',
          replacement: _kV02Downgrade,
        ),
      );
      return '$_kV02Downgrade$tail';
    },
  );
  return (text: out, fixes: fixes);
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
  // 后果是 V-03 编号泄漏拦截失效、用户直接看到 P010 这类裸编号
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
///
/// 2026-09-17：字段类型由 `dynamic` 收紧为 `String?`。本函数已是「非 String
/// 一律按缺失」的唯一收敛点，就地收敛后上游 `_mapToParsedDiagnosis` 里 7 处
/// `is String ? x : null` 的类型在编译期即可证明（严格模式下原报 7 条
/// argument_type_not_assignable）。收敛逻辑与原逐处判断完全等价 ⇒ 零行为变更。
/// 注：漂移检测走 _collectOptionalFieldDrifts(data) 读**原始** Map，不经本函数，
/// 故收敛不影响漂移告警。
({
  String? nextFocusRaw,
  String? rootCauseRaw,
  String? feedbackRaw,
  String? phaseRaw,
  String? levelRaw,
  String? modeRaw,
  String? focusIdRaw,
  String? focusReasonRaw,
})
_readOptionalRawFields(
  Map<String, dynamic> data,
  Map<String, dynamic>? teachingPlan,
) {
  String? asText(Object? v) => v is String ? v : null;
  return (
    nextFocusRaw: asText(data['next_focus']),
    rootCauseRaw: asText(data['root_cause_analysis']),
    feedbackRaw: asText(data['feedback_summary']),
    phaseRaw: asText(data['suggested_phase']),
    levelRaw: asText(data['suggested_beginner_level']),
    modeRaw: asText(data['teaching_mode']),
    focusIdRaw: asText(teachingPlan?['current_teaching_focus_id']),
    focusReasonRaw: asText(teachingPlan?['focus_reason']),
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
  } catch (e, st) {
    logDecodeFailure(field: 'diagnosis', error: e, stack: st, category: 'api');
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
