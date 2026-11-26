// coach_persona_real_injection_test — 真实「AI 润色」文本注入诊断 system prompt
//
// 目的：把 outputs/polish/persona_<key>.txt（真实 DeepSeek 润色输出，由
// generate_personas.py 用 app 的 _polish 请求复刻生成）作为自定义教练的
// systemPromptFragment，喂给 buildSystemPromptV2（诊断所用生产函数），
// 断言：
//   1. 润色文本进入 system prompt；
//   2. 默认态度档（态度：温柔语气）被替换（loadedSkillIds 记 persona-<id>，
//      不再出现 attitude-gentle）；
//   3. personaLayer 为空时只注入基础语气，无 persona-layer-<id>。
//
// 与 coach_persona_injection_test 的区别：那是用例级别的机制守护（样本文本）；
// 本文件做端到端内容守护，证明润色出来的语气真的能注入诊断。
//
// ★ 内容来源分两档（T-20261126-11 甲案，2026-11-26）：
//   · 主仓有 outputs/polish/persona_<key>.txt ⇒ 用**真实润色产物**（本文件原意）；
//   · 干净 clone 缺该目录（.gitignore 整目录排除）⇒ 显式降级到**内联 fixture**
//     （_personaFixture），并打一行 `[降级]` 标记。降级后仍验「文本原样注入 +
//     态度档被替换」，只是不再证明「文本由 DeepSeek 产出」——那一层由产物本身
//     的存在性承担。fixture 刻意保留标点 / 换行 / 中文引号形态，不丢注入链覆盖。
//   ⚠️ 若在主仓（有真实产物）看到 `[降级]`，说明 _readPolished 被改坏了
//      —— 用例体内的反向哨兵会直接打红。

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

/// 干净 clone 没有 outputs/polish/（.gitignore 整目录排除），
/// 但本条用例守的是「润色文本能否原样注入 + 态度档是否被替换」，
/// 这层性质**不依赖文本是不是真的由 DeepSeek 产出**。
/// ⇒ 缺件时用下列固定文本继续跑（**显式降级，不静默**）。
///
/// 每份都刻意保留：中文逗号「，」/ 句号「。」/ 问号或感叹号 / 中文双引号「“”」
/// / 换行 `\n` —— 这些形态正是「原样穿过注入链」这条覆盖的载体。
/// 文本为本次手写，**与真实产物不同**，且不含英文 key / 个人信息。
const Map<String, String> _personaFixture = {
  'girl':
      '我觉得，你先别急着改，好吗？先把这句话在心里轻轻念一遍，听听有没有“别扭”的地方。\n'
      '要是说不顺，就换个更软的说法，比如把“你必须”改成“你要不要试试”，听着就亲近多了。\n'
      '我陪你一句一句来，慢慢调，慢慢顺。要是还拿不准，就把想说的话先写下来，再一个字一个字地挑，'
      '挑到念出来自己也觉得舒服为止。别怕改，改到顺口就是好句子，你也可以先读给我听，我陪你一起挑，好吗？',
  'old_man':
      '我说句实在的，说话别绕弯子。先想清楚这一句到底要说什么，再讲道理。\n'
      '别一口气堆三层意思，听着累。拿不准就停下来问自己：“这句话，人家一听就懂吗？”\n'
      '不懂就拆开说，一句一句来。慢点儿，不丢人！咱们写字跟说话一个理儿，实打实、慢条斯理，'
      '人家才愿意一直听下去。记住，话是说给人听的，不是摆着好看的，这话糙，理不糙。',
  'chinese_teacher':
      '同学们，先别忙着下笔，读一读自己写的那一句：“它通顺吗？”\n'
      '通顺，才谈得上有没有味道。句子要短，主谓要清，虚词别堆。\n'
      '“虽然……但是……”用得太密，读起来就像绕口令；改一改，把多余的枝蔓剪掉，骨架自然就立起来了。\n'
      '写完之后再朗读一遍，气顺不顺、字咬不咬得清，耳朵最诚实。改文章跟修枝一样，急不得，慢慢来。',
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
        // 真实产物优先；缺件回退内联 fixture（显式降级，打标记不静默）。
        final real = _readPolished(key);
        final usingFixture = real == null || real.isEmpty;
        final polished = usingFixture ? _personaFixture[key]! : real;
        if (usingFixture) {
          // ignore: avoid_print
          print(
            '[降级] outputs/polish/persona_$key.txt 缺失 ⇒ '
            '使用内联 fixture（非真实润色产物）',
          );
        }

        // ★ 反向哨兵（T-20261127-02 补）：产物在盘上 ⇒ 必须走真实文本。
        // 这三条与 _readPolished 完全独立（自己开 File 读），专门挡三种走偏：
        //   a) _readPolished 失效恒返回 null ⇒ 静默降级（usingFixture 应为 false）
        //   b) 读到了但内容被截断 / 改写 ⇒ polished 与磁盘不一致
        //   c) 交叉错配 key ⇒ 注入的是别人的文本
        // 干净 clone 无 outputs/polish/ ⇒ 整段不执行（否则就是假红）。
        final sentinel = File('outputs/polish/persona_$key.txt');
        if (sentinel.existsSync()) {
          final onDisk = sentinel.readAsStringSync().trim();
          expect(onDisk, isNotEmpty, reason: '产物文件存在但为空');
          expect(
            usingFixture,
            isFalse,
            reason:
                '真实产物存在（outputs/polish/persona_$key.txt）却走了降级 '
                '⇒ _readPolished 失效',
          );
          expect(polished, onDisk, reason: '注入文本与磁盘产物不一致 ⇒ 读取链被截断或错配');
        }

        final persona = CoachPersona(
          id: 'real_$key',
          name: label,
          label: '自定义教练',
          isSystem: false,
          attitudeLevel: AttitudeLevel.gentle,
          systemPromptFragment: polished,
        );

        final ctx = SkillLoadContext(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.gentle,
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
        // 2. 默认态度档被替换（不再出现 attitude-gentle 内容标记）
        expect(r.loadedSkillIds, contains('persona-real_$key'));
        expect(r.loadedSkillIds, isNot(contains('attitude-gentle')));
        // 3. 无 personaLayer → 不应出现 persona-layer 标记
        expect(r.loadedSkillIds, isNot(contains('persona-layer-real_$key')));
      });
    }
  });
}
