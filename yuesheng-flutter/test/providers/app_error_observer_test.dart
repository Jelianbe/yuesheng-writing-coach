import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/providers/app_error_observer.dart';
import 'package:writingcoach/services/app_error.dart';

void main() {
  late List<Map<String, Object?>> calls;

  void Function({
    required String level,
    required String category,
    required String message,
    String? stack,
    Map<String, dynamic>? context,
  })
  spy() {
    return ({
      required String level,
      required String category,
      required String message,
      String? stack,
      Map<String, dynamic>? context,
    }) {
      calls.add({
        'level': level,
        'category': category,
        'message': message,
        'stack': stack,
        'context': context,
      });
    };
  }

  setUp(() => calls = []);

  group('AppErrorObserver（provider 失败全局拦截）', () {
    test('providerDidFail → 记录到全局（含 provider 名）', () {
      final observer = AppErrorObserver(onError: spy());
      final container = ProviderContainer();

      observer.providerDidFail(
        StateProvider<int>((ref) => 0),
        StateError('boom'),
        StackTrace.current,
        container,
      );

      expect(calls, hasLength(1));
      expect(calls[0]['level'], 'error');
      expect(calls[0]['category'], 'general');
      expect((calls[0]['message']! as String), contains('StateProvider'));
      expect(calls[0]['stack'], isNotNull);
      expect(calls[0]['context'], isEmpty);
      container.dispose();
    });

    test('AppError → context 提取 appErrorCode', () {
      final observer = AppErrorObserver(onError: spy());
      final container = ProviderContainer();

      observer.providerDidFail(
        StateProvider<int>((ref) => 0),
        const AppError(AppErrorCode.database, '迁移失败'),
        StackTrace.current,
        container,
      );

      expect(calls, hasLength(1));
      final context = calls[0]['context']! as Map<String, dynamic>;
      expect(context['appErrorCode'], 'database');
      container.dispose();
    });

    test('内部 provider 前缀（errorLog）失败不记录（防递归）', () {
      final observer = AppErrorObserver(onError: spy());
      final container = ProviderContainer();

      observer.providerDidFail(
        StateProvider<int>((ref) => 0),
        StateError('log 失败'),
        StackTrace.current,
        container,
      );
      expect(calls, hasLength(1)); // 非 errorLog 前缀，正常记录

      final errorLogProvider = Provider<String>(
        (ref) => throw StateError('x'),
        name: 'errorLogProvider',
      );
      observer.providerDidFail(
        errorLogProvider,
        StateError('log 失败'),
        StackTrace.current,
        container,
      );
      expect(calls, hasLength(1)); // errorLog 前缀被跳过，未新增
      container.dispose();
    });
  });
}
