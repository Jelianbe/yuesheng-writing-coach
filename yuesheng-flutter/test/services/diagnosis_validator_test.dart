// ─────────────────────────────────────────────────────────────
// diagnosis_validator_test — 诊断校验器测试（批次4 补充）
//
// 覆盖：
//   validateSyndromeMutexWarnings（4.1 O6）:
//     1. 互斥对同时命中 → 返回对应 warning
//     2. 非互斥组合 → 无 warning
//   validateDiagnosisSchema（4.1）:
//     3. 含互斥对 → valid=true + warnings 非空（warning 级不阻断）
//     4. 无互斥对 → valid=true + warnings 空
//   validateNaturalLanguage V-02（4.6）:
//     5. "你应该/你务必" 类判决句命中共享词表 → 产生 V-02 fix
//     6. 非判决句 → 无 V-02 fix
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/diagnosis_validator.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart'
    show kTechniqueShortNames;
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('validateSyndromeMutexWarnings（4.1 O6）', () {
    test('互斥对同时命中 → 返回对应 warning', () {
      final warnings = validateSyndromeMutexWarnings(['P004', 'P017']);
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('P004'));
      expect(warnings.first, contains('P017'));
    });

    test('三对互斥规则均生效（P013/P010、P007/P015）', () {
      expect(validateSyndromeMutexWarnings(['P013', 'P010']), hasLength(1));
      expect(validateSyndromeMutexWarnings(['P007', 'P015']), hasLength(1));
    });

    test('非互斥组合 → 无 warning', () {
      expect(validateSyndromeMutexWarnings(['P004', 'P001']), isEmpty);
      expect(validateSyndromeMutexWarnings(['P004']), isEmpty);
    });

    test('互斥对仅一侧命中 → 无 warning', () {
      expect(validateSyndromeMutexWarnings(['P017', 'P002']), isEmpty);
    });
  });

  group('validateDiagnosisSchema（4.1 warning 不阻断）', () {
    Map<String, dynamic> validDiagnosis(List<String> syndromeIds) {
      return {
        'syndromes': [
          for (final id in syndromeIds)
            {
              'syndrome_id': id,
              'name': '症候$id',
              'severity': 'L2',
              'evidence': ['证据'],
              'explanation': '解释',
            },
        ],
        'suggested_actions': ['动作1'],
        'confidence': 0.8,
      };
    }

    test('含互斥对 → valid=true 且 warnings 非空（不阻断落库）', () {
      final result = validateDiagnosisSchema(
        validDiagnosis(['P004', 'P017', 'P001']),
      );
      expect(result.valid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('P004/P017'));
    });

    test('无互斥对 → valid=true 且 warnings 空', () {
      final result = validateDiagnosisSchema(
        validDiagnosis(['P004', 'P001', 'P002']),
      );
      expect(result.valid, isTrue);
      expect(result.warnings, isEmpty);
    });

    // ── D04 / ADR-C102：零症候合法，仅放宽「空数组」判据，类型守卫不动 ──
    Map<String, dynamic> diagnosisWithSyndromes(dynamic syndromes) {
      return {
        'syndromes': syndromes,
        'suggested_actions': ['动作1'],
        'confidence': 0.8,
      };
    }

    test('空数组 syndromes（零症候 clean/insufficient）→ valid=true', () {
      final result = validateDiagnosisSchema(
        diagnosisWithSyndromes(<String>[]),
      );
      expect(result.valid, isTrue, reason: '零症候合法，不应判为整条拒');
      expect(result.errors, isEmpty);
    });

    test('syndromes 为 null → valid=false（类型守卫保留）', () {
      final result = validateDiagnosisSchema(diagnosisWithSyndromes(null));
      expect(result.valid, isFalse);
      expect(result.errors, isNotEmpty);
    });

    test('syndromes 为非数组（字符串）→ valid=false（类型守卫保留）', () {
      final result = validateDiagnosisSchema(diagnosisWithSyndromes('P001'));
      expect(result.valid, isFalse);
      expect(result.errors, isNotEmpty);
    });
  });

  group('validateNaturalLanguage V-02 判决词（4.6 共享常量）', () {
    test('"你应该" → 命中 V-02（仅记录不阻断）', () {
      final result = validateNaturalLanguage('你应该调整一下这段的结构');
      final v02 = result.fixes.where((f) => f.type == 'V-02');
      expect(v02, isNotEmpty);
      expect(v02.first.original, '你应该');
      expect(result.valid, isTrue); // V-02 非真拦截
    });

    test('"你务必" → 命中 V-02', () {
      final result = validateNaturalLanguage('你务必先写完这个情节');
      expect(
        result.fixes.any((f) => f.type == 'V-02' && f.original == '你务必'),
        isTrue,
      );
    });

    test('非判决句 → 无 V-02', () {
      final result = validateNaturalLanguage('这一段的人物动机可以再明确一点');
      expect(result.fixes.any((f) => f.type == 'V-02'), isFalse);
    });

    group('validateNaturalLanguage V-01/V-03/V-04（R-019 批次二补判据边界）', () {
      test('#N1 V-03 编号泄漏 → 回填名称（不再抹成空壳，P0\'-3）', () {
        final result = validateNaturalLanguage('这里有 P002 与 A001 编号');
        expect(result.cleaned.contains('P002'), isFalse);
        expect(result.cleaned.contains('【症候】'), isFalse);
        expect(result.cleaned, contains('信息倾泻症')); // P002 名
        expect(result.cleaned.contains('【动作】'), isFalse);
        expect(result.cleaned, contains('缩小范围')); // A001 名
        expect(result.fixes.any((f) => f.type == 'V-03'), isTrue);
      });

      test('#N2 V-04 sensei 档含糖水词 → 拦截（valid=false）', () {
        final result = validateNaturalLanguage(
          '你写得真棒',
          attitude: AttitudeLevel.sensei,
        );
        expect(
          result.fixes.any((f) => f.type == 'V-04' && f.original == '真棒'),
          isTrue,
        );
        expect(result.valid, isFalse); // V-04 是阻断型
      });

      test('#N3 V-04 非 sensei 档含糖水词 → 不拦', () {
        final result = validateNaturalLanguage('你写得真棒');
        expect(result.fixes.any((f) => f.type == 'V-04'), isFalse);
      });

      test('#N4 V-01 恰好 80 字符无引号段落 → 不触发（阈值边界）', () {
        final longPara = '甲' * 80;
        final result = validateNaturalLanguage(longPara);
        expect(result.fixes.any((f) => f.type == 'V-01'), isFalse);
      });

      test('#N5 V-01 81 字符无引号段落 → 触发', () {
        final longPara = '甲' * 81;
        final result = validateNaturalLanguage(longPara);
        expect(result.fixes.any((f) => f.type == 'V-01'), isTrue);
      });
    });
  });

  // ═════════════════════════════════════════════════════════════
  // C123 任务4 / R-009：V-01/V-02 由「仅记录」升级为「真降级 cleaned」。
  // 判据精度原则：只拦确定性违规，宁漏勿伤。
  //   正例（拦）→ cleaned 不含原文、含 R-009 合规降级文案；
  //   反例（不拦）→ cleaned 与输入逐字节一致、无对应 fix。
  // ═════════════════════════════════════════════════════════════
  group('R-009 V-01 代写段真降级', () {
    const blocked = <String>[
      '夜风穿过空荡的长廊，他缓缓抬起头，指节因用力而泛白，眼中闪过一丝不易察觉的决绝，往事如潮水般涌上心头，他知道这一次再也没有回头的余地，脚下的青砖在月光下泛着冷冽的光。',
      '她缓缓推开那扇斑驳的木门，尘土在斜射的光柱里飞舞，多年未见的老宅在那一刻仿佛重新活了过来，墙角的蛛网轻轻晃动，像是在替这个沉默多年的屋子迎接迟来的主人，院外的风声低低地掠过。',
      '雨还在下，街道被霓虹染成一片流动的暗红，行人撑起伞，像一朵朵沉默移动的蘑菇，没人知道今夜会发生什么，只有路灯把每个人的影子拉得很长很长，像是走不到尽头，雨丝斜斜地打在橱窗上。',
      '他笑了笑，把那封信仔细折好塞进信封，又最后看了一眼窗外，终于做出了那个决定，尽管他知道这个决定会改变一切，而他已经没有勇气再去反悔，只能任凭心跳在胸口擂鼓，窗外的天色一点点暗了下去。',
      '月光洒在开阔的湖面，波光粼粼，远处传来若有若无的琴声，宁静得像一幅被时间遗忘的油画，岸边的芦苇随风轻摇，把整个夜晚的心事都揉进了水波里，没有一个人说话，远处的灯火一盏盏亮起。',
    ];
    // 反例：正常教练反馈（短点评 + 一段 >80 字但满是教练元话语的长点评）。
    const preserved = <String>[
      '这句的镜头感不错，光影交代得很清楚。',
      '第二段的人物动机可以再明确一点，读者目前还看不出他为什么生气。',
      '这里的对话节奏偏快，两句之间缺一个动作缓冲。',
      '这个比喻很贴切，把紧张感具象化了。',
      '上一句的环境描写帮读者进入了场景，可以再多给一句他的反应。',
      '这一段的人物动机可以再明确一点，读者目前还看不出他为什么生气，因为他的反应来得太突兀，情绪转变缺少铺垫，这里需要补上一个他内心动摇的细节，这样读者才会真正相信这个决定。',
    ];

    test('正例：长段代写 → 从 cleaned 降级为「邀请学员自己写」', () {
      for (final para in blocked) {
        final r = validateNaturalLanguage(para);
        expect(r.cleaned.contains(para), isFalse, reason: '代写段未被摘除：$para');
        expect(r.cleaned, contains('我不替你落笔'), reason: '缺 R-009 降级文案：$para');
        expect(
          r.fixes.any((f) => f.type == 'V-01'),
          isTrue,
          reason: '未记 V-01 fix：$para',
        );
      }
    });

    test('反例：正常教练反馈 → cleaned 逐字节保留、无 V-01', () {
      for (final para in preserved) {
        final r = validateNaturalLanguage(para);
        expect(r.cleaned, para, reason: '误伤正常反馈：$para');
        expect(
          r.fixes.any((f) => f.type == 'V-01'),
          isFalse,
          reason: '误报 V-01：$para',
        );
      }
    });
  });

  group('R-009 V-02 判决句真降级', () {
    const blocked = <String>[
      '你应该把整个故事重写。',
      '整篇都很差，节奏拖沓，没有一句能看。',
      '你必须删掉这一章，它完全是多余的。',
      '你的小说彻底失败了，通篇平庸。',
      '整体而言这一章不知所云，毫无逻辑。',
    ];
    const preserved = <String>[
      '这句的镜头感不错。',
      '这一段的人物动机可以再明确一点。',
      '这个比喻贴切，但下一句的转折有点突兀。',
      '如果把第二句的环境描写再压缩一点，节奏会更紧。',
      '你这句的情绪铺垫到位了，只是结尾收得太急。',
      '比如「你应该这样写」只是一个教学例句，不代表对你的判断。',
    ];

    test('正例：指令判决 / 整篇定性 → 整句降级为「邀请一起定位」', () {
      for (final sentence in blocked) {
        final r = validateNaturalLanguage(sentence);
        expect(
          r.cleaned.contains(sentence),
          isFalse,
          reason: '判决句未被降级：$sentence',
        );
        expect(r.cleaned, contains('我先不下'), reason: '缺 R-009 降级文案：$sentence');
        expect(
          r.fixes.any((f) => f.type == 'V-02'),
          isTrue,
          reason: '未记 V-02 fix：$sentence',
        );
      }
    });

    test('反例：具体反馈与引号教学例句 → cleaned 逐字节保留、无 V-02', () {
      for (final sentence in preserved) {
        final r = validateNaturalLanguage(sentence);
        expect(r.cleaned, sentence, reason: '误伤正常反馈：$sentence');
        expect(
          r.fixes.any((f) => f.type == 'V-02'),
          isFalse,
          reason: '误报 V-02：$sentence',
        );
      }
    });
  });

  // ── P0'-3（2026-09-30）：V-03 由「抹成空壳」改为「回填名称」──────
  //
  // 病因：`_applyCodeReplacement` 把 LLM 输出里的 P0xx 抹成 【症候】，但全仓
  // 没有反向渲染器 ⇒ 用户直接读到占位符（取证实测 68 处）。
  // 变异验证：把 `_applyCodeReplacement` 改回 `return '【症候】'`（无条件抹除）
  //   → 下面第 1、2 条必红（残留空壳 + 未回填名字）。
  group('P0\'-3 V-03 编号回填（全注册表覆盖）', () {
    test('全部注册症候 ID → 回填为名字：无【症候】空壳、无编号泄漏', () {
      final bad = <String>[];
      for (final id in kSyndromeIds) {
        final r = validateNaturalLanguage('问题 $id 出现在这里');
        final name = syndromeNameOf(id);
        if (r.cleaned.contains('【症候】')) bad.add('$id 仍残留【症候】空壳');
        if (name == null || !r.cleaned.contains(name)) {
          bad.add('$id 未回填为「$name」');
        }
        if (r.cleaned.contains(id)) bad.add('$id 编号原文泄漏未清除');
      }
      expect(bad, isEmpty, reason: '未正确回填的症候编号:\n${bad.join('\n')}');
    });

    test('全部动作编号 → 回填为动作名', () {
      final bad = <String>[];
      for (final entry in kActionShortNames.entries) {
        final r = validateNaturalLanguage('动作 ${entry.key} 出现在这里');
        if (r.cleaned.contains('【动作】')) {
          bad.add('${entry.key} 仍残留【动作】空壳');
        }
        if (!r.cleaned.contains(entry.value)) {
          bad.add('${entry.key} 未回填为「${entry.value}」');
        }
        if (r.cleaned.contains(entry.key)) bad.add('${entry.key} 编号原文泄漏');
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    test('覆盖度自检：注册表/动作表非空（防循环空过造成假绿）', () {
      expect(kSyndromeIds.length, greaterThanOrEqualTo(30));
      expect(kActionShortNames.length, greaterThanOrEqualTo(10));
    });

    test('当前编号优先于 legacy 归一：P001 不得被写成 P002 的名', () {
      // mergeMap['P001'] = 'P002' 是**历史 ghost**语义（世界观膨胀）；
      // 当前 P001 是「情绪标签化」。回填必须精确匹配优先，否则名会错。
      final r = validateNaturalLanguage('这里有 P001 的问题');
      expect(r.cleaned, contains('情绪标签化'));
      expect(r.cleaned.contains('信息倾泻症'), isFalse);
    });

    test('LLM 偶发旧编号 → 经 mergeMap 回填吸收方名字', () {
      final r = validateNaturalLanguage('这里有 P048 的问题'); // 语法层语病症 → P018
      expect(r.cleaned.contains('P048'), isFalse);
      expect(r.cleaned, contains('重复用词/基础语病'));
    });

    test('越界编号 → 退化为占位符（底线：编号不外泄）', () {
      final r = validateNaturalLanguage('这里有 P099 的问题');
      expect(r.cleaned.contains('P099'), isFalse);
      expect(r.cleaned, contains('【症候】'));
    });
  });

  group('syndromeNameOf（P0\'-3 新增解析器）', () {
    test('精确匹配优先、legacy 归一兜底、未知返回 null', () {
      expect(syndromeNameOf('P002'), '信息倾泻症');
      expect(syndromeNameOf('P048'), '重复用词/基础语病'); // legacy → P018
      expect(syndromeNameOf('P001'), '情绪标签化'); // 当前语义，不被 ghost 归一改写
      expect(syndromeNameOf('P099'), isNull);
      expect(syndromeNameOf(''), isNull);
      expect(syndromeNameOf(null), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // ADR-C105 A9：技法编号 `T0xx` 纳入 V-03 回填面
  //
  // 修复前 `kSyndromeCodeRe`/`kActionCodeRe` 只覆盖 P0xx/A0xx，`T0\d{2}`
  // 全仓 0 命中 ⇒ 模型回显的裸技法编号**原样落到学员可见文本**。
  // 泄漏产生点（实测）：`technique_kb_content.dart:35-40` 的索引表首列，
  // 以及 `technique_knowledge_base.dart:265` 的斜杠组分支
  //（P004/P005/P006/P007/P009 → `T017/T018/T022`，**无技法名**）。
  // ═════════════════════════════════════════════════════════════

  group('ADR-C105 A9 V-03 技法编号回填（T0xx）', () {
    test('全部注册技法编号 → 回填为技法名：无【技法】空壳、无编号泄漏', () {
      final bad = <String>[];
      for (final entry in kTechniqueShortNames.entries) {
        final r = validateNaturalLanguage('这一段可以用 ${entry.key} 来处理');
        if (r.cleaned.contains('【技法】')) {
          bad.add('${entry.key} 仍残留【技法】空壳');
        }
        if (!r.cleaned.contains(entry.value)) {
          bad.add('${entry.key} 未回填为「${entry.value}」');
        }
        if (r.cleaned.contains(entry.key)) bad.add('${entry.key} 编号原文泄漏');
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    test('★斜杠组原样输出（真实触发形态）→ T017/T018/T022 逐个回填', () {
      final r = validateNaturalLanguage('备选技法：T017/T018/T022');
      expect(r.cleaned.contains('T017'), isFalse);
      expect(r.cleaned.contains('T018'), isFalse);
      expect(r.cleaned.contains('T022'), isFalse);
      expect(r.cleaned, contains('悬念伏笔法'));
      expect(r.cleaned, contains('欲扬先抑法'));
      expect(r.cleaned, contains('场景概述交替法'));
    });

    test('越界技法编号 → 退化为占位符（底线：编号不外泄）', () {
      final r = validateNaturalLanguage('这里提到 T099 的写法');
      expect(r.cleaned.contains('T099'), isFalse);
      expect(r.cleaned, contains('【技法】'));
    });

    test('V-03 属阻断型 ⇒ 技法编号命中时 valid=false（与症候/动作同待遇）', () {
      final r = validateNaturalLanguage('备选技法：T017');
      expect(r.valid, isFalse);
      expect(r.fixes.any((f) => f.type == 'V-03'), isTrue);
    });

    test('覆盖度自检：技法短名表非空（防循环空过造成假绿）', () {
      expect(kTechniqueShortNames.length, greaterThanOrEqualTo(20));
      expect(
        kTechniqueShortNames.keys.every(
          (k) => RegExp(r'^T0\d{2}$').hasMatch(k),
        ),
        isTrue,
        reason: '本组用例的扫描面依赖键格式恒为 T0xx；格式一变则本组会静默空过',
      );
    });
  });
}
