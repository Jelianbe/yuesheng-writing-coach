import React from 'react';
import { ConfigPage } from '../pages/ConfigPage';
import { OnboardingFlow } from '../onboarding/OnboardingFlow';
import type { ApiConfig, ConnectionTestResult, OnboardingBaseline } from '../../shared/types';

export interface AppConfigGateProps {
  /** 是否正在加载配置 */
  isConfigLoading: boolean;
  /** 是否已配置 API Key */
  isConfigured: boolean;
  /** 是否显示引导流程 */
  showOnboarding: boolean;
  /** API 配置 */
  config: ApiConfig & { attitudeLevel: string; maxTokens: number };
  /** 保存配置回调 */
  onSaveConfig: (config: ApiConfig) => Promise<void>;
  /** 测试连接回调 */
  onTestConnection: (apiKey: string, baseUrl: string) => Promise<ConnectionTestResult>;
  /** 引导完成回调 */
  onOnboardingComplete: (baseline: OnboardingBaseline) => Promise<void>;
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
 * 2. 配置页 → 显示完整配置页面
 * 3. 未配置 → 显示居中配置页面
 * 4. 新用户引导 → 显示引导流程
 * 5. 全部通过 → 渲染 children（主应用）
 */
export const AppConfigGate: React.FC<AppConfigGateProps> = ({
  isConfigLoading,
  isConfigured,
  showOnboarding,
  config,
  onSaveConfig,
  onTestConnection,
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

  // === 配置页（按钮触发）===
  // 由外部通过 onBackToMain 控制返回
  // 直接通过 props 传入 view 状态

  // === 未配置 ===
  if (!isConfigured) {
    return (
      <div style={{ height: '100vh', width: '100vw', backgroundColor: 'var(--color-bg)', overflowY: 'auto' }}>
        <div style={{ maxWidth: '512px', margin: '0 auto', padding: '24px 16px' }}>
          <ConfigPage
            config={config}
            onSave={onSaveConfig}
            onBack={() => {}}
            onTestConnection={onTestConnection}
          />
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
