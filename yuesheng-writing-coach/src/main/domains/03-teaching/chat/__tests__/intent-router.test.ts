/**
 * IntentRouter 单元测试
 *
 * 覆盖场景：
 * - 规则关键词命中（5 种意图各 1+ 测试）
 * - LLM 兜底分类
 * - 低置信度降级
 * - 空字符串 / 非常用词 fallback
 * - JSON 解析容错（markdown 包裹、无效 JSON）
 */

import { describe, it, expect, vi } from 'vitest';
import { IntentRouter } from '../intent-router';
import type { LLMProvider, StreamEvent } from '../../../../shared/llm/types';
import type { IntentType } from '../intent-router.types';

// ============================================================
// Helper: 创建 Mock LLMProvider
// ============================================================
function createMockLLMProvider(responseText?: string): LLMProvider {
  const response = responseText ?? '{"intent":"general_chat","confidence":1.0}';

  return {
    chatStream: vi.fn().mockImplementation(async function* (): AsyncGenerator<string> {
      yield response;
    }),
    chatStreamWithTools: vi.fn().mockImplementation(async function* (): AsyncGenerator<StreamEvent> {
      yield { type: 'text', content: 'mock' };
    }),
    evaluateRewrite: vi.fn().mockResolvedValue({
      improvement: '略有改善' as const,
      analysis: 'mock',
      suggestion: 'mock',
    }),
    testConnection: vi.fn().mockResolvedValue({ success: true }),
    getBaseUrl: vi.fn().mockReturnValue('https://mock.api.com'),
    getApiKey: vi.fn().mockReturnValue('mock-key'),
    updateConfig: vi.fn(),
  };
}

// ============================================================
// 测试套件
// ============================================================
describe('IntentRouter', () => {
  describe('规则关键词命中', () => {
    it('"帮我看看" → diagnose', async () => {
      const router = new IntentRouter(createMockLLMProvider());
      const result = await router.route('帮我看看这段对话写得怎么样', 'session-1');
      expect(result.intent).toBe('diagnose');
      expect(result.source).toBe('keyword');
      expect(result.confidence).toBe(1.0);
    });

    it('"分析一下" → diagnose', async () => {
      const router = new IntentRouter(createMockLLMProvider());
      const result = await router.route('分析一下我的开头', 'session-1');
      expect(result.intent).toBe('diagnose');
      expect(result.source).toBe('keyword');
    });

    it('"怎么" → learn', async () => {
      const router = new IntentRouter(createMockLLMProvider());
      const result = await router.route('怎么才能写好人物对话', 'session-1');
      expect(result.intent).toBe('learn');
      expect(result.source).toBe('keyword');
    });

    it('"教教" → learn', async () => {
      const router = new IntentRouter(createMockLLMProvider());
      const result = await router.route('教教我怎么写环境描写', 'session-1');
      expect(result.intent).toBe('learn');
    });

    it('"练习" → train', async () => {
      const router = new IntentRouter(createMockLLMProvider());
      const result = await router.route('我想练习对话描写', 'session-1');
      expect(result.intent).toBe('train');
      expect(result.source).toBe('keyword');
    });

    it('"写一个" → train', async () => {
      const router = new IntentRouter(createMockLLMProvider());
      const result = await router.route('写一个关于黄昏的描写片段', 'session-1');
      expect(result.intent).toBe('train');
    });

    it('"进步" → review', async () => {
      const router = new IntentRouter(createMockLLMProvider());
      const result = await router.route('我最近有进步吗', 'session-1');
      expect(result.intent).toBe('review');
      expect(result.source).toBe('keyword');
    });

    it('"复盘" → review', async () => {
      const router = new IntentRouter(createMockLLMProvider());
      const result = await router.route('帮我来一次复盘总结', 'session-1');
      expect(result.intent).toBe('review');
    });
  });

  describe('LLM 兜底分类', () => {
    it('无关键词时调用 LLM 并返回 learn', async () => {
      const mockProvider = createMockLLMProvider('{"intent":"learn","confidence":0.85}');
      const router = new IntentRouter(mockProvider);
      const result = await router.route('老师说人物要立体，但是我总写不立体', 'session-1');
      expect(result.intent).toBe('learn');
      expect(result.source).toBe('llm');
      expect(result.confidence).toBe(0.85);
      // 确认确实调用了 chatStream
      expect(mockProvider.chatStream).toHaveBeenCalledOnce();
    });

    it('无关键词时调用 LLM 并返回 diagnose', async () => {
      const mockProvider = createMockLLMProvider('{"intent":"diagnose","confidence":0.9}');
      const router = new IntentRouter(mockProvider);
      // 消息不含任何规则关键词，确保走 LLM 分类
      const result = await router.route('我写了一章但是感觉不对劲又说不出哪里有问题', 'session-1');
      expect(result.intent).toBe('diagnose');
      expect(result.source).toBe('llm');
    });
  });

  describe('低置信度降级', () => {
    it('LLM 返回 confidence 0.4 → 降级到 general_chat', async () => {
      const mockProvider = createMockLLMProvider('{"intent":"learn","confidence":0.4}');
      const router = new IntentRouter(mockProvider);
      const result = await router.route('写小说', 'session-1');
      expect(result.intent).toBe('general_chat');
      expect(result.source).toBe('llm');
      expect(result.confidence).toBe(0.4);
    });

    it('LLM 返回 confidence 0.6（等于阈值）→ 不降级', async () => {
      const mockProvider = createMockLLMProvider('{"intent":"learn","confidence":0.6}');
      const router = new IntentRouter(mockProvider);
      const result = await router.route('怎么写小说', 'session-1');
      expect(result.intent).toBe('learn');
    });
  });

  describe('fallback 行为', () => {
    it('空字符串 → general_chat', async () => {
      const router = new IntentRouter(createMockLLMProvider());
      const result = await router.route('', 'session-1');
      expect(result.intent).toBe('general_chat');
      expect(result.source).toBe('keyword');
    });

    it('仅空白字符串 → general_chat', async () => {
      const router = new IntentRouter(createMockLLMProvider());
      const result = await router.route('   ', 'session-1');
      expect(result.intent).toBe('general_chat');
    });

    it('非常用词闲聊 → general_chat', async () => {
      const mockProvider = createMockLLMProvider('{"intent":"general_chat","confidence":0.95}');
      const router = new IntentRouter(mockProvider);
      const result = await router.route('今天天气真好', 'session-1');
      expect(result.intent).toBe('general_chat');
    });

    it('问候语 → general_chat', async () => {
      const mockProvider = createMockLLMProvider('{"intent":"general_chat","confidence":0.95}');
      const router = new IntentRouter(mockProvider);
      const result = await router.route('你好，吃了吗', 'session-1');
      expect(result.intent).toBe('general_chat');
    });
  });

  describe('JSON 解析容错', () => {
    it('LLM 返回 markdown 包裹的 JSON', async () => {
      const mockProvider = createMockLLMProvider('```json\n{"intent":"train","confidence":0.9}\n```');
      const router = new IntentRouter(mockProvider);
      // 消息不含任何规则关键词，确保走 LLM 分类
      const result = await router.route('我想提升写作水平', 'session-1');
      expect(result.intent).toBe('train');
      expect(result.source).toBe('llm');
    });

    it('LLM 返回无效 JSON → general_chat', async () => {
      const mockProvider = createMockLLMProvider('我不是JSON，我是文本');
      const router = new IntentRouter(mockProvider);
      const result = await router.route('随便说点什么', 'session-1');
      expect(result.intent).toBe('general_chat');
      expect(result.confidence).toBe(0);
    });

    it('LLM 返回未知 intent 值 → general_chat', async () => {
      const mockProvider = createMockLLMProvider('{"intent":"unknown","confidence":0.9}');
      const router = new IntentRouter(mockProvider);
      const result = await router.route('随便说点什么', 'session-1');
      expect(result.intent).toBe('general_chat');
    });

    it('LLM 分类抛出异常 → 降级到 general_chat', async () => {
      const errorProvider: LLMProvider = {
        ...createMockLLMProvider(),
        chatStream: vi.fn().mockImplementation(async function* (): AsyncGenerator<string> {
          throw new Error('LLM connection failed');
          yield ''; // unreachable but needed for type
        }),
      };
      const router = new IntentRouter(errorProvider);
      const result = await router.route('随便说点什么', 'session-1');
      expect(result.intent).toBe('general_chat');
      expect(result.source).toBe('llm');
    });
  });

  describe('自定义关键词规则', () => {
    it('可以注入自定义规则覆盖默认规则', async () => {
      const customRules = [
        { intent: 'diagnose' as IntentType, keywords: ['特殊诊断词'] },
      ];
      const router = new IntentRouter(createMockLLMProvider(), customRules);
      const result = await router.route('特殊诊断词触发诊断', 'session-1');
      expect(result.intent).toBe('diagnose');
      expect(result.source).toBe('keyword');
    });
  });

  describe('updateLLMProvider', () => {
    it('调换 provider 后使用新的 provider 进行 LLM 分类', async () => {
      const oldProvider = createMockLLMProvider('{"intent":"train","confidence":0.9}');
      const newProvider = createMockLLMProvider('{"intent":"review","confidence":0.85}');
      const router = new IntentRouter(oldProvider);

      router.updateLLMProvider(newProvider);

      // 触发 LLM 分类（无关键词命中）
      const result = await router.route('无关键词的句子', 'session-1');
      expect(result.intent).toBe('review');
      expect(newProvider.chatStream).toHaveBeenCalled();
    });
  });
});
