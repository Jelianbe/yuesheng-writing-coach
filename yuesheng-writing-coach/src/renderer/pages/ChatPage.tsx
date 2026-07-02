/**
 * ChatPage — 教学对话
 *
 * 对齐设计稿：
 * - Navbar: ‹ 返回 + 标题 + 副标题 + ⋯
 * - 欢迎引导区（月头像 + 快捷选项）
 * - 消息气泡（用户/诊断教学/AI思考中）
 * - 输入栏（工具条 + 输入框 + 发送按钮）
 */

import React, { useState } from 'react';
import { ArrowLeft, Send, Type, Image, FileText, Settings, MessageSquare } from 'lucide-react';
import { usePageStackStore } from '../stores/page-stack.store';
import { MoreMenu } from '../components/navigation/MoreMenu';

/* ── 欢迎引导区 ── */
const WelcomeGuide: React.FC = () => (
  <div style={{
    display: 'flex', flexDirection: 'column', alignItems: 'center',
    padding: '32px 16px 24px', gap: 16,
  }}>
    {/* 月头像 */}
    <div style={{
      width: 56, height: 56, borderRadius: '50%',
      background: 'linear-gradient(135deg, #8A7A9E, #B8A9D4)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      color: '#fff', fontSize: 22, fontWeight: 700,
    }}>
      月
    </div>
    <div style={{ fontSize: 15, color: 'var(--text-primary)', fontWeight: 500 }}>
      嘿，今天想从哪里开始？
    </div>
    <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', justifyContent: 'center' }}>
      {['分析一下作品', '学点描写技法', '出个题目练练'].map(text => (
        <button
          key={text}
          style={{
            padding: '8px 14px', borderRadius: 20,
            border: '1px solid var(--border)', background: 'var(--bg-card)',
            color: 'var(--text-secondary)', fontSize: 13, cursor: 'pointer',
          }}
        >
          {text}
        </button>
      ))}
    </div>
  </div>
);

/* ── 用户消息气泡 ── */
const UserBubble: React.FC<{ text: string }> = ({ text }) => (
  <div style={{ display: 'flex', justifyContent: 'flex-end', padding: '0 16px 8px' }}>
    <div style={{
      maxWidth: '75%', padding: '10px 14px', borderRadius: 12,
      background: 'var(--accent)', color: '#fff', fontSize: 14,
      lineHeight: 1.5, borderBottomRightRadius: 4,
    }}>
      {text}
    </div>
  </div>
);

/* ── AI 思考中 ── */
const ThinkingIndicator: React.FC = () => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '0 16px 8px' }}>
    <div style={{
      padding: '10px 14px', borderRadius: 12, background: 'var(--bg-card)',
      border: '1px solid var(--border)',
      display: 'flex', alignItems: 'center', gap: 8,
    }}>
      <div style={{ display: 'flex', gap: 3 }}>
        {[0, 1, 2].map(i => (
          <span key={i} style={{
            width: 6, height: 6, borderRadius: '50%',
            background: 'var(--accent)',
            animation: `pulse 1.4s ${i * 0.2}s infinite`,
          }} />
        ))}
      </div>
      <span style={{ fontSize: 13, color: 'var(--text-tertiary)' }}>我整理一下核心问题…</span>
    </div>
  </div>
);

/* ── 诊断教学气泡 ── */
const DiagBubble: React.FC = () => (
  <div style={{ padding: '0 16px 8px' }}>
    <div style={{
      background: 'var(--bg-card)', border: '1px solid var(--border)',
      borderRadius: 12, overflow: 'hidden',
    }}>
      {/* 标签 */}
      <div style={{
        padding: '8px 12px', background: 'var(--accent-light)',
        fontSize: 11, fontWeight: 600, color: 'var(--accent)',
      }}>
        诊断分析
      </div>
      {/* 问题列表 */}
      <div style={{ padding: '10px 12px' }}>
        {[
          { id: 1, text: '主角的行为动机缺乏深层逻辑支撑，导致读者难以产生共情' },
          { id: 2, text: '对话部分过于直白，缺乏潜台词和人物个性的表达' },
          { id: 3, text: '关键情节节点的节奏控制不够，高潮部分铺垫不足' },
        ].map(item => (
          <div key={item.id} style={{
            display: 'flex', gap: 8, padding: '6px 0',
            borderBottom: '1px solid var(--border)',
          }}>
            <span style={{
              width: 20, height: 20, borderRadius: '50%', flexShrink: 0,
              background: 'var(--accent)', color: '#fff', fontSize: 11,
              fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              {item.id}
            </span>
            <span style={{ fontSize: 13, color: 'var(--text-primary)', lineHeight: 1.5 }}>
              {item.text}
            </span>
          </div>
        ))}
      </div>
      {/* 引导按钮 */}
      <div style={{ display: 'flex', gap: 8, padding: '8px 12px 12px' }}>
        <button style={{
          padding: '7px 14px', borderRadius: 20, border: '1px solid var(--accent)',
          background: 'transparent', color: 'var(--accent)', fontSize: 12, cursor: 'pointer',
        }}>
          先看改写示例
        </button>
        <button style={{
          padding: '7px 14px', borderRadius: 20, border: 'none',
          background: 'var(--accent)', color: '#fff', fontSize: 12, cursor: 'pointer',
        }}>
          好，讲讲
        </button>
      </div>
    </div>
  </div>
);

/* ── 输入栏 ── */
const TOOLBAR_ITEMS = [
  { Icon: Type, label: '文字' },
  { Icon: Image, label: '图片' },
  { Icon: FileText, label: '文档' },
  { Icon: Settings, label: '设定' },
];

const InputBar: React.FC = () => {
  const [text, setText] = useState('');
  const hasContent = text.trim().length > 0;

  return (
    <div style={{
      borderTop: '1px solid var(--border)', background: 'var(--bg-card)',
      padding: '8px 12px', paddingBottom: `calc(8px + env(safe-area-inset-bottom, 0px))`,
    }}>
      {/* 工具条 */}
      <div style={{ display: 'flex', gap: 12, marginBottom: 6, paddingLeft: 4 }}>
        {TOOLBAR_ITEMS.map(({ Icon, label }) => (
          <button
            key={label}
            style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4, borderRadius: 6, transition: 'background 150ms' }}
            aria-label={label}
          >
            <Icon size={18} color="var(--text-tertiary)" strokeWidth={1.5} />
          </button>
        ))}
      </div>
      {/* 输入行 */}
      <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
        <input
          value={text}
          onChange={e => setText(e.target.value)}
          placeholder="输入你的问题和作品…"
          style={{
            flex: 1, height: 38, borderRadius: 8, border: 'none',
            background: 'var(--bg-input)', padding: '0 12px',
            fontSize: 13, color: 'var(--text-primary)', outline: 'none',
          }}
        />
        <button
          style={{
            width: 38, height: 38, borderRadius: 8, border: 'none',
            background: hasContent ? 'var(--accent)' : 'var(--bg-input)',
            color: hasContent ? '#fff' : 'var(--text-tertiary)',
            cursor: hasContent ? 'pointer' : 'default',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            transition: 'all 200ms',
          }}
          aria-label="发送"
        >
          <Send size={16} />
        </button>
      </div>
    </div>
  );
};

/* ── 主组件 ── */
export const ChatPage: React.FC<{ params?: Record<string, string> }> = ({ params }) => {
  const pop = usePageStackStore(s => s.pop);
  const push = usePageStackStore(s => s.push);
  const title = params?.title ?? '深海回响';

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Navbar */}
      <div style={{
        height: 52, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 12px', borderBottom: '1px solid var(--border)',
        background: 'var(--bg-card)', flexShrink: 0,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
          <button onClick={pop} style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4 }}>
            <ArrowLeft size={20} color="var(--text-primary)" strokeWidth={1.5} />
          </button>
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            <span style={{ fontSize: 15, fontWeight: 600, color: 'var(--text-primary)', lineHeight: 1.3 }}>
              {title}
            </span>
            <span style={{ fontSize: 11, color: 'var(--color-teaching)' }}>
              人物动机学习 · 进行中
            </span>
          </div>
        </div>
        <MoreMenu options={[
          { label: '新建对话', icon: <MessageSquare size={16} />, onClick: () => push('chat', { title }) },
          { label: '对话配置', icon: <Settings size={16} />, onClick: () => {/* Phase C: 对话配置面板 */} },
        ]} />
      </div>

      {/* 消息区 */}
      <div style={{
        flex: 1, overflow: 'auto', display: 'flex', flexDirection: 'column',
        paddingTop: 8,
      }}>
        {/* 欢迎引导 */}
        <WelcomeGuide />

        {/* 消息列表 */}
        <UserBubble text="老师，我写的对话总觉得不自然，能帮我看看吗？" />
        <ThinkingIndicator />
        <DiagBubble />
        <UserBubble text="分析的很有道理，能教教我怎么改吗？" />

        {/* 底部占位 */}
        <div style={{ height: 8 }} />
      </div>

      {/* 输入栏 */}
      <InputBar />
    </div>
  );
};
