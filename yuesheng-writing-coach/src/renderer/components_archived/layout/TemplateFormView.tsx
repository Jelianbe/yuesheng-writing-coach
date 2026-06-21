/**
 * TemplateFormView — 模板辅助表单（V4 I-04）
 *
 * 功能：
 * - 当 sidebarMode === 'template' 时在右边栏显示
 * - 表单字段随对话上下文逐步自动填充
 */

import React, { useState, useEffect } from 'react';
import { FileText, Send } from 'lucide-react';
import { usePanelSessionStore } from '../../stores/panel-session.store';
import { useChatStore } from '../../stores/chat.store';

interface FormData {
  diagnosisText: string;
  goal: string;
  notes: string;
}

export const TemplateFormView: React.FC<{ onSubmit?: (text: string) => void }> = ({ onSubmit }) => {
  const sidebarMode = usePanelSessionStore(s => s.sidebarMode);
  const messages = useChatStore(s => s.messages);
  const [form, setForm] = useState<FormData>({ diagnosisText: '', goal: '', notes: '' });

  // 从对话上下文中自动填充诊断文本
  useEffect(() => {
    if (sidebarMode !== 'template') return;
    const lastUserMsg = [...messages].reverse().find(m => m.role === 'user');
    if (lastUserMsg && !form.diagnosisText) {
      const preview = lastUserMsg.content.slice(0, 200);
      setForm(prev => ({ ...prev, diagnosisText: preview }));
    }
  }, [sidebarMode, messages, form.diagnosisText]);

  const handleSubmit = () => {
    if (!form.diagnosisText.trim()) return;
    const fullText = [
      form.goal ? `目标：${form.goal}` : '',
      form.diagnosisText,
      form.notes ? `备注：${form.notes}` : '',
    ].filter(Boolean).join('\n\n');
    onSubmit?.(fullText);
  };

  const fieldLabel: Record<keyof FormData, string> = {
    diagnosisText: '诊断文本',
    goal: '写作目标',
    notes: '补充说明',
  };

  return (
    <div style={{ padding: '12px', display: 'flex', flexDirection: 'column', gap: 10 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
        <FileText size={16} strokeWidth={1.8} color="var(--accent)" />
        <span style={{ fontSize: '0.82rem', fontWeight: 600, color: 'var(--text-primary)' }}>模板辅助</span>
      </div>
      {(Object.keys(fieldLabel) as (keyof FormData)[]).map((key) => (
        <div key={key} style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <label style={{ fontSize: '0.68rem', fontWeight: 500, color: 'var(--text-secondary)' }}>
            {fieldLabel[key]}
          </label>
          {key === 'diagnosisText' ? (
            <textarea
              value={form[key]}
              onChange={e => setForm(f => ({ ...f, [key]: e.target.value }))}
              rows={4}
              style={{
                padding: '8px',
                border: '1px solid var(--border)',
                borderRadius: 'var(--radius-md)',
                background: 'var(--bg-card)',
                color: 'var(--text-primary)',
                fontFamily: 'var(--font-body)',
                fontSize: '0.82rem',
                lineHeight: 1.5,
                resize: 'vertical',
                outline: 'none',
              }}
              placeholder="输入或粘贴需要诊断的文本..."
            />
          ) : (
            <input
              value={form[key]}
              onChange={e => setForm(f => ({ ...f, [key]: e.target.value }))}
              style={{
                padding: '8px',
                border: '1px solid var(--border)',
                borderRadius: 'var(--radius-md)',
                background: 'var(--bg-card)',
                color: 'var(--text-primary)',
                fontFamily: 'var(--font-body)',
                fontSize: '0.82rem',
                outline: 'none',
              }}
              placeholder={key === 'goal' ? '例如：优化开篇吸引力' : '可选补充说明'}
            />
          )}
        </div>
      ))}
      <button
        onClick={handleSubmit}
        disabled={!form.diagnosisText.trim()}
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 6,
          padding: '8px 16px',
          border: 'none',
          borderRadius: 'var(--radius-md)',
          background: form.diagnosisText.trim() ? 'var(--accent)' : 'var(--bg-disabled)',
          color: form.diagnosisText.trim() ? 'var(--text-on-accent)' : 'var(--text-tertiary)',
          fontSize: '0.82rem',
          fontWeight: 500,
          cursor: form.diagnosisText.trim() ? 'pointer' : 'not-allowed',
          marginTop: 4,
        }}
      >
        <Send size={14} strokeWidth={1.8} />
        发送诊断请求
      </button>
    </div>
  );
};
