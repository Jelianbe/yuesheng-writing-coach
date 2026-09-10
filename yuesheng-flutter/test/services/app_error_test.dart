import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/app_error.dart';

void main() {
  group('AppError 基类', () {
    test('构造：code + message + 可选 cause', () {
      final cause = StateError('底层原因');
      final error = AppError(
        AppErrorCode.validation,
        '标题不能为空',
        cause: cause,
        stackTrace: StackTrace.current,
      );

      expect(error.code, AppErrorCode.validation);
      expect(error.message, '标题不能为空');
      expect(error.cause, cause);
      expect(error.stackTrace, isNotNull);
    });

    test('toString 带 code 前缀', () {
      const error = AppError(AppErrorCode.notFound, '会话不存在');
      expect(error.toString(), 'AppError(notFound): 会话不存在');
    });

    test('from：AppError 原样识别', () {
      const error = AppError(AppErrorCode.timeout, '超时');
      expect(AppError.from(error), same(error));
    });

    test('from：非 AppError 返回 null', () {
      expect(AppError.from(StateError('x')), isNull);
      expect(AppError.from('string error'), isNull);
    });
  });
}
