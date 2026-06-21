import React from 'react';
import { OnboardingFlow } from '../onboarding/OnboardingFlow';

export interface AppConfigGateProps {
  /** 是否正在加载配置 */
  isConfigLoading: boolean;
  /** 是否已配置 API Key */
  isConfigured: boolean;
  /** 是否显示引导流程 */
  showOnboarding: boolean;
  /** 引导完成回调 */
  onOnboardingComplete: (baseline: any) => Promise<void>;
  /** 引导跳过回调 */
  onOnboardingSkip: () => Promise<void>;
  /** 通过守卫后的子节点（主应用内容） */
  children: React.ReactNode;
}

/**
 * 应用配置守卫
 *
 * 在渲染主应用内容前，处理以下前置条件：
 * 1. 配置加载中 → 显示加载动画
 * 2. 新用户引导 → 显示引导流程
 * 3. 全部通过 → 渲染 children（主应用）
 *
 * 配置由 App.tsx 通过 view 状态统一控制，
 * 不在本守卫内部渲染，避免与 view 状态产生冲突。
 */
export const AppConfigGate: React.FC<AppConfigGateProps> = ({
  isConfigLoading,
  showOnboarding,
  onOnboardingComplete,
  onOnboardingSkip,
  children,
}) => {
  // === 加载中 ===
  if (isConfigLoading) {
    return (
      <div className="h-screen w-screen bg-[var(--color-bg)] flex items-center justify-center">
        <div className="text-center">
          <div className="w-12 h-12 rounded-[var(--radius-lg)] bg-surface-secondary flex items-center justify-center mx-auto mb-4 animate-pulse-custom">
            <svg className="w-6 h-6 text-accent-primary animate-spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M21 12a9 9 0 11-6.219-8.56" />
            </svg>
          </div>
          <p className="text-sm text-text-secondary">加载中...</p>
        </div>
      </div>
    );
  }

  // === 新用户引导 ===
  if (showOnboarding) {
    return (
      <div className="h-screen w-screen bg-[var(--color-bg)] flex items-center justify-center">
        <OnboardingFlow
          onComplete={onOnboardingComplete}
          onSkip={onOnboardingSkip}
        />
      </div>
    );
  }

  // === 全部通过，渲染主应用 ===
  return <>{children}</>;
};
