import { useMutation } from "@tanstack/react-query"
import { Link } from "@tanstack/react-router"
import { Bot, Send, Settings, User } from "lucide-react"
import { useCallback, useEffect, useRef, useState } from "react"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Separator } from "@/components/ui/separator"
import { ApiError, aiApi } from "@/lib/api"
import { cn } from "@/lib/utils"

interface Message {
  content: string
  id: string
  role: "user" | "assistant"
  timestamp: Date
}

interface AIChatContentProps {
  onInsertText?: (text: string) => void
  projectId?: string
}

// Cap the history sent to the model to keep requests small
const MAX_HISTORY_MESSAGES = 12

const PROMPT_SUGGESTIONS = [
  "Help me develop this character",
  "Suggest plot twists for this scene",
  "Improve the pacing here",
  "Make this dialogue more realistic",
  "Add more sensory details",
  "What's missing from this scene?",
]

export function AIChatContent({ onInsertText, projectId }: AIChatContentProps) {
  const [messages, setMessages] = useState<Message[]>([])
  const [input, setInput] = useState("")
  const [needsProvider, setNeedsProvider] = useState(false)
  const [errorText, setErrorText] = useState<string | null>(null)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  const scrollToBottom = useCallback(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [])

  useEffect(() => {
    if (messages.length > 0) {
      scrollToBottom()
    }
  }, [messages, scrollToBottom])

  const chatMutation = useMutation({
    mutationFn: async (history: Message[]) =>
      await aiApi.chat({
        messages: history
          .slice(-MAX_HISTORY_MESSAGES)
          .map((message) => ({ role: message.role, content: message.content })),
        projectId,
      }),
    onSuccess: (response) => {
      setMessages((prev) => [
        ...prev,
        {
          id: crypto.randomUUID(),
          content: response.message,
          role: "assistant",
          timestamp: new Date(),
        },
      ])
    },
    onError: (error) => {
      if (error instanceof ApiError && error.code === "no_provider") {
        setNeedsProvider(true)
        return
      }
      setErrorText(error instanceof Error ? error.message : "Something went wrong")
    },
  })

  const isTyping = chatMutation.isPending

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!input.trim() || isTyping) {
      return
    }

    const userMessage: Message = {
      id: crypto.randomUUID(),
      content: input.trim(),
      role: "user",
      timestamp: new Date(),
    }

    const nextMessages = [...messages, userMessage]
    setMessages(nextMessages)
    setInput("")
    setErrorText(null)
    chatMutation.mutate(nextMessages)
  }

  const handleSuggestionClick = (suggestion: string) => {
    setInput(suggestion)
    inputRef.current?.focus()
  }

  const handleInsertToEditor = (text: string) => {
    onInsertText?.(text)
  }

  if (needsProvider) {
    return (
      <div className="flex h-full flex-col items-center justify-center p-6 text-center">
        <div className="mb-3 w-fit rounded-full bg-muted p-3">
          <Settings className="h-6 w-6 text-muted-foreground" />
        </div>
        <h3 className="mb-2 font-semibold text-sm">Connect an AI provider</h3>
        <p className="mb-4 text-muted-foreground text-sm">
          The writing assistant uses your own AI provider account (OpenRouter, OpenAI, Anthropic,
          Ollama, and more). Connect one to start chatting.
        </p>
        <Button asChild size="sm">
          <Link to="/dashboard/ai">Set up AI provider</Link>
        </Button>
      </div>
    )
  }

  return (
    <div className="flex h-full flex-col">
      {/* Messages Area */}
      <div className="flex-1 overflow-y-auto p-4">
        <div className="space-y-4">
          {messages.length === 0 && (
            <div className="py-8 text-center">
              <div className="mx-auto mb-3 w-fit rounded-full bg-muted p-3">
                <Bot className="h-6 w-6 text-muted-foreground" />
              </div>
              <p className="mb-4 text-muted-foreground text-sm">
                Hi! I'm here to help with your writing. Ask me anything about characters, plot,
                style, or storytelling.
              </p>
              <div className="space-y-2">
                <p className="font-medium text-muted-foreground text-xs uppercase tracking-wide">
                  Try asking:
                </p>
                <div className="flex flex-wrap gap-2">
                  {PROMPT_SUGGESTIONS.map((suggestion) => (
                    <Badge
                      className="cursor-pointer py-1 text-xs hover:bg-secondary/80"
                      key={suggestion}
                      onClick={() => handleSuggestionClick(suggestion)}
                      variant="secondary"
                    >
                      {suggestion}
                    </Badge>
                  ))}
                </div>
              </div>
            </div>
          )}

          {messages.map((message) => (
            <div
              className={cn(
                "flex gap-3",
                message.role === "user" ? "justify-end" : "justify-start"
              )}
              key={message.id}
            >
              {message.role === "assistant" && (
                <Avatar className="mt-1 h-8 w-8 shrink-0">
                  <AvatarFallback className="bg-primary text-primary-foreground">
                    <Bot className="h-4 w-4" />
                  </AvatarFallback>
                </Avatar>
              )}

              <div
                className={cn(
                  "max-w-[240px] rounded-lg px-3 py-2 text-sm",
                  message.role === "user" ? "bg-primary text-primary-foreground" : "bg-muted"
                )}
              >
                <p className="whitespace-pre-wrap">{message.content}</p>
                {message.role === "assistant" && (
                  <div className="mt-2 border-border/50 border-t pt-2">
                    <Button
                      className="h-6 p-1 text-xs"
                      onClick={() => handleInsertToEditor(message.content)}
                      size="sm"
                      variant="ghost"
                    >
                      Insert into editor
                    </Button>
                  </div>
                )}
              </div>

              {message.role === "user" && (
                <Avatar className="mt-1 h-8 w-8 shrink-0">
                  <AvatarFallback className="bg-secondary">
                    <User className="h-4 w-4" />
                  </AvatarFallback>
                </Avatar>
              )}
            </div>
          ))}

          {isTyping && (
            <div className="flex justify-start gap-3">
              <Avatar className="mt-1 h-8 w-8 shrink-0">
                <AvatarFallback className="bg-primary text-primary-foreground">
                  <Bot className="h-4 w-4" />
                </AvatarFallback>
              </Avatar>
              <div className="rounded-lg bg-muted px-3 py-2 text-sm">
                <div className="flex gap-1">
                  <div className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground/60" />
                  <div
                    className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground/60"
                    style={{ animationDelay: "0.1s" }}
                  />
                  <div
                    className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground/60"
                    style={{ animationDelay: "0.2s" }}
                  />
                </div>
              </div>
            </div>
          )}

          <div ref={messagesEndRef} />
        </div>
      </div>

      <Separator />

      {/* Input Area */}
      <div className="p-4">
        {errorText && <p className="mb-2 text-destructive text-xs">{errorText}</p>}
        <form className="flex gap-2" onSubmit={handleSubmit}>
          <Input
            className="flex-1"
            disabled={isTyping}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Ask about your writing..."
            ref={inputRef}
            value={input}
          />
          <Button className="px-3" disabled={!input.trim() || isTyping} size="sm" type="submit">
            <Send className="h-4 w-4" />
          </Button>
        </form>
      </div>
    </div>
  )
}
