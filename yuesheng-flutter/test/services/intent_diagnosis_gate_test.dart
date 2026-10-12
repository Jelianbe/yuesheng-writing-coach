// ─────────────────────────────────────────────────────────────
// intent_diagnosis_gate_test — 意图↔诊断协议注入硬门（ADR-0005 · 2026-10-12）
//
// 本批核心不变量（可变红判据）：
//   **不存在任何句子同时满足「意图指令要求不要诊断」与「协议被注入」。**
//   旧结构下该矛盾真实存在（ask 指令「不要展开新的诊断」+ 强信号触发的
//   协议注入同帧；smalltalk 指令「不要发起诊断」+ 弱信号+上下文触发同帧），
//   本测试集把它钉成红灯 —— 谁把硬门拆掉，这里立刻红。
//
// 覆盖：
//   hasExplicitDiagnosisSignal  显式判据（含否定前缀、弱信号不算显式）
//   classifyUserIntent          显式信号升级（寒暄/疑问形态不被吞）
//   shouldInjectDiagnosisProtocol  硬门裁决矩阵
//   不变量                      语料 × 意图 × 上下文 全量扫描
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/intent_classifier.dart';

void main() {
  group('hasExplicitDiagnosisSignal（显式判据 · 单一真源）', () {
    test('#1 显式强信号 → true', () {
      expect(hasExplicitDiagnosisSignal('请帮我诊断这段文字'), isTrue);
      expect(hasExplicitDiagnosisSignal('你好，评价一下这段'), isTrue);
      expect(hasExplicitDiagnosisSignal('diagnose it'), isTrue);
      expect(hasExplicitDiagnosisSignal('Please DIAGNOSE this'), isTrue);
    });

    test('#2 弱信号 / 英文降级项单独出现 → false（不构成明确请求）', () {
      expect(hasExplicitDiagnosisSignal('这段怎么改更好'), isFalse);
      expect(hasExplicitDiagnosisSignal('哪里不好'), isFalse);
      expect(hasExplicitDiagnosisSignal('analyze my writing'), isFalse);
      expect(hasExplicitDiagnosisSignal('give me feedback'), isFalse);
    });

    test('#3 否定前缀修饰 → false（取消类措辞不是请求）', () {
      expect(hasExplicitDiagnosisSignal('别诊断了'), isFalse);
      expect(hasExplicitDiagnosisSignal('不想评价这段'), isFalse);
      expect(hasExplicitDiagnosisSignal('取消诊断'), isFalse);
    });

    test('#4 空串 → false', () {
      expect(hasExplicitDiagnosisSignal(''), isFalse);
      expect(hasExplicitDiagnosisSignal('   '), isFalse);
    });
  });

  group('classifyUserIntent 显式信号升级（ADR-0005 步 0）', () {
    test('#5 寒暄 + 显式诊断 → compose（不再被判闲聊吞掉）', () {
      expect(classifyUserIntent('你好，评价一下这段'), UserIntent.compose);
      expect(classifyUserIntent('谢谢，帮我诊断一下'), UserIntent.compose);
    });

    test('#6 疑问形态 + 显式诊断 → compose（消除指令矛盾）', () {
      expect(classifyUserIntent('帮我分析一下这段对话'), UserIntent.compose);
      expect(classifyUserIntent('这段怎么改更好，请分析一下'), UserIntent.compose);
    });

    test('#7 无显式信号 → 原判定不变（防升级逻辑误伤）', () {
      expect(classifyUserIntent('你好'), UserIntent.smalltalk);
      expect(classifyUserIntent('好的，谢谢'), UserIntent.smalltalk);
      expect(classifyUserIntent('在吗'), UserIntent.smalltalk);
      expect(classifyUserIntent('这段怎么改更好'), UserIntent.ask);
      expect(classifyUserIntent('为什么我的角色会出戏？'), UserIntent.ask);
      expect(classifyUserIntent('教我什么是潜台词'), UserIntent.ask);
      expect(classifyUserIntent('把这段改成动作描写'), UserIntent.revise);
      expect(classifyUserIntent('他推开门，风灌了进来'), UserIntent.compose);
    });

    test('#8 否定前缀的显式信号不触发升级', () {
      // 「别诊断了，直接教我」：信号被否 ⇒ 不升级 ⇒ 落 ask（"教我"）
      expect(classifyUserIntent('别诊断了，直接教我'), UserIntent.ask);
      // 「不想评价，谢谢」：信号被否 + 社交短句 ⇒ 闲聊
      expect(classifyUserIntent('不想评价，谢谢'), UserIntent.smalltalk);
    });
  });

  group('shouldInjectDiagnosisProtocol（硬门裁决矩阵）', () {
    test('#9 纯闲聊 → 不注入（有诊断上下文也不注入）', () {
      expect(
        shouldInjectDiagnosisProtocol(
          '你好',
          intent: UserIntent.smalltalk,
          hasDiagnosisContext: false,
        ),
        isFalse,
      );
      expect(
        shouldInjectDiagnosisProtocol(
          '在吗',
          intent: UserIntent.smalltalk,
          hasDiagnosisContext: true,
        ),
        isFalse,
      );
    });

    test('#10 寒暄 + 显式诊断 → 注入（带寒暄的诊断请求不被吞）', () {
      const text = '你好，评价一下这段';
      expect(
        shouldInjectDiagnosisProtocol(
          text,
          intent: classifyUserIntent(text),
          hasDiagnosisContext: false,
        ),
        isTrue,
      );
    });

    test('#11 弱信号 + 非创作意图 + 有上下文 → 不注入（旧行为会注入）', () {
      // 旧结构矛盾实例：smalltalk/ask 指令明写禁止诊断，协议块却照注
      expect(
        shouldInjectDiagnosisProtocol(
          '这段怎么改更好',
          intent: UserIntent.ask,
          hasDiagnosisContext: true,
        ),
        isFalse,
      );
      expect(
        shouldInjectDiagnosisProtocol(
          '好的，哪里不好',
          intent: UserIntent.smalltalk,
          hasDiagnosisContext: true,
        ),
        isFalse,
      );
    });

    test('#12 弱信号 + 创作/修改意图 → 仍注入（TH 五批语义保持）', () {
      expect(
        shouldInjectDiagnosisProtocol(
          '这段怎么改更好',
          intent: UserIntent.compose,
          hasDiagnosisContext: true,
        ),
        isTrue,
      );
      expect(
        shouldInjectDiagnosisProtocol(
          '把这段改成动作描写，看看哪里不好',
          intent: UserIntent.revise,
          hasDiagnosisContext: true,
        ),
        isTrue,
      );
    });

    test('#13 英文降级项需上下文（与 isDiagnosisRequest 判据一致）', () {
      expect(
        shouldInjectDiagnosisProtocol(
          'analyze my writing',
          intent: UserIntent.compose,
          hasDiagnosisContext: false,
        ),
        isFalse,
      );
      expect(
        shouldInjectDiagnosisProtocol(
          'analyze my writing',
          intent: UserIntent.compose,
          hasDiagnosisContext: true,
        ),
        isTrue,
      );
    });

    test('#14 显式信号无视上下文（强信号语义保持）', () {
      expect(
        shouldInjectDiagnosisProtocol(
          '请诊断这段',
          intent: UserIntent.compose,
          hasDiagnosisContext: false,
        ),
        isTrue,
      );
    });

    test('#15 未命中任何诊断判据 → 不注入（与 isDiagnosisRequest 一致）', () {
      for (final intent in UserIntent.values) {
        for (final ctx in [false, true]) {
          expect(
            shouldInjectDiagnosisProtocol(
              '他推开门，风灌了进来',
              intent: intent,
              hasDiagnosisContext: ctx,
            ),
            isFalse,
            reason: '非诊断文本任何意图/上下文组合都不得注入',
          );
        }
      }
    });
  });

  group('核心不变量：意图指令与协议注入不得矛盾', () {
    test('#16 语料 × 意图 × 上下文 全量扫描', () {
      const corpus = <String>[
        '你好',
        '在吗',
        '谢谢老师',
        '好的，谢谢',
        '你好，评价一下这段',
        '请帮我诊断这段文字',
        '帮我分析一下这段对话',
        '这段怎么改更好',
        '为什么我的角色会出戏？',
        '教我什么是潜台词',
        '把这段改成动作描写',
        '他推开门，风灌了进来',
        'analyze my writing',
        'diagnose it',
        '别诊断了，直接教我',
        '好的，哪里不好',
        '这段怎么改更好，请分析一下',
        '谢谢，你觉得我今天写得怎么样',
      ];
      for (final text in corpus) {
        for (final ctx in [false, true]) {
          final intent = classifyUserIntent(text);
          final inject = shouldInjectDiagnosisProtocol(
            text,
            intent: intent,
            hasDiagnosisContext: ctx,
          );
          if (!inject) continue;
          final note = buildIntentInstruction(intent, const []);
          final forbidsDiagnosis =
              note != null &&
              (note.contains('不要发起诊断') || note.contains('不要展开新的诊断'));
          expect(
            forbidsDiagnosis,
            isFalse,
            reason:
                '矛盾：文本「$text」意图=${intent.value} 注入了诊断协议，'
                '但意图指令同时禁止诊断',
          );
        }
      }
    });
  });
}
