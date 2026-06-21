/**
 * CatalogWorkspace — 技法目录工作区
 *
 * 从 training:catalog IPC 获取真实技法数据。
 * 每个分类卡片：coreName + 技法列表。
 * 技法项：名称 + 难度标签 + 简短描述。
 * 点击技法查看详情（当前触发训练）。
 *
 * 用法:
 * ```tsx
 * <CatalogWorkspace />
 * ```
 */
import { useState, useCallback, useEffect } from 'react';
import { useTrainingStore } from '@/stores/training.store';
import { getInvoke } from '@/utils/ipc';
import styles from './index.module.css';

/** 难度等级 */
const DIFFICULTY_LABEL: Record<string, string> = {
  beginner: '初级',
  intermediate: '中级',
  advanced: '高级',
};

const DIFFICULTY_CLASS: Record<string, string> = {
  beginner: styles.diffBeginner,
  intermediate: styles.diffIntermediate,
  advanced: styles.diffAdvanced,
};

/** 技法分类（来自 IPC training:catalog） */
interface CatalogGroup {
  coreId: string;
  coreName: string;
  count: number;
  techniques: Array<{
    id: string;
    name: string;
    difficulty: string;
    description: string;
  }>;
}

export function CatalogWorkspace(): JSX.Element {
  const [categories, setCategories] = useState<CatalogGroup[]>([]);
  const [fetchLoading, setFetchLoading] = useState(true);
  const [fetchError, setFetchError] = useState<string | null>(null);
  const [filterDifficulty, setFilterDifficulty] = useState<string | null>(null);

  const startTraining = useTrainingStore((s) => s.startTraining);

  // 加载技法目录
  useEffect(() => {
    let cancelled = false;
    setFetchLoading(true);
    setFetchError(null);
    (async () => {
      try {
        const invoke = getInvoke();
        const result = await invoke('training:catalog', {}) as { success: boolean; data?: { groups: CatalogGroup[] }; error?: string };
        if (cancelled) return;
        if (result.success && result.data) {
          setCategories(result.data.groups);
        } else {
          setFetchError(result.error ?? '加载失败');
        }
      } catch (err) {
        if (!cancelled) setFetchError(err instanceof Error ? err.message : '未知错误');
      } finally {
        if (!cancelled) setFetchLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, []);

  const handleTechClick = useCallback(
    (techId: string) => {
      startTraining(techId);
    },
    [startTraining],
  );

  const filteredCategories = categories.map((cat) => ({
    ...cat,
    techniques: filterDifficulty
      ? cat.techniques.filter((t) => t.difficulty === filterDifficulty)
      : cat.techniques,
  })).filter((cat) => cat.techniques.length > 0);

  if (fetchLoading) {
    return (
      <div className={styles.container}>
        <div className={styles.centerMessage}>加载技法目录...</div>
      </div>
    );
  }

  if (fetchError) {
    return (
      <div className={styles.container}>
        <div className={styles.centerMessage}>
          <span className={styles.errorText}>{fetchError}</span>
        </div>
      </div>
    );
  }

  if (categories.length === 0) {
    return (
      <div className={styles.container}>
        <div className={styles.centerMessage}>暂无技法数据</div>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      {/* 难度过滤栏 */}
      <div className={styles.filterBar} role="group" aria-label="技法难度过滤">
        {(['beginner', 'intermediate', 'advanced'] as const).map((diff) => (
          <button
            key={diff}
            className={[
              styles.filterBtn,
              filterDifficulty === diff ? styles.filterBtnActive : '',
            ]
              .filter(Boolean)
              .join(' ')}
            onClick={() => setFilterDifficulty(filterDifficulty === diff ? null : diff)}
            type="button"
          >
            {DIFFICULTY_LABEL[diff]}
          </button>
        ))}
      </div>

      {/* 分类卡片列表 */}
      <div className={styles.list} role="list" aria-label="技法分类列表">
        {filteredCategories.map((cat) => (
          <section key={cat.coreId} className={styles.category} role="listitem">
            <h3 className={styles.coreName}>{cat.coreName}</h3>
            <span className={styles.techCount}>{cat.techniques.length} 个技法</span>
            <div className={styles.techList}>
              {cat.techniques.map((tech) => (
                <button
                  key={tech.id}
                  className={styles.techCard}
                  onClick={() => handleTechClick(tech.id)}
                  type="button"
                >
                  <div className={styles.techHeader}>
                    <span className={styles.techName}>{tech.name}</span>
                    <span
                      className={[
                        styles.diffTag,
                        DIFFICULTY_CLASS[tech.difficulty] ?? styles.diffBeginner,
                      ].join(' ')}
                    >
                      {DIFFICULTY_LABEL[tech.difficulty] ?? tech.difficulty}
                    </span>
                  </div>
                  <p className={styles.techDesc}>{tech.description}</p>
                </button>
              ))}
            </div>
          </section>
        ))}
      </div>
    </div>
  );
}
