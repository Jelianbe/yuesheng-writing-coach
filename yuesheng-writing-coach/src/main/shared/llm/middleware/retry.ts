/**
 * 指数退避重试工具
 *
 * 异步操作的通用重试机制，失败时以指数级延迟（baseDelay * 2^attempt）重试。
 */
/**
 * 带指数退避的异步重试
 *
 * @param fn - 要重试的异步操作
 * @param maxRetries - 最大重试次数（总尝试次数 = maxRetries + 1）
 * @param baseDelayMs - 基础延迟基数（毫秒）
 * @param context - 日志上下文标识
 * @returns 函数返回值
 * @throws 所有重试均失败时抛出最后一次错误
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  maxRetries: number,
  baseDelayMs: number,
  context: string,
): Promise<T> {
  let lastError: Error | undefined;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      if (attempt < maxRetries) {
        const delay = baseDelayMs * 2 ** attempt;
        console.warn(
          `[LLM] ${context} 第${attempt + 1}次尝试失败，${delay}ms 后重试: ${lastError.message}`,
        );
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }
  throw lastError!;
}
