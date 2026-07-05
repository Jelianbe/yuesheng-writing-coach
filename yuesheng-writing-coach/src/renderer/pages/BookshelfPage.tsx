/**
 * BookshelfPage — 书架首页（Sprint 39 增强版）
 *
 * - Navbar: "书架" + 🔍/➕
 * - 书卡: 渐变色封面 + 书名 + 类型 + 菜单(⋮)
 * - 新建弹窗: 名称 + 类型 + 描述
 * - 卡片操作: 重命名 / 编辑详情 / 删除 / 进入作品详情
 */
import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Search, Plus, Book, X, MoreVertical, Edit3, Trash2, FileText } from 'lucide-react';
import { useShallow } from 'zustand/react/shallow';
import { usePageStackStore } from '../stores/page-stack.store';
import { useManuscriptStore } from '../stores/manuscript.store';

const COVER_W = 46;
const COVER_H = 60;

const colorFromString = (s: string): string => {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  const hue = Math.abs(h) % 360;
  return `linear-gradient(135deg, hsl(${hue}, 35%, 55%), hsl(${(hue + 30) % 360}, 45%, 75%))`;
};

/** 新建/编辑弹窗 */
const WorkFormDialog: React.FC<{
  mode: 'create' | 'edit';
  initialName?: string;
  initialGenre?: string;
  initialDesc?: string;
  onConfirm: (name: string, genre: string, desc: string) => void;
  onCancel: () => void;
}> = ({ mode, initialName, initialGenre, initialDesc, onConfirm, onCancel }) => {
  const [name, setName] = useState(initialName ?? '');
  const [genre, setGenre] = useState(initialGenre ?? '');
  const [desc, setDesc] = useState(initialDesc ?? '');
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => { inputRef.current?.focus(); }, []);

  return (
    <div style={{
      position: 'fixed', inset: 0, zIndex: 100,
      background: 'rgba(0,0,0,0.4)', display: 'flex',
      alignItems: 'center', justifyContent: 'center',
      padding: 24,
    }} onClick={onCancel}>
      <div style={{
        background: 'var(--bg-card)', borderRadius: 16, padding: 20,
        width: '100%', maxWidth: 320, boxShadow: '0 8px 32px rgba(0,0,0,0.15)',
      }} onClick={e => e.stopPropagation()}>
        <h3 style={{ margin: '0 0 16px', fontSize: 16, fontWeight: 600, color: 'var(--text-primary)' }}>
          {mode === 'create' ? '新建作品' : '编辑作品'}
        </h3>
        <input
          ref={inputRef}
          value={name}
          onChange={e => setName(e.target.value)}
          placeholder="作品名称 *"
          style={{
            width: '100%', padding: '10px 12px', borderRadius: 8,
            border: '1px solid var(--border)', background: 'var(--bg-main)',
            color: 'var(--text-primary)', fontSize: 14, outline: 'none',
            boxSizing: 'border-box', marginBottom: 8,
          }}
        />
        <input
          value={genre}
          onChange={e => setGenre(e.target.value)}
          placeholder="类型（可选）"
          style={{
            width: '100%', padding: '10px 12px', borderRadius: 8,
            border: '1px solid var(--border)', background: 'var(--bg-main)',
            color: 'var(--text-primary)', fontSize: 14, outline: 'none',
            boxSizing: 'border-box', marginBottom: 8,
          }}
        />
        <textarea
          value={desc}
          onChange={e => setDesc(e.target.value)}
          placeholder="描述（可选）"
          rows={3}
          style={{
            width: '100%', padding: '10px 12px', borderRadius: 8,
            border: '1px solid var(--border)', background: 'var(--bg-main)',
            color: 'var(--text-primary)', fontSize: 14, outline: 'none', resize: 'none',
            boxSizing: 'border-box', marginBottom: 16,
          }}
        />
        <div style={{ display: 'flex', gap: 8 }}>
          <button onClick={onCancel} style={{
            flex: 1, padding: '10px 0', borderRadius: 8,
            border: '1px solid var(--border)', background: 'transparent',
            color: 'var(--text-secondary)', fontSize: 14, cursor: 'pointer',
            font: 'inherit',
          }}>取消</button>
          <button onClick={() => onConfirm(name.trim(), genre.trim(), desc.trim())}
            disabled={!name.trim()}
            style={{
              flex: 1, padding: '10px 0', borderRadius: 8,
              border: 'none', background: !name.trim() ? 'var(--border)' : 'var(--accent)',
              color: !name.trim() ? 'var(--text-tertiary)' : 'var(--text-on-accent)',
              fontSize: 14, cursor: !name.trim() ? 'not-allowed' : 'pointer',
              font: 'inherit',
            }}
          >{mode === 'create' ? '创建' : '保存'}</button>
        </div>
      </div>
    </div>
  );
};

export const BookshelfPage: React.FC = () => {
  const push = usePageStackStore(s => s.push);
  const { manuscripts, loading, error, fetchList, create, update, remove } = useManuscriptStore(
    useShallow(s => ({
      manuscripts: s.manuscripts,
      loading: s.loading,
      error: s.error,
      fetchList: s.fetchList,
      create: s.create,
      update: s.update,
      remove: s.remove,
    })),
  );
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [editingManuscript, setEditingManuscript] = useState<{ id: string; title: string; genre: string; description: string } | null>(null);
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameValue, setRenameValue] = useState('');
  const [menuOpenId, setMenuOpenId] = useState<string | null>(null);
  const menuRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => { void fetchList(); }, [fetchList]);

  // 点击菜单外部关闭
  useEffect(() => {
    if (!menuOpenId) return;
    const handler = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setMenuOpenId(null);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [menuOpenId]);

  const handleCreate = useCallback(async (name: string, genre: string, desc: string) => {
    await create(name, desc, genre || undefined);
    setShowCreate(false);
  }, [create]);

  const handleDelete = useCallback(async (id: string) => {
    setMenuOpenId(null);
    await remove(id);
  }, [remove]);

  const handleRename = useCallback(async (id: string) => {
    setMenuOpenId(null);
    const m = manuscripts.find(x => x.id === id);
    if (!m) return;
    setRenameValue(m.title);
    setRenamingId(id);
  }, [manuscripts]);

  const confirmRename = useCallback(async () => {
    if (!renamingId || !renameValue.trim()) return;
    await update(renamingId, { title: renameValue.trim() });
    setRenamingId(null);
    setRenameValue('');
  }, [renamingId, renameValue, update]);

  const handleEdit = useCallback((id: string) => {
    setMenuOpenId(null);
    const m = manuscripts.find(x => x.id === id);
    if (!m) return;
    setEditingManuscript({ id: m.id, title: m.title, genre: m.genre, description: m.description });
  }, [manuscripts]);

  const confirmEdit = useCallback(async (name: string, genre: string, desc: string) => {
    if (!editingManuscript) return;
    await update(editingManuscript.id, { title: name, genre, description: desc });
    setEditingManuscript(null);
  }, [editingManuscript, update]);

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
          <button type="button" aria-label="搜索"
            onClick={() => { setSearchOpen(!searchOpen); setSearchQuery(''); }}
            style={{ border: 'none', background: 'none', padding: 4, cursor: 'pointer', display: 'flex' }}
          >
            <Search size={20} color={searchOpen ? 'var(--accent)' : 'var(--text-secondary)'} strokeWidth={1.5} />
          </button>
          <button type="button" aria-label="新建作品"
            onClick={() => setShowCreate(true)}
            style={{ border: 'none', background: 'none', padding: 4, cursor: 'pointer', display: 'flex' }}
          >
            <Plus size={20} color="var(--text-secondary)" strokeWidth={1.5} />
          </button>
        </div>
      </header>

      {/* 搜索栏 */}
      {searchOpen && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8, padding: '8px 16px',
          borderBottom: '1px solid var(--border)', background: 'var(--bg-card)', flexShrink: 0,
        }}>
          <Search size={16} color="var(--text-tertiary)" />
          <input value={searchQuery} onChange={e => setSearchQuery(e.target.value)}
            placeholder="搜索作品名或类型…" autoFocus
            style={{
              flex: 1, height: 32, border: 'none', background: 'transparent',
              fontSize: 13, color: 'var(--text-primary)', outline: 'none',
            }}
          />
          {searchQuery && (
            <button onClick={() => setSearchQuery('')} aria-label="清除"
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
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>加载中…</div>
        ) : filtered.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>
            {searchQuery ? `未找到匹配"${searchQuery}"的作品` : '暂无作品,点击右上角 + 创建'}
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {filtered.map(m => (
              <div key={m.id} style={{ position: 'relative' }}>
                {/* 重命名模式 */}
                {renamingId === m.id ? (
                  <div style={{
                    display: 'flex', gap: 8, padding: 12,
                    background: 'var(--bg-card)', borderRadius: 12,
                    border: '1px solid var(--accent)',
                  }}>
                    <input value={renameValue} onChange={e => setRenameValue(e.target.value)}
                      autoFocus onKeyDown={e => { if (e.key === 'Enter') void confirmRename(); if (e.key === 'Escape') setRenamingId(null); }}
                      style={{
                        flex: 1, padding: '6px 10px', borderRadius: 6,
                        border: '1px solid var(--border)', background: 'var(--bg-main)',
                        color: 'var(--text-primary)', fontSize: 14, outline: 'none',
                      }}
                    />
                    <button onClick={confirmRename} style={{
                      padding: '6px 12px', borderRadius: 6, border: 'none',
                      background: 'var(--accent)', color: 'var(--text-on-accent)',
                      fontSize: 12, cursor: 'pointer', font: 'inherit',
                    }}>确定</button>
                    <button onClick={() => setRenamingId(null)} style={{
                      padding: '6px 12px', borderRadius: 6, border: '1px solid var(--border)',
                      background: 'transparent', color: 'var(--text-secondary)',
                      fontSize: 12, cursor: 'pointer', font: 'inherit',
                    }}>取消</button>
                  </div>
                ) : (
                  <div style={{
                    display: 'flex', gap: 12, padding: 12,
                    background: 'var(--bg-card)', borderRadius: 12,
                    border: '1px solid var(--border)', cursor: 'pointer',
                    transition: 'box-shadow 200ms',
                  }}>
                    {/* 封面 — 点击进入作品详情 */}
                    <div onClick={() => push('work-detail', { id: m.id, title: m.title })}
                      style={{
                        width: COVER_W, height: COVER_H, borderRadius: 6, flexShrink: 0,
                        background: colorFromString(m.genre || m.title),
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                      }}
                    >
                      <Book size={20} color="var(--text-on-accent-muted)" />
                    </div>

                    {/* 信息 — 点击进入项目空间 */}
                    <div onClick={() => push('project-space', { id: m.projectId ?? m.id, title: m.title })}
                      style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: 4, minWidth: 0 }}
                    >
                      <div style={{ fontSize: 15, fontWeight: 600, color: 'var(--text-primary)' }}>{m.title}</div>
                      <div style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>{m.genre || '未分类'}</div>
                    </div>

                    {/* 操作菜单按钮 */}
                    <button onClick={e => { e.stopPropagation(); setMenuOpenId(menuOpenId === m.id ? null : m.id); }}
                      style={{ border: 'none', background: 'none', padding: 4, cursor: 'pointer', display: 'flex', alignSelf: 'center', color: 'var(--text-tertiary)' }}
                    >
                      <MoreVertical size={18} strokeWidth={1.5} />
                    </button>

                    {/* 下拉菜单 */}
                    {menuOpenId === m.id && (
                      <div ref={menuRef} style={{
                        position: 'absolute', right: 8, top: 48, zIndex: 10,
                        background: 'var(--bg-card)', border: '1px solid var(--border)',
                        borderRadius: 10, boxShadow: '0 4px 16px rgba(0,0,0,0.12)',
                        overflow: 'hidden', minWidth: 140,
                      }}>
                        <button onClick={() => handleRename(m.id)} style={{
                          display: 'flex', alignItems: 'center', gap: 8, width: '100%',
                          padding: '10px 14px', border: 'none', background: 'transparent',
                          color: 'var(--text-primary)', fontSize: 13, cursor: 'pointer',
                          font: 'inherit', textAlign: 'left',
                        }}>
                          <Edit3 size={14} strokeWidth={1.5} /> 重命名
                        </button>
                        <button onClick={() => handleEdit(m.id)} style={{
                          display: 'flex', alignItems: 'center', gap: 8, width: '100%',
                          padding: '10px 14px', border: 'none', background: 'transparent',
                          color: 'var(--text-primary)', fontSize: 13, cursor: 'pointer',
                          font: 'inherit', textAlign: 'left',
                        }}>
                          <FileText size={14} strokeWidth={1.5} /> 编辑详情
                        </button>
                        <button onClick={() => push('work-detail', { id: m.id, title: m.title })} style={{
                          display: 'flex', alignItems: 'center', gap: 8, width: '100%',
                          padding: '10px 14px', border: 'none', background: 'transparent',
                          color: 'var(--text-primary)', fontSize: 13, cursor: 'pointer',
                          font: 'inherit', textAlign: 'left', borderTop: '1px solid var(--border)',
                        }}>
                          <FileText size={14} strokeWidth={1.5} /> 作品详情
                        </button>
                        <button onClick={() => { if (confirm('确定删除「' + m.title + '」？')) void handleDelete(m.id); }}
                          style={{
                            display: 'flex', alignItems: 'center', gap: 8, width: '100%',
                            padding: '10px 14px', border: 'none', background: 'transparent',
                            color: 'var(--error)', fontSize: 13, cursor: 'pointer',
                            font: 'inherit', textAlign: 'left', borderTop: '1px solid var(--border)',
                          }}
                        >
                          <Trash2 size={14} strokeWidth={1.5} /> 删除
                        </button>
                      </div>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* 新建弹窗 */}
      {showCreate && (
        <WorkFormDialog mode="create" onConfirm={handleCreate} onCancel={() => setShowCreate(false)} />
      )}

      {/* 编辑弹窗 */}
      {editingManuscript && (
        <WorkFormDialog
          mode="edit"
          initialName={editingManuscript.title}
          initialGenre={editingManuscript.genre}
          initialDesc={editingManuscript.description}
          onConfirm={confirmEdit}
          onCancel={() => setEditingManuscript(null)}
        />
      )}
    </div>
  );
};
