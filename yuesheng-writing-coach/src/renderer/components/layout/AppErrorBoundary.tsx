import React from 'react';

interface AppErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

/**
 * 全局错误边界
 * 捕获渲染进程未处理异常，避免白屏
 */
export class AppErrorBoundary extends React.Component<
  { children: React.ReactNode },
  AppErrorBoundaryState
> {
  constructor(props: { children: React.ReactNode }) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): AppErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo): void {
    console.error('[AppErrorBoundary] 捕获未处理异常:', error, info);
  }

  render(): React.ReactNode {
    if (this.state.hasError) {
      return (
        <div style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          height: '100vh',
          padding: 24,
          background: 'var(--bg-primary)',
          color: 'var(--text-primary)',
        }}>
          <h2 style={{ marginBottom: 8 }}>应用遇到问题</h2>
          <p style={{ marginBottom: 16, color: 'var(--text-secondary)' }}>
            {this.state.error?.message ?? '未知错误'}
          </p>
          <button
            onClick={() => window.location.reload()}
            style={{
              padding: '8px 20px',
              border: '1px solid var(--accent)',
              borderRadius: 'var(--radius-full)',
              background: 'var(--accent)',
              color: '#fff',
              cursor: 'pointer',
            }}
          >
            重新加载
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
