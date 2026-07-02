/**
 * BookshelfPage — 书架首页
 *
 * 对齐设计稿暖紫体系：
 * - Navbar: "书架" + 🔍/➕
 * - 书卡（渐变色封面 + 书名 + 元数据 + 成长指示）
 * - 虚线新建按钮
 */

import React from 'react';
import { Search, Plus, Book } from 'lucide-react';
import { usePageStackStore } from '../stores/page-stack.store';

const BOOKS = [
  { id: '1', title: '深海回响', chapters: 12, words: '4.2w', growth: 3, gradient: 'linear-gradient(135deg, #8A7A9E, #B8A9D4)' },
  { id: '2', title: '星尘之旅', chapters: 8, words: '2.8w', growth: 2, gradient: 'linear-gradient(135deg, #7A93AC, #A8C4D8)' },
  { id: '3', title: '春日迟迟', chapters: 6, words: '1.5w', growth: 1, gradient: 'linear-gradient(135deg, #7BA089, #A8D4B8)' },
];

const COVER_W = 46;
const COVER_H = 60;

export const BookshelfPage: React.FC = () => {
  const push = usePageStackStore(s => s.push);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Navbar */}
      <div style={{
        height: 52, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 16px', borderBottom: '1px solid var(--border)', flexShrink: 0,
        background: 'var(--bg-card)',
      }}>
        <h1 style={{ fontSize: 18, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>
          书架
        </h1>
        <div style={{ display: 'flex', gap: 12 }}>
          <Search size={20} color="var(--text-secondary)" style={{ cursor: 'pointer' }} strokeWidth={1.5} />
          <Plus size={20} color="var(--text-secondary)" style={{ cursor: 'pointer' }} strokeWidth={1.5} />
        </div>
      </div>

      {/* 内容区 */}
      <div style={{ flex: 1, overflow: 'auto', padding: '16px 16px 8px' }}>
        {/* 书卡列表 */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {BOOKS.map(book => (
            <div
              key={book.id}
              onClick={() => push('project-space', { id: book.id, title: book.title })}
              style={{
                display: 'flex', gap: 12, padding: 12,
                background: 'var(--bg-card)', borderRadius: 12,
                border: '1px solid var(--border)',
                cursor: 'pointer', transition: 'box-shadow 200ms',
              }}
            >
              {/* 封面 */}
              <div style={{
                width: COVER_W, height: COVER_H, borderRadius: 6, flexShrink: 0,
                background: book.gradient,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <Book size={20} color="rgba(255,255,255,0.7)" />
              </div>

              {/* 信息 */}
              <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: 4 }}>
                <div style={{ fontSize: 15, fontWeight: 600, color: 'var(--text-primary)' }}>{book.title}</div>
                <div style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>
                  {book.chapters} 章 · {book.words} 字
                </div>
                {/* 成长指示点 */}
                <div style={{ display: 'flex', gap: 4, marginTop: 2 }}>
                  {Array.from({ length: 5 }).map((_, i) => (
                    <div key={i} style={{
                      width: 6, height: 6, borderRadius: '50%',
                      background: i < book.growth ? 'var(--color-growth)' : 'var(--border)',
                    }} />
                  ))}
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* 新建按钮 */}
        <div style={{
          marginTop: 12, padding: '14px 0',
          border: '1.5px dashed var(--border)',
          borderRadius: 12, textAlign: 'center',
          color: 'var(--text-tertiary)', fontSize: 13,
          cursor: 'pointer',
        }}>
          + 新建学习项目
        </div>
      </div>
    </div>
  );
};
