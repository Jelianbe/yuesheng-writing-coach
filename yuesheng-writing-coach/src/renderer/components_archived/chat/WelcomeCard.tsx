/**
 * WelcomeCard — 欢迎卡片（未配置 API Key 时显示）
 *
 * 从 ChatView 拆分出的纯展示组件，
 * 在用户未配置 API Key 且无历史消息时显示引导信息。
 */

import React from 'react';

export const WelcomeCard: React.FC = () => {
  return (
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      height: '100%',
      padding: '40px 20px',
      textAlign: 'center',
    }}>
      <div style={{
        width: 64,
        height: 64,
        borderRadius: 16,
        background: 'var(--bg-card)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        marginBottom: 24,
        fontSize: 28,
        boxShadow: '0 2px 8px rgba(0,0,0,0.06)',
      }}>
        ⚙️
      </div>
      <div style={{
        fontSize: '1.25rem',
        fontWeight: 600,
        color: 'var(--text-primary)',
        marginBottom: 12,
      }}>
        欢迎使用月笙
      </div>
      <div style={{
        fontSize: '0.9rem',
        color: 'var(--text-secondary)',
        marginBottom: 8,
        maxWidth: 320,
        lineHeight: 1.6,
      }}>
        请先配置 API Key 开始写作旅程
      </div>
      <div style={{
        fontSize: '0.8rem',
        color: 'var(--text-tertiary)',
      }}>
        点击右下角齿轮图标打开设置
      </div>
    </div>
  );
};
