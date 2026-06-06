/**
 * ActiveTrainingView — 训练工坊步骤式练习视图
 *
 * 所有 mode 共享通用三步框架，Step 2 提交后由 AI 评估是否符合约束。
 * 前端不做任何 mode 特定的硬编码校验。添加新 mode 只需改模板 JSON。
 */

import React from 'react';
import type { ActiveTrainingSession } from '../../shared/types';
import {
  containerStyle,
  backBtnStyle,
  primaryBtnStyle,
  secondaryBtnStyle,
} from './training-styles';

interface ActiveTrainingViewProps {
  activeTraining: ActiveTrainingSession;
  submissionResult: { passed: boolean; feedback: string } | null;
  isLoading: boolean;
  onBackToChat: () => void;
  onSubmitStep: () => void;
  onSkipTraining: () => void;
  onUpdateDraft: (content: string) => void;
}

const ActiveTrainingView: React.FC<ActiveTrainingViewProps> = ({
  activeTraining,
  submissionResult,
  isLoading,
  onBackToChat,
  onSubmitStep,
  onSkipTraining,
  onUpdateDraft,
}) => (
  <div style={containerStyle}>
    {/* 练习头部 */}
    <div style={{
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      padding: '16px 24px',
      backgroundColor: 'var(--color-accent-subtle)',
      borderBottom: '1px solid var(--border)',
    }}>
      <div>
        <div style={{ fontSize: '1rem', fontWeight: 600, color: 'var(--color-text-primary)' }}>
          {activeTraining.challengeName}
        </div>
        <div style={{ fontSize: '0.75rem', color: 'var(--color-text-secondary)' }}>
          步骤 {activeTraining.currentStepIndex + 1}/{activeTraining.steps.length}
        </div>
      </div>
      <button onClick={onSkipTraining} style={{ ...backBtnStyle, fontSize: '0.8rem' }}>
        返回
      </button>
    </div>

    {/* 进度条 */}
    <div style={{ padding: '0 24px 12px', backgroundColor: 'var(--color-accent-subtle)' }}>
      <div style={{
        height: 4,
        backgroundColor: 'var(--border)',
        borderRadius: 2,
        overflow: 'hidden',
      }}>
        <div style={{
          height: '100%',
          width: `${((activeTraining.currentStepIndex + 1) / activeTraining.steps.length) * 100}%`,
          backgroundColor: 'var(--color-accent-primary)',
          borderRadius: 2,
          transition: 'width 0.3s ease',
        }} />
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
                backgroundColor: step.status === 'active' ? 'var(--color-accent-subtle)' : 'transparent',
                fontSize: '0.85rem',
              }}
            >
              <span style={{
                width: 20, height: 20, borderRadius: '50%',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontSize: '0.7rem', fontWeight: 600,
                backgroundColor: step.status === 'completed' ? '#27ae60'
                  : step.status === 'active' ? 'var(--color-accent-primary)' : 'var(--border)',
                color: '#fff',
              }}>
                {step.status === 'completed' ? '✓' : step.status === 'active' ? (activeTraining.steps.indexOf(step) + 1) : ''}
              </span>
              <div>
                <div style={{ fontWeight: step.status === 'active' ? 600 : 400, color: 'var(--color-text-primary)' }}>
                  {step.title}
                </div>
                {step.status === 'active' && step.description && (
                  <div style={{ fontSize: '0.8rem', color: 'var(--color-text-secondary)' }}>
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
            color: 'var(--color-text-secondary)',
            lineHeight: 1.6,
          }}>
            <div style={{ fontWeight: 600, color: 'var(--color-text-primary)', marginBottom: 6 }}>
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
                color: 'var(--color-text-secondary)',
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
                backgroundColor: 'var(--color-bg-input)',
                color: 'var(--color-text-primary)',
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
            padding: 12,
            backgroundColor: '#eafaf1',
            borderRadius: 8,
            borderLeft: '3px solid #27ae60',
            fontSize: '0.85rem',
            color: 'var(--color-text-secondary)',
            lineHeight: 1.6,
          }}>
            <div style={{ fontWeight: 600, color: '#27ae60', marginBottom: 6 }}>
              评估通过
            </div>
            {submissionResult?.feedback && (
              <p style={{ margin: '0 0 8px 0' }}>{submissionResult.feedback}</p>
            )}
            <p style={{ margin: 0 }}>
              提交后，训练记录会保存到你的学习档案中。
            </p>
          </div>
        )}

        {/* 操作按钮 */}
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 20 }}>
          <button onClick={onSkipTraining} style={secondaryBtnStyle}>
            {activeTraining.currentStepIndex >= 1 ? '存草稿' : '跳过'}
          </button>
          <button
            onClick={onSubmitStep}
            style={primaryBtnStyle}
            disabled={(activeTraining.currentStepIndex === 1 && !activeTraining.userDraft.trim()) || isLoading}
          >
            {isLoading ? '评估中...'
              : activeTraining.currentStepIndex === 2 ? '提交完成'
              : '继续'}
          </button>
        </div>
      </div>
    </div>
  </div>
);

export default ActiveTrainingView;
