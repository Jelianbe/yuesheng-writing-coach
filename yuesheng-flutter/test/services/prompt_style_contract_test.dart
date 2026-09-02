import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/skill_registry.dart';

/// E.8(a) `SkillMeta.promptStyle` 档位契约护栏。
///
/// 目的：让「示例是不是格式」这一判断从"人读一遍才知道"变成机器可断言。
/// 直接服务 E.3 元规则第 6 条（示例话术非格式要求）。
///
/// 三层：
/// 1. 语料自检 —— 注册表塌了会让下面所有断言"两边皆空"而假绿
/// 2. 档位期望表 —— 37 条显式映射，改档必须同步改这里（防误改）
/// 3. 档位与正文自洽 —— 档位声明必须与正文实际形态对得上
///
/// 注意：本护栏只校验**元数据与正文是否自洽**，不校验档位判得"对不对"——
/// 后者是设计裁决，理由见 skill_registry.dart 的 PromptStyle 文档注释。
/// 若某条判定被推翻，改期望表 + 枚举注释，并在台账记一行。

/// 37 条档位期望表。改动任何一条的档位，必须同步改这里。
const Map<String, PromptStyle> kExpectedPromptStyle = {
  // ── strict（10）：输出契约或铁律级硬约束 ──
  'core-iron-triangle': PromptStyle.strict, // 铁三角「必须遵守」+ 元规则裁决顺序
  'core-product-identity': PromptStyle.strict, // 底线清单「永远不可违反」
  'phase-mapper': PromptStyle.strict, // 决策矩阵 + 迁移规则（系统强制）
  'teaching-strategy': PromptStyle.strict, // 教学策略铁律 / 隐性诊断铁律
  'validation-rules': PromptStyle.strict, // 输出验证清单（E.8 原文点名）
  'demonstration': PromptStyle.strict, // 有「展示格式」代码块 = 输出契约
  'timed-rewrite': PromptStyle.strict, // 四步计时流程 + 禁用行为
  'diagnosis-confirmation': PromptStyle.strict, // 确认步骤规则 + 严禁行为
  'training-evaluation-v2': PromptStyle.strict, // 评估输出格式 + 训练结果协议
  'syndrome-diagnosis-index': PromptStyle.strict, // JSON 输出格式 + 字段说明
  // ── guided（17）：示例话术 / 示例文本，示例仅参考 ──
  'scenario-rules': PromptStyle.guided, // 「怎么说由你自己组织…不是必须复述的台词」
  'teaching-modes': PromptStyle.guided, // 切换原则 + 映射，含示例话术
  'coaching-rhythm': PromptStyle.guided, // 五步节奏 + 大量话术示例
  'comparison': PromptStyle.guided, // 对比类型库 = A/B 示例素材
  'model-rewrite': PromptStyle.guided, // 范文是参考靶子，非格式
  'writer-psychology': PromptStyle.guided, // 话术示例 + 「不是诊断」
  'beginner-path': PromptStyle.guided, // N0 开场「根据状态选择」「三种选一种」
  'genre-guide': PromptStyle.guided, // 体裁调整指南；「必须」是描述体裁特征
  'narrative-design': PromptStyle.guided, // 五层递进提问框架 + 示例提问
  'outline-diagnosis': PromptStyle.guided, // 五步诊断法属方法论，非输出契约
  'plot-design': PromptStyle.guided, // 「引擎启动三问（必问，顺序不绑死）」
  'reader-awareness': PromptStyle.guided, // 诊断工具 + 示例提问
  'revision-methodology': PromptStyle.guided, // 层级模型 + 示例
  'writing-style': PromptStyle.guided, // 示例文本 + 引导
  'advanced-phases': PromptStyle.guided, // 「示例（不是模板——照抄…像读报表）」
  'feedback-cognition': PromptStyle.guided, // 「说什么（不是句式模板）」
  'gap-detector': PromptStyle.guided, // 「四、说什么（不是句式模板）」
  // ── free（10）：纯原则 / 底线 / 索引 ──
  'reply-voice': PromptStyle.free, // 必守规则 + 快速自检，无示例无格式
  'writing-anchors': PromptStyle.free, // 「认知参考，非诊断标准」
  'attitude-doubao': PromptStyle.free, // 态度档位：风格原则
  'attitude-yuesheng': PromptStyle.free,
  'attitude-sensei': PromptStyle.free,
  'coaching-actions-v2': PromptStyle.free, // 「不是话术库，不包含固定话术」
  'technique-library-index': PromptStyle.free, // 纯索引
  'text-surgery-v2': PromptStyle.free, // 「只规定底线，不规定流程」
  'training-loop-v2': PromptStyle.free, // 「不是必须执行的脚本」
  'training-templates-index': PromptStyle.free, // 纯索引
};

/// 分布期望。改动分布时提醒复核：是新增 skill，还是档位被误改。
const Map<PromptStyle, int> kExpectedDistribution = {
  PromptStyle.strict: 10,
  PromptStyle.guided: 17,
  PromptStyle.free: 10,
};

/// 示例证据：正文含示例类用词，或含引文话术行（行首 `> "` / `> “`）。
final RegExp _exampleWord = RegExp('示例|示范|例如|参考|比如|样例');
final RegExp _quoteLine = RegExp(r'^>\s*["“]', multiLine: true);

/// 反模板声明：正文自述示例不是格式。
const List<String> _antiTemplate = [
  '不是句式模板',
  '不是模板',
  '不是台词',
  '说法自定',
  '不照念',
  '由你自己组织',
  '由你组织',
  '怎么说由你',
  '不是必须复述',
  '语气参考',
];

/// 硬约束标记：输出契约或铁律级约束。
const List<String> _hardMarks = [
  '铁律',
  '底线',
  '不可违反',
  '系统强制',
  '输出格式',
  '展示格式',
  'JSON 字段说明',
  '必守',
  '必须遵守',
  '严禁',
  '禁止行为',
  '禁用行为',
  '输出要求',
  // validation-rules 的表述：「合规校验（V-01 ~ V-10，强制执行）」/
  // 「以下 10 条是硬性约束，违反任何一条都必须重写回复」
  '强制执行',
  '硬性约束',
  '必须重写',
];

/// 输出契约标记：free 档不得出现，否则说明它其实有格式要照做。
const List<String> _contractMarks = ['输出格式', '展示格式', 'JSON 字段说明', '输出契约'];

void main() {
  group('E.8(a) 一、语料自检（防空集假绿）', () {
    test('注册表规模与期望表一致', () {
      expect(
        skillRegistry.length,
        kExpectedPromptStyle.length,
        reason:
            '注册表 skill 数与档位期望表不一致——'
            '新增 skill 必须显式声明 promptStyle 并登记到本表',
      );
    });

    test('期望表的 id 与注册表完全对齐', () {
      final missing =
          skillRegistry.keys
              .where((id) => !kExpectedPromptStyle.containsKey(id))
              .toList()
            ..sort();
      final ghost =
          kExpectedPromptStyle.keys
              .where((id) => !skillRegistry.containsKey(id))
              .toList()
            ..sort();
      expect(missing, isEmpty, reason: '注册表里有 skill 未登记档位: $missing');
      expect(ghost, isEmpty, reason: '期望表里有注册表不存在的 id: $ghost');
    });

    test('正文语料非空', () {
      final total = skillRegistry.values.fold<int>(
        0,
        (a, s) => a + s.content.length,
      );
      expect(
        total,
        greaterThan(100000),
        reason:
            '语料总量异常（$total）——注册表或 content 加载失败时，'
            '下面的自洽断言会因"两边皆空"而假绿',
      );
    });
  });

  group('E.8(a) 二、档位期望表', () {
    for (final entry in kExpectedPromptStyle.entries) {
      test('${entry.key} → ${entry.value.name}', () {
        final skill = skillRegistry[entry.key];
        expect(skill, isNotNull, reason: '注册表中不存在 ${entry.key}');
        expect(
          skill!.meta.promptStyle,
          entry.value,
          reason:
              '${entry.key} 档位与期望表不一致。'
              '若是有意调整，请同步改 kExpectedPromptStyle 与枚举注释',
        );
      });
    }
  });

  group('E.8(a) 三、档位与正文自洽', () {
    for (final entry in kExpectedPromptStyle.entries) {
      final id = entry.key;
      final style = entry.value;
      final content = skillRegistry[id]!.content;

      switch (style) {
        case PromptStyle.guided:
          test('guided/$id 正文确有示例或反模板声明', () {
            final hasExample =
                _exampleWord.hasMatch(content) || _quoteLine.hasMatch(content);
            final hasAnti = _antiTemplate.any(content.contains);
            expect(
              hasExample || hasAnti,
              isTrue,
              reason:
                  '$id 标为 guided（示例仅参考），'
                  '但正文既无示例话术/示例文本，也无"示例不是格式"的自述。'
                  '要么档位判错，要么正文缺示例',
            );
          });
        case PromptStyle.strict:
          test('strict/$id 正文确有硬约束标记', () {
            final hits = _hardMarks.where(content.contains).toList();
            expect(
              hits,
              isNotEmpty,
              reason:
                  '$id 标为 strict（逐条执行的硬约束），'
                  '但正文未出现任何硬约束标记 $_hardMarks',
            );
          });
        case PromptStyle.free:
          test('free/$id 正文不含输出契约', () {
            final hits = _contractMarks.where(content.contains).toList();
            expect(
              hits,
              isEmpty,
              reason:
                  '$id 标为 free（无格式要照做），'
                  '但正文出现输出契约标记 $hits',
            );
          });
      }
    }
  });

  group('E.8(a) 四、分布自检', () {
    test('三档分布与期望一致', () {
      final actual = <PromptStyle, int>{
        for (final s in PromptStyle.values) s: 0,
      };
      for (final s in skillRegistry.values) {
        actual[s.meta.promptStyle] = actual[s.meta.promptStyle]! + 1;
      }
      expect(
        actual,
        kExpectedDistribution,
        reason:
            '档位分布变了。若是新增 skill 或有意调档，'
            '同步改 kExpectedDistribution 并复核 token 影响',
      );
    });

    test('必填性：PromptStyle 无默认值依赖', () {
      // 若哪天给 promptStyle 加了默认值，本测试仍绿——真正的防线是
      // SkillMeta 构造函数的 required。这里只断言三者都被用到，
      // 防止出现"某档位零使用"这类静默退化。
      for (final s in PromptStyle.values) {
        final n = skillRegistry.values
            .where((v) => v.meta.promptStyle == s)
            .length;
        expect(n, greaterThan(0), reason: '档位 ${s.name} 未被任何 skill 使用');
      }
    });
  });
}
