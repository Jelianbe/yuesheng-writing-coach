/** AppSidebar V2 组件测试
 * 覆盖：渲染、折叠/展开切换、混合内容区
 */
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AppSidebarV2 } from './AppSidebar';

describe('AppSidebarV2', () => {
  const defaultProps = {
    collapsed: false,
    onToggleCollapse: vi.fn(),
    onNewSession: vi.fn(),
    activeSessionId: '',
    onSelectSession: vi.fn(),
  };

  it('应该渲染侧栏容器', () => {
    const { container } = render(<AppSidebarV2 {...defaultProps} />);
    const sidebar = container.firstChild as HTMLElement;
    expect(sidebar).toBeInTheDocument();
  });

  it('折叠时应渲染 aria-label 为展开侧边栏', () => {
    const { rerender } = render(<AppSidebarV2 {...defaultProps} collapsed={false} />);
    // 展开时按钮 aria-label = "折叠侧边栏"
    expect(screen.getByRole('button', { name: /折叠侧边栏/i })).toBeInTheDocument();

    rerender(<AppSidebarV2 {...defaultProps} collapsed={true} />);
    // 折叠时按钮 aria-label = "展开侧边栏"
    expect(screen.getByRole('button', { name: /展开侧边栏/i })).toBeInTheDocument();
  });

  it('切换按钮点击应调用 onToggleCollapse', async () => {
    const user = userEvent.setup();
    const onToggleCollapse = vi.fn();
    render(<AppSidebarV2 {...defaultProps} onToggleCollapse={onToggleCollapse} />);

    const toggleButton = screen.getByRole('button', { name: /折叠侧边栏/i });
    await user.click(toggleButton);
    expect(onToggleCollapse).toHaveBeenCalledTimes(1);
  });
});
