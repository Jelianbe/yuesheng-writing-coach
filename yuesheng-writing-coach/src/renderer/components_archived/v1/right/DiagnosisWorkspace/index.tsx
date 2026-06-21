/**
 * DiagnosisWorkspace — 诊断工作区
 *
 * 使用 useDiagStore 显示当前诊断结果信息：
 * 症候 ID、严重程度、描述、置信度、诊断时间。
 *
 * 挂载时自动调用 diagnosis:query IPC 拉取最新诊断。
 * 订阅 diagnosis:updated 事件实时更新。
 *
 * 用法:
 * ```tsx
 * <DiagnosisWorkspace />
 * ```
 */
import { useEffect } from 'react';
import { useDiagStore, selectCurrentSyndromes } from '@/stores/diag.store';
import { useChatStore } from '@/stores/chat.store';
import styles from './index.module.css';

/** 严重程度中文映射 */
const SEVERITY_LABEL: Record<string, string> = {
  L1: 'L1 - 轻微',
  L2: 'L2 - 中等',
  L3: 'L3 - 严重',
};

/** 严重程度 CSS 类名映射 */
const SEVERITY_CLASS: Record<string, string> = {
  L1: styles.severityL1,
  L2: styles.severityL2,
  L3: styles.severityL3,
};

/** 格式化 ISO 时间戳为可读字符串 */
function formatTimestamp(iso: string): string {
  try {
    const d = new Date(iso);
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    const hour = String(d.getHours()).padStart(2, '0');
    const min = String(d.getMinutes()).padStart(2, '0');
    return `${year}-${month}-${day} ${hour}:${min}`;
  } catch {
    return iso;
  }
}

/** 格式化置信度为百分比字符串 */
function formatConfidence(value: number): string {
  return `${Math.round(value * 100)}%`;
}

export function DiagnosisWorkspace(): JSX.Element {
  const currentDiagnosis = useDiagStore((s) => s.currentDiagnosis);
  const isLoading = useDiagStore((s) => s.isLoading);
  const error = useDiagStore((s) => s.error);
  const syndromes = useDiagStore(selectCurrentSyndromes);
  const sessionId = useChatStore((s) => s.currentSessionId);
  const fetchLatestDiagnosis = useDiagStore((s) => s.fetchLatestDiagnosis);

  // 挂载时从后端拉取最新诊断
  useEffect(() => {
    if (!currentDiagnosis && sessionId) {
      void fetchLatestDiagnosis(sessionId);
    }
  }, [sessionId, currentDiagnosis, fetchLatestDiagnosis]);

  if (isLoading) {
    return (
      <div className={styles.container}>
        <div className={styles.centerMessage}>诊断中...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className={styles.container}>
        <div className={styles.centerMessage}>
          <span className={styles.errorText}>{error}</span>
        </div>
      </div>
    );
  }

  if (!currentDiagnosis) {
    return (
      <div className={styles.container}>
        <div className={styles.emptyState}>
          <span className={styles.emptyIcon} aria-hidden="true">{'\uD83D\uDD0D'}</span>
          <p className={styles.emptyText}>暂无诊断数据</p>
        </div>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      {/* 标题区 */}
      <div className={styles.header}>
        <h3 className={styles.title}>诊断结果</h3>
      </div>

      <div className={styles.content}>
        {/* 整体信息 */}
        <div className={styles.card}>
          <span className={styles.cardLabel}>会话 ID</span>
          <span className={styles.cardValue}>{currentDiagnosis.sessionId}</span>
        </div>

        <div className={styles.card}>
          <span className={styles.cardLabel}>诊断时间</span>
          <span className={styles.cardValue}>
            {formatTimestamp(currentDiagnosis.timestamp)}
          </span>
        </div>

        <div className={styles.card}>
          <span className={styles.cardLabel}>整体置信度</span>
          <span className={styles.cardValue}>
            {formatConfidence(currentDiagnosis.confidence)}
          </span>
        </div>

        {/* 识别到的症候列表 */}
        <div className={styles.card}>
          <span className={styles.cardLabel}>
            识别症候（{syndromes.length}）
          </span>
          <div className={styles.syndromeList}>
            {syndromes.length > 0 ? (
              syndromes.map((syndrome) => (
                <div key={syndrome.id} className={styles.syndromeItem}>
                  <div className={styles.syndromeHeader}>
                    <span className={styles.syndromeId}>{syndrome.id}</span>
                    <span
                      className={[
                        styles.severityTag,
                        SEVERITY_CLASS[syndrome.severity] ?? '',
                      ].join(' ')}
                    >
                      {SEVERITY_LABEL[syndrome.severity] ?? syndrome.severity}
                    </span>
                  </div>
                  <p className={styles.syndromeDesc}>{syndrome.name}</p>
                </div>
              ))
            ) : (
              <span className={styles.noItems}>无症候记录</span>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
