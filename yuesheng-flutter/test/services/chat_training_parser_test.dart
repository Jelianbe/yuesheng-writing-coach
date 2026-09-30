// ─────────────────────────────────────────────────────────────
// ChatTrainingParser 单元测试 — 批次2（2.4）回退顺序
//
// 修复前：关键词 Map 遍历 passed→partial→failed，"完成"先命中 →
// 混合表述"完成度不错，但还需要重新处理"被虚报为达标（passed）。
// 修复后：partial → failed → passed（保守偏置：宁可多练一轮不虚报达标）。
//
// ADR-C105（2026-09-30）追加：`[YS_TRAINING]` 协议层三件套
//（常量 / parseTrainingProtocol / stripTrainingBlock）+ 两级判定
//（协议优先 → 关键词回退）+ 否定式中缀集。原 2.4/ADR-C100 用例**原样保留**，
// 作为「Tier 2 回退行为未回归」的锚点。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/chat_training_parser.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('parseTrainingResult（批次2 2.4 回退顺序）', () {
    test('#1 混合表述：完成度不错 + 还需要重新处理 → partial（不虚报达标）', () {
      expect(
        parseTrainingResult('完成度不错，但因果链还需要重新处理'),
        TrainingResult.partial,
        reason: '同时含 partial「还需要」与 passed「完成」，partial 优先（保守偏置）',
      );
    });

    test('#2 精确短语「部分达标」→ partial', () {
      expect(parseTrainingResult('这部分算部分达标'), TrainingResult.partial);
    });

    test('#3 精确短语「未达标」→ failed', () {
      expect(parseTrainingResult('本次练习未达标'), TrainingResult.failed);
    });

    test('#4 「达标」→ passed', () {
      expect(parseTrainingResult('这次已经达标了'), TrainingResult.passed);
    });

    test('#5 「未通过」→ failed', () {
      expect(parseTrainingResult('本次练习未通过'), TrainingResult.failed);
    });

    test('#6 「方向对了」→ partial', () {
      expect(parseTrainingResult('方向对了，但细节还要打磨'), TrainingResult.partial);
    });

    test('#7 无关键词 → null', () {
      expect(parseTrainingResult('继续练习吧'), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // ADR-C105 A1：`[YS_TRAINING]` 协议解析
  // ═════════════════════════════════════════════════════════════

  group('parseTrainingProtocol（ADR-C105 A1 协议解析）', () {
    test('#P1 无起始标记 → null', () {
      expect(parseTrainingProtocol('本节练习到此结束，下次继续。'), isNull);
    });

    test('#P2 完整块 → 五个字段全解析', () {
      final p = parseTrainingProtocol(
        '正文先写在这里。\n[YS_TRAINING]\n'
        '{"result":"failed","reason":"没能写出动作细节",'
        '"evidence":["他很生气"],"next_step":"重写第二段",'
        '"state_suggestion":"保持 L2"}\n[/YS_TRAINING]',
      );
      expect(p, isNotNull);
      expect(p!.result, TrainingResult.failed);
      expect(p.reason, '没能写出动作细节');
      expect(p.evidence, ['他很生气']);
      expect(p.nextStep, '重写第二段');
      expect(p.stateSuggestion, '保持 L2');
    });

    test('#P3 有起始标记无结束标记 → 容错解析到文本末尾（同事实提取）', () {
      final p = parseTrainingProtocol('[YS_TRAINING]{"result":"passed"}');
      expect(p?.result, TrainingResult.passed);
    });

    test('#P4 result 取值为非法枚举 → result 为 null（不得兜成某个合法态）', () {
      final p = parseTrainingProtocol(
        '[YS_TRAINING]{"result":"unknown","reason":"r"}[/YS_TRAINING]',
      );
      expect(p, isNotNull);
      expect(
        p!.result,
        isNull,
        reason: 'fromString 对未知取值返回 null（实测），调用方据此回退关键词表',
      );
      expect(p.reason, 'r', reason: '单字段非法只废该字段，不整块作废');
    });

    test('#P5 载荷为空 → null', () {
      expect(parseTrainingProtocol('[YS_TRAINING]   [/YS_TRAINING]'), isNull);
    });

    test('#P6 载荷非 JSON / JSON 非对象 → null（不 throw）', () {
      expect(
        parseTrainingProtocol('[YS_TRAINING]not json[/YS_TRAINING]'),
        isNull,
      );
      expect(parseTrainingProtocol('[YS_TRAINING][1,2][/YS_TRAINING]'), isNull);
    });
  });

  group('stripTrainingBlock（ADR-C105 A1 剥离）', () {
    test('#S1 无标记 → 逐字节返回原文', () {
      const s = '正文一段。\n正文二段。';
      expect(stripTrainingBlock(s), s);
    });

    test('#S2 中间完整块 → 移除后前后拼接（保留一个换行）', () {
      expect(
        stripTrainingBlock(
          '前文\n[YS_TRAINING]{"result":"passed"}[/YS_TRAINING]\n后文',
        ),
        '前文\n后文',
      );
    });

    test('#S3 块在末尾 → 只留前文并去尾空白', () {
      expect(
        stripTrainingBlock(
          '前文\n[YS_TRAINING]{"result":"passed"}[/YS_TRAINING]',
        ),
        '前文',
      );
    });

    test('#S4 有头无尾 → 自头截断（保守防泄漏）', () {
      expect(stripTrainingBlock('前文\n[YS_TRAINING]{"result":"passed"}'), '前文');
    });

    test('#S5 全文仅一个块 → 空串', () {
      expect(stripTrainingBlock('[YS_TRAINING]{"a":1}[/YS_TRAINING]'), '');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // ADR-C105 A1：两级判定（协议优先 → 关键词回退）
  // ═════════════════════════════════════════════════════════════

  group('parseTrainingResult 协议优先（ADR-C105 A1）', () {
    test('★#T1 模型判 failed、reason 含「完成」→ failed（本 ADR 的核心反转）', () {
      const raw =
          '这次改得还是太急。\n[YS_TRAINING]\n'
          '{"result":"failed","reason":"学员没能完成动作细节的改写"}\n'
          '[/YS_TRAINING]';
      expect(
        parseTrainingResult(raw),
        TrainingResult.failed,
        reason:
            '协议优先。旧实现扫自由文本，reason 里的「完成」会把它记成 passed —— '
            '判定值经 onTrainingResult 贯穿 FSM/达标率/徽章，等于 UI 撒谎',
      );
    });

    test('#T2 模型判 passed、正文含「未达标」→ 仍 passed（不做交叉校验，见 ADR R1）', () {
      const raw =
          '整体已经到位。\n[YS_TRAINING]\n'
          '{"result":"passed","reason":"完成度达标"}\n[/YS_TRAINING]\n'
          '（上一轮它未达标，这轮补上了）';
      expect(
        parseTrainingResult(raw),
        TrainingResult.passed,
        reason:
            'prompt 已授权模型自主判定（skills_training_p3.dart:128 '
            '「由你自主判断，不受代码数据绑架」）⇒ 代码侧刻意不做正文交叉校验。'
            '此断言锁定的是**已裁定**的行为（ADR-C105 §13 R1），不是疏漏',
      );
    });

    test('#T3 result 非法 → 回退关键词表（在已剥协议块的文本上扫描）', () {
      expect(
        parseTrainingResult(
          '[YS_TRAINING]{"result":"?"}[/YS_TRAINING] 本次练习未达标',
        ),
        TrainingResult.failed,
      );
    });

    test('★#T4 协议块内自述不参与 Tier2：result 缺失 + reason 含「完成」→ null', () {
      const raw = '[YS_TRAINING]{"reason":"学员没能完成这次改写"}[/YS_TRAINING]';
      expect(
        parseTrainingResult(raw),
        isNull,
        reason:
            '剥块后正文为空 ⇒ 无关键词命中 ⇒ null（= 不计通过、不写 history）。'
            '若 Tier2 未先剥块，「完成」会被扫到并虚报 passed',
      );
    });

    test('#T5 无协议块 → 关键词表行为逐条不变（回归锚点）', () {
      expect(parseTrainingResult('本次练习达标'), TrainingResult.passed);
      expect(parseTrainingResult('本次练习未达标'), TrainingResult.failed);
      expect(parseTrainingResult('方向对了，但细节还要打磨'), TrainingResult.partial);
      expect(parseTrainingResult('继续练习吧'), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // ADR-C105 A2：否定式中缀集
  // ═════════════════════════════════════════════════════════════

  group('否定式中缀集（ADR-C105 A2）', () {
    test('#A2-1 「没能完成」→ failed（旧实现漏判，落到 passed 词表）', () {
      expect(parseTrainingResult('这篇没能完成动作改写'), TrainingResult.failed);
    });

    test('#A2-2 「无法通过」→ failed', () {
      expect(parseTrainingResult('本次练习无法通过'), TrainingResult.failed);
    });

    test('#A2-3 「难以达标」→ failed', () {
      expect(parseTrainingResult('这个目标难以达标'), TrainingResult.failed);
    });

    test('#A2-4 「不太成功」→ failed', () {
      expect(parseTrainingResult('这次改写不太成功'), TrainingResult.failed);
    });

    test('#A2-5 空中缀（前缀紧邻词干）与旧实现逐字节等价', () {
      expect(parseTrainingResult('本次练习不达标'), TrainingResult.failed);
      expect(parseTrainingResult('没有完成'), TrainingResult.failed);
      expect(parseTrainingResult('不通过'), TrainingResult.failed);
    });

    test('★#A2-R 反例：指令句不得被判 failed（中缀集不放开通配）', () {
      final r = parseTrainingResult('不要通过抄袭来完成这次改写');
      expect(
        r,
        isNot(TrainingResult.failed),
        reason:
            '「要」不在中缀集内 ⇒ 前缀与词干不相邻 ⇒ 否定式不命中。'
            '（该句仍会被既有 passed 词表判 passed —— 那是本批之前就有的行为，'
            '本断言只锁定「中缀扩充没有把它**新**误判成 failed」；'
            '若有人把中缀放开为任意通配，本用例立即变红。）',
      );
    });
  });
}
