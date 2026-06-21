import React from 'react';

interface TypingIndicatorProps {
  className?: string;
}

export const TypingIndicator: React.FC<TypingIndicatorProps> = ({ className = '' }) => {
  return (
    <div className={`flex items-center gap-1 py-3 px-1 animate-fade-in ${className}`} role="status" aria-label="AI is typing">
      <div className="flex gap-1.5">
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            className="w-2 h-2 rounded-full bg-accent-primary/60"
            style={{
              animation: `pulseDot 1.4s ease-in-out ${i * 0.16}s infinite both`,
            }}
          />
        ))}
      </div>
      <span className="text-sm text-text-tertiary ml-2">
        月笙正在思考...
      </span>
    </div>
  );
};

// Usage example:
// {isStreaming && <TypingIndicator />}
