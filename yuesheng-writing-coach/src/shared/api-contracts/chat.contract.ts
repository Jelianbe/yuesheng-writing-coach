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

// Sprint 20 A-4: 编排器订阅式入口
export interface ChatHandleTurnRequest {
  userMessage: string;
  sessionId: string;
  phase?: 'trust_building' | 'requirement' | 'diagnosis' | 'training' | 'reflection';
  attitudeLevel?: string;
  history?: Array<{ role: 'user' | 'assistant'; content: string }>;
  studentContext?: string;
  activeProblemId?: string;
  activeTrainingSessionId?: string;
}

// ─── 响应类型 ───

export interface ChatSendResponse {
  acknowledged: true;
  messageId: string;
}

export interface ChatStopResponse {
  stopped: true;
}

// Sprint 20 A-4
export interface ChatHandleTurnResponse {
  acknowledged: true;
  streamId: string;
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

// Sprint 20 A-4: 编排器标准化事件推送
export interface ChatEventPayload {
  streamId: string;
  sessionId: string;
  event: unknown;
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

  handleTurn: {
    channel: 'chat:handleTurn' as const,
    request: {} as ChatHandleTurnRequest,
    response: {} as ChatHandleTurnResponse,
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

  event: {
    channel: 'chat:event' as const,
    event: {} as ChatEventPayload,
  },
} as const;

export type ChatInvokeChannels =
  | typeof ChatApi.send.channel
  | typeof ChatApi.stop.channel
  | typeof ChatApi.handleTurn.channel;

export type ChatEventChannels =
  | typeof ChatApi.streamData.channel
  | typeof ChatApi.streamEnd.channel
  | typeof ChatApi.toolExecuting.channel
  | typeof ChatApi.event.channel;
