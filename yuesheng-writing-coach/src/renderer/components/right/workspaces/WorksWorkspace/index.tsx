import React, { useEffect, useState } from 'react';
import { useRightToolsStore } from '../../../../stores/right-tools.store';
import { useProjectStore } from '../../../../stores/project.store';
import { getInvoke } from '../../../../utils/ipc';
import styles from './index.module.css';

/** IPC chapter:get 返回的章节数据类型 */
interface ChapterData {
  id: string;
  manuscript_id: string;
  title: string;
  content: string;
  word_count: number;
  sort_order: number;
}

export const WorksWorkspace: React.FC = () => {
  const selectedProjectId = useRightToolsStore(s => s.activeProjectTabId);
  const [chapterData, setChapterData] = useState<ChapterData | null>(null);
  const [loading, setLoading] = useState(false);
  const projectName = useProjectStore(s => {
    if (!selectedProjectId) return null;
    const p = s.projects.find(x => x.id === selectedProjectId);
    return p?.name || null;
  });

  useEffect(() => {
    if (!selectedProjectId) {
      setChapterData(null);
      return;
    }

    (async () => {
      setLoading(true);
      try {
        const res = await getInvoke()('chapter:get', { id: selectedProjectId }) as ChapterData | null;
        if (res?.id) {
          setChapterData(res);
        } else {
          setChapterData(null);
        }
      } catch {
        setChapterData(null);
      } finally {
        setLoading(false);
      }
    })();
  }, [selectedProjectId]);

  // 提取变量避免类型收窄问题
  const chContent = chapterData?.content ?? null;
  const chWords = chapterData?.word_count ?? 0;

  if (!selectedProjectId) {
    return (
      <div className={styles.emptyState}>
        <h3 className={styles.emptyTitle}>作品</h3>
        <p className={styles.emptyDesc}>从左侧栏选择章节查看内容</p>
      </div>
    );
  }

  // IPC 数据
  if (chapterData) {
    return (
      <div className={styles.container}>
        <div className={styles.header}>
          <span className={styles.title}>{chapterData.title}</span>
          <span className={styles.typeTag}>正文</span>
        </div>
        <div className={styles.contentArea}>
          <div className={styles.contentBox}>{chapterData.content}</div>
        </div>
        <div className={styles.footer}>
          共 {chapterData.word_count} 字，可请求诊断分析
        </div>
      </div>
    );
  }

  if (loading) {
    return (
      <div className={styles.container}>
        <div className={styles.header}>
          <span className={styles.title}>{projectName || '作品'}</span>
          <span className={styles.typeTag}>正文</span>
        </div>
        <div className={styles.contentArea}>
          <div className={styles.contentBox}>加载中...</div>
        </div>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <span className={styles.title}>{projectName || '作品'}</span>
        <span className={styles.typeTag}>正文</span>
      </div>
      <div className={styles.contentArea}>
        <div className={styles.contentBox}>{chContent || '(暂无正文内容)'}</div>
      </div>
      {chContent && (
        <div className={styles.footer}>
          共 {chWords} 字，可请求诊断分析
        </div>
      )}
    </div>
  );
};
