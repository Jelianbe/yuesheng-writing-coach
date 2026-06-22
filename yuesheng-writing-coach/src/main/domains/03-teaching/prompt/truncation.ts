/**
 * 长文截断工具 (ADR-003 D 阶段)
 *
 * 策略：hard-cap + warn，不做 chunking
 * 阈值：MAX_CHARS = 4000 字符 (≈ 6000 tokens)，超出即截断
 * 截断模式：保留头 70% + 省略提示 + 保留尾 30%
 *
 * 设计依据：
 * - DeepSeek 8K 模型可用输入约 6K tokens
 * - Prompt 框架本身（核心层 + 上下文层 + 历史）已占 2-3K tokens
 * - 留给章节内容的安全余量约 4K 字符
 * - 头尾保留策略保证 LLM 能看到开头（背景/角色）和结尾（结论/伏笔）
 */

export const MAX_CHARS = 4000;

/** 默认头尾比例（前段占总截断长度的比例） */
const DEFAULT_HEAD_RATIO = 0.7;

/** 截断后中间插入的省略标记 */
const TRUNCATION_MARKER = '\n\n[... 章节内容过长，中间部分已省略 ...]\n\n';

/** 截断结果 */
export interface TruncationResult {
  /** 截断后文本 */
  text: string;
  /** 是否发生了截断 */
  truncated: boolean;
  /** 原始字符数 */
  originalLength: number;
  /** 截断后字符数 */
  truncatedLength: number;
}

/** 截断选项 */
export interface TruncationOptions {
  /** 最大字符数（默认 MAX_CHARS） */
  maxChars?: number;
  /** 头尾比例（默认 0.7，即前段占 70%） */
  headRatio?: number;
  /** 章节 ID（用于告警日志） */
  chapterId?: string;
  /** 来源标识（用于告警日志） */
  source?: string;
  /** 是否静默（不输出告警日志） */
  silent?: boolean;
}

/**
 * 截断章节内容，超出阈值时保留头尾并插入省略标记
 *
 * @param content - 原始章节内容
 * @param options - 截断选项
 * @returns 截断结果
 */
export function truncateChapterContent(
  content: string,
  options: TruncationOptions = {},
): TruncationResult {
  // 防御：空内容 / null / undefined 直接返回
  if (!content) {
    return {
      text: '',
      truncated: false,
      originalLength: 0,
      truncatedLength: 0,
    };
  }

  const maxChars = options.maxChars ?? MAX_CHARS;
  const headRatio = options.headRatio ?? DEFAULT_HEAD_RATIO;
  const originalLength = content.length;

  // 未超阈值，无需截断
  if (originalLength <= maxChars) {
    return {
      text: content,
      truncated: false,
      originalLength,
      truncatedLength: originalLength,
    };
  }

  // 计算头尾长度（扣除省略标记）
  const markerLength = TRUNCATION_MARKER.length;
  const availableForContent = Math.max(0, maxChars - markerLength);
  const headLength = Math.floor(availableForContent * headRatio);
  const tailLength = availableForContent - headLength;

  // 防御：阈值过小时降级为仅保留头部
  if (headLength <= 0 || tailLength <= 0) {
    const head = content.slice(0, Math.max(0, maxChars - markerLength));
    const text = head + TRUNCATION_MARKER;
    logTruncation(options, originalLength, text.length);
    return {
      text,
      truncated: true,
      originalLength,
      truncatedLength: text.length,
    };
  }

  const head = content.slice(0, headLength);
  const tail = content.slice(content.length - tailLength);
  const text = head + TRUNCATION_MARKER + tail;

  logTruncation(options, originalLength, text.length);

  return {
    text,
    truncated: true,
    originalLength,
    truncatedLength: text.length,
  };
}

/** 输出截断告警日志 */
function logTruncation(
  options: TruncationOptions,
  originalLength: number,
  truncatedLength: number,
): void {
  if (options.silent) return;
  const tag = options.chapterId ? `chapterId=${options.chapterId}` : 'unknown';
  const src = options.source ?? 'unspecified';
  console.warn(
    `[Truncation] ${src} ${tag} original=${originalLength} truncated=${truncatedLength}`,
  );
}
