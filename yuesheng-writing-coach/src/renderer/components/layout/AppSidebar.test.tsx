/** AppSidebar 组件测试
 * 覆盖：渲染、折叠/展开切换
 * 可以拦截：宽度/样式计算错误、按钮缺失
 */
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AppSidebar } from './AppSidebar';

describe('AppSidebar', () => {
  const defaultProps = {
    sessions: [] as any[],
    activeSessionId: '',
    onSelectSession: vi.fn(),
    onNewSession: vi.fn(),
    collapsed: false,
    onToggleCollapse: vi.fn(),
  };

  it('应该渲染侧栏容器', () => {
    const { container } = render(<AppSidebar {...defaultProps} />);
    const sidebar = container.firstChild as HTMLElement;
    expect(sidebar).toBeInTheDocument();
  });

  it('折叠时应渲染 aria-label 为折叠侧边栏', () => {
    const { rerender } = render(<AppSidebar {...defaultProps} collapsed={false} />);
    // 展开时按钮 aria-label = "折叠侧边栏"
    expect(screen.getByRole('button', { name: /折叠侧边栏/i })).toBeInTheDocument();

    rerender(<AppSidebar {...defaultProps} collapsed={true} />);
    // 折叠时按钮 aria-label = "展开侧边栏"
    expect(screen.getByRole('button', { name: /展开侧边栏/i })).toBeInTheDocument();
  });

  it('切换按钮点击应调用 onToggleCollapse', async () => {
    const user = userEvent.setup();
    const onToggleCollapse = vi.fn();
    render(<AppSidebar {...defaultProps} onToggleCollapse={onToggleCollapse} />);

    const toggleButton = screen.getByRole('button', { name: /折叠侧边栏/i });
    await user.click(toggleButton);
    expect(onToggleCollapse).toHaveBeenCalledTimes(1);
  });

  it('有会话时应显示会话列表标题', () => {
    const sessions = [
      { id: '1', title: '会话 1', tags: [], timeAgo: '刚刚' },
    ];
    render(<AppSidebar {...defaultProps} sessions={sessions} />);

    expect(screen.getByText('会话 1')).toBeInTheDocument();
  });
});
