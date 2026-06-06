import React from 'react';

const styles = {
  container: {
    display: 'flex',
    flexDirection: 'column' as const,
    alignItems: 'center',
    justifyContent: 'flex-start',
    textAlign: 'center' as const,
    padding: '30px 20px 16px',
    overflowY: 'auto' as const,
    gap: 8,
  },
  icon: {
    width: 64,
    height: 64,
    background: 'var(--accent-subtle)',
    borderRadius: 'var(--radius-xl)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontFamily: 'var(--font-display)',
    fontSize: '1.8rem',
    color: 'var(--accent)',
    marginBottom: 8,
    flexShrink: 0,
  },
  title: {
    fontFamily: 'var(--font-display)',
    fontSize: '1.2rem',
    fontWeight: 600,
    color: 'var(--text-primary)',
    margin: 0,
    marginBottom: 4,
    flexShrink: 0,
  },
  desc: {
    fontSize: '0.9rem',
    color: 'var(--text-tertiary)',
    maxWidth: 400,
    lineHeight: 1.7,
    margin: 0,
    marginBottom: 16,
    flexShrink: 0,
  },
  suggestionsContainer: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 8,
    width: '100%',
    maxWidth: 400,
    marginBottom: 16,
    flexShrink: 0,
  },
  suggestionBtn: {
    padding: '12px 16px',
    background: 'var(--bg-card)',
    border: '1px solid var(--border-light)',
    borderRadius: 'var(--radius-md)',
    fontSize: '0.85rem',
    color: 'var(--text-secondary)',
    cursor: 'pointer',
    textAlign: 'left' as const,
    fontFamily: 'var(--font-body)',
    lineHeight: 1.5,
    transition: 'all 0.15s',
  },
};

const SUGGESTIONS = [
  '我写了一段开头，帮我看看有什么问题',
  '怎么让角色更立体、更有记忆点？',
  '世界观设定太多，第一章塞不进去怎么办？',
];

export interface WelcomeEmptyStateProps {
  onSelectSuggestion: (text: string) => void;
  visible: boolean;
}

export const WelcomeEmptyState: React.FC<WelcomeEmptyStateProps> = ({
  onSelectSuggestion,
  visible,
}) => {
  return (
    <div style={{ ...styles.container, display: visible ? 'flex' : 'none' }}>
      <style>{`
        .welcome-suggestion-btn:hover {
          background: var(--accent-subtle) !important;
          border-color: var(--accent-light) !important;
          color: var(--accent) !important;
        }
      `}</style>
      <div style={styles.icon}>月</div>
      <h2 style={styles.title}>今天想聊些什么？</h2>
      <p style={styles.desc}>
        你可以粘贴一段文字让月笙诊断，也可以直接聊聊你的写作困扰。
      </p>
      <div style={styles.suggestionsContainer}>
        {SUGGESTIONS.map((text) => (
          <button
            key={text}
            className="welcome-suggestion-btn"
            style={styles.suggestionBtn}
            onClick={() => onSelectSuggestion(text)}
          >
            {text}
          </button>
        ))}
      </div>
    </div>
  );
};
