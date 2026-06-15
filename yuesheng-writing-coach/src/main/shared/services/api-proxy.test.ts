import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ApiProxy } from '../../api-proxy';
import { ApiConfig } from '../../../shared/types/index';

// 测试专用配置 — 凭据从环境变量读取，避免扫描器误报
const TEST_CONFIG: ApiConfig = {
  apiKey: process.env.TEST_API_KEY ?? '',
  baseUrl: 'https://api.test.com/v1',
  modelName: 'test-model',
  temperature: 0.7,
  attitudeLevel: 'yuesheng',
  maxTokens: 8192,
};

function makeStreamResponse(chunks: string[]): Response {
  const encoder = new TextEncoder();
  const bytes = chunks.map((c) => encoder.encode(`data: ${c}\n\n`));
  const body = new ReadableStream({
    async start(controller) {
      for (const chunk of bytes) {
        controller.enqueue(chunk);
      }
      controller.close();
    },
  });
  return new Response(body, { status: 200 });
}

function makeTextResponse(status: number, body: string): Response {
  return new Response(body, { status });
}

describe('ApiProxy', () => {
  let proxy: ApiProxy;

  beforeEach(() => {
    vi.restoreAllMocks();
    proxy = new ApiProxy(TEST_CONFIG);
  });

  describe('chatStream - 流式 SSE 解析', () => {
    it('正确解析单个 data chunk', async () => {
      const response = makeStreamResponse([
        JSON.stringify({ choices: [{ delta: { content: '你好' } }] }),
        JSON.stringify({ choices: [{ delta: { content: '世界' } }] }),
        '[DONE]',
      ]);
      vi.spyOn(globalThis, 'fetch').mockResolvedValue(response);

      const chunks: string[] = [];
      for await (const chunk of proxy.chatStream([{ role: 'user', content: 'hi' }])) {
        chunks.push(chunk);
      }

      expect(chunks).toEqual(['你好', '世界']);
    });

    it('处理跨 chunk 的 SSE 行拆分', async () => {
      const encoder = new TextEncoder();
      const rawData = `data: ${JSON.stringify({ choices: [{ delta: { content: 'Hello' } }] })}\n\ndata: [DONE]\n\n`;
      const body = new ReadableStream({
        async start(controller) {
          // 分两次发送，模拟 TCP 分包
          controller.enqueue(encoder.encode(rawData.slice(0, 20)));
          controller.enqueue(encoder.encode(rawData.slice(20)));
          controller.close();
        },
      });
      vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(body, { status: 200 }));

      const chunks: string[] = [];
      for await (const chunk of proxy.chatStream([{ role: 'user', content: 'hi' }])) {
        chunks.push(chunk);
      }

      expect(chunks).toEqual(['Hello']);
    });

    it('跳过无 content 的 delta', async () => {
      const response = makeStreamResponse([
        JSON.stringify({ choices: [{ delta: {} }] }),
        JSON.stringify({ choices: [{ delta: { content: '有效' } }] }),
        '[DONE]',
      ]);
      vi.spyOn(globalThis, 'fetch').mockResolvedValue(response);

      const chunks: string[] = [];
      for await (const chunk of proxy.chatStream([{ role: 'user', content: 'hi' }])) {
        chunks.push(chunk);
      }

      expect(chunks).toEqual(['有效']);
    });

    it('静默跳过格式错误的 JSON chunk', async () => {
      const response = makeStreamResponse([
        'not json at all',
        JSON.stringify({ choices: [{ delta: { content: '修复' } }] }),
        '[DONE]',
      ]);
      vi.spyOn(globalThis, 'fetch').mockResolvedValue(response);

      const chunks: string[] = [];
      for await (const chunk of proxy.chatStream([{ role: 'user', content: 'hi' }])) {
        chunks.push(chunk);
      }

      expect(chunks).toEqual(['修复']);
    });

    it('跳过非 data: 开头的行', async () => {
      const encoder = new TextEncoder();
      const rawData = `data: ${JSON.stringify({ choices: [{ delta: { content: 'A' } }] })}\n\n:keepalive\n\ndata: [DONE]\n\n`;
      const body = new ReadableStream({
        async start(controller) {
          controller.enqueue(encoder.encode(rawData));
          controller.close();
        },
      });
      vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(body, { status: 200 }));

      const chunks: string[] = [];
      for await (const chunk of proxy.chatStream([{ role: 'user', content: 'hi' }])) {
        chunks.push(chunk);
      }

      expect(chunks).toEqual(['A']);
    });

    it('长时间流式响应中累积多个 token', async () => {
      const tokens = ['这是', '一个', '完整', '的', '句子'];
      const response = makeStreamResponse([
        ...tokens.map((t) => JSON.stringify({ choices: [{ delta: { content: t } }] })),
        '[DONE]',
      ]);
      vi.spyOn(globalThis, 'fetch').mockResolvedValue(response);

      const chunks: string[] = [];
      for await (const chunk of proxy.chatStream([{ role: 'user', content: 'hi' }])) {
        chunks.push(chunk);
      }

      expect(chunks).toEqual(tokens);
    });
  });

  describe('chatStream - HTTP 错误处理', () => {
    it('401 认证失败时抛出明确错误', async () => {
      vi.spyOn(globalThis, 'fetch').mockResolvedValue(
        makeTextResponse(401, 'Invalid API key'),
      );

      await expect(async () => {
        for await (const _ of proxy.chatStream([{ role: 'user', content: 'hi' }])) {
          // should not reach here
        }
      }).rejects.toThrow(/401/);
    });

    it('500 服务端错误时抛出明确错误', async () => {
      vi.spyOn(globalThis, 'fetch').mockResolvedValue(
        makeTextResponse(500, 'Internal error'),
      );

      await expect(async () => {
        for await (const _ of proxy.chatStream([{ role: 'user', content: 'hi' }])) {
        }
      }).rejects.toThrow(/500/);
    });

    it('网络错误时抛出', async () => {
      vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('net::ERR_CONNECTION_REFUSED'));

      await expect(async () => {
        for await (const _ of proxy.chatStream([{ role: 'user', content: 'hi' }])) {
        }
      }).rejects.toThrow('net::ERR_CONNECTION_REFUSED');
    });
  });

  describe('chatStream - AbortController', () => {
    it('AbortController 停止后抛出', async () => {
      const controller = new AbortController();
      vi.spyOn(globalThis, 'fetch').mockImplementation(async (_url, init) => {
        const signal = init?.signal as AbortSignal;
        return new Promise((_, reject) => {
          signal.addEventListener('abort', () => {
            reject(new DOMException('Aborted', 'AbortError'));
          });
        });
      });

      setTimeout(() => controller.abort(), 10);

      await expect(async () => {
        for await (const _ of proxy.chatStream([{ role: 'user', content: 'hi' }], controller.signal)) {
        }
      }).rejects.toThrow('Aborted');
    });
  });

  describe('chatStream - 响应体为空', () => {
    it('无 body 时抛出明确错误', async () => {
      vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 200 }));

      await expect(async () => {
        for await (const _ of proxy.chatStream([{ role: 'user', content: 'hi' }])) {
        }
      }).rejects.toThrow('No response body');
    });
  });

  describe('testConnection', () => {
    it('连接成功返回 success: true', async () => {
      vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 200 }));

      const result = await proxy.testConnection();

      expect(result.success).toBe(true);
      expect(result.error).toBeUndefined();
    });

    it('HTTP 401 返回带错误信息的失败', async () => {
      vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 401 }));

      const result = await proxy.testConnection();

      expect(result.success).toBe(false);
      expect(result.error).toContain('401');
    });

    it('网络错误返回带错误信息的失败', async () => {
      vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('ENOTFOUND'));

      const result = await proxy.testConnection();

      expect(result.success).toBe(false);
      expect(result.error).toBe('ENOTFOUND');
    });
  });

  describe('updateConfig', () => {
    it('更新配置后使用新 baseUrl', async () => {
      const newConfig = { ...TEST_CONFIG, baseUrl: 'https://new.api.com/v1' };
      proxy.updateConfig(newConfig);

      vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 200 }));
      await proxy.testConnection();

      expect(globalThis.fetch).toHaveBeenCalledWith(
        'https://new.api.com/v1/models',
        expect.anything(),
      );
    });
  });
});
