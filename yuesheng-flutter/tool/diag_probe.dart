// 提取真实 system prompt（P0_ENGAGE + yuesheng 态度）供 API 复现验证
import 'dart:io';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  final ctx = SkillLoadContext(
    phase: TeachingPhase.p0Engage,
    attitude: AttitudeLevel.yuesheng,
    subphase: null,
    isBeginner: false,
  );
  final r = buildSystemPromptV2(ctx);
  File('outputs/_real_system_prompt.txt').writeAsStringSync(r.systemPrompt);
  stdout.writeln('PROMPT_LEN=${r.systemPrompt.length}');
}
