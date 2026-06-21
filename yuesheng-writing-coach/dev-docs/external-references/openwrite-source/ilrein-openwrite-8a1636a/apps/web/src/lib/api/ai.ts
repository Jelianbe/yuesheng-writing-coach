/**
 * AI chat API client
 *
 * Sends chat messages to the server, which routes them to the
 * user's configured AI provider.
 */

import { apiCall } from "./base"

export interface AiChatMessage {
  content: string
  role: "user" | "assistant"
}

export interface AiChatRequest {
  messages: AiChatMessage[]
  model?: string
  projectId?: string
}

export interface AiChatResponse {
  message: string
  model: string | null
  provider: string
}

export const aiApi = {
  /**
   * Send a chat conversation and get the assistant's reply
   */
  async chat(data: AiChatRequest): Promise<AiChatResponse> {
    return (await apiCall("/api/ai/chat", {
      method: "POST",
      body: JSON.stringify(data),
    })) as AiChatResponse
  },
}
