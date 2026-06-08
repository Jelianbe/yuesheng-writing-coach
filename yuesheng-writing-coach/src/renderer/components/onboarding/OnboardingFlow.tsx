import { useState, useCallback } from 'react';
import type { OnboardingBaseline } from '../../shared/types';

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
      // 调用 AI 分析（复用 sendMessage）
      const result = await window.electronAPI?.invoke('onboarding:analyze', { text: sampleText }) as { summary: string } | null;
      if (result?.summary) {
        setAnalysisSummary(result.summary);
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
    <div className="flex flex-col items-center justify-center min-h-[calc(100vh-80px)] px-6 py-8">
      {/* 进度条 */}
      <div className="flex items-center gap-2 mb-8">
        {[1, 2, 3].map((s) => (
          <div
            key={s}
            className={`h-1 rounded-full transition-all duration-300 ${
              s <= step ? 'w-8 bg-[var(--accent-primary)]' : 'w-4 bg-[var(--border-secondary)]'
            }`}
          />
        ))}
      </div>

      {/* Step 1: 互相认识 */}
      {step === 1 && (
        <div className="max-w-md w-full text-center animate-fade-in">
          {/* 月笙自我介绍 */}
          <div className="mb-8 p-6 rounded-[var(--radius-lg)] bg-[var(--surface-secondary)] border border-[var(--border-secondary)]">
            <div className="text-3xl mb-3">🌙</div>
            <h2 className="text-lg font-medium text-[var(--text-primary)] mb-3">你好！我是月笙，你的写作教练。</h2>
            <p className="text-sm text-[var(--text-secondary)] leading-relaxed">
              我不是帮你写作文的工具，而是帮你<strong className="text-[var(--text-primary)]">成为更好的写作者</strong>。
            </p>
            <p className="text-sm text-[var(--text-secondary)] leading-relaxed mt-2">
              我会读你的文字，指出可以提升的地方，但不会替你改写——因为<strong className="text-[var(--text-primary)]">成长属于你</strong>。
            </p>
          </div>

          <p className="text-sm text-[var(--text-secondary)] mb-4">先认识一下：你主要写什么类型？</p>

          <div className="grid grid-cols-2 gap-3">
            {WRITING_TYPES.map((t) => (
              <button
                key={t.value}
                onClick={() => handleTypeSelect(t.value)}
                className={`flex items-center justify-center gap-2 p-3 rounded-[var(--radius-md)] border transition-all duration-200 hover:scale-[1.02] ${
                  writingType === t.value
                    ? 'border-[var(--accent-primary)] bg-[var(--accent-primary)]/10 text-[var(--accent-primary)]'
                    : 'border-[var(--border-secondary)] bg-[var(--surface-secondary)] text-[var(--text-secondary)] hover:border-[var(--accent-primary)]/50'
                }`}
              >
                <span>{t.icon}</span>
                <span className="text-sm">{t.label}</span>
              </button>
            ))}
          </div>

          {/* 跳过按钮 */}
          <button
            onClick={onSkip}
            className="mt-6 text-xs text-[var(--text-tertiary)] hover:text-[var(--text-secondary)] transition-colors"
          >
            跳过引导，直接开始
          </button>
        </div>
      )}

      {/* Step 2: 设定基线 */}
      {step === 2 && (
        <div className="max-w-md w-full text-center animate-fade-in">
          <div className="mb-6 p-5 rounded-[var(--radius-lg)] bg-[var(--surface-secondary)] border border-[var(--border-secondary)]">
            <h3 className="text-sm font-medium text-[var(--text-primary)] mb-2">
              {writingType === 'unknown'
                ? '没关系～随便聊聊天也行。'
                : `好的，${writingType === 'fantasy' ? '玄幻/都市' : writingType === 'sci-fi' ? '科幻' : writingType === 'historical' ? '历史' : '写作'}！`}
            </h3>
            <p className="text-sm text-[var(--text-secondary)] leading-relaxed">
              为了更好帮你，能不能发一段你最近写的文字？<br />
              不用很长，三五句话也行。
            </p>
            <p className="text-xs text-[var(--text-tertiary)] mt-2">
              我会看看你现在的写作特点，这样后面给你的建议会更准。
            </p>
          </div>

          <textarea
            value={sampleText}
            onChange={(e) => setSampleText(e.target.value)}
            placeholder="在这里粘贴你的文字..."
            className="w-full h-32 p-3 rounded-[var(--radius-md)] bg-[var(--surface-secondary)] border border-[var(--border-secondary)] text-sm text-[var(--text-primary)] placeholder:text-[var(--text-tertiary)] resize-none focus:outline-none focus:border-[var(--accent-primary)]/50 transition-colors"
          />

          <div className="flex items-center justify-between mt-3">
            <button
              onClick={handleSkipStep2}
              className="text-sm text-[var(--text-tertiary)] hover:text-[var(--text-secondary)] transition-colors"
            >
              跳过，直接开始
            </button>
            <button
              onClick={handleTextSubmit}
              disabled={!sampleText.trim() || isAnalyzing}
              className={`px-4 py-2 rounded-[var(--radius-md)] text-sm font-medium transition-all duration-200 ${
                sampleText.trim() && !isAnalyzing
                  ? 'bg-[var(--accent-primary)] text-white hover:bg-[var(--accent-primary)]/90'
                  : 'bg-[var(--surface-secondary)] text-[var(--text-tertiary)] cursor-not-allowed'
              }`}
            >
              {isAnalyzing ? '分析中...' : '发送'}
            </button>
          </div>
        </div>
      )}

      {/* Step 3: 推荐起步路径 */}
      {step === 3 && (
        <div className="max-w-md w-full text-center animate-fade-in">
          {/* AI 分析结果 */}
          {analysisSummary && (
            <div className="mb-6 p-5 rounded-[var(--radius-lg)] bg-[var(--surface-secondary)] border border-[var(--border-secondary)] text-left">
              <h3 className="text-sm font-medium text-[var(--text-primary)] mb-3">我看了你的文字，有几个感觉：</h3>
              <p className="text-sm text-[var(--text-secondary)] leading-relaxed whitespace-pre-wrap">{analysisSummary}</p>
            </div>
          )}

          <p className="text-sm text-[var(--text-secondary)] mb-4">你现在最想提升哪方面？</p>

          <div className="flex flex-col gap-2 mb-6">
            {IMPROVEMENT_GOALS.map((g) => (
              <button
                key={g.value}
                onClick={() => handleGoalSelect(g.value)}
                className={`p-3 rounded-[var(--radius-md)] border text-sm transition-all duration-200 hover:scale-[1.01] ${
                  improvementGoal === g.value
                    ? 'border-[var(--accent-primary)] bg-[var(--accent-primary)]/10 text-[var(--accent-primary)]'
                    : 'border-[var(--border-secondary)] bg-[var(--surface-secondary)] text-[var(--text-secondary)] hover:border-[var(--accent-primary)]/50'
                }`}
              >
                {g.label}
              </button>
            ))}
          </div>

          {/* 推荐行动卡片 */}
          <div className="p-4 rounded-[var(--radius-lg)] bg-gradient-to-br from-[var(--accent-primary)]/5 to-transparent border border-[var(--accent-primary)]/20">
            <div className="text-sm font-medium text-[var(--text-primary)] mb-1">📍 推荐起步</div>
            <p className="text-xs text-[var(--text-secondary)]">
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
