/**
 * BookshelfPage — 书架首页
 *
 * 对齐设计稿暖紫体系:
 * - Navbar: "书架" + 🔍/➕
 * - 书卡(渐变色封面 + 书名 + 元数据 + 成长指示)
 * - 虚线新建按钮
 *
 * 数据来源:useManuscriptStore (真实 manuscripts 表)
 */

import React, { useEffect, useState } from 'react';
import { Search, Plus, Book, X } from 'lucide-react';
import { useShallow } from 'zustand/react/shallow';
import { usePageStackStore } from '../stores/page-stack.store';
import { useManuscriptStore } from '../stores/manuscript.store';

const COVER_W = 46;
const COVER_H = 60;

/** 根据 genre/title 衍生稳定颜色 hash */
const colorFromString = (s: string): string => {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  const hue = Math.abs(h) % 360;
  return `linear-gradient(135deg, hsl(${hue}, 35%, 55%), hsl(${(hue + 30) % 360}, 45%, 75%))`;
};

export const BookshelfPage: React.FC = () => {
  const push = usePageStackStore(s => s.push);
  const { manuscripts, loading, error, fetchList, create } = useManuscriptStore(
    useShallow(s => ({
      manuscripts: s.manuscripts,
      loading: s.loading,
      error: s.error,
      fetchList: s.fetchList,
      create: s.create,
    })),
  );
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');

  useEffect(() => {
    void fetchList();
  }, [fetchList]);

  const handleCreate = async () => {
    // Electron 28+ 不支 window.prompt（存在但调用时抛异常），直接用默认名创建
    await create('未命名作品');
  };

  const filtered = searchQuery.trim()
    ? manuscripts.filter(m =>
        m.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
        (m.genre || '').toLowerCase().includes(searchQuery.toLowerCase()),
      )
    : manuscripts;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Navbar */}
      <header style={{
        height: 52, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 16px', borderBottom: '1px solid var(--border)', flexShrink: 0,
        background: 'var(--bg-card)',
      }}>
        <h1 style={{ fontSize: 18, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>
          书架
        </h1>
        <div style={{ display: 'flex', gap: 12 }}>
          <button
            type="button"
            aria-label="搜索"
            onClick={() => { setSearchOpen(!searchOpen); setSearchQuery(''); }}
            style={{ border: 'none', background: 'none', padding: 4, cursor: 'pointer', display: 'flex' }}
          >
            <Search size={20} color={searchOpen ? 'var(--accent)' : 'var(--text-secondary)'} strokeWidth={1.5} />
          </button>
          <button
            type="button"
            aria-label="新建作品"
            onClick={handleCreate}
            style={{ border: 'none', background: 'none', padding: 4, cursor: 'pointer', display: 'flex' }}
          >
            <Plus size={20} color="var(--text-secondary)" strokeWidth={1.5} />
          </button>
        </div>
      </header>

      {/* 搜索栏 */}
      {searchOpen && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          padding: '8px 16px', borderBottom: '1px solid var(--border)',
          background: 'var(--bg-card)', flexShrink: 0,
        }}>
          <Search size={16} color="var(--text-tertiary)" />
          <input
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
            placeholder="搜索作品名或类型…"
            autoFocus
            style={{
              flex: 1, height: 32, border: 'none', background: 'transparent',
              fontSize: 13, color: 'var(--text-primary)', outline: 'none',
            }}
          />
          {searchQuery && (
            <button
              onClick={() => setSearchQuery('')}
              aria-label="清除"
              style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 2, display: 'flex' }}
            >
              <X size={16} color="var(--text-tertiary)" />
            </button>
          )}
        </div>
      )}

      {/* 内容区 */}
      <div style={{ flex: 1, overflow: 'auto', padding: '16px 16px 8px' }}>
        {error && (
          <div style={{ padding: 12, marginBottom: 12, borderRadius: 8, background: 'var(--error-light)', color: 'var(--error)', fontSize: 12 }}>
            {error}
          </div>
        )}

        {loading && manuscripts.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>
            加载中…
          </div>
        ) : filtered.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>
            {searchQuery ? `未找到匹配"${searchQuery}"的作品` : '暂无作品,点击下方按钮创建'}
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {filtered.map(m => (
              <button
                key={m.id}
                type="button"
                onClick={() => push('project-space', { id: m.projectId ?? m.id, title: m.title })}
                style={{
                  display: 'flex', gap: 12, padding: 12,
                  background: 'var(--bg-card)', borderRadius: 12,
                  border: '1px solid var(--border)',
                  cursor: 'pointer', textAlign: 'left',
                  transition: 'box-shadow 200ms',
                  color: 'inherit',
                  font: 'inherit',
                }}
              >
                {/* 封面 */}
                <div style={{
                  width: COVER_W, height: COVER_H, borderRadius: 6, flexShrink: 0,
                  background: colorFromString(m.genre || m.title),
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>
                  <Book size={20} color="var(--text-on-accent-muted)" />
                </div>

                {/* 信息 */}
                <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: 4 }}>
                  <div style={{ fontSize: 15, fontWeight: 600, color: 'var(--text-primary)' }}>{m.title}</div>
                  <div style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>
                    {m.genre || '未分类'}
                  </div>
                </div>
              </button>
            ))}
          </div>
        )}

        {/* 新建按钮 */}
        <button
          type="button"
          onClick={handleCreate}
          style={{
            marginTop: 12, padding: '14px 0', width: '100%',
            border: '1.5px dashed var(--border)',
            borderRadius: 12, textAlign: 'center',
            color: 'var(--text-tertiary)', fontSize: 13,
            cursor: 'pointer', background: 'transparent',
            font: 'inherit',
          }}
        >
          + 新建学习项目
        </button>
      </div>
    </div>
  );
};
