/**
 * 聊天工具调用 — Tool Calling 定义、处理器、模型兼容性探测
 *
 * 从 chat-orchestrator.service.ts 提取，职责：
 * 1. 工具函数注册（readChapter 等）
 * 2. 工具定义列表（供 AI 模型识别）
 * 3. 模型 tool calling 兼容性探测
 */

import type Database from 'better-sqlite3';
import type { ApiProxy} from '../../../api-proxy';
import { type ChatCompletionTool } from '../../../api-proxy';
import { truncateChapterContent } from '../prompt/truncation';

// ─── 工具处理函数 ───

/** 工具处理函数映射表 */
export const toolHandlers: Record<string, (args: unknown, db: Database.Database) => Promise<unknown>> = {
  readChapter: async (args, db) => {
    const { chapterId, titleHint } = args as { chapterId?: string; titleHint?: string };

    if (chapterId) {
      const row = db.prepare('SELECT id, title, content FROM chapters WHERE id = ?').get(chapterId) as
        { id: string; title: string; content: string } | undefined;
      if (!row) return { found: false, error: '章节不存在' };
      // ADR-003 D 阶段：长文截断（hard-cap + warn），避免 readChapter 返回内容挤爆 prompt
      const { text, truncated, originalLength, truncatedLength } = truncateChapterContent(row.content ?? '', {
        chapterId: row.id,
        source: 'chat-tools.readChapter',
      });
      return {
        found: true,
        title: row.title,
        content: text,
        wordCount: row.content?.length ?? 0,
        ...(truncated ? { truncated: true, originalLength, truncatedLength } : {}),
      };
    }

    if (titleHint) {
      const row = db.prepare('SELECT id, title, content FROM chapters WHERE title LIKE ? ORDER BY updated_at DESC LIMIT 1').get(`%${titleHint}%`) as
        { id: string; title: string; content: string } | undefined;
      if (!row) return { found: false, error: '未找到匹配章节', titleHint };
      // ADR-003 D 阶段：长文截断
      const { text, truncated, originalLength, truncatedLength } = truncateChapterContent(row.content ?? '', {
        chapterId: row.id,
        source: 'chat-tools.readChapter',
      });
      return {
        found: true,
        title: row.title,
        content: text,
        wordCount: row.content?.length ?? 0,
        ...(truncated ? { truncated: true, originalLength, truncatedLength } : {}),
      };
    }

    const recent = db.prepare('SELECT id, title, length(content) as wordCount FROM chapters ORDER BY updated_at DESC LIMIT 5').all();
    return { found: false, recentChapters: recent, message: '未指定章节，以下是最近的 5 个章节' };
  },

  writeChapter: async (args, db) => {
    const { chapterId, content, titleHint } = args as { chapterId?: string; content?: string; titleHint?: string };

    if (!content) {
      return { success: false, error: '写入内容不能为空' };
    }

    if (chapterId) {
      db.prepare('UPDATE chapters SET content = ?, updated_at = datetime("now") WHERE id = ?').run(content, chapterId);
      return { success: true, chapterId };
    }

    if (titleHint) {
      const row = db.prepare('SELECT id, title FROM chapters WHERE title LIKE ? ORDER BY updated_at DESC LIMIT 1').get(`%${titleHint}%`) as
        { id: string; title: string } | undefined;
      if (!row) return { success: false, error: '未找到匹配章节', titleHint };
      db.prepare('UPDATE chapters SET content = ?, updated_at = datetime("now") WHERE id = ?').run(content, row.id);
      return { success: true, chapterId: row.id };
    }

    return { success: false, error: '未指定章节，请提供 chapterId 或 titleHint' };
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
  {
    type: 'function',
    function: {
      name: 'writeChapter',
      description: '修改或写入用户作品章节的正文内容。当用户要求改写/润色/扩写/续写/修改某章节时调用。注意：内容替换是一次性全量替换，不会局部插入。',
      parameters: {
        type: 'object',
        properties: {
          chapterId: { type: 'string', description: '章节 UUID' },
          content: { type: 'string', description: '要写入的完整章节正文内容' },
          titleHint: { type: 'string', description: '章节标题关键词，用于模糊匹配（当没有 chapterId 时使用）' },
        },
        required: ['content'],
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
