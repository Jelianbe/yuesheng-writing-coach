// ─────────────────────────────────────────────────────────────
// Repository 写操作统一留痕（CR-12）
//
// 背景：全仓 17 个 repository 中 13 个写路径完全没有 try/catch。
// PROBE-V5 实测异常会自然冒泡（既不被吞、也不损坏数据），所以真正缺失的
// 不是「异常被吃掉」，而是「失败不可归因」——DB 写失败时 error_logs 里
// 一条记录都没有，线上问题无从定位。
//
// 处置原则（对齐 R-028「每个函数都包 try/catch 属过度防御」）：
//   - 只包**写操作**（insert / update / delete / 事务）；
//   - 读操作不包：其失败由上层 provider 的 try/catch 处理，重复加壳只会
//     制造样板噪音、放大堆栈，且掩盖真实抛出点；
//   - 捕获后**必须 rethrow**：本包装只补留痕，不改变任何控制流与语义，
//     因此接入它不构成行为变更。
//
// 所有 repository 共用这一份实现，避免同形逻辑在多处复制后再次分歧
// （清单 P1-13 同源一致性）。
// ─────────────────────────────────────────────────────────────

import '../../services/error_handler.dart';

/// 执行 [body]，失败时落一条 error_logs 后**原样抛出**。
///
/// [repo] 仓库名（如 'chapter'），[op] 方法名（如 'createChapter'）。
/// [context] 只允许放**非内容**的定位信息（id、计数、状态值）；
/// 禁止传章节正文或用户文本，避免写作内容进入日志（R-029 脱敏）。
Future<T> guardRepoWrite<T>(
  String repo,
  String op,
  Future<T> Function() body, {
  Map<String, dynamic>? context,
}) async {
  try {
    return await body();
  } catch (e, st) {
    ErrorHandler.instance.captureError(
      level: 'error',
      category: 'database',
      message: '$repo.$op 写操作失败',
      context: <String, dynamic>{
        'repo': repo,
        'op': op,
        'error': '$e',
        ...?context,
      },
      stack: st.toString(),
    );
    rethrow;
  }
}
