/**
 * ConversationsPage — 对话列表
 *
 * 对齐设计稿：
 * - Navbar: "对话"
 * - 列表项：标题 | 摘要 | 时间 | 作品关联
 * - 空状态引导
 */

import React from 'react';
import { MessageCircle } from 'lucide-react';
import { usePageStackStore } from '../stores/page-stack.store';

const CONVERSATIONS = [
  { id: '1', title: '人物动机分析', summary: '分析了主角深海回响中的人物动机冲突…', time: '10分钟前', project: '深海回响' },
  { id: '2', title: '对话写作练习', summary: '完成了三个对话场景的修改练习…', time: '昨天', project: '星尘之旅' },
  { id: '3', title: '环境描写技法', summary: '学习了五种环境描写的技法…', time: '3天前', project: '春日迟迟' },
];

export const ConversationsPage: React.FC = () => {
  const push = usePageStackStore(s => s.push);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Navbar */}
      <div style={{
        height: 52, display: 'flex', alignItems: 'center',
        padding: '0 16px', borderBottom: '1px solid var(--border)',
        background: 'var(--bg-card)',
      }}>
        <h1 style={{ fontSize: 18, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>
          对话
        </h1>
      </div>

      {/* 列表 */}
      <div style={{ flex: 1, overflow: 'auto', padding: '8px 16px' }}>
        {CONVERSATIONS.length === 0 ? (
          <div style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center',
            justifyContent: 'center', height: '100%', gap: 12,
            color: 'var(--text-tertiary)',
          }}>
            <MessageCircle size={32} strokeWidth={1.5} />
            <div style={{ fontSize: 14 }}>还没有对话记录</div>
            <div style={{ fontSize: 12 }}>打开项目开始学习吧</div>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {CONVERSATIONS.map(c => (
              <div
                key={c.id}
                onClick={() => push('chat', { id: c.id, title: c.title })}
                style={{
                  display: 'flex', flexDirection: 'column', gap: 4,
                  padding: '12px 0', borderBottom: '1px solid var(--border)',
                  cursor: 'pointer',
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontSize: 14, fontWeight: 500, color: 'var(--text-primary)' }}>{c.title}</span>
                  <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>{c.time}</span>
                </div>
                <div style={{ fontSize: 12, color: 'var(--text-secondary)', lineHeight: 1.4 }}>{c.summary}</div>
                <span style={{ fontSize: 11, color: 'var(--color-teaching)' }}>{c.project}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
