import React, { useState, useEffect } from 'react';
import { useRightToolsStore } from '../../../../stores/right-tools.store';
import { useStartTraining } from '../../../../hooks/useStartTraining';
import { getInvoke } from '../../../../utils/ipc';
import styles from './index.module.css';

/** 技法条目 */
interface Technique {
  id: string;
  name: string;
  difficulty: string;
  category: string;
  description: string;
}

/** 核心组 */
interface CoreGroup {
  coreId: string;
  coreName: string;
  count: number;
  techniques: Technique[];
}

const DIFF_LABEL: Record<string, string> = {
  beginner: '入门', intermediate: '进阶', advanced: '高阶',
};

export const CatalogWorkspace: React.FC = () => {
  const [groups, setGroups] = useState<CoreGroup[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showingCatalog, setShowingCatalog] = useState(true);
  const [selectedTechnique, setSelectedTechnique] = useState<Technique | null>(null);
  const { subTabs, activeSubTabId, addSubTab } = useRightToolsStore();
  const catalogSubTabs = subTabs['catalog'] ?? [];
  const handleStartTraining = useStartTraining();

  // 从后端加载技法目录
  useEffect(() => {
    (async () => {
      setLoading(true);
      setError(null);
      try {
        const res = await getInvoke()('training:catalog', {}) as { groups?: CoreGroup[] };
        if (res?.groups && Array.isArray(res.groups) && res.groups.length > 0) {
          setGroups(res.groups);
        } else {
          setError('技法目录为空');
        }
      } catch (e) {
        setError('加载技法目录失败，请检查后端服务');
        console.warn('[CatalogWorkspace] IPC training:catalog failed', e);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  useEffect(() => {
    if (!activeSubTabId && catalogSubTabs.length === 0) {
      setShowingCatalog(true);
    }
  }, [activeSubTabId, catalogSubTabs.length]);

  const selectCoreGroup = (coreId: string) => {
    setShowingCatalog(false);
    setSelectedTechnique(null);
    const g = groups.find(c => c.coreId === coreId);
    if (g) addSubTab('catalog', { id: coreId, label: g.coreName });
  };

  const selectTechnique = (techId: string) => {
    for (const g of groups) {
      const found = g.techniques.find(t => t.id === techId);
      if (found) { setSelectedTechnique(found); return; }
    }
  };

  const handleBackToList = () => setSelectedTechnique(null);

  const renderBody = () => {
    if (loading) {
      return <div className={styles.loading}>加载技法目录中...</div>;
    }

    if (error) {
      return <div className={styles.error}>{error}</div>;
    }

    if (selectedTechnique) {
      const t = selectedTechnique;
      const coreGroup = groups.find(g => g.techniques.some(x => x.id === t.id));
      return (
        <div className={styles.detailWrap}>
          <button className={styles.backBtn} onClick={handleBackToList}>← 返回列表</button>
          <div className={styles.detailCard}>
            <div className={styles.detailHeader}>
              <span className={styles.detailName}>{t.name}</span>
              <span className={styles.badge}>{DIFF_LABEL[t.difficulty] || t.difficulty}</span>
              <span className={styles.categoryTag}>{t.category}</span>
              <span className={styles.techId}>{t.id}</span>
            </div>
            <p className={styles.detailDesc}>{t.description}</p>
            {coreGroup && (
              <p className={styles.detailCore}>所属：{coreGroup.coreName}（共 {coreGroup.count} 条技法）</p>
            )}
            <button className={styles.startTrainBtn} onClick={() => handleStartTraining(t.name)}>
              开始训练「{t.name}」
            </button>
          </div>
        </div>
      );
    }

    if (!showingCatalog) {
      const activeCoreGroup = groups.find(g => catalogSubTabs.some(t => t.id === g.coreId));
      if (activeCoreGroup) {
        const sorted = [...activeCoreGroup.techniques].sort((a, b) => a.id.localeCompare(b.id));
        return (
          <div className={styles.coreGroupList}>
            <h3 className={styles.coreGroupTitle}>{activeCoreGroup.coreName}</h3>
            {sorted.map(t => (
              <div key={t.id} className={styles.techCard} onClick={() => selectTechnique(t.id)}>
                <span className={styles.techName}>{t.name}</span>
                <span className={styles.badge}>{DIFF_LABEL[t.difficulty] || t.difficulty}</span>
                <span className={styles.categoryTag}>{t.category}</span>
              </div>
            ))}
          </div>
        );
      }
    }

    return (
      <div className={styles.catalogGrid}>
        {groups.map(g => (
          <div key={g.coreId} className={styles.coreGroupCard} onClick={() => selectCoreGroup(g.coreId)}>
            <div className={styles.coreGroupHeader}>
              <span className={styles.coreName}>{g.coreName}</span>
              <span className={styles.coreCount}>{g.count} 条技法</span>
            </div>
          </div>
        ))}
      </div>
    );
  };

  return <div className={styles.wrapper}>{renderBody()}</div>;
};
