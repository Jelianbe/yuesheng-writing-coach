/**
 * ActiveTrainingView — 训练工坊步骤式练习视图
 *
 * 所有 mode 共享通用三步框架，Step 2 提交后由 AI 评估是否符合约束。
 * 前端不做任何 mode 特定的硬编码校验。添加新 mode 只需改模板 JSON。
 */

import React from 'react';
import { ArrowLeft } from 'lucide-react';
import type { ActiveTrainingSession, EvaluationResult } from '../../shared/types';
import { getStructuredTaskForActiveTraining } from '../../shared/structured-tasks';
import {
  containerStyle,
  primaryBtnStyle,
  secondaryBtnStyle,
} from './training-styles';

/** SF-001: 场景元数据下拉框统一样式 */
const selectStyle: React.CSSProperties = {
  padding: '6px 12px',
  borderRadius: 6,
  border: '1px solid var(--border)',
  backgroundColor: 'var(--bg-input)',
  color: 'var(--text-primary)',
  fontSize: '0.8rem',
  fontFamily: 'inherit',
  cursor: 'pointer',
  outline: 'none',
  minWidth: 120,
};

interface ActiveTrainingViewProps {
  activeTraining: ActiveTrainingSession;
  submissionResult: { passed: boolean; feedback: string } | null;
  evaluationResult: EvaluationResult | null;
  isLoading: boolean;
  onBackToChat: () => void;
  onSubmitStep: () => void;
  onSkipTraining: () => void;
  onUpdateDraft: (content: string) => void;
}

const ActiveTrainingView: React.FC<ActiveTrainingViewProps> = ({
  activeTraining,
  submissionResult,
  evaluationResult,
  isLoading,
  onBackToChat,
  onSubmitStep,
  onSkipTraining,
  onUpdateDraft,
}) => {

  // SF-001: 场景元数据（仅 Step 1 显示，纯前端状态不入训练记录）
  const [selectedPov, setSelectedPov] = React.useState<'first_person' | 'third_person' | ''>('');
  const [selectedTone, setSelectedTone] = React.useState<'tense' | 'neutral' | 'suspenseful' | ''>('');
  const [selectedLine, setSelectedLine] = React.useState<'main' | 'sub_a' | 'sub_b' | ''>('');

  // 结构化任务数据（当 challengeId 能映射到 structured-tasks 时可用）
  const structuredTask = React.useMemo(
    () => getStructuredTaskForActiveTraining(activeTraining.challengeId),
    [activeTraining.challengeId],
  );

  return <div style={containerStyle}>
    {/* 练习头部 */}
    <div style={{
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      padding: '16px 24px',
      backgroundColor: 'var(--accent-subtle)',
      borderBottom: '1px solid var(--border)',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <button
          onClick={onBackToChat}
          style={{
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            width: 30, height: 30, borderRadius: 'var(--radius-sm)',
            border: '1px solid var(--border)', background: 'white',
            color: 'var(--text-secondary)', cursor: 'pointer',
            transition: 'all 120ms ease', flexShrink: 0,
          }}
          onMouseEnter={e => { e.currentTarget.style.borderColor = 'var(--accent)'; e.currentTarget.style.color = 'var(--accent)'; }}
          onMouseLeave={e => { e.currentTarget.style.borderColor = 'var(--border)'; e.currentTarget.style.color = 'var(--text-secondary)'; }}
          title="返回对话"
        >
          <ArrowLeft size={15} strokeWidth={1.8} />
        </button>
        <div>
          <div style={{ fontSize: '1rem', fontWeight: 600, color: 'var(--text-primary)' }}>
            {activeTraining.challengeName}
          </div>
          <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>
            步骤 {activeTraining.currentStepIndex + 1}/{activeTraining.steps.length}
          </div>
        </div>
      </div>
    </div>

    {/* 进度条 */}
    <div style={{ padding: '0 24px 12px', backgroundColor: 'var(--accent-subtle)' }}>
      <div style={{
        height: 4,
        backgroundColor: 'var(--border)',
        borderRadius: 2,
        overflow: 'hidden',
      }}>
        <div style={{
          height: '100%',
          width: `${((activeTraining.currentStepIndex + 1) / activeTraining.steps.length) * 100}%`,
          backgroundColor: 'var(--accent)',
          borderRadius: 2,
          transition: 'width 320ms cubic-bezier(0.25, 1, 0.5, 1)',
        }} />
      </div>
    </div>

    {/* SF-002: 三级目标追踪 */}
    <div style={{
      display: 'flex',
      gap: 12,
      padding: '8px 24px',
      backgroundColor: 'var(--bg-secondary)',
      borderBottom: '1px solid var(--border)',
      fontSize: '0.75rem',
    }}>
      {/* 短期目标: 当前训练步骤 */}
      <div style={{ flex: 1 }}>
        <div style={{ color: 'var(--text-secondary)', marginBottom: 2 }}>
          短期 · 步骤完成度
        </div>
        <div style={{ height: 6, backgroundColor: 'var(--border)', borderRadius: 3, overflow: 'hidden', marginBottom: 2 }}>
          <div style={{
            height: '100%',
            width: `${((activeTraining.currentStepIndex + 1) / activeTraining.steps.length) * 100}%`,
            backgroundColor: '#27ae60',
            borderRadius: 3,
            transition: 'width 320ms cubic-bezier(0.25, 1, 0.5, 1)',
          }} />
        </div>
        <div style={{ color: 'var(--text-secondary)', fontSize: '0.7rem' }}>
          {activeTraining.currentStepIndex + 1}/{activeTraining.steps.length} 步
        </div>
      </div>
      {/* 中期目标: 核心技法模式 */}
      <div style={{ flex: 1 }}>
        <div style={{ color: 'var(--text-secondary)', marginBottom: 2 }}>
          中期 · 技法掌握
        </div>
        <div style={{ height: 6, backgroundColor: 'var(--border)', borderRadius: 3, overflow: 'hidden', marginBottom: 2 }}>
          <div style={{
            height: '100%',
            width: activeTraining.corePatterns ? '60%' : '30%',
            backgroundColor: '#3498db',
            borderRadius: 3,
          }} />
        </div>
        <div style={{ color: 'var(--text-secondary)', fontSize: '0.7rem' }}>
          {activeTraining.corePatterns ?? '基础练习'}
        </div>
      </div>
      {/* 长期目标: 症候改善（基于诊断严重度动态计算） */}
      <div style={{ flex: 1 }}>
        <div style={{ color: 'var(--text-secondary)', marginBottom: 2 }}>
          长期 · 症候改善
        </div>
        <div style={{ height: 6, backgroundColor: 'var(--border)', borderRadius: 3, overflow: 'hidden', marginBottom: 2 }}>
          <div style={{
            height: '100%',
            width: `${activeTraining.longTermProgress}%`,
            backgroundColor: '#8e44ad',
            borderRadius: 3,
            transition: 'width 0.3s ease',
          }} />
        </div>
        <div style={{ color: 'var(--text-secondary)', fontSize: '0.7rem' }}>
          {activeTraining.targetSyndrome ?? '综合提升'} · {activeTraining.longTermProgress}%
        </div>
      </div>
    </div>

    {/* 步骤内容 */}
    <div style={{ flex: 1, overflow: 'auto', padding: 24 }}>
      <div style={{ maxWidth: 720, margin: '0 auto' }}>
        {/* 步骤状态列表 */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginBottom: 24 }}>
          {activeTraining.steps.map((step) => (
            <div
              key={step.id}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 10,
                padding: '8px 12px',
                borderRadius: 8,
                backgroundColor: step.status === 'active' ? 'var(--accent-subtle)' : 'transparent',
                fontSize: '0.85rem',
              }}
            >
              <span style={{
                width: 20, height: 20, borderRadius: '50%',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontSize: '0.7rem', fontWeight: 600,
                backgroundColor: step.status === 'completed' ? '#27ae60'
                  : step.status === 'active' ? 'var(--accent)' : 'var(--border)',
                color: '#fff',
              }}>
                {step.status === 'completed' ? '✓' : step.status === 'active' ? (activeTraining.steps.indexOf(step) + 1) : ''}
              </span>
              <div>
                <div style={{ fontWeight: step.status === 'active' ? 600 : 400, color: 'var(--text-primary)' }}>
                  {step.title}
                </div>
                {step.status === 'active' && step.description && (
                  <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>
                    {step.description}
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>

        {/* Step 0: 阅读原始文本 */}
        {activeTraining.currentStepIndex === 0 && activeTraining.originalQuote && (
          <div style={{
            padding: 12,
            backgroundColor: '#fdf0ef',
            borderRadius: 8,
            borderLeft: '3px solid #e74c3c',
            marginBottom: 16,
            fontSize: '0.85rem',
            color: 'var(--text-secondary)',
            lineHeight: 1.6,
          }}>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)', marginBottom: 6 }}>
              你的原始文本
            </div>
            &ldquo;{activeTraining.originalQuote}&rdquo;
          </div>
        )}

        {/* Step 1: 约束改写 */}
        {activeTraining.currentStepIndex === 1 && (
          <>
            {activeTraining.challengeDescription && (
              <div style={{
                padding: 12,
                backgroundColor: '#eaf7fd',
                borderRadius: 8,
                borderLeft: '3px solid #3498db',
                marginBottom: 12,
                fontSize: '0.85rem',
                lineHeight: 1.6,
                color: 'var(--text-secondary)',
              }}>
                {activeTraining.challengeDescription}
              </div>
            )}

            {activeTraining.constraint && (
              <div style={{
                padding: 10,
                backgroundColor: '#fef5e7',
                borderRadius: 8,
                borderLeft: '3px solid #f39c12',
                marginBottom: 12,
                fontSize: '0.85rem',
                color: '#c0392b',
              }}>
                <strong>约束条件：</strong>{activeTraining.constraint}
              </div>
            )}

            {/* ===== 结构化任务增强信息（来自 training-tasks.md） ===== */}
            {structuredTask && (
              <>
                {/* 禁止词标签 */}
                {structuredTask.forbiddenWords && structuredTask.forbiddenWords.length > 0 && (
                  <div style={{ marginBottom: 12 }}>
                    <div style={{
                      fontSize: '0.75rem',
                      fontWeight: 600,
                      color: '#c0392b',
                      marginBottom: 6,
                    }}>
                      🚫 禁止词（{structuredTask.forbiddenWords.length} 个）
                    </div>
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>
                      {structuredTask.forbiddenWords.map((word) => (
                        <span
                          key={word}
                          style={{
                            fontSize: '0.75rem',
                            padding: '3px 8px',
                            borderRadius: 4,
                            backgroundColor: '#fdf0ef',
                            color: '#c0392b',
                            border: '1px solid #fadbd8',
                            fontWeight: 500,
                          }}
                        >
                          {word}
                        </span>
                      ))}
                    </div>
                  </div>
                )}

                {/* 字数要求 + 场景 + 模式 */}
                <div style={{
                  display: 'flex',
                  gap: 16,
                  marginBottom: 12,
                  flexWrap: 'wrap',
                  fontSize: '0.8rem',
                  color: 'var(--text-secondary)',
                }}>
                  {structuredTask.wordCount && (
                    <span style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 4,
                      padding: '4px 10px',
                      backgroundColor: '#eaf7fd',
                      borderRadius: 4,
                      border: '1px solid #d6eaf8',
                      color: '#2980b9',
                      fontWeight: 500,
                    }}>
                      📝 目标：{structuredTask.wordCount} 字
                    </span>
                  )}
                  {structuredTask.scene && (
                    <span style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 4,
                      padding: '4px 10px',
                      backgroundColor: '#fef9e7',
                      borderRadius: 4,
                      border: '1px solid #f9e79f',
                      color: '#b7950b',
                      fontWeight: 500,
                    }}>
                      🎬 场景：{structuredTask.scene}
                    </span>
                  )}
                  {structuredTask.mode === 'reading' && (
                    <span style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 4,
                      padding: '4px 10px',
                      backgroundColor: '#ebf5fb',
                      borderRadius: 4,
                      border: '1px solid #d4e6f1',
                      color: '#2874a6',
                      fontWeight: 500,
                    }}>
                      📖 阅读任务模式
                    </span>
                  )}
                </div>

                {/* 评估标准预览 */}
                {structuredTask.criteria && structuredTask.criteria.length > 0 && (
                  <div style={{
                    marginBottom: 12,
                    padding: '10px 12px',
                    backgroundColor: '#eafaf1',
                    borderRadius: 6,
                    borderLeft: '3px solid #27ae60',
                  }}>
                    <div style={{
                      fontSize: '0.75rem',
                      fontWeight: 600,
                      color: '#1e8449',
                      marginBottom: 6,
                    }}>
                      ✅ 评估标准
                    </div>
                    <ul style={{
                      margin: 0,
                      paddingLeft: 18,
                      fontSize: '0.8rem',
                      color: 'var(--text-secondary)',
                      lineHeight: 1.7,
                    }}>
                      {structuredTask.criteria.map((c, i) => (
                        <li key={i}>{c}</li>
                      ))}
                    </ul>
                  </div>
                )}
              </>
            )}

            {/* SF-001: 场景元数据面板 — 3个下拉选择 */}
            <div style={{
              display: 'flex',
              gap: 8,
              marginBottom: 12,
              flexWrap: 'wrap',
            }}>
              <select
                value={selectedPov}
                onChange={(e) => setSelectedPov(e.target.value as typeof selectedPov)}
                style={selectStyle}
              >
                <option value="">POV 视角</option>
                <option value="first_person">第一人称</option>
                <option value="third_person">第三人称</option>
              </select>
              <select
                value={selectedTone}
                onChange={(e) => setSelectedTone(e.target.value as typeof selectedTone)}
                style={selectStyle}
              >
                <option value="">基调</option>
                <option value="tense">紧张</option>
                <option value="neutral">平淡</option>
                <option value="suspenseful">悬念</option>
              </select>
              <select
                value={selectedLine}
                onChange={(e) => setSelectedLine(e.target.value as typeof selectedLine)}
                style={selectStyle}
              >
                <option value="">叙事线</option>
                <option value="main">主线</option>
                <option value="sub_a">副线 A</option>
                <option value="sub_b">副线 B</option>
              </select>
            </div>

            <textarea
              value={activeTraining.userDraft}
              onChange={(e) => { onUpdateDraft(e.target.value); }}
              placeholder="在此输入你的改写..."
              style={{
                width: '100%',
                minHeight: 160,
                padding: 12,
                borderRadius: 8,
                border: `1px solid ${submissionResult && !submissionResult.passed ? '#e74c3c' : 'var(--border)'}`,
                backgroundColor: 'var(--bg-input)',
                color: 'var(--text-primary)',
                fontSize: '0.875rem',
                lineHeight: 1.6,
                resize: 'vertical',
                fontFamily: 'inherit',
                boxSizing: 'border-box',
              }}
            />

            {submissionResult && !submissionResult.passed && (
              <div style={{
                marginTop: 8,
                padding: 10,
                backgroundColor: '#fdf0ef',
                borderRadius: 8,
                border: '1px solid #e74c3c',
                fontSize: '0.8rem',
                color: '#c0392b',
                lineHeight: 1.5,
              }}>
                {submissionResult.feedback}
              </div>
            )}
          </>
        )}

        {/* Step 2: 提交评估结果 */}
        {activeTraining.currentStepIndex === 2 && (
          <div style={{
            padding: 16,
            backgroundColor: '#eafaf1',
            borderRadius: 8,
            borderLeft: '3px solid #27ae60',
            fontSize: '0.85rem',
            color: 'var(--text-secondary)',
            lineHeight: 1.6,
          }}>
            {/* 评分展示 */}
            {evaluationResult && (
              <div style={{
                display: 'flex',
                alignItems: 'center',
                gap: 12,
                marginBottom: 12,
                padding: 12,
                backgroundColor: '#fff',
                borderRadius: 8,
                border: '1px solid #d5f5e3',
              }}>
                <div style={{
                  width: 56,
                  height: 56,
                  borderRadius: '50%',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  backgroundColor: evaluationResult.score >= 7 ? '#27ae60' : evaluationResult.score >= 4 ? '#f39c12' : '#e74c3c',
                  color: '#fff',
                  fontSize: '1.4rem',
                  fontWeight: 700,
                  flexShrink: 0,
                }}>
                  {evaluationResult.score}
                </div>
                <div>
                  <div style={{ fontWeight: 600, color: 'var(--text-primary)', marginBottom: 2 }}>
                    {evaluationResult.score >= 7 ? '表现优秀' : evaluationResult.score >= 4 ? '还需努力' : '继续练习'}
                    {evaluationResult.improved && <span style={{ color: '#27ae60', marginLeft: 6 }}>相比原文有改善</span>}
                  </div>
                  <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>
                    满分 10 分
                  </div>
                </div>
              </div>
            )}

            <div style={{ fontWeight: 600, color: '#27ae60', marginBottom: 6 }}>
              训练完成！
            </div>
            {submissionResult?.feedback && (
              <p style={{ margin: '0 0 8px 0' }}>{submissionResult.feedback}</p>
            )}
            {evaluationResult?.nextStep && (
              <div style={{
                marginTop: 8,
                padding: 10,
                backgroundColor: '#eaf7fd',
                borderRadius: 6,
                borderLeft: '3px solid #3498db',
                fontSize: '0.8rem',
              }}>
                <strong>下一步建议：</strong>{evaluationResult.nextStep}
              </div>
            )}
            <p style={{ margin: '8px 0 0 0' }}>
              训练记录已保存到你的学习档案中。
            </p>

            {/* === 训练完成后的操作出口 === */}
            <div style={{
              display: 'flex',
              gap: 10,
              marginTop: 16,
              paddingTop: 16,
              borderTop: '1px dashed #a9dfbf',
            }}>
              <button
                onClick={onSubmitStep}
                disabled={isLoading}
                style={{
                  flex: 1,
                  padding: '10px 20px',
                  borderRadius: 8,
                  border: 'none',
                  background: 'var(--accent)',
                  color: '#fff',
                  cursor: isLoading ? 'not-allowed' : 'pointer',
                  fontSize: '0.85rem',
                  fontWeight: 500,
                  opacity: isLoading ? 0.6 : 1,
                  transition: 'all 0.15s',
                }}
              >
                {isLoading ? '加载中...' : '完成训练'}
              </button>
            </div>
          </div>
        )}

        {/* 操作按钮（Step 2 已在内嵌出口中，此处隐藏） */}
        {activeTraining.currentStepIndex < 2 && (
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 20 }}>
          <button onClick={onSkipTraining} style={secondaryBtnStyle}>
            {activeTraining.currentStepIndex >= 1 ? '存草稿' : '跳过'}
          </button>
          <button
            onClick={onSubmitStep}
            style={primaryBtnStyle}
            disabled={(activeTraining.currentStepIndex === 1 && !activeTraining.userDraft.trim()) || isLoading}
          >
            {isLoading ? '评估中...' : '继续'}
          </button>
        </div>
        )}
      </div>
    </div>
  </div>;
};

export default ActiveTrainingView;
