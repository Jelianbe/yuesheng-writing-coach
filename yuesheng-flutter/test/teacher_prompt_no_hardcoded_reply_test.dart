// ─────────────────────────────────────────────────────────────
// 反硬编码话术护栏（批次 96-17）
//
// 设计原则（用户明确要求）：回复话术必须由 AI 现场生成，禁止硬编码"语录"
// 或固定话术模板。本测试把这一原则**固化到实际注入的 teacher 系统提示**
// （kTeacherSkillContent —— 即 teacher_service.dart:69 真正喂给 LLM 的
// 系统消息），防止未来把反硬编码指令从"注入提示"误删/遗漏。
//
// 背景：此前该指令只存在于未注入的 skill_registry.dart，运行时 AI 并未被
// 约束"自主组织话术、不使用固定话术模板"，构成硬编码回复的隐患。
//
// 断言：注入提示必须显式——
//   1) 禁止固定话术模板
//   2) 教原理而非标准答案
//   3) 要求 AI 自主组织话术
//   4) 明示话术由 AI 现场生成、不存在可照搬的标准回复
// 这是对"话术由 AI 决定"的回归护栏，不依赖 API key，常驻可跑。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/agent_skills.dart';

void main() {
  group('teacher 系统提示禁止硬编码话术（话术由 AI 生成）', () {
    final p = kTeacherSkillContent;

    test('注入提示禁止固定话术模板并教原理而非标准答案', () {
      expect(p, contains('不使用固定话术模板'), reason: '注入提示必须禁止固定话术模板（话术由 AI 现场生成）');
      expect(p, contains('标准答案'), reason: '注入提示必须教原理而非标准答案');
      expect(p, contains('自主组织话术'), reason: '注入提示必须要求 AI 自主组织话术');
    });

    test('注入提示明示话术由 AI 现场生成、无标准回复可照搬', () {
      expect(p, contains('AI 现场生成'), reason: '应明示话术由 AI 现场生成');
      expect(p, contains('标准回复'), reason: '应明示不存在可照搬的标准回复');
    });
  });
}
