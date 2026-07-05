// 聊天与会话类型
import type { DiagnosisEntry } from './types-diagnosis';

/** 聊天消息角色 */
export type MessageRole = 'user' | 'assistant' | 'system';

/** 单条消息 */
export interface ChatMessage {
  id: string;
  role: MessageRole;
  content: string;
  timestamp: number;
  diagnosis?: DiagnosisEntry;
  /** 系统消息扩展元数据（如诊断 payload/阶段转换/训练触发等） */
  metadata?: Record<string, unknown>;
}

/** 会话 */
export interface Session {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  messages: ChatMessage[];
  lastMessage?: string;
}

/** 聊天发送请求 */
export interface ChatSendRequest {
  message: string;
  sessionId: string;
}

/** 流式数据块 */
export interface StreamChunk {
  sessionId: string;
  chunk: string;
}

/** 流式结束 */
export interface StreamEnd {
  sessionId: string;
  fullResponse: string;
  messageId: string;
}

/** 消息行（数据库行映射） */
export interface MessageRow {
  id: string;
  session_id: string;
  role: string;
  content: string;
  timestamp: number;
}

/** 会话元数据（含 preview） */
export interface SessionMeta {
  id: string;
  title: string;
  preview: string;
  createdAt: string;
  updatedAt: string;
}
