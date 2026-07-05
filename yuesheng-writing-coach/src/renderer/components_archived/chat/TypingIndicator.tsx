import React from 'react';
import styles from './TypingIndicator.module.css';

interface TypingIndicatorProps {
  className?: string;
}

export const TypingIndicator: React.FC<TypingIndicatorProps> = ({ className = '' }) => {
  return (
    <div className={`${styles.container} ${className}`} role="status" aria-label="AI is typing">
      <div className={styles.dots}>
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            className={styles.dot}
            style={{
              animation: `pulseDot 1.4s ease-in-out ${i * 0.16}s infinite both`,
            }}
          />
        ))}
      </div>
      <span className={styles.label}>
        月笙正在思考...
      </span>
    </div>
  );
};

// Usage example:
// {isStreaming && <TypingIndicator />}
