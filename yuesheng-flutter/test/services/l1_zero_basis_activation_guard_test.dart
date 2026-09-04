// ─────────────────────────────────────────────────────────────
// ADR-C72 §3 护栏：零基础首次识别的最小激活块（N-1 裁决）
//
// 防「唯一例外」被后续批次删掉或改残：三处交叉引用逐处计数断言，
// 激活块判据关键锚文本存在性断言（V4.8：逐处判，别求和）。
// ─────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/skill_registry.dart';

void main() {
  final content = skillRegistry['teaching-strategy']!.content;

  group('ADR-C72 最小激活块护栏', () {
    test('撞车裁决第三行存在且判据完整', () {
      expect(content, contains('疑似零基础学员首次出现'));
      expect(content, contains('**仍附最小激活块**'));
      // 激活字段的精确写法（含引号形态）——模型照此填 JSON
      expect(content, contains('suggested_beginner_level: "N0_ENGAGE"'));
      expect(content, contains('激活零基础路径'));
      expect(content, contains('系统激活信号的信封'));
      // 最小块的约束：syndromes 必空
      expect(content, contains('`syndromes` 必为空'));
    });

    test('三处「唯一例外」交叉引用逐处齐备（§7.3 / §3.9 不附加 / 第三行）', () {
      // V4.8：计数断言，多一处少一处都红
      expect('唯一例外'.allMatches(content).length, 3);
      expect(content, contains('唯一例外：首次识别零基础学员时，按 §3.9 撞车裁决第三行输出最小激活块'));
      expect(content, contains('唯一例外见下方撞车裁决第三行——首次识别零基础学员的最小激活块'));
    });

    test('例外不放松 N0 铁律与「不附加」清单本体', () {
      // 第三行必须显式保留 N0 约束，防止例外被泛化为「从零构建可诊断」
      expect(content, contains('自然语言部分照常按 N0 铁律：不诊断、不评判、不给技法提示'));
      // 「不附加」清单的从零构建条目仍在（只是注明例外）
      expect(content, contains('从零构建引导模式（7.3，用户还没有可诊断的内容；唯一例外'));
    });
  });
}
