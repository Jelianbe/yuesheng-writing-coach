// coach_persona_real_injection_test — 真实「AI 润色」文本注入诊断 system prompt
//
// 目的：把 outputs/polish/persona_<key>.txt（真实 DeepSeek 润色输出，由
// generate_personas.py 用 app 的 _polish 请求复刻生成）作为自定义教练的
// systemPromptFragment，喂给 buildSystemPromptV2（诊断所用生产函数），
// 断言：
//   1. 润色文本进入 system prompt；
//   2. 默认态度档（态度：豆包）被替换（loadedSkillIds 记 persona-<id>，
//      不再出现 attitude-doubao）；
//   3. personaLayer 为空时只注入基础语气，无 persona-layer-<id>。
//
// 与 coach_persona_injection_test 的区别：那是用例级别的机制守护（样本文本）；
// 本文件用「真实润色产物」做端到端内容守护，证明润色出来的语气真的能注入诊断。
//
// 若 outputs/polish/ 下对应文件缺失，本测试 skip（不阻塞；机制守护仍由
// coach_persona_injection_test 承担）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/types/coach_persona.dart';
import 'package:writingcoach/types/teaching_types.dart';

const Map<String, String> _personaMeta = {
  'girl': '少女',
  'old_man': '老大爷',
  'chinese_teacher': '中年语文老师',
};

String? _readPolished(String key) {
  for (final candidate in [
    'outputs/polish/persona_$key.txt',
    'yuesheng-flutter/outputs/polish/persona_$key.txt',
  ]) {
    final f = File(candidate);
    if (f.existsSync()) return f.readAsStringSync().trim();
  }
  return null;
}

void main() {
  group('真实润色人设 → 诊断 system prompt 注入', () {
    for (final entry in _personaMeta.entries) {
      final key = entry.key;
      final label = entry.value;

      test('「$label」润色文本注入并替换默认态度档', () {
        final polished = _readPolished(key);
        if (polished == null || polished.isEmpty) {
          markTestSkipped(
            'outputs/polish/persona_$key.txt 缺失，跳过'
            '（先运行 outputs/polish/generate_personas.py）',
          );
        }

        final persona = CoachPersona(
          id: 'real_$key',
          name: label,
          label: '自定义教练',
          isSystem: false,
          attitudeLevel: AttitudeLevel.doubao,
          systemPromptFragment: polished!,
        );

        final ctx = SkillLoadContext(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.doubao,
          subphase: TeachingSubphase.diagnosis,
          activePersona: persona,
        );

        final r = buildSystemPromptV2(ctx);

        // 1. 润色文本确实进入诊断 system prompt
        expect(
          r.systemPrompt,
          contains(polished),
          reason: '润色文本未注入 system prompt',
        );
        // 2. 默认态度档被替换（不再出现 attitude-doubao 内容标记）
        expect(r.loadedSkillIds, contains('persona-real_$key'));
        expect(r.loadedSkillIds, isNot(contains('attitude-doubao')));
        // 3. 无 personaLayer → 不应出现 persona-layer 标记
        expect(r.loadedSkillIds, isNot(contains('persona-layer-real_$key')));
      });
    }
  });
}
