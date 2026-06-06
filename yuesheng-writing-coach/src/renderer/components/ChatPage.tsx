import React, { useRef, useEffect } from 'react';
import { useChatStore } from '../stores/chat.store';
import { useConfigStore } from '../stores/config.store';
import { ChatMessage, AttitudeLevel } from '../shared/types';

function AttitudeToggle(): React.ReactElement {
  const { attitudeLevel } = useConfigStore();
  const setAttitudeLevel = useConfigStore((s) => s.setAttitudeLevel);

  const handleToggle = (level: AttitudeLevel) => {
    if (level !== attitudeLevel) {
      setAttitudeLevel(level);
    }
  };

  const buttonClass = (level: AttitudeLevel) =>
    `px-3 py-1 text-sm rounded-md transition-all ${
      attitudeLevel === level
        ? 'bg-blue-600 text-white shadow-sm'
        : 'text-slate-400 hover:text-slate-200'
    }`;

  return (
    <div className="flex bg-slate-800 rounded-lg p-0.5">
      <button
        className={buttonClass('doubao')}
        onClick={() => handleToggle('doubao')}
      >
        豆包
      </button>
      <button
        className={buttonClass('yuesheng')}
        onClick={() => handleToggle('yuesheng')}
      >
        月笙如歌
      </button>
    </div>
  );
}

function ChatMessageBubble({ msg }: { msg: ChatMessage }): React.ReactElement {
  const isUser = msg.role === 'user';
  const isAssistant = msg.role === 'assistant';
  const isStreaming = isAssistant && msg.content === '';

  return (
    <div className={`flex ${isUser ? 'justify-end' : 'justify-start'} mb-4`}>
      <div
        className={`max-w-[75%] rounded-2xl px-4 py-3 ${
          isUser
            ? 'bg-blue-600 text-white rounded-br-md'
            : 'bg-slate-800 text-slate-200 rounded-bl-md border border-slate-700'
        }`}
      >
        {isStreaming ? (
          <div className="flex items-center gap-1">
            <span className="w-2 h-2 bg-slate-400 rounded-full animate-bounce" style={{ animationDelay: '0ms' }} />
            <span className="w-2 h-2 bg-slate-400 rounded-full animate-bounce" style={{ animationDelay: '150ms' }} />
            <span className="w-2 h-2 bg-slate-400 rounded-full animate-bounce" style={{ animationDelay: '300ms' }} />
          </div>
        ) : (
          <div className="text-sm leading-relaxed whitespace-pre-wrap">{msg.content}</div>
        )}
        <div className={`text-xs mt-1 ${isUser ? 'text-blue-200' : 'text-slate-500'}`}>
          {new Date(msg.timestamp).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })}
        </div>
      </div>
    </div>
  );
}

export function ChatPage(): React.ReactElement {
  const { messages, isLoading, error, sendMessage } = useChatStore();
  const [input, setInput] = React.useState('');
  const listRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (listRef.current) {
      listRef.current.scrollTop = listRef.current.scrollHeight;
    }
  }, [messages]);

  const handleSend = () => {
    const text = input.trim();
    if (!text || isLoading) return;
    setInput('');
    sendMessage(text);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const hasMessages = messages.length > 0;

  return (
    <div className="flex flex-col h-full">
      <div className="flex items-center justify-between border-b border-slate-700 px-4 py-2 bg-slate-900/50">
        <span className="text-sm font-medium text-slate-300">月笙写作教练</span>
        <AttitudeToggle />
      </div>
      <div className="flex-1 overflow-y-auto p-4 space-y-2" ref={listRef}>
        {!hasMessages && (
          <div className="flex flex-col items-center justify-center h-full text-center">
            <div className="text-5xl mb-4 opacity-30">✍️</div>
            <h2 className="text-xl font-semibold text-slate-300 mb-2">月笙写作教练</h2>
            <p className="text-sm text-slate-500 max-w-md">
              描述你的写作困惑或分享你的作品片段，月笙将帮你诊断问题并提供针对性的教学建议。
            </p>
          </div>
        )}
        {messages.map((msg) => (
          <ChatMessageBubble key={msg.id} msg={msg} />
        ))}
        {error && (
          <div className="flex justify-center">
            <div className="bg-red-900/50 text-red-300 text-sm px-4 py-2 rounded-lg border border-red-800">
              {error}
            </div>
          </div>
        )}
      </div>

      <div className="border-t border-slate-700 p-4">
        <div className="flex gap-2">
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="描述你的写作问题..."
            rows={2}
            className="flex-1 bg-slate-800 text-slate-200 rounded-xl px-4 py-3 text-sm resize-none outline-none focus:ring-2 focus:ring-blue-500 border border-slate-700 placeholder-slate-500"
            disabled={isLoading}
          />
          <button
            onClick={handleSend}
            disabled={isLoading || !input.trim()}
            className="px-5 py-3 bg-blue-600 text-white rounded-xl hover:bg-blue-500 disabled:opacity-40 disabled:cursor-not-allowed transition-all self-end"
          >
            {isLoading ? (
              <svg className="w-5 h-5 animate-spin" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
              </svg>
            ) : (
              <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path strokeLinecap="round" strokeLinejoin="round" d="M5 12h14M12 5l7 7-7 7" />
              </svg>
            )}
          </button>
        </div>
      </div>
    </div>
  );
}
