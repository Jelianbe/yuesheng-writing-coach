// ChatSend/ChatStop 响应直接使用具体类型而非 ApiResponse 包装

// ─── 请求类型 ───

export interface ChatSendRequest {
  message: string;
  sessionId: string;
  history: Array<{ role: 'user' | 'assistant'; content: string }>;
  attitudeLevel: string;
  studentContext: string;
}

export interface ChatStopRequest {
  sessionId: string;
}

// ─── 响应类型 ───

export interface ChatSendResponse {
  acknowledged: true;
  messageId: string;
}

export interface ChatStopResponse {
  stopped: true;
}

// ─── Event 推送类型 ───

export interface ChatStreamDataEvent {
  sessionId: string;
  chunk: string;
}

export interface ChatStreamEndEvent {
  sessionId: string;
  fullResponse: string;
  messageId: string;
  error?: string;
  aborted?: boolean;
}

export interface ChatToolExecutingEvent {
  sessionId: string;
  toolName: string;
  status: 'start' | 'end' | 'error';
}

// ─── API 接口定义 ───

export const ChatApi = {
  send: {
    channel: 'chat:send' as const,
    request: {} as ChatSendRequest,
    response: {} as ChatSendResponse,
  },

  stop: {
    channel: 'chat:stop' as const,
    request: {} as ChatStopRequest,
    response: {} as ChatStopResponse,
  },

  streamData: {
    channel: 'chat:stream:data' as const,
    event: {} as ChatStreamDataEvent,
  },

  streamEnd: {
    channel: 'chat:stream:end' as const,
    event: {} as ChatStreamEndEvent,
  },

  toolExecuting: {
    channel: 'chat:tool:executing' as const,
    event: {} as ChatToolExecutingEvent,
  },
} as const;

export type ChatInvokeChannels =
  | typeof ChatApi.send.channel
  | typeof ChatApi.stop.channel;

export type ChatEventChannels =
  | typeof ChatApi.streamData.channel
  | typeof ChatApi.streamEnd.channel
  | typeof ChatApi.toolExecuting.channel;
