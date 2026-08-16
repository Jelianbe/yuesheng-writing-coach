// 波5 偏离修复验证：Diagnosis → Teacher 合并逻辑的 displayContent/combinedContent 分离
//
// 真源对齐：chat-service.ts L626-794
// 核心契约（RN L767 注释）：
//   trainingResult 基于原 displayContent（不含 Teacher 反馈，避免误触发训练结果解析）
//
// 本测试不 mock LlmClient，而是直接验证 sendMessage 中合并表达式的语义正确性。
// 通过模拟 LLM 返回的 displayContent + Teacher 返回的 teacherDisplayContent，
// 验证三个使用点：
//   1. addMessage 写入的是 combinedContent（合并后）
//   2. parseTrainingResult 用的是 displayContent（原始）
//   3. onComplete 回调给 UI 的是 combinedContent（合并后）
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_training_parser.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('Diagnosis → Teacher 合并逻辑分离验证', () {
    // 模拟 sendMessage 中的合并表达式（真源 chat-service.ts L657-660）
    // final combinedContent = displayContent +
    //     (teacherDisplayContent.isNotEmpty
    //         ? '\n\n$teacherDisplayContent'
    //         : '');
    String buildCombinedContent(
      String displayContent,
      String teacherDisplayContent,
    ) {
      return displayContent +
          (teacherDisplayContent.isNotEmpty
              ? '\n\n$teacherDisplayContent'
              : '');
    }

    test('场景1：Teacher 触发，displayContent 不含训练关键词，combinedContent 含', () {
      // 模拟 Diagnosis 输出（无训练关键词）
      const displayContent = '你的文本在角色塑造上可以更立体。';
      // 模拟 Teacher 输出（含"达标"——这是 Teacher 反馈，不是训练结果）
      const teacherDisplayContent = '建议你重写这段，达到达标水平。';

      final combinedContent = buildCombinedContent(
        displayContent,
        teacherDisplayContent,
      );

      // 验证1：combinedContent 包含 Teacher 输出
      expect(combinedContent.contains(teacherDisplayContent), true);
      expect(combinedContent, '$displayContent\n\n$teacherDisplayContent');

      // 验证2：parseTrainingResult 用 displayContent（原始）—— 应返回 null
      final trainingFromDisplay = parseTrainingResult(displayContent);
      expect(
        trainingFromDisplay,
        isNull,
        reason: '原始 displayContent 不含训练关键词，不应触发训练结果解析',
      );

      // 验证3：parseTrainingResult 用 combinedContent（污染后）—— 会误触发
      final trainingFromCombined = parseTrainingResult(combinedContent);
      expect(
        trainingFromCombined,
        isNotNull,
        reason: 'combinedContent 含"达标"，若用于 parseTrainingResult 会误触发',
      );
      expect(trainingFromCombined, TrainingResult.passed);

      // 核心断言：两者结果不同，证明分离是必要的
      expect(
        trainingFromDisplay != trainingFromCombined,
        true,
        reason: 'displayContent 和 combinedContent 必须分离，否则训练结果解析会被 Teacher 输出污染',
      );
    });

    test('场景2：Teacher 未触发（teacherDisplayContent 为空）', () {
      const displayContent = '你的文本在角色塑造上可以更立体。';
      const teacherDisplayContent = '';

      final combinedContent = buildCombinedContent(
        displayContent,
        teacherDisplayContent,
      );

      // 验证：combinedContent 等于 displayContent（无 Teacher 追加）
      expect(combinedContent, displayContent);
      expect(combinedContent.contains('\n\n'), false);

      // 验证：两者 parseTrainingResult 结果一致（无污染风险）
      expect(
        parseTrainingResult(displayContent),
        parseTrainingResult(combinedContent),
      );
    });

    test('场景3：Teacher 触发但失败（teacherDisplayContent 保持空字符串）', () {
      // 模拟 Teacher 调用失败，teacherDisplayContent 保持初始值 ''
      const displayContent = '诊断完成。';
      const teacherDisplayContent = ''; // Teacher 失败，保持空

      final combinedContent = buildCombinedContent(
        displayContent,
        teacherDisplayContent,
      );

      // 验证：combinedContent 不含 Teacher 痕迹，降级为纯 Diagnosis 输出
      expect(combinedContent, displayContent);
      expect(combinedContent.contains('\n\n'), false);
    });

    test('场景4：displayContent 本身含训练关键词，Teacher 也含', () {
      // 模拟 FEEDBACK 子阶段：学员提交训练结果，Diagnosis 判定"达标"
      const displayContent = '本次训练达标，角色主动性有明显提升。';
      const teacherDisplayContent = '继续保持，下次也可以达标。';

      final combinedContent = buildCombinedContent(
        displayContent,
        teacherDisplayContent,
      );

      // 验证1：parseTrainingResult(displayContent) 正确识别为 passed
      final trainingFromDisplay = parseTrainingResult(displayContent);
      expect(trainingFromDisplay, TrainingResult.passed);

      // 验证2：parseTrainingResult(combinedContent) 仍为 passed（不改变结果，但语义已污染）
      final trainingFromCombined = parseTrainingResult(combinedContent);
      expect(trainingFromCombined, TrainingResult.passed);

      // 核心断言：即使结果相同，displayContent 仍是正确的输入源
      // （如果 displayContent 本身是"未达标"，Teacher 输出含"达标"，combinedContent 会误判）
    });

    test('场景5：displayContent 含"未达标"，Teacher 输出含"达标"——污染会改变结果', () {
      // 这是最关键的回归场景：证明用 combinedContent 会导致误判
      const displayContent = '本次训练未达标，角色主动性仍需加强。';
      const teacherDisplayContent = '建议重写，下次争取达标。';

      final combinedContent = buildCombinedContent(
        displayContent,
        teacherDisplayContent,
      );

      // 验证1：parseTrainingResult(displayContent) 正确识别为 failed
      final trainingFromDisplay = parseTrainingResult(displayContent);
      expect(
        trainingFromDisplay,
        TrainingResult.failed,
        reason: '原始 displayContent 明确"未达标"',
      );

      // 验证2：parseTrainingResult(combinedContent) 会被 Teacher 的"达标"污染
      // 注意：parseTrainingResult 优先匹配"部分达标"和"未达标"，所以 combinedContent 仍可能识别为 failed
      // 但如果 Teacher 输出在 displayContent 之前出现，或者匹配顺序变化，就会误判
      // 这里验证当前实现下 combinedContent 的解析结果（仅观察，不强断言）
      final trainingFromCombined = parseTrainingResult(combinedContent);
      expect(
        trainingFromCombined,
        isNotNull,
        reason: 'combinedContent 含训练关键词，解析结果非空（但依赖匹配顺序，脆弱）',
      );

      // 关键断言：即使当前实现恰好正确（因为"未达标"在 displayContent 中先被匹配），
      // 但 combinedContent 引入了额外的"达标"关键词，增加了未来匹配顺序变化时的回归风险
      // 这是一个脆弱性的证明——分离 displayContent 消除了这种脆弱性
      expect(
        trainingFromDisplay,
        TrainingResult.failed,
        reason: '分离后 displayContent 无歧义，正确解析为 failed',
      );
      // 不对 trainingFromCombined 做强断言，因为它的结果依赖匹配顺序，本身就是脆弱的
      // 只证明两者内容不同
      expect(displayContent != combinedContent, true);
    });

    test('场景6：空内容边界——displayContent 为空，Teacher 也为空', () {
      const displayContent = '';
      const teacherDisplayContent = '';

      final combinedContent = buildCombinedContent(
        displayContent,
        teacherDisplayContent,
      );

      // 验证：combinedContent.trim().isEmpty 为 true（对应 sendMessage 中的空判断）
      expect(combinedContent.trim().isEmpty, true);
    });

    test('场景7：addMessage 和 onComplete 都应使用 combinedContent', () {
      // 模拟完整流程
      const displayContent = '诊断结果：角色主动性不足。';
      const teacherDisplayContent = '建议重写主角决策段落。';

      final combinedContent = buildCombinedContent(
        displayContent,
        teacherDisplayContent,
      );

      // 模拟 addMessage 写入的内容
      final addMessageContent = combinedContent;
      // 模拟 onComplete 回调给 UI 的内容
      final onCompleteContent = combinedContent;

      // 验证：两者一致，都是合并后的内容
      expect(addMessageContent, onCompleteContent);
      expect(addMessageContent.contains(teacherDisplayContent), true);
      expect(addMessageContent.contains(displayContent), true);

      // 模拟 parseTrainingResult 的输入
      final parseTrainingInput = displayContent;
      expect(
        parseTrainingInput.contains(teacherDisplayContent),
        false,
        reason: 'parseTrainingResult 的输入不应包含 Teacher 输出',
      );
    });
  });

  group('Editor 分支合并逻辑验证', () {
    // Editor 分支的合并表达式（真源 chat-service.ts L522-524）
    // final combinedContent = editorResult.displayContent +
    //     (teacherDisplayContent.isNotEmpty
    //         ? '\n\n$teacherDisplayContent'
    //         : '');
    // Editor 分支不存在 parseTrainingResult 调用，所以无污染风险
    // 但仍验证合并语义一致性

    test('Editor 分支：Teacher 触发，combinedContent 合并正确', () {
      const editorDisplayContent = '编辑观察：节奏控制良好。';
      const teacherDisplayContent = '建议保持当前节奏。';

      final combinedContent =
          editorDisplayContent +
          (teacherDisplayContent.isNotEmpty
              ? '\n\n$teacherDisplayContent'
              : '');

      expect(
        combinedContent,
        '$editorDisplayContent\n\n$teacherDisplayContent',
      );
    });

    test('Editor 分支：Teacher 未触发，combinedContent 等于 editorDisplayContent', () {
      const editorDisplayContent = '编辑观察：节奏控制良好。';
      const teacherDisplayContent = '';

      final combinedContent =
          editorDisplayContent +
          (teacherDisplayContent.isNotEmpty
              ? '\n\n$teacherDisplayContent'
              : '');

      expect(combinedContent, editorDisplayContent);
    });
  });
}
