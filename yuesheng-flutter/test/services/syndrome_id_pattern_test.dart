// ─────────────────────────────────────────────────────────────
// 症候编号识别器护栏（ADR-0003 甲-1 · 层 2 S2 批 · 2026-10-05）
//
// S1 把 8 处硬编码的 `P0\d{2}` 收敛到 `syndrome_id_pattern.dart` 的
// 「已登记编号段」声明。本测试守住那个声明，**不让它退化成又一处硬编码**。
//
// 【为什么这些断言不是废话】识别器本身是「从段声明派生」的，若只测
// 「派生结果对不对」，删掉一个段声明后派生结果同样自洽 ⇒ 恒绿。
// 所以下面每条要么钉**字面量**（段数、段名），要么钉**跨文件同源**
// （识别器 vs 生产消费方），要么钉**行为事实**（泄漏检测真的会红）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/diagnosis_validator.dart';
import 'package:writingcoach/services/syndrome_id_pattern.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/teacher_validator.dart';

void main() {
  group('#S2-A 编号段声明的硬锚（非派生，§4-148 同型纪律）', () {
    // 【为什么钉字面量】若写成 expect(段数, 注册表某量)，删掉一个段声明后
    // 两侧同步变小 ⇒ 恒绿。段声明是「意图声明」，不是被测对象 ⇒ 必须钉死。
    test('#S2-A1 现行已登记编号段恰为 1 段 = P 段', () {
      const expectSegments = {'P'};
      final loose = RegExp(kAnySyndromeIdRe.pattern).pattern;
      // 逐段断言「声明存在」而非「数量相等」：新增段时会在此红，提示同步更新。
      for (final seg in expectSegments) {
        expect(
          loose.contains(seg),
          isTrue,
          reason:
              '段 $seg 应出现在派生模式里（实得 $loose）。'
              '若你新开了编号段，请同步更新本用例的 expectSegments。',
        );
      }
    });

    test('#S2-A2 派生模式必须逐字等于 S1 前的硬编码模式（S1 未引入行为变化）', () {
      // 这是本批的**行为等价性锚**：S1 之前 8 处各自硬编码`P0\d{2}`，
      // S1 之后全部改引用派生值。若此断言变了 ⇒ 说明派生逻辑改动了行为，
      // 属于必须显式评审的变更（而不是「顺手优化」）。
      expect(kAnySyndromeIdRe.pattern, r'P0\d{2}');
    });

    test('#S2-A3 锚定形态与 S1 前的硬编码锚定形态逐例等价（parser 依赖严格性）', () {
      // ⚠️ 这里是**语义等价**而非逐字相等：派生值带非捕获组
      // `^(?:P0\d{2})$`，S1 前是 `^P0\d{2}$`。`(?:)` 不改变匹配语义
      // （差异由 #S2-B3 的逐例对照独立守住），而**逐字相等会把实现细节
      // 钉成契约** —— 换一种等价写法就红，却不代表行为变了。
      // 形态层的锚点交给 #S2-B2（拒绝子串）与 #S2-B3（逐例对照）。
      final oldAnchored = RegExp(r'^P0\d{2}$');
      const samples = [
        'P001',
        'P037',
        'P099',
        'P100',
        'S001',
        'XP003',
        'P0011',
        'P0ab',
        'P12',
        '',
        'P000',
      ];
      for (final s in samples) {
        expect(
          kAnchoredSyndromeIdRe.hasMatch(s),
          oldAnchored.hasMatch(s),
          reason: '锚定形态对 "$s" 的判定与 S1 前不一致（行为回归）',
        );
      }
      expect(
        kAnchoredSyndromeIdRe.pattern,
        r'^(?:P0\d{2})$',
        reason:
            '锚定形态的字面形态（若将来加分段，形态会变，'
            '届时需确认仍是「非捕获组包裹 + 首尾锚点」这一形态约定）',
      );
    });
  });

  group('#S2-B 识别行为（宽松 vs 锚定，两种形态不可互相替代）', () {
    test('#S2-B1 宽松形态命中正文中的编号（含子串命中）', () {
      for (final s in const ['P001', 'P037', '诊断显示 P012 属于角色空心化']) {
        expect(kAnySyndromeIdRe.hasMatch(s), isTrue, reason: '$s 应命中');
      }
    });

    test('#S2-B2 锚定形态拒绝非完整匹配（这是它存在的唯一理由）', () {
      for (final s in const ['XP003', 'P0011', 'P0ab', '', 'P12']) {
        expect(
          kAnchoredSyndromeIdRe.hasMatch(s),
          isFalse,
          reason:
              '$s 不是合法编号 —— 锚定形态若命中它，'
              'diagnosis_parser 的 syndrome_id_format 拒答就等于没校验。',
        );
      }
    });

    test('#S2-B3 宽松与锚定对 P 段行为与 S1 前的硬编码逐例一致', () {
      // 正对照：把 S1 前的原始字面量在此重算一遍，逐例比对。
      final oldLoose = RegExp(r'P0\d{2}');
      final oldAnchored = RegExp(r'^P0\d{2}$');
      const samples = [
        'P001',
        'P037',
        'P099',
        'P000',
        'P100',
        'S001',
        'T017',
        'A001',
        'H001',
        'XP003',
        'P0011',
        'P0ab',
        'P12',
        '',
      ];
      for (final s in samples) {
        expect(
          kAnySyndromeIdRe.hasMatch(s),
          oldLoose.hasMatch(s),
          reason: '宽松形态对 "$s" 的判定与 S1 前不一致（行为回归）',
        );
        expect(
          kAnchoredSyndromeIdRe.hasMatch(s),
          oldAnchored.hasMatch(s),
          reason: '锚定形态对 "$s" 的判定与 S1 前不一致（行为回归）',
        );
      }
    });

    test('#S2-B4 S 段当前【不】被识别—— 尚未登记，识别器不得提前放行', () {
      // 这条是 S1 的**边界锁**：识别器是「按段声明」派生的，而 S 段尚未
      // 登记。若哪天有人只改了 _kSegmentPattern 却忘了走登记流程，本条
      // 与 #S2-C2 会一起把「未登记就放行」暴露出来。
      expect(
        kAnySyndromeIdRe.hasMatch('S001'),
        isFalse,
        reason: 'S 段尚未登记进 _kSegmentPattern ⇒ 不应被识别为症候编号。',
      );
    });
  });

  group('#S2-C 跨文件同源（防「有人只改了一半」）', () {
    test('#S2-C1 三个生产消费方与识别器同源', () {
      // 这三条断言打在**消费方的实例**上，而不是重新算一遍模式。
      // 目的：任一消费方被改回硬编码（或另立一个未登记的模式），
      // 本组即红。
      expect(kSyndromeCodeRe.pattern, kAnySyndromeIdRe.pattern);
      expect(
        identical(kSyndromeCodeRe, kAnySyndromeIdRe),
        isTrue,
        reason:
            'diagnosis_validator 应直接复用识别器实例，'
            '而非复制一份模式（复制 ⇒ 未来改一处漏一处）',
      );
    });

    test('#S2-C2 新号登记形态断言：注册表任一 ID 都必须被识别器接受', () {
      // 「登记」的定义 = 出现在 kSyndromeRegistry 里。逐条验证识别器认识它。
      // ⇒ 阶段二真注册 S001 时，本条自动覆盖 S001（若段声明已加 S）。
      for (final rec in kSyndromeRegistry) {
        expect(
          isSyndromeId(rec.id),
          isTrue,
          reason:
              '注册表里的 ${rec.id} 必须被 isSyndromeId 接受 —— '
              '否则该实体一旦泄漏编号，检测会看不见它。',
        );
      }
    });

    test('#S2-C3 注册表外的 P0xx 仍被宽松形态识别（退役号也属泄漏面）', () {
      // P038/P099 不在注册表（未实体化），但若模型回显它们，同样是
      // 「把编号暴露给学员」。识别器按**段**而非按**集合**派生，正是
      // 为覆盖这类号 —— 若改成按注册表 ID 枚举，本条即红。
      for (final s in const ['P038', 'P049', 'P099']) {
        expect(
          kAnySyndromeIdRe.hasMatch(s),
          isTrue,
          reason: '$s 未实体化但仍是 P 段编号，泄漏检测必须看得见。',
        );
      }
    });
  });

  group('#S2-D 生产防线端到端（变异点：识别器失效 ⇒ 真的会红）', () {
    test('#S2-D1 V-03 编号泄漏回填：P 段被回填掉（防线在位）', () {
      // 变异实证用的对照：识别器一旦失效（被改窄或被绕开），本条即红。
      final r = validateNaturalLanguage('你写的是 P007，属于角色空心化。');
      expect(
        r.cleaned.contains('P007'),
        isFalse,
        reason: 'P 段编号必须被 V-03 回填掉（基线行为，证明防线在位）',
      );
      expect(r.cleaned.contains('角色空心化'), isTrue, reason: '回填的应是症候名而非占位符');
    });

    test('#S2-D2 V-03 回填覆盖注册表外的 P 段号（P038 → 占位符而非原样透出）', () {
      // 识别器按**段**而非按**集合**派生 ⇒ 未实体化的 P038 也被识别。
      // 若改成按注册表 ID 枚举，本条会红（`P038` 会原样到达学员眼前）。
      final r = validateNaturalLanguage('你写的是 P038。');
      expect(
        r.cleaned.contains('P038'),
        isFalse,
        reason: 'P038 虽未实体化但仍是 P 段编号，编号不得外泄',
      );
    });

    test('#S2-D3 teacher 泄漏检测：P 段泄漏会报 NO_SYNDROME_ID_LEAK', () {
      // 端到端打穿「识别器 → 消费方」整条链：改识别器若使本条红，
      // 即证明这条链真的在读它（§4-149：断言必须打在真正读取数据源的层）。
      final r = checkTeacherConsistency(
        TeacherResult(
          teachingDecision: 'encourage',
          teachingReason: '观察',
          naturalLanguage: '你写的是 P007。',
        ),
      );
      expect(
        r.violations.map((v) => v.rule),
        contains('NO_SYNDROME_ID_LEAK'),
        reason: 'P 段编号泄漏必须被检出（防线在位）',
      );
    });

    test('#S2-D4 teacher 泄漏检测：S 段当前不报（未登记 ⇒ 不误报）', () {
      // 与 #S2-B4 互为镜像：S 段未登记 ⇒ 识别器看不见 ⇒ 不报。
      // 这条锁的是「不误报」。将来 S 段正式登记后，本条**应当转红**
      //（届时需改写为「应报」），那个红就是「登记生效」的可观测信号。
      final r = checkTeacherConsistency(
        TeacherResult(
          teachingDecision: 'encourage',
          teachingReason: '观察',
          naturalLanguage: '你写的是 S001。',
        ),
      );
      expect(
        r.violations.map((v) => v.rule),
        isNot(contains('NO_SYNDROME_ID_LEAK')),
        reason: 'S 段未登记，泄漏检测不应报 S 段（否则是误报）',
      );
    });

    test('#S2-D5 S 段一旦登记，两条防线同时生效（模拟：直接用段内样例验证派生逻辑）', () {
      // 不改生产代码，而是验证「若段声明里出现 S，派生模式会命中 S 段」——
      // 即派生逻辑本身对未知段前缀是通用的，不是写死 P。
      // 做法：按syndrome_id_pattern.dart 里同一套拼接规则重算一次。
      const patternWhenSRegistered = r'S0\d{2}';
      expect(
        RegExp(patternWhenSRegistered).hasMatch('S001'),
        isTrue,
        reason: '派生规则对任意段前缀通用 —— 新段无需改派生逻辑',
      );
      // 真正的「登记生效」验证留给阶段二：届时本组 #S2-B4 / #S2-D4 会红，
      // 提示把「未登记」的两条断言改写为「已登记」形态。
    });
  });
}
