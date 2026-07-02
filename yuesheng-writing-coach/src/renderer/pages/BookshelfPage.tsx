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

import React, { useEffect } from 'react';
import { Search, Plus, Book } from 'lucide-react';
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

  useEffect(() => {
    void fetchList();
  }, [fetchList]);

  const handleCreate = async () => {
    const title = window.prompt('新作品名称', '未命名作品')?.trim();
    if (!title) return;
    await create(title);
  };

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
            style={{ border: 'none', background: 'none', padding: 4, cursor: 'pointer', display: 'flex' }}
          >
            <Search size={20} color="var(--text-secondary)" strokeWidth={1.5} />
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
        ) : manuscripts.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>
            暂无作品,点击下方按钮创建
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {manuscripts.map(m => (
              <button
                key={m.id}
                type="button"
                onClick={() => push('project-space', { id: m.id, title: m.title })}
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
                  <Book size={20} color="rgba(255,255,255,0.7)" />
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
