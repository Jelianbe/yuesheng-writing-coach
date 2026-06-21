/**
 * WorksWorkspace — 作品工作区
 *
 * 使用 useManuscriptStore 获取作品列表。
 * 每个作品：标题 + 类型标签 + 状态 + 更新时间。
 * 点击选中作品，空状态显示"暂无作品"。
 * 新建作品按钮。
 *
 * 用法:
 * ```tsx
 * <WorksWorkspace />
 * ```
 */
import { useCallback, useEffect } from 'react';
import { useManuscriptStore } from '@/stores/manuscript.store';
import styles from './index.module.css';

/** 作品状态中文映射 */
const STATUS_LABEL: Record<string, string> = {
  active: '进行中',
  archived: '已归档',
};

/** 作品类型中文映射 */
const GENRE_LABEL: Record<string, string> = {
  novel: '小说',
  essay: '散文',
  poetry: '诗歌',
  script: '剧本',
  other: '其他',
};

/** 格式化时间戳为简短日期 */
function formatTimestamp(ts: number): string {
  try {
    const d = new Date(ts);
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  } catch {
    return String(ts);
  }
}

export function WorksWorkspace(): JSX.Element {
  const manuscripts = useManuscriptStore((s) => s.manuscripts);
  const currentManuscript = useManuscriptStore((s) => s.currentManuscript);
  const loading = useManuscriptStore((s) => s.loading);
  const error = useManuscriptStore((s) => s.error);
  const fetchList = useManuscriptStore((s) => s.fetchList);
  const select = useManuscriptStore((s) => s.select);
  const create = useManuscriptStore((s) => s.create);

  // 组件挂载时获取作品列表（已有数据且非加载中则跳过）
  useEffect(() => {
    if (manuscripts.length === 0 && !loading) {
      fetchList();
    }
  }, [fetchList, manuscripts.length, loading]);

  const handleSelect = useCallback(
    (id: string) => {
      select(id);
    },
    [select],
  );

  const handleCreate = useCallback(() => {
    const title = `新作品 ${new Date().toLocaleDateString('zh-CN')}`;
    create(title, '', 'other');
  }, [create]);

  if (loading && manuscripts.length === 0) {
    return (
      <div className={styles.container}>
        <div className={styles.centerMessage}>加载中...</div>
      </div>
    );
  }

  if (error && manuscripts.length === 0) {
    return (
      <div className={styles.container}>
        <div className={styles.centerMessage}>
          <span className={styles.errorText}>{error}</span>
        </div>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      {/* 顶部操作栏 */}
      <div className={styles.header}>
        <h3 className={styles.title}>我的作品</h3>
        <button
          className={styles.createBtn}
          onClick={handleCreate}
          type="button"
        >
          + 新建
        </button>
      </div>

      {/* 作品列表 */}
      <div className={styles.list} role="list" aria-label="作品列表">
        {manuscripts.length === 0 ? (
          <div className={styles.emptyState}>
            <span className={styles.emptyIcon} aria-hidden="true">{'\uD83D\uDCDD'}</span>
            <p className={styles.emptyText}>暂无作品</p>
            <p className={styles.emptyHint}>点击上方"新建"开始你的创作</p>
          </div>
        ) : (
          manuscripts.map((ms) => {
            const isSelected = currentManuscript?.id === ms.id;
            return (
              <button
                key={ms.id}
                className={[
                  styles.workCard,
                  isSelected ? styles.workCardSelected : '',
                ]
                  .filter(Boolean)
                  .join(' ')}
                onClick={() => handleSelect(ms.id)}
                role="listitem"
                type="button"
              >
                <div className={styles.workHeader}>
                  <span className={styles.workTitle}>{ms.title}</span>
                  <span className={styles.workStatus}>
                    {STATUS_LABEL[ms.status] ?? ms.status}
                  </span>
                </div>
                <div className={styles.workMeta}>
                  {ms.genre ? (
                    <span className={styles.workGenre}>
                      {GENRE_LABEL[ms.genre] ?? ms.genre}
                    </span>
                  ) : null}
                  {ms.updated_at ? (
                    <span className={styles.workDate}>
                      {formatTimestamp(ms.updated_at)}
                    </span>
                  ) : null}
                </div>
              </button>
            );
          })
        )}
      </div>
    </div>
  );
}
