// svc_copy_test — L-SVC 层单一真源（R-027 任务 A）
//
// 锚定：
//   1. kOperationFailed 模板形态与「重试」统一收尾（无「再试」变体）；
//   2. 各迁移文案与原服务层硬编码逐字一致（回归不冻结文案本身，
//      但单一真源必须自证产出形态正确）；
//   3. AppError.toUserMessage 按 code 映射且不外露内部 message。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/svc_copy.dart';
import 'package:writingcoach/services/app_error.dart';

void main() {
  group('kOperationFailed', () {
    test(r'无 next：$action失败，请稍后重试', () {
      expect(kOperationFailed('加载'), '加载失败，请稍后重试');
    });

    test('有 next：追加句原样拼接', () {
      expect(kOperationFailed('保存', next: '（请到设置页检查）'), '保存失败，请稍后重试（请到设置页检查）');
    });

    test('统一「重试」，不产出「再试」', () {
      expect(kOperationFailed('操作'), isNot(contains('再试')));
    });
  });

  group('LLM 错误码文案', () {
    test('timeout / server 带参数逐字形态', () {
      expect(kLlmTimeoutMessage(60), '请求超时（60秒无响应），请稍后重试');
      expect(kLlmServerMessage(503), '服务端异常（HTTP 503），请稍后重试');
    });

    test('rateLimited 统一「重试」（原 llm_error_codes 误写「再试」）', () {
      expect(kLlmRateLimitedMessage, '请求过于频繁，请稍后重试');
      expect(kLlmRateLimitedMessage, isNot(contains('再试')));
    });
  });

  group('熔断开路 / 流式超时', () {
    test('熔断提示带秒数', () {
      expect(kCircuitOpenMessage(30), '服务暂时不可用（连续失败熔断），30 秒后自动恢复');
    });

    test('两段超时文案', () {
      expect(kStreamIdleInterruptMessage(60), '模型响应中断（超过 60 秒未收到新内容）');
      expect(kStreamConnectTimeoutMessage(30), '模型响应超时（超过 30 秒未返回首个字符）');
    });
  });

  group('兜底 / 占位文案', () {
    test('编辑观察兜底逐字不变', () {
      expect(kEditorObservationFailed, '审稿通过，但生成编辑观察失败，请稍后重试');
    });

    test('会话缺失提示逐字不变', () {
      expect(kSessionMissingReopen, '会话不存在或已被删除，请重新打开教练面板');
    });

    test('空输出占位按保存物分型', () {
      expect(
        kEmptyContentSavedNotice(syndromeCount: 1),
        '诊断数据已保存（1 条症候），但这次教练没有附上文字点评——通常是网络或模型临时故障。',
      );
      expect(
        kEmptyContentSavedNotice(entityCount: 2),
        '大纲实体已保存（2 条），但这次教练没有附上文字点评——通常是网络或模型临时故障。',
      );
    });

    test('报告尾逐字不变', () {
      expect(kReportFooter, '✨ 继续加油，坚持写作！');
    });
  });

  group('AppError.toUserMessage', () {
    test('可重试族走 svc_copy 真源', () {
      expect(
        const AppError(AppErrorCode.network, '内部详情：socket 104').toUserMessage(),
        kLlmNetworkMessage,
      );
      expect(
        const AppError(AppErrorCode.rateLimited, 'x').toUserMessage(),
        kLlmRateLimitedMessage,
      );
      expect(
        const AppError(AppErrorCode.timeout, 'x').toUserMessage(),
        kOperationFailed('操作'),
      );
    });

    test('不外露内部 message', () {
      const err = AppError(AppErrorCode.internal, 'LeakingStackTrace: #0 main');
      expect(err.toUserMessage(), isNot(contains('LeakingStackTrace')));
    });

    test('取消为预期行为 → 空串', () {
      expect(
        const AppError(AppErrorCode.cancelled, '用户取消').toUserMessage(),
        '',
      );
    });
  });
}
