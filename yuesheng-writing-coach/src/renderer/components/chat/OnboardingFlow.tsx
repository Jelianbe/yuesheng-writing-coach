/**
 * OnboardingFlow — 新用户引导流程（步骤1-3）
 *
 * 从 ChatView 拆分出的独立引导组件，负责：
 * - 步骤1：写作类型选择
 * - 步骤2：邀请用户发送文字
 * - 步骤3：引导完成确认
 */

import React from 'react';
import styles from './ChatView.module.css';

interface OnboardingFlowProps {
  onboardingStep: number;
  skipOnboarding: () => void;
  setOnboardingStep: (step: 0 | 1 | 2 | 3) => void;
  completeOnboarding: () => void;
}

export const OnboardingFlow: React.FC<OnboardingFlowProps> = ({
  onboardingStep,
  skipOnboarding,
  setOnboardingStep,
  completeOnboarding,
}) => {
  if (onboardingStep === 1) {
    return (
      <div className={styles.onboarding}>
        <div className={styles.onboardingTitle}>
          你好！我是月笙，你的写作教练。
        </div>
        <div className={styles.onboardingDesc}>
          我不是帮你写作文的工具，而是帮你成为更好的写作者。
          我会读你的文字，指出可以提升的地方，但不会替你改写——因为成长属于你。
        </div>
        <div className={styles.onboardingQuestion}>
          先认识一下：你主要写什么类型？
        </div>
        <div className={styles.typeButtons}>
          {['玄幻', '都市', '科幻', '现实', '历史', '其他'].map(type => (
            <button key={type}
              onClick={() => { setOnboardingStep(2); }}
              className={styles.typeBtn}
            >
              {type}
            </button>
          ))}
          <button onClick={() => setOnboardingStep(2)}
            className={styles.typeBtnGhost}
          >
            说不清
          </button>
        </div>
        <div className={styles.skipLinkWrapper}>
          <button onClick={skipOnboarding}
            className={styles.skipLink}
          >
            跳过引导，直接开始
          </button>
        </div>
      </div>
    );
  }

  if (onboardingStep === 2) {
    return (
      <div className={styles.onboarding}>
        <div className={styles.onboardingTitle}>
          好的，玄幻小说！
        </div>
        <div className={styles.onboardingDesc}>
          为了更好帮你，能不能发一段你最近写的文字？
          不用很长，三五句话也行。
        </div>
        <div className={styles.onboardingHint}>
          （在下方输入框发送你的文字，或者）
        </div>
        <button onClick={() => { setOnboardingStep(3); }}
          className={styles.typeBtnGhost}
        >
          跳过，直接开始
        </button>
      </div>
    );
  }

  if (onboardingStep === 3) {
    return (
      <div className={styles.onboarding}>
        <div className={styles.onboardingTitleAccent}>
          引导完成！🎉
        </div>
        <div className={styles.onboardingDesc}>
          你现在可以开始和月笙对话了。
          月笙会读你的文字，指出可以提升的地方。
        </div>
        <button onClick={completeOnboarding}
          className={styles.primaryBtn}
        >
          开始对话
        </button>
      </div>
    );
  }

  return null;
};
