# -*- coding: utf-8 -*-
"""A-1c 认知风格段迁出稳定注入段 —— 批量精确替换（保持 CRLF）。
每个替换校验命中次数，全部命中后才写回。
"""
import sys

ROOT = r"D:\ai-teacher\yuesheng-flutter"

# (path, [(old, new), ...])
EDITS = [
    # ── A. student_profile_format.dart ──
    (ROOT + r"\lib\services\student_profile_format.dart", [
        # 1. formatProfileText 签名加 includeCognitiveStyle
        (
            "String formatProfileText(\r\n"
            "  StudentProfile profile,\r\n"
            "  StagnationResult? stagnation,\r\n"
            "  String? effectivenessText,\r\n"
            "  OnboardingData? onboarding,\r\n"
            ") {",
            "String formatProfileText(\r\n"
            "  StudentProfile profile,\r\n"
            "  StagnationResult? stagnation,\r\n"
            "  String? effectivenessText,\r\n"
            "  OnboardingData? onboarding, {\r\n"
            "  bool includeCognitiveStyle = true,\r\n"
            "}) {",
        ),
        # 2. _appendProficiencyAssessment 调用加参数
        (
            "  _appendProficiencyAssessment(\r\n"
            "    sections,\r\n"
            "    profile,\r\n"
            "    onboarding,\r\n"
            "    stagnation,\r\n"
            "    totalDiagnoses,\r\n"
            "  );",
            "  _appendProficiencyAssessment(\r\n"
            "    sections,\r\n"
            "    profile,\r\n"
            "    onboarding,\r\n"
            "    stagnation,\r\n"
            "    totalDiagnoses,\r\n"
            "    includeCognitiveStyle,\r\n"
            "  );",
        ),
        # 3. _appendProficiencyAssessment 签名加参数
        (
            "void _appendProficiencyAssessment(\r\n"
            "  List<String> sections,\r\n"
            "  StudentProfile profile,\r\n"
            "  OnboardingData? onboarding,\r\n"
            "  StagnationResult? stagnation,\r\n"
            "  int totalDiagnoses,\r\n"
            ") {",
            "void _appendProficiencyAssessment(\r\n"
            "  List<String> sections,\r\n"
            "  StudentProfile profile,\r\n"
            "  OnboardingData? onboarding,\r\n"
            "  StagnationResult? stagnation,\r\n"
            "  int totalDiagnoses,\r\n"
            "  bool includeCognitiveStyle,\r\n"
            ") {",
        ),
        # 4. _appendCognitiveStyleInfo 调用加参数
        (
            "  _appendCognitiveStyleInfo(sections, profile, onboarding);",
            "  _appendCognitiveStyleInfo(\r\n"
            "    sections,\r\n"
            "    profile,\r\n"
            "    onboarding,\r\n"
            "    includeCognitiveStyle,\r\n"
            "  );",
        ),
        # 5. _appendCognitiveStyleInfo 重构 + 新增 buildCognitiveStyleNote
        (
            "/// 认知风格段（R-019 拆出：_appendProficiencyAssessment）。\r\n"
            "void _appendCognitiveStyleInfo(\r\n"
            "  List<String> sections,\r\n"
            "  StudentProfile profile,\r\n"
            "  OnboardingData? onboarding,\r\n"
            ") {\r\n"
            "  if (profile.cognitiveStyle == null || onboarding != null) return;\r\n"
            "  final styleLabel = _cognitiveStyleLabel(profile.cognitiveStyle!.style);\r\n"
            "  sections.add(\r\n"
            "    '认知风格：$styleLabel（置信度 ${(profile.cognitiveStyle!.confidence * 100).toStringAsFixed(0)}%）',\r\n"
            "  );\r\n"
            "  final styleBasis = profile.cognitiveStyle!.style == CognitiveStyle.analytical\r\n"
            "      ? '分析型'\r\n"
            "      : profile.cognitiveStyle!.style == CognitiveStyle.intuitive\r\n"
            "      ? '直觉型'\r\n"
            "      : '混合型';\r\n"
            "  sections.add('依据：基于用户历史 $styleBasis 关键词使用频率推断');\r\n"
            "  sections.add('');\r\n"
            "}",
            "/// 认知风格注文（A-1c）：供 LLM 注入路径在历史之后单独追加。\r\n"
            "/// onboarding 存在（与「学习偏好」同源去重，ADR-C71 §3.4）或风格缺失时返回 null。\r\n"
            "String? buildCognitiveStyleNote(\r\n"
            "  StudentProfile profile, {\r\n"
            "  required bool hasOnboarding,\r\n"
            "}) {\r\n"
            "  final style = profile.cognitiveStyle;\r\n"
            "  if (style == null || hasOnboarding) return null;\r\n"
            "  final styleLabel = _cognitiveStyleLabel(style.style);\r\n"
            "  final styleBasis = style.style == CognitiveStyle.analytical\r\n"
            "      ? '分析型'\r\n"
            "      : style.style == CognitiveStyle.intuitive\r\n"
            "      ? '直觉型'\r\n"
            "      : '混合型';\r\n"
            "  return '认知风格：$styleLabel（置信度 ${(style.confidence * 100).toStringAsFixed(0)}%）\\n'\r\n"
            "      '依据：基于用户历史 $styleBasis 关键词使用频率推断';\r\n"
            "}\r\n"
            "\r\n"
            "/// 认知风格段（R-019 拆出：_appendProficiencyAssessment）。\r\n"
            "void _appendCognitiveStyleInfo(\r\n"
            "  List<String> sections,\r\n"
            "  StudentProfile profile,\r\n"
            "  OnboardingData? onboarding,\r\n"
            "  bool includeCognitiveStyle,\r\n"
            ") {\r\n"
            "  if (!includeCognitiveStyle) return;\r\n"
            "  final note = buildCognitiveStyleNote(\r\n"
            "    profile,\r\n"
            "    hasOnboarding: onboarding != null,\r\n"
            "  );\r\n"
            "  if (note == null) return;\r\n"
            "  sections.add(note);\r\n"
            "  sections.add('');\r\n"
            "}",
        ),
    ]),

    # ── B. student_profile.dart ──
    (ROOT + r"\lib\services\student_profile.dart", [
        # 1. buildStudentContext 签名加参数
        (
            "Future<ProfileTextResult> buildStudentContext({\r\n"
            "  required DiagnosisRepository diagnosisRepo,\r\n"
            "  required StudentModelRepository studentModelRepo,\r\n"
            "  required SessionRepository sessionRepo,\r\n"
            "  String? sessionId,\r\n"
            "}) async {",
            "Future<ProfileTextResult> buildStudentContext({\r\n"
            "  required DiagnosisRepository diagnosisRepo,\r\n"
            "  required StudentModelRepository studentModelRepo,\r\n"
            "  required SessionRepository sessionRepo,\r\n"
            "  String? sessionId,\r\n"
            "  bool includeCognitiveStyle = true,\r\n"
            "}) async {",
        ),
        # 2. _assembleProfileText 调用加参数
        (
            "  final fullText = _assembleProfileText(\r\n"
            "    built.profile,\r\n"
            "    built.stagnation,\r\n"
            "    effectivenessText,\r\n"
            "    effectiveOnboarding,\r\n"
            "    styleProfileText,\r\n"
            "  );",
            "  final fullText = _assembleProfileText(\r\n"
            "    built.profile,\r\n"
            "    built.stagnation,\r\n"
            "    effectivenessText,\r\n"
            "    effectiveOnboarding,\r\n"
            "    styleProfileText,\r\n"
            "    includeCognitiveStyle,\r\n"
            "  );",
        ),
        # 3. 返回 hasOnboarding
        (
            "  return ProfileTextResult(text: fullText, profile: built.profile);",
            "  return ProfileTextResult(\r\n"
            "    text: fullText,\r\n"
            "    profile: built.profile,\r\n"
            "    hasOnboarding: effectiveOnboarding != null,\r\n"
            "  );",
        ),
        # 4. _emptyProfileResult 加 hasOnboarding
        (
            "  return ProfileTextResult(\r\n"
            "    text: '',\r\n"
            "    profile: StudentProfile(\r\n"
            "      proficiency: ProficiencyLevel.beginner,\r\n"
            "      confidence: 0,\r\n"
            "      syndromeProfile: const {},\r\n"
            "      totalSessions: 0,\r\n"
            "    ),\r\n"
            "  );",
            "  return ProfileTextResult(\r\n"
            "    text: '',\r\n"
            "    profile: StudentProfile(\r\n"
            "      proficiency: ProficiencyLevel.beginner,\r\n"
            "      confidence: 0,\r\n"
            "      syndromeProfile: const {},\r\n"
            "      totalSessions: 0,\r\n"
            "    ),\r\n"
            "    hasOnboarding: false,\r\n"
            "  );",
        ),
        # 5. _assembleProfileText 签名加参数
        (
            "String _assembleProfileText(\r\n"
            "  StudentProfile profile,\r\n"
            "  StagnationResult stagnation,\r\n"
            "  String? effectivenessText,\r\n"
            "  OnboardingData? effectiveOnboarding,\r\n"
            "  String? styleProfileText,\r\n"
            ") {",
            "String _assembleProfileText(\r\n"
            "  StudentProfile profile,\r\n"
            "  StagnationResult stagnation,\r\n"
            "  String? effectivenessText,\r\n"
            "  OnboardingData? effectiveOnboarding,\r\n"
            "  String? styleProfileText,\r\n"
            "  bool includeCognitiveStyle,\r\n"
            ") {",
        ),
        # 6. formatProfileText 调用传参
        (
            "  final text = formatProfileText(\r\n"
            "    profile,\r\n"
            "    stagnation,\r\n"
            "    effectivenessText,\r\n"
            "    effectiveOnboarding,\r\n"
            "  );",
            "  final text = formatProfileText(\r\n"
            "    profile,\r\n"
            "    stagnation,\r\n"
            "    effectivenessText,\r\n"
            "    effectiveOnboarding,\r\n"
            "    includeCognitiveStyle: includeCognitiveStyle,\r\n"
            "  );",
        ),
    ]),

    # ── C. teaching_types.dart ──
    (ROOT + r"\lib\types\teaching_types.dart", [
        (
            "/// 画像文本构建结果\r\n"
            "class ProfileTextResult {\r\n"
            "  final String text;\r\n"
            "  final StudentProfile profile;\r\n"
            "  const ProfileTextResult({required this.text, required this.profile});\r\n"
            "}",
            "/// 画像文本构建结果\r\n"
            "class ProfileTextResult {\r\n"
            "  final String text;\r\n"
            "  final StudentProfile profile;\r\n"
            "\r\n"
            "  /// A-1c：本次构建是否命中有效 onboarding（决定认知风格是否单独注入）\r\n"
            "  final bool hasOnboarding;\r\n"
            "\r\n"
            "  const ProfileTextResult({\r\n"
            "    required this.text,\r\n"
            "    required this.profile,\r\n"
            "    this.hasOnboarding = false,\r\n"
            "  });\r\n"
            "}",
        ),
    ]),

    # ── D. message_injector.dart ──
    (ROOT + r"\lib\services\message_injector.dart", [
        # 0. import student_profile_format
        (
            "import 'package:writingcoach/services/student_profile.dart';\r\n",
            "import 'package:writingcoach/services/student_profile.dart';\r\n"
            "import 'package:writingcoach/services/student_profile_format.dart';\r\n",
        ),
        # 1. 类字段
        (
            "  /// 批次63（B62b）：L1 意图向量——每个 session 最近 3 次交互意图\r\n"
            "  /// 随 _injectProfileAndIntents 迁入\r\n"
            "  final Map<String, List<String>> _recentIntentsBySession = {};",
            "  /// 批次63（B62b）：L1 意图向量——每个 session 最近 3 次交互意图\r\n"
            "  /// 随 _injectProfileAndIntents 迁入\r\n"
            "  final Map<String, List<String>> _recentIntentsBySession = {};\r\n"
            "\r\n"
            "  /// A-1c：认知风格注文（无 onboarding 时随画像计算，历史之后追加）。\r\n"
            "  /// 依赖当前会话消息关键词计数，属消息级动态项，不得留在稳定注入段。\r\n"
            "  String? _cognitiveStyleNote;",
        ),
        # 2. _injectStudentProfile
        (
            "  }) async {\r\n"
            "    try {\r\n"
            "      final profileResult = await buildStudentContext(\r\n"
            "        diagnosisRepo: _diagnosisRepo,\r\n"
            "        studentModelRepo: _studentModelRepo,\r\n"
            "        sessionRepo: _sessionRepo,\r\n"
            "        sessionId: sessionId,\r\n"
            "      );\r\n"
            "      if (profileResult.text.isNotEmpty) {\r\n"
            "        markStage(BudgetStageNames.studentProfile);\r\n"
            "        messages.add(ChatMessage(role: 'system', content: profileResult.text));\r\n"
            "      }\r\n"
            "    } catch (e, st) {\r\n"
            "      _logSafeRun('画像注入失败不阻断主流程', e, st);\r\n"
            "    }\r\n"
            "  }",
            "  }) async {\r\n"
            "    // A-1c：认知风格段随消息关键词计数变化（消息级动态项），\r\n"
            "    // 从稳定注入段移除，改由 injectTrailingHints 在历史之后追加。\r\n"
            "    _cognitiveStyleNote = null;\r\n"
            "    try {\r\n"
            "      final profileResult = await buildStudentContext(\r\n"
            "        diagnosisRepo: _diagnosisRepo,\r\n"
            "        studentModelRepo: _studentModelRepo,\r\n"
            "        sessionRepo: _sessionRepo,\r\n"
            "        sessionId: sessionId,\r\n"
            "        includeCognitiveStyle: false,\r\n"
            "      );\r\n"
            "      _cognitiveStyleNote = buildCognitiveStyleNote(\r\n"
            "        profileResult.profile,\r\n"
            "        hasOnboarding: profileResult.hasOnboarding,\r\n"
            "      );\r\n"
            "      if (profileResult.text.isNotEmpty) {\r\n"
            "        markStage(BudgetStageNames.studentProfile);\r\n"
            "        messages.add(ChatMessage(role: 'system', content: profileResult.text));\r\n"
            "      }\r\n"
            "    } catch (e, st) {\r\n"
            "      _logSafeRun('画像注入失败不阻断主流程', e, st);\r\n"
            "    }\r\n"
            "  }",
        ),
        # 3. injectTrailingHints 尾部追加
        (
            "    _injectReplyDetailGuidance(content: content, messages: messages);\r\n"
            "  }",
            "    _injectReplyDetailGuidance(content: content, messages: messages);\r\n"
            "    // A-1c：认知风格注文（消息级动态项）追加在历史之后——前缀保持稳定。\r\n"
            "    final note = _cognitiveStyleNote;\r\n"
            "    if (note != null) {\r\n"
            "      messages.add(ChatMessage(role: 'system', content: note));\r\n"
            "    }\r\n"
            "  }",
        ),
    ]),
]


def _detect_eol(data: bytes) -> bytes:
    """按文件实际行尾返回 \r\n 或 \n（逐文件自适应）。"""
    return b"\r\n" if data.count(b"\r\n") >= data.count(b"\n") / 2 else b"\n"


def _norm(s: str) -> str:
    """模板先归一为 LF（模板内混有 CRLF 字面量）。"""
    return s.replace("\r\n", "\n")


def main():
    for path, pairs in EDITS:
        with open(path, "rb") as f:
            data = f.read()
        eol = _detect_eol(data)
        for old, new in pairs:
            if eol == b"\r\n":
                old_b = _norm(old).replace("\n", "\r\n").encode("utf-8")
                new_b = _norm(new).replace("\n", "\r\n").encode("utf-8")
            else:
                old_b = _norm(old).encode("utf-8")
                new_b = _norm(new).encode("utf-8")
            cnt = data.count(old_b)
            if cnt != 1:
                print(f"FAIL {path}: hit={cnt} for:\n{old[:120]!r}")
                sys.exit(1)
            data = data.replace(old_b, new_b)
        with open(path, "wb") as f:
            f.write(data)
        print(f"OK   {path} ({len(pairs)} edits)")


if __name__ == "__main__":
    main()
