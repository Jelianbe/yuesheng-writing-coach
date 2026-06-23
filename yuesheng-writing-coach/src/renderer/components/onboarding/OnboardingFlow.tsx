import { useState, useCallback } from 'react';
import type { OnboardingBaseline } from '../../shared/types';
import { IPC_CHANNELS } from '../../shared/constants';
import styles from './OnboardingFlow.module.css';

// === 常量 ===

const WRITING_TYPES: Array<{ value: OnboardingBaseline['writingType']; label: string; icon: string }> = [
  { value: 'fantasy', label: '玄幻/都市', icon: '🌙' },
  { value: 'sci-fi', label: '科幻/现实', icon: '🚀' },
  { value: 'historical', label: '历史/其他', icon: '📜' },
  { value: 'unknown', label: '说不清', icon: '💭' },
];

const IMPROVEMENT_GOALS: Array<{ value: string; label: string }> = [
  { value: 'character', label: '角色塑造' },
  { value: 'pacing', label: '情节节奏' },
  { value: 'worldbuild', label: '世界观构建' },
  { value: 'expression', label: '文字表达' },
  { value: 'any', label: '随便，你推荐' },
];

// === 引导组件 ===

interface OnboardingFlowProps {
  onComplete: (baseline: OnboardingBaseline) => void;
  onSkip: () => void;
}

export function OnboardingFlow({ onComplete, onSkip }: OnboardingFlowProps) {
  const [step, setStep] = useState<1 | 2 | 3>(1);
  const [writingType, setWritingType] = useState<OnboardingBaseline['writingType'] | null>(null);
  const [sampleText, setSampleText] = useState('');
  const [improvementGoal, setImprovementGoal] = useState<string | null>(null);
  const [analysisSummary, setAnalysisSummary] = useState('');
  const [isAnalyzing, setIsAnalyzing] = useState(false);

  // Step 1: Select writing type
  const handleTypeSelect = useCallback((type: OnboardingBaseline['writingType']) => {
    setWritingType(type);
    // 选择后立即进入 Step 2
    setTimeout(() => setStep(2), 150);
  }, []);

  // Step 2: Submit sample text or skip
  const handleSkipStep2 = useCallback(() => {
    // 跳过直接进入 Step 3
    setStep(3);
  }, []);

  const handleTextSubmit = useCallback(async () => {
    if (!sampleText.trim()) return;

    setIsAnalyzing(true);
    try {
      // P-04 Phase 3: 调用 AI 分析（返回格式为 apiSuccess 的 data.summary）
      const raw = await window.electronAPI?.invoke(IPC_CHANNELS.ONBOARDING_ANALYZE, { text: sampleText.trim() });
      const result = raw as { success: boolean; data?: { summary: string } } | null;
      if (result?.success && result?.data?.summary) {
        setAnalysisSummary(result.data.summary);
      } else {
        setAnalysisSummary('你的文字挺有潜力的，我们继续吧！');
      }
    } catch {
      setAnalysisSummary('你的文字挺有潜力的，我们继续吧！');
    } finally {
      setIsAnalyzing(false);
      setStep(3);
    }
  }, [sampleText]);

  // Step 3: Select improvement goal and complete
  const handleGoalSelect = useCallback((goal: string) => {
    setImprovementGoal(goal);
    if (!writingType) return;

    onComplete({
      writingType,
      sampleText: sampleText.trim() || undefined,
      analysisSummary,
      improvementGoal: goal,
      capturedAt: Date.now(),
    });
  }, [writingType, sampleText, analysisSummary, onComplete]);

  return (
    <div className={`${styles.container} animate-fade-in`}>
      {/* 进度条 */}
      <div className={styles.progressBar}>
        {[1, 2, 3].map((s) => (
          <div
            key={s}
            className={`${styles.progressDot} ${
              s <= step ? styles.progressDotActive : styles.progressDotInactive
            }`}
          />
        ))}
      </div>

      {/* Step 1: 互相认识 */}
      {step === 1 && (
        <div className={styles.stepWrapper}>
          {/* 月笙自我介绍 */}
          <div className={styles.welcomeCard}>
            <div className={styles.welcomeIcon}>🌙</div>
            <h2 className={styles.welcomeHeading}>你好！我是月笙，你的写作教练。</h2>
            <p className={styles.welcomeParagraph}>
              我不是帮你写作文的工具，而是帮你<strong className={styles.welcomeStrong}>成为更好的写作者</strong>。
            </p>
            <p className={styles.welcomeParagraph}>
              我会读你的文字，指出可以提升的地方，但不会替你改写——因为<strong className={styles.welcomeStrong}>成长属于你</strong>。
            </p>
          </div>

          <p className={styles.sectionPrompt}>先认识一下：你主要写什么类型？</p>

          <div className={styles.typeGrid}>
            {WRITING_TYPES.map((t) => (
              <button
                key={t.value}
                onClick={() => handleTypeSelect(t.value)}
                className={`${styles.typeButton} ${
                  writingType === t.value ? styles.typeButtonActive : ''
                }`}
              >
                <span>{t.icon}</span>
                <span>{t.label}</span>
              </button>
            ))}
          </div>

          {/* 跳过按钮 */}
          <button
            onClick={onSkip}
            className={styles.skipLink}
          >
            跳过引导，直接开始
          </button>
        </div>
      )}

      {/* Step 2: 设定基线 */}
      {step === 2 && (
        <div className={styles.stepWrapper}>
          <div className={styles.infoCard}>
            <h3 className={styles.infoCardTitle}>
              {writingType === 'unknown'
                ? '没关系～随便聊聊天也行。'
                : `好的，${writingType === 'fantasy' ? '玄幻/都市' : writingType === 'sci-fi' ? '科幻' : writingType === 'historical' ? '历史' : '写作'}！`}
            </h3>
            <p className={styles.infoCardText}>
              为了更好帮你，能不能发一段你最近写的文字？<br />
              不用很长，三五句话也行。
            </p>
            <p className={styles.infoCardHint}>
              我会看看你现在的写作特点，这样后面给你的建议会更准。
            </p>
          </div>

          <textarea
            value={sampleText}
            onChange={(e) => setSampleText(e.target.value)}
            placeholder="在这里粘贴你的文字..."
            className={styles.textarea}
          />

          <div className={styles.textareaActions}>
            <button
              onClick={handleSkipStep2}
              className={styles.skipTextButton}
            >
              跳过，直接开始
            </button>
            <button
              onClick={handleTextSubmit}
              disabled={!sampleText.trim() || isAnalyzing}
              className={`${styles.submitButton} ${
                sampleText.trim() && !isAnalyzing
                  ? styles.submitButtonActive
                  : styles.submitButtonDisabled
              }`}
            >
              {isAnalyzing ? '分析中...' : '发送'}
            </button>
          </div>
        </div>
      )}

      {/* Step 3: 推荐起步路径 */}
      {step === 3 && (
        <div className={styles.stepWrapper}>
          {/* AI 分析结果 */}
          {analysisSummary && (
            <div className={styles.analysisCard}>
              <h3 className={styles.analysisTitle}>我看了你的文字，有几个感觉：</h3>
              <p className={styles.analysisText}>{analysisSummary}</p>
            </div>
          )}

          <p className={styles.sectionPrompt}>你现在最想提升哪方面？</p>

          <div className={styles.goalList}>
            {IMPROVEMENT_GOALS.map((g) => (
              <button
                key={g.value}
                onClick={() => handleGoalSelect(g.value)}
                className={`${styles.goalButton} ${
                  improvementGoal === g.value ? styles.goalButtonActive : ''
                }`}
              >
                {g.label}
              </button>
            ))}
          </div>

          {/* 推荐行动卡片 */}
          <div className={styles.recommendationCard}>
            <div className={styles.recommendationTitle}>📍 推荐起步</div>
            <p className={styles.recommendationText}>
              {improvementGoal === 'expression' && '诊断：情绪展示 vs 告知 — 让读者"感受"到而非"被告知"'}
              {improvementGoal === 'character' && '诊断：角色动机缺失 — 让每个角色有自己的立场和欲望'}
              {improvementGoal === 'worldbuild' && '诊断：世界观膨胀 — 设定可以后续逐步展开'}
              {improvementGoal === 'pacing' && '诊断：旁白介入过多 — 让故事动起来'}
              {!improvementGoal && '选择一个目标，我会推荐具体的诊断方向'}
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
