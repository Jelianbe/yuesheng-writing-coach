/**
 * WorkDetailPage — 作品详情页（Sprint 39）
 *
 * 展示作品元数据、统计信息、章节列表，支持编辑元数据和管理章节。
 */
import React, { useCallback, useEffect, useState } from 'react';
import { ArrowLeft, Book, Edit3, Plus, Trash2, FileText, MessageSquare, BarChart3 } from 'lucide-react';
import { useShallow } from 'zustand/react/shallow';
import { usePageStackStore } from '../stores/page-stack.store';
import { useManuscriptStore } from '../stores/manuscript.store';
import { useChapterStore } from '../stores/chapter.store';
import { serviceBridge } from '../services/service-bridge';
import type { Manuscript } from '../shared/types';

interface ManuscriptStats {
  chapterCount: number;
  totalWordCount: number;
  sessionCount: number;
  trainingCount: number;
}

const SectionTitle: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <h3 style={{ fontSize: 14, fontWeight: 600, color: 'var(--text-primary)', margin: '16px 0 8px' }}>{children}</h3>
);

const StatCard: React.FC<{ label: string; value: string | number; icon: React.ReactNode }> = ({ label, value, icon }) => (
  <div style={{
    flex: 1, padding: '10px 12px', background: 'var(--bg-main)', borderRadius: 10,
    display: 'flex', alignItems: 'center', gap: 10, minWidth: 0,
  }}>
    <div style={{ color: 'var(--text-tertiary)', flexShrink: 0 }}>{icon}</div>
    <div style={{ minWidth: 0 }}>
      <div style={{ fontSize: 16, fontWeight: 700, color: 'var(--text-primary)' }}>{value}</div>
      <div style={{ fontSize: 11, color: 'var(--text-tertiary)', whiteSpace: 'nowrap' }}>{label}</div>
    </div>
  </div>
);

export const WorkDetailPage: React.FC<{ params?: Record<string, string> }> = ({ params }) => {
  const push = usePageStackStore(s => s.push);
  const pop = usePageStackStore(s => s.pop);
  const manuscriptId = params?.id ?? '';

  const { manuscripts, update } = useManuscriptStore(
    useShallow(s => ({ manuscripts: s.manuscripts, update: s.update })),
  );
  const { chapters, fetchByWork, createChapter, deleteChapter } = useChapterStore(
    useShallow(s => ({
      chapters: s.chapters, fetchByWork: s.fetchByWork,
      createChapter: s.createChapter, deleteChapter: s.deleteChapter,
    })),
  );

  const [stats, setStats] = useState<ManuscriptStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [showEdit, setShowEdit] = useState(false);
  const [editName, setEditName] = useState('');
  const [editGenre, setEditGenre] = useState('');
  const [editDesc, setEditDesc] = useState('');
  const [newChapterTitle, setNewChapterTitle] = useState('');

  const manuscript: Manuscript | undefined = manuscripts.find(m => m.id === manuscriptId);

  // 加载数据
  useEffect(() => {
    if (!manuscriptId) return;
    setLoading(true);
    void Promise.all([
      fetchByWork(manuscriptId),
      serviceBridge.invoke<{ id: string }, ManuscriptStats>('manuscript:stats', { id: manuscriptId }),
    ]).then(([_, s]) => {
      if (s) setStats(s);
      setLoading(false);
    });
  }, [manuscriptId, fetchByWork]);

  const handleEdit = useCallback(() => {
    if (!manuscript) return;
    setEditName(manuscript.title);
    setEditGenre(manuscript.genre);
    setEditDesc(manuscript.description);
    setShowEdit(true);
  }, [manuscript]);

  const confirmEdit = useCallback(async () => {
    if (!manuscriptId || !editName.trim()) return;
    await update(manuscriptId, { title: editName.trim(), genre: editGenre.trim(), description: editDesc.trim() });
    setShowEdit(false);
  }, [manuscriptId, editName, editGenre, editDesc, update]);

  const handleAddChapter = useCallback(async () => {
    if (!manuscriptId || !newChapterTitle.trim()) return;
    await createChapter(manuscriptId, newChapterTitle.trim());
    setNewChapterTitle('');
  }, [manuscriptId, newChapterTitle, createChapter]);

  const handleDeleteChapter = useCallback(async (id: string, title: string) => {
    if (!confirm('确定删除章节「' + title + '」？')) return;
    await deleteChapter(id, manuscriptId);
  }, [manuscriptId, deleteChapter]);

  if (!manuscriptId) {
    return <div style={{ padding: 20, color: 'var(--text-tertiary)' }}>未指定作品</div>;
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Header */}
      <header style={{
        height: 52, display: 'flex', alignItems: 'center', gap: 8,
        padding: '0 12px', borderBottom: '1px solid var(--border)',
        background: 'var(--bg-card)', flexShrink: 0,
      }}>
        <button aria-label="返回" onClick={() => pop()} style={{
          border: 'none', background: 'none', padding: 4, cursor: 'pointer', display: 'flex',
        }}>
          <ArrowLeft size={20} color="var(--text-secondary)" strokeWidth={1.5} />
        </button>
        <h1 style={{
          flex: 1, fontSize: 17, fontWeight: 600, color: 'var(--text-primary)',
          margin: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
        }}>
          {manuscript?.title ?? '作品详情'}
        </h1>
        <button aria-label="编辑作品" onClick={handleEdit} style={{
          border: 'none', background: 'none', padding: 4, cursor: 'pointer', display: 'flex',
        }}>
          <Edit3 size={18} color="var(--text-secondary)" strokeWidth={1.5} />
        </button>
        <button aria-label="作品统计" onClick={() => push('project-space', { id: manuscript?.projectId ?? manuscriptId, title: manuscript?.title ?? '' })}
          style={{
            border: 'none', background: 'none', padding: 4, cursor: 'pointer', display: 'flex',
          }}
        >
          <BarChart3 size={18} color="var(--text-secondary)" strokeWidth={1.5} />
        </button>
      </header>

      {/* Content */}
      <div style={{ flex: 1, overflow: 'auto', padding: '16px' }}>
        {loading ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>加载中…</div>
        ) : !manuscript ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>作品不存在</div>
        ) : (
          <>
            {/* 元数据 */}
            {manuscript.description && (
              <p style={{ fontSize: 13, color: 'var(--text-secondary)', margin: '0 0 4px', lineHeight: 1.5 }}>
                {manuscript.description}
              </p>
            )}
            <p style={{ fontSize: 12, color: 'var(--text-tertiary)', margin: '0 0 12px' }}>
              <span>{manuscript.genre || '未分类'}</span> · 创建于 {new Date(manuscript.created_at * 1000).toLocaleDateString()}
            </p>

            {/* 统计卡片 */}
            <SectionTitle>统计概览</SectionTitle>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              <StatCard label="章节" value={stats?.chapterCount ?? 0} icon={<FileText size={16} />} />
              <StatCard label="总字数" value={(stats?.totalWordCount ?? 0).toLocaleString()} icon={<Book size={16} />} />
              <StatCard label="对话" value={stats?.sessionCount ?? 0} icon={<MessageSquare size={16} />} />
              <StatCard label="训练" value={stats?.trainingCount ?? 0} icon={<BarChart3 size={16} />} />
            </div>

            {/* 章节列表 */}
            <SectionTitle>章节管理</SectionTitle>

            {/* 新增章节 */}
            <div style={{ display: 'flex', gap: 8, marginBottom: 8 }}>
              <input value={newChapterTitle} onChange={e => setNewChapterTitle(e.target.value)}
                placeholder="章节名称…"
                onKeyDown={e => { if (e.key === 'Enter') void handleAddChapter(); }}
                style={{
                  flex: 1, padding: '8px 12px', borderRadius: 8,
                  border: '1px solid var(--border)', background: 'var(--bg-main)',
                  color: 'var(--text-primary)', fontSize: 13, outline: 'none',
                }}
              />
              <button aria-label="添加章节" onClick={handleAddChapter} disabled={!newChapterTitle.trim()}
                style={{
                  padding: '8px 14px', borderRadius: 8, border: 'none',
                  background: !newChapterTitle.trim() ? 'var(--border)' : 'var(--accent)',
                  color: !newChapterTitle.trim() ? 'var(--text-tertiary)' : 'var(--text-on-accent)',
                  fontSize: 13, cursor: !newChapterTitle.trim() ? 'not-allowed' : 'pointer',
                  display: 'flex', alignItems: 'center', gap: 4, font: 'inherit',
                }}
              >
                <Plus size={14} strokeWidth={2} /> 添加
              </button>
            </div>

            {/* 章节列表 */}
            {chapters.length === 0 ? (
              <div style={{ padding: 20, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>
                暂无章节，在上方添加
              </div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                {chapters.map((ch, idx) => (
                  <div key={ch.id} style={{
                    display: 'flex', alignItems: 'center', gap: 8, padding: '10px 12px',
                    background: 'var(--bg-card)', borderRadius: 10,
                    border: '1px solid var(--border)',
                  }}>
                    <div style={{
                      width: 22, height: 22, borderRadius: '50%',
                      background: 'var(--bg-main)', display: 'flex', alignItems: 'center',
                      justifyContent: 'center', fontSize: 11, color: 'var(--text-tertiary)', flexShrink: 0,
                    }}>
                      {idx + 1}
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-primary)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                        {ch.title}
                      </div>
                      <div style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>
                        <span>{(Number((ch as unknown as Record<string, unknown>).wordCount ?? ch.word_count ?? 0)).toLocaleString()}</span> 字
                      </div>
                    </div>
                    <button aria-label={`删除章节 ${ch.title}`} onClick={() => handleDeleteChapter(ch.id, ch.title)}
                      style={{
                        border: 'none', background: 'none', padding: 4, cursor: 'pointer',
                        display: 'flex', color: 'var(--text-tertiary)', flexShrink: 0,
                      }}
                    >
                      <Trash2 size={14} strokeWidth={1.5} />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </div>

      {/* 编辑弹窗 */}
      {showEdit && (
        <div style={{
          position: 'fixed', inset: 0, zIndex: 100,
          background: 'rgba(0,0,0,0.4)', display: 'flex',
          alignItems: 'center', justifyContent: 'center', padding: 24,
        }} onClick={() => setShowEdit(false)}>
          <div style={{
            background: 'var(--bg-card)', borderRadius: 16, padding: 20,
            width: '100%', maxWidth: 320, boxShadow: '0 8px 32px rgba(0,0,0,0.15)',
          }} onClick={e => e.stopPropagation()}>
            <h3 style={{ margin: '0 0 16px', fontSize: 16, fontWeight: 600, color: 'var(--text-primary)' }}>编辑作品</h3>
            <input value={editName} onChange={e => setEditName(e.target.value)}
              placeholder="作品名称 *"
              style={{
                width: '100%', padding: '10px 12px', borderRadius: 8, boxSizing: 'border-box',
                border: '1px solid var(--border)', background: 'var(--bg-main)',
                color: 'var(--text-primary)', fontSize: 14, outline: 'none', marginBottom: 8,
              }}
            />
            <input value={editGenre} onChange={e => setEditGenre(e.target.value)}
              placeholder="类型（可选）"
              style={{
                width: '100%', padding: '10px 12px', borderRadius: 8, boxSizing: 'border-box',
                border: '1px solid var(--border)', background: 'var(--bg-main)',
                color: 'var(--text-primary)', fontSize: 14, outline: 'none', marginBottom: 8,
              }}
            />
            <textarea value={editDesc} onChange={e => setEditDesc(e.target.value)}
              placeholder="描述（可选）" rows={3}
              style={{
                width: '100%', padding: '10px 12px', borderRadius: 8, boxSizing: 'border-box',
                border: '1px solid var(--border)', background: 'var(--bg-main)',
                color: 'var(--text-primary)', fontSize: 14, outline: 'none', resize: 'none', marginBottom: 16,
              }}
            />
            <div style={{ display: 'flex', gap: 8 }}>
              <button onClick={() => setShowEdit(false)} style={{
                flex: 1, padding: '10px 0', borderRadius: 8,
                border: '1px solid var(--border)', background: 'transparent',
                color: 'var(--text-secondary)', fontSize: 14, cursor: 'pointer', font: 'inherit',
              }}>取消</button>
              <button onClick={confirmEdit} disabled={!editName.trim()} style={{
                flex: 1, padding: '10px 0', borderRadius: 8, border: 'none',
                background: !editName.trim() ? 'var(--border)' : 'var(--accent)',
                color: !editName.trim() ? 'var(--text-tertiary)' : 'var(--text-on-accent)',
                fontSize: 14, cursor: !editName.trim() ? 'not-allowed' : 'pointer', font: 'inherit',
              }}>保存</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
