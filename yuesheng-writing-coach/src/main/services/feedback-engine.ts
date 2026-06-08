/**
 * Realtime Feedback Engine Service
 * 
 * 实时检测用户写作中的技术问题并给出即时反馈
 * 检测段落长度、对话格式、节奏、信息密度等
 * 
 * @module services/feedback-engine
 * @phase Phase 2（MVP 后实现，当前为类型骨架）
 */

export type IssueType = 
  | 'paragraph-length'
  | 'dialogue-format'
  | 'pacing'
  | 'information-density'
  | 'show-vs-tell'
  | 'anchor-missing'
  | 'static-description'
  | 'transition-abrupt';

export interface FeedbackContext {
  studentType?: string;
  currentFocus?: string;
  previousIssues?: string[];
}

export interface IssueLocation {
  line?: number;
  paragraph?: number;
  textSnippet?: string;
}

export interface TechnicalIssue {
  type: IssueType;
  description: string;
  location?: IssueLocation;
  severity: 'minor' | 'moderate' | 'major';
}

export interface FeedbackSuggestion {
  issueType: IssueType;
  suggestion: string;
  example?: string;
  priority: number;
}

export interface FeedbackResult {
  issues: TechnicalIssue[];
  suggestions: FeedbackSuggestion[];
  urgency: 'low' | 'medium' | 'high';
  overallScore?: number;      // 0-10
  timestamp: string;
}

export interface FeedbackConfig {
  paragraphThreshold: {
    long: number;
    medium: number;
    short: number;
  };
  maxIssuesPerFeedback: number;
  urgencyRules: {
    high: IssueType[];
    medium: IssueType[];
    low: IssueType[];
  };
  debounceMs: number;
}

const DEFAULT_CONFIG: FeedbackConfig = {
  paragraphThreshold: {
    long: 300,
    medium: 150,
    short: 50,
  },
  maxIssuesPerFeedback: 3,
  urgencyRules: {
    high: ['paragraph-length', 'dialogue-format'],
    medium: ['pacing', 'information-density'],
    low: ['show-vs-tell', 'transition-abrupt'],
  },
  debounceMs: 2000,
};

/**
 * 分析写作内容并生成即时反馈
 * @param content 用户写作内容
 * @param contentType 内容类型
 * @param context 上下文信息
 * @param config 反馈配置
 */
export async function generateFeedback(
  _content: string,
  _contentType: 'narrative' | 'dialogue' | 'description' | 'mixed' = 'mixed',
  _context?: FeedbackContext,
  _config: Partial<FeedbackConfig> = {},
): Promise<FeedbackResult> {
  void { ...DEFAULT_CONFIG, ..._config };
  
  // TODO: 实现反馈逻辑
  // 1. 分析段落结构
  // 2. 识别对话和叙述
  // 3. 计算信息密度
  // 4. 应用检测规则
  // 5. 生成反馈建议
  
  return {
    issues: [],
    suggestions: [],
    urgency: 'low',
    timestamp: new Date().toISOString(),
  };
}

/**
 * 检测段落长度问题
 */
export function checkParagraphLength(text: string, threshold: FeedbackConfig['paragraphThreshold']): TechnicalIssue[] {
  const paragraphs = text.split(/\n\s*\n/);
  const issues: TechnicalIssue[] = [];
  
  paragraphs.forEach((para, index) => {
    const length = para.length;
    
    if (length > threshold.long) {
      issues.push({
        type: 'paragraph-length',
        description: `段落 ${index + 1} 过长（${length} 字），建议拆分`,
        severity: 'major',
        location: { paragraph: index + 1 },
      });
    } else if (length > threshold.medium) {
      issues.push({
        type: 'paragraph-length',
        description: `段落 ${index + 1} 偏长（${length} 字），建议在对话处拆分`,
        severity: 'moderate',
        location: { paragraph: index + 1 },
      });
    }
  });
  
  return issues;
}
