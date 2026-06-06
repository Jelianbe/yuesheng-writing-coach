import React from 'react';

const styles = {
  overlay: {
    position: 'fixed' as const,
    inset: 0,
    background: 'rgba(61, 50, 41, 0.3)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 200,
    backdropFilter: 'blur(4px)',
    WebkitBackdropFilter: 'blur(4px)',
  },
  panel: {
    background: 'var(--bg-card)',
    border: '1px solid var(--border-light)',
    borderRadius: 'var(--radius-xl)',
    padding: '32px',
    width: 480,
    maxWidth: '90vw',
    maxHeight: '80vh',
    overflowY: 'auto' as const,
    boxShadow: 'var(--shadow-xl)',
    animation: 'settingsIn 0.3s ease-out',
  },
  header: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 24,
  },
  title: {
    fontFamily: 'var(--font-display)',
    fontSize: '1.2rem',
    fontWeight: 600,
    color: 'var(--text-primary)',
    margin: 0,
  },
  closeBtn: {
    width: 28,
    height: 28,
    borderRadius: 'var(--radius-sm)',
    border: 'none',
    background: 'var(--bg-hover)',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: 'var(--text-tertiary)',
    fontSize: 14,
    lineHeight: 1,
    transition: 'all 0.15s',
  },
  section: {
    marginBottom: 20,
  },
  sectionLabel: {
    fontSize: '0.75rem',
    fontWeight: 600,
    color: 'var(--text-tertiary)',
    marginBottom: 8,
    textTransform: 'uppercase' as const,
    letterSpacing: '0.5px',
  },
  field: {
    marginBottom: 12,
  },
  fieldLabel: {
    display: 'block',
    fontSize: '0.8rem',
    fontWeight: 500,
    color: 'var(--text-primary)',
    marginBottom: 4,
  },
  input: {
    width: '100%',
    padding: '8px 12px',
    border: '1px solid var(--border)',
    borderRadius: 'var(--radius-md)',
    fontFamily: 'var(--font-body)',
    fontSize: '0.85rem',
    color: 'var(--text-primary)',
    background: 'var(--bg-input)',
    outline: 'none',
    boxSizing: 'border-box' as const,
    transition: 'border-color 0.2s, box-shadow 0.2s',
  },
  select: {
    width: '100%',
    padding: '8px 12px',
    border: '1px solid var(--border)',
    borderRadius: 'var(--radius-md)',
    fontFamily: 'var(--font-body)',
    fontSize: '0.85rem',
    color: 'var(--text-primary)',
    background: 'var(--bg-input)',
    outline: 'none',
    boxSizing: 'border-box' as const,
    transition: 'border-color 0.2s, box-shadow 0.2s',
  },
  saveBtn: {
    width: '100%',
    padding: 10,
    background: 'var(--accent)',
    color: '#fff',
    border: 'none',
    borderRadius: 'var(--radius-md)',
    fontFamily: 'var(--font-body)',
    fontSize: '0.9rem',
    fontWeight: 500,
    cursor: 'pointer',
    transition: 'background 0.15s',
    marginTop: 8,
  },
  aboutText: {
    fontSize: '0.85rem',
    color: 'var(--text-secondary)',
    lineHeight: 1.7,
    margin: 0,
  },
};

export interface SettingsModalProps {
  open: boolean;
  onClose: () => void;
  onSave: (settings: { apiKey: string; model: string; attitude: string }) => void;
  initialSettings?: { apiKey: string; model: string; attitude: string };
}

export const SettingsModal: React.FC<SettingsModalProps> = React.memo(({
  open,
  onClose,
  onSave,
  initialSettings,
}) => {
  const [apiKey, setApiKey] = React.useState(initialSettings?.apiKey ?? '');
  const [model, setModel] = React.useState(initialSettings?.model ?? 'gpt-4o');
  const [attitude, setAttitude] = React.useState(initialSettings?.attitude ?? 'balanced');

  const handleOverlayClick = (e: React.MouseEvent) => {
    if (e.target === e.currentTarget) {
      onClose();
    }
  };

  const handleSave = () => {
    onSave({ apiKey, model, attitude });
  };

  if (!open) return null;

  return (
    <>
      <style>{`
        @keyframes settingsIn {
          from { opacity: 0; transform: translateY(-10px) scale(0.98); }
          to { opacity: 1; transform: translateY(0) scale(1); }
        }
        .settings-input:focus,
        .settings-select:focus {
          border-color: var(--accent) !important;
          box-shadow: 0 0 0 3px var(--accent-light) !important;
        }
        .settings-close-btn:hover {
          background: var(--accent-subtle) !important;
          color: var(--accent) !important;
        }
        .settings-save-btn:hover {
          background: var(--accent-hover) !important;
        }
      `}</style>
      <div style={styles.overlay} onClick={handleOverlayClick}>
        <div style={styles.panel}>
          <div style={styles.header}>
            <h2 style={styles.title}>设置</h2>
            <button
              style={styles.closeBtn}
              onClick={onClose}
              className="settings-close-btn"
              aria-label="关闭设置"
            >
              ✕
            </button>
          </div>

          <div style={styles.section}>
            <div style={styles.sectionLabel}>API 配置</div>
            <div style={styles.field}>
              <label style={styles.fieldLabel}>API Key</label>
              <input
                className="settings-input"
                style={styles.input}
                type="password"
                value={apiKey}
                onChange={(e) => setApiKey(e.target.value)}
                placeholder="输入你的 API Key"
              />
            </div>
            <div style={styles.field}>
              <label style={styles.fieldLabel}>模型</label>
              <select
                className="settings-select"
                style={styles.select}
                value={model}
                onChange={(e) => setModel(e.target.value)}
              >
                <option value="gpt-4o">GPT-4o</option>
                <option value="gpt-4o-mini">GPT-4o-mini</option>
                <option value="claude-3.5-sonnet">Claude 3.5 Sonnet</option>
                <option value="deepseek-chat">DeepSeek Chat</option>
              </select>
            </div>
          </div>

          <div style={styles.section}>
            <div style={styles.sectionLabel}>教学风格</div>
            <div style={styles.field}>
              <label style={styles.fieldLabel}>回复态度</label>
              <select
                className="settings-select"
                style={styles.select}
                value={attitude}
                onChange={(e) => setAttitude(e.target.value)}
              >
                <option value="gentle">温柔鼓励 — 多肯定，少批评</option>
                <option value="balanced">平衡建议 — 指出问题也给出肯定</option>
                <option value="direct">直接犀利 — 直指问题，不绕弯子</option>
              </select>
            </div>
          </div>

          <div style={styles.section}>
            <div style={styles.sectionLabel}>关于</div>
            <p style={styles.aboutText}>
              月笙写作教练 v2.0 — 你的写作成长伙伴。通过智能诊断和个性化训练，帮助你提升写作技巧。
            </p>
          </div>

          <button
            style={styles.saveBtn}
            className="settings-save-btn"
            onClick={handleSave}
          >
            保存设置
          </button>
        </div>
      </div>
    </>
  );
});
