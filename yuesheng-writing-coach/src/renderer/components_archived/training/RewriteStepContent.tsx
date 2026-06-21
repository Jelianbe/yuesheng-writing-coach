/**
 * RewriteStepContent — Step 1: 约束改写（通用） / 写下分析（阅读任务）
 *
 * 包含挑战描述、约束条件、结构化任务增强信息、场景元数据选择器、
 * 草稿文本框和提交反馈错误提示。
 */
import React from 'react';
import type { ActiveTrainingSession } from '../../shared/types-training';
import type { StructuredTrainingTask } from '../../shared/structured-tasks';
import styles from './ActiveTrainingView.module.css';

interface RewriteStepContentProps {
  session: ActiveTrainingSession;
  structuredTask: StructuredTrainingTask | null;
  submissionResult: { passed: boolean; feedback: string } | null;
  isLoading: boolean;
  onUpdateDraft: (content: string) => void;
}

/** SF-001: 场景元数据状态类型 */
type PovValue = 'first_person' | 'third_person' | '';
type ToneValue = 'tense' | 'neutral' | 'suspenseful' | '';
type LineValue = 'main' | 'sub_a' | 'sub_b' | '';

export const RewriteStepContent: React.FC<RewriteStepContentProps> = ({
  session,
  structuredTask,
  submissionResult,
  onUpdateDraft,
}) => {
  // SF-001: 场景元数据（纯前端状态不入训练记录）
  const [selectedPov, setSelectedPov] = React.useState<PovValue>('');
  const [selectedTone, setSelectedTone] = React.useState<ToneValue>('');
  const [selectedLine, setSelectedLine] = React.useState<LineValue>('');

  return (
    <>
      {/* 挑战描述（阅读任务已在 Step 0 展示，跳过重复渲染） */}
      {session.challengeDescription && session.mode !== 'reading_task' && (
        <div
          className={`${styles.challengeDesc} ${
            session.mode === 'reading_task'
              ? styles.challengeDescReading
              : styles.challengeDescWriting
          }`}
        >
          {session.challengeDescription}
        </div>
      )}

      {/* 约束条件（非阅读任务模式） */}
      {session.constraint && session.mode !== 'reading_task' && (
        <div className={styles.constraintBox}>
          <strong>约束条件：</strong>{session.constraint}
        </div>
      )}

      {/* 结构化任务增强信息 */}
      {structuredTask && (
        <>
          {/* 禁止词标签 */}
          {structuredTask.forbiddenWords && structuredTask.forbiddenWords.length > 0 && (
            <div className={styles.forbiddenWordsSection}>
              <div className={styles.forbiddenWordsLabel}>
                🚫 禁止词（{structuredTask.forbiddenWords.length} 个）
              </div>
              <div className={styles.forbiddenWordsList}>
                {structuredTask.forbiddenWords.map((word) => (
                  <span key={word} className={styles.forbiddenWordTag}>
                    {word}
                  </span>
                ))}
              </div>
            </div>
          )}

          {/* 字数要求 + 场景 + 模式 */}
          <div className={styles.taskMetaRow}>
            {structuredTask.wordCount && (
              <span className={`${styles.taskMetaTag} ${styles.metaWordCount}`}>
                📝 目标：{structuredTask.wordCount} 字
              </span>
            )}
            {structuredTask.scene && (
              <span className={`${styles.taskMetaTag} ${styles.metaScene}`}>
                🎬 场景：{structuredTask.scene}
              </span>
            )}
            {structuredTask.mode === 'reading' && (
              <span className={`${styles.taskMetaTag} ${styles.metaReadingMode}`}>
                📖 阅读任务模式
              </span>
            )}
          </div>

          {/* 评估标准预览 */}
          {structuredTask.criteria && structuredTask.criteria.length > 0 && (
            <div className={styles.criteriaPreview}>
              <div className={styles.criteriaTitle}>✅ 评估标准</div>
              <ul className={styles.criteriaList}>
                {structuredTask.criteria.map((c, i) => (
                  <li key={i}>{c}</li>
                ))}
              </ul>
            </div>
          )}
        </>
      )}

      {/* SF-001: 场景元数据面板（仅通用改写模式） */}
      {session.mode !== 'reading_task' && (
        <div className={styles.metadataSelects}>
          <select
            value={selectedPov}
            onChange={(e) => setSelectedPov(e.target.value as PovValue)}
            className={styles.selectInput}
          >
            <option value="">POV 视角</option>
            <option value="first_person">第一人称</option>
            <option value="third_person">第三人称</option>
          </select>
          <select
            value={selectedTone}
            onChange={(e) => setSelectedTone(e.target.value as ToneValue)}
            className={styles.selectInput}
          >
            <option value="">基调</option>
            <option value="tense">紧张</option>
            <option value="neutral">平淡</option>
            <option value="suspenseful">悬念</option>
          </select>
          <select
            value={selectedLine}
            onChange={(e) => setSelectedLine(e.target.value as LineValue)}
            className={styles.selectInput}
          >
            <option value="">叙事线</option>
            <option value="main">主线</option>
            <option value="sub_a">副线 A</option>
            <option value="sub_b">副线 B</option>
          </select>
        </div>
      )}

      {/* 草稿文本框 */}
      <textarea
        className={`${styles.draftTextarea}${
          submissionResult && !submissionResult.passed ? ` ${styles.draftTextareaError}` : ''
        }`}
        value={session.userDraft}
        onChange={(e) => onUpdateDraft(e.target.value)}
        placeholder={
          session.mode === 'reading_task'
            ? '在此写下你的阅读分析和观察...'
            : '在此输入你的改写...'
        }
      />

      {/* 提交失败反馈 */}
      {submissionResult && !submissionResult.passed && (
        <div className={styles.submissionError}>{submissionResult.feedback}</div>
      )}
    </>
  );
};
