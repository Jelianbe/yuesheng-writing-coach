/**
 * BehaviorDerivationTool — F-03 角色行为推导工具
 *
 * 三问推导法：用户围绕角色回答三个问题，AI 推演合理行为预期。
 * 用户自行对比"自己的写法"与"推导结果"的一致性。
 *
 * 已拆分子文件：
 * - BehaviorDerivation.styles.ts: 样式常量
 * - QuestionField.tsx: 三问输入框子组件
 */

import React from 'react';
import { useTrainingStore } from '../../stores/training.store';
import {
  sectionStyle,
  sectionTitleStyle,
  expandIconStyle,
  inputStyle,
  labelStyle,
  fieldRowStyle,
  primaryBtnStyle,
  resultCardStyle,
} from './BehaviorDerivation.styles';
import { QuestionField } from './QuestionField';

// ===== 主组件 =====

export const BehaviorDerivationTool: React.FC = () => {
  const [expanded, setExpanded] = React.useState(false);
  const derivationLoading = useTrainingStore(s => s.derivationLoading);
  const derivationError = useTrainingStore(s => s.derivationError);
  const derivationResult = useTrainingStore(s => s.derivationResult);
  const deriveBehavior = useTrainingStore(s => s.deriveBehavior);
  const resetDerivation = useTrainingStore(s => s.resetDerivation);

  // 表单状态（本地管理，不写入 Store）
  const [characterName, setCharacterName] = React.useState('');
  const [sceneDescription, setSceneDescription] = React.useState('');
  const [question1, setQuestion1] = React.useState('');
  const [question2, setQuestion2] = React.useState('');
  const [question3, setQuestion3] = React.useState('');

  const isFormValid = characterName.trim() && sceneDescription.trim()
    && question1.trim() && question2.trim() && question3.trim();

  // 使用 Store 的推导错误作为结果卡片 key（每次推导时重置）
  const deriveKey = React.useRef(0);

  const handleDerive = async () => {
    if (!isFormValid) return;
    deriveKey.current += 1;
    await deriveBehavior({
      characterName: characterName.trim(),
      sceneDescription: sceneDescription.trim(),
      question1: question1.trim(),
      question2: question2.trim(),
      question3: question3.trim(),
    });
  };

  const handleReset = () => {
    setCharacterName('');
    setSceneDescription('');
    setQuestion1('');
    setQuestion2('');
    setQuestion3('');
    resetDerivation();
  };

  return (
    <div style={sectionStyle}>
      {/* 折叠头部 */}
      <div
        onClick={() => setExpanded(!expanded)}
        style={sectionTitleStyle}
      >
        <span>角色行为推导</span>
        <span style={{ ...expandIconStyle, transform: expanded ? 'rotate(180deg)' : 'rotate(0deg)' }}>
          ▼
        </span>
      </div>

      {/* 折叠内容 */}
      {expanded && (
        <div style={{ padding: '0 16px 16px' }}>
          <div style={{
            fontSize: '0.8rem',
            color: 'var(--text-tertiary)',
            marginBottom: 12,
            lineHeight: 1.5,
          }}>
            回答以下三个问题，AI 会推导该角色在给定场景下的合理行为预期。
            对比你的实际写法，看看是否一致。
          </div>

          {/* 角色名 */}
          <div style={fieldRowStyle}>
            <label style={labelStyle}>角色名</label>
            <input
              value={characterName}
              onChange={(e) => setCharacterName(e.target.value)}
              placeholder="输入角色名称..."
              style={{ ...inputStyle, padding: 8 }}
            />
          </div>

          {/* 场景描述 */}
          <div style={fieldRowStyle}>
            <label style={labelStyle}>场景描述</label>
            <textarea
              value={sceneDescription}
              onChange={(e) => setSceneDescription(e.target.value)}
              placeholder="描述当前场景..."
              rows={2}
              style={inputStyle}
            />
          </div>

          {/* 三问 */}
          <QuestionField
            number={1}
            label="他的过往经历让他怎么看待这件事？"
            value={question1}
            onChange={setQuestion1}
          />
          <QuestionField
            number={2}
            label="他当前的利益诉求是什么？"
            value={question2}
            onChange={setQuestion2}
          />
          <QuestionField
            number={3}
            label="他的性格底色驱使他怎么做？"
            value={question3}
            onChange={setQuestion3}
          />

          {/* 操作按钮 */}
          <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
            <button
              onClick={handleDerive}
              disabled={!isFormValid || derivationLoading}
              aria-label={derivationLoading ? '推导中' : '开始推导'}
              style={{
                ...primaryBtnStyle,
                opacity: (!isFormValid || derivationLoading) ? 0.5 : 1,
              }}
            >
              {derivationLoading ? '推导中...' : '开始推导'}
            </button>
            {derivationResult && (
              <button
                onClick={handleReset}
                aria-label="清空重试"
                style={{
                  padding: '8px 16px',
                  borderRadius: 6,
                  border: '1px solid var(--border)',
                  backgroundColor: 'transparent',
                  color: 'var(--text-secondary)',
                  cursor: 'pointer',
                  fontSize: '0.85rem',
                }}
              >
                清空重试
              </button>
            )}
          </div>

          {/* 错误提示 */}
          {derivationError && (
            <div style={{
              marginTop: 12,
              padding: 10,
              backgroundColor: '#fdf0ef',
              borderRadius: 8,
              border: '1px solid #e74c3c',
              fontSize: '0.8rem',
              color: 'var(--error)',
            }}>
              {derivationError}
            </div>
          )}

          {/* 推导结果 */}
          {derivationResult && (
            <div key={deriveKey.current} style={resultCardStyle}>
              <div style={{ fontWeight: 600, color: 'var(--success)', marginBottom: 8 }}>
                推导结果
              </div>

              <div style={{ fontWeight: 500, color: 'var(--text-primary)', marginBottom: 4 }}>
                合理行为预期
              </div>
              <div style={{ marginBottom: 12, color: 'var(--text-secondary)' }}>
                {derivationResult.derivedBehavior}
              </div>

              <div style={{ fontWeight: 500, color: 'var(--text-primary)', marginBottom: 4 }}>
                推导依据
              </div>
              <div style={{ marginBottom: 12, color: 'var(--text-secondary)', fontSize: '0.8rem' }}>
                {derivationResult.analysis}
              </div>

              <div style={{
                padding: 8,
                backgroundColor: '#fef5e7',
                borderRadius: 6,
                border: '1px solid #f9e79f',
                fontSize: '0.8rem',
              }}>
                <div style={{ fontWeight: 500, color: '#d35400', marginBottom: 2 }}>
                  一致性自省
                </div>
                <div style={{ color: 'var(--text-secondary)' }}>
                  {derivationResult.consistencyCheck}
                </div>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
