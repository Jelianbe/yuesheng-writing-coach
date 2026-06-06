/**
 * SSE (Server-Sent Events) 模拟工具
 *
 * 用于生成符合 OpenAI SSE 格式的流式响应
 * ApiProxy.chatStream() 使用 ReadableStream + TextDecoder 逐行解析
 * 格式：data: {"choices":[{"delta":{"content":"chunk"}}]}\n\n
 */

/**
 * 将文本转换为 SSE 分块数组（每块包含一个 data: 行）
 * @param text 要转换为 SSE 的完整文本
 * @param chunkSize 每个 SSE 块包含的字符数（默认 20）
 */
export function textToSSEChunks(text: string, chunkSize = 20): string[] {
  const chunks: string[] = [];
  for (let i = 0; i < text.length; i += chunkSize) {
    const content = text.slice(i, i + chunkSize);
    chunks.push(`data: ${JSON.stringify({ choices: [{ delta: { content } }] })}\n\n`);
  }
  // 终止标记
  chunks.push('data: [DONE]\n\n');
  return chunks;
}

/**
 * 创建一个 SSE 流 Response，用于 wire mock
 * @param text 要流式传输的完整文本
 * @param chunkSize 每个 SSE 块的字符数
 */
export function createSSEResponse(text: string, chunkSize = 20): Response {
  const encoder = new TextEncoder();
  const chunks = textToSSEChunks(text, chunkSize);

  let index = 0;
  const stream = new ReadableStream({
    pull(controller) {
      if (index < chunks.length) {
        controller.enqueue(encoder.encode(chunks[index]));
        index++;
      } else {
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: { 'Content-Type': 'text/event-stream' },
  });
}

/**
 * 诊断 Agent JSON 响应（不含 SSE 包装，直接输出纯 JSON）
 * 注意：Diagnosis Agent 的 callDiagnosisAgent() 使用 /\{[\s\S]*\}/ 正则提取 JSON
 * 所以必须放在首行，且不被 SSE 分块破坏
 */
export function createDiagnosisAgentSSE(diagnosisJson: object): string[] {
  const jsonStr = JSON.stringify(diagnosisJson, null, 2);
  // DiagnosisAgent 在 chatStream 后使用 /\{[\s\S]*\}/ 提取 JSON
  // 不需要 SSE 包装——ApiProxy 会解析 SSE，然后 callDiagnosisAgent 会用正则提取
  // 但 ApiProxy 期望 SSE 格式，所以仍然需要 data: {...} \n\n
  return textToSSEChunks(jsonStr, 50);
}

/**
 * 将 SSE chunks 数组拼合为一个 Response（整个响应一次性返回）
 * 用于测试不考虑流式分块的场景
 */
export function createSSEBufferedResponse(sseChunks: string[]): Response {
  const encoder = new TextEncoder();
  const allData = sseChunks.join('');

  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(encoder.encode(allData));
      controller.close();
    },
  });

  return new Response(stream, {
    headers: { 'Content-Type': 'text/event-stream' },
  });
}

/**
 * 非流式 JSON Response（用于 evaluateRewrite）
 */
export function createJSONResponse(data: object): Response {
  return new Response(JSON.stringify({
    choices: [{ message: { content: JSON.stringify(data) } }],
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
}
