/**
 * 聊天工具调用 — Tool Calling 定义、处理器、模型兼容性探测
 *
 * 从 chat-orchestrator.service.ts 提取，职责：
 * 1. 工具函数注册（readChapter 等）
 * 2. 工具定义列表（供 AI 模型识别）
 * 3. 模型 tool calling 兼容性探测
 */

import Database from 'better-sqlite3';
import { ApiProxy, type ChatCompletionTool } from '../../api-proxy';

// ─── 工具处理函数 ───

/** 工具处理函数映射表 */
export const toolHandlers: Record<string, (args: unknown, db: Database.Database) => Promise<unknown>> = {
  readChapter: async (args, db) => {
    const { chapterId, titleHint } = args as { chapterId?: string; titleHint?: string };

    if (chapterId) {
      const row = db.prepare('SELECT id, title, content FROM chapters WHERE id = ?').get(chapterId) as
        { id: string; title: string; content: string } | undefined;
      if (!row) return { found: false, error: '章节不存在' };
      return { found: true, title: row.title, content: row.content, wordCount: row.content?.length ?? 0 };
    }

    if (titleHint) {
      const row = db.prepare('SELECT id, title, content FROM chapters WHERE title LIKE ? ORDER BY updated_at DESC LIMIT 1').get(`%${titleHint}%`) as
        { id: string; title: string; content: string } | undefined;
      if (!row) return { found: false, error: '未找到匹配章节', titleHint };
      return { found: true, title: row.title, content: row.content, wordCount: row.content?.length ?? 0 };
    }

    const recent = db.prepare('SELECT id, title, length(content) as wordCount FROM chapters ORDER BY updated_at DESC LIMIT 5').all();
    return { found: false, recentChapters: recent, message: '未指定章节，以下是最近的 5 个章节' };
  },
};

// ─── 工具定义 ───

/** 工具定义列表（供 AI 模型识别） */
export const TOOLS_DEFINITIONS: ChatCompletionTool[] = [
  {
    type: 'function',
    function: {
      name: 'readChapter',
      description: '读取用户已保存的章节内容。当用户提到某个章节、作品、或要求看看/分析/读某段文字时调用。如果用户直接给出 /chapters/{uuid} 格式的引用，提取 chapterId；如果是自然语言描述（如"第六章""昨天写的"），用 titleHint 模糊匹配。',
      parameters: {
        type: 'object',
        properties: {
          chapterId: { type: 'string', description: '章节 UUID' },
          titleHint: { type: 'string', description: '章节标题关键词，用于模糊匹配' },
        },
      },
    },
  },
];

// ─── 模型兼容性 ───

/** 白名单模型 — 确定支持 tool calling */
const TOOL_WHITELIST = ['deepseek', 'gpt-', 'claude-'];
/** 黑名单模型 — 确定不支持 tool calling */
const TOOL_BLACKLIST = ['llama-2', 'mixtral-8x7b'];

/**
 * 探测模型是否支持 tool calling
 * 优先用白/黑名单快速判断，未知模型发探测请求
 */
export async function probeToolSupport(
  modelName: string,
  getProxy: () => ApiProxy,
  cache: { value: boolean | null },
): Promise<boolean> {
  if (cache.value !== null) return cache.value;

  const lower = modelName.toLowerCase();
  if (TOOL_BLACKLIST.some(b => lower.includes(b))) {
    cache.value = false;
    return false;
  }
  if (TOOL_WHITELIST.some(w => lower.includes(w))) {
    cache.value = true;
    return true;
  }

  try {
    const proxy = getProxy();
    const response = await fetch(`${proxy.getBaseUrl()}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${proxy.getApiKey()}`,
      },
      body: JSON.stringify({
        model: modelName,
        messages: [{ role: 'user', content: 'hi' }],
        tools: [{ type: 'function', function: { name: 'ping', description: 'ping', parameters: { type: 'object', properties: {} } } }],
        max_tokens: 10,
        stream: false,
      }),
    });
    const data = await response.json();
    cache.value = !!data.choices?.[0]?.message?.tool_calls;
  } catch {
    cache.value = false;
  }
  return cache.value;
}
