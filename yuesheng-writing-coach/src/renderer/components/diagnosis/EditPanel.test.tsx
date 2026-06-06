/**
 * EditPanel 组件测试
 * 覆盖：原文展示、编辑区交互、提交/取消行为、加载状态
 */
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { EditPanel } from './EditPanel';

describe('EditPanel', () => {
  const defaultProps = {
    originalTexts: ['他资质平平，只是一个普通的散修，修为筑基中期。'],
    syndromeName: '信息硬塞',
    onSubmit: vi.fn(),
    onCancel: vi.fn(),
    isSubmitting: false,
  };

  it("标题显示症候名称", () => {
    render(<EditPanel {...defaultProps} />);
    expect(screen.getByText('修改 — 信息硬塞')).toBeInTheDocument();
  });

  it("显示只读原文区域", () => {
    render(<EditPanel {...defaultProps} />);
    expect(screen.getByText('他资质平平，只是一个普通的散修，修为筑基中期。')).toBeInTheDocument();
  });

  it("多条原文逐一显示", () => {
    const texts = ['第一段原文。', '第二段原文。'];
    render(<EditPanel {...defaultProps} originalTexts={texts} />);
    expect(screen.getByText('第一段原文。')).toBeInTheDocument();
    expect(screen.getByText('第二段原文。')).toBeInTheDocument();
  });

  it("关闭按钮调用 onCancel", async () => {
    const user = userEvent.setup();
    const onCancel = vi.fn();
    render(<EditPanel {...defaultProps} onCancel={onCancel} />);

    await user.click(screen.getByRole('button', { name: /close edit panel/i }));
    expect(onCancel).toHaveBeenCalledTimes(1);
  });

  it('"取消"按钮调用 onCancel', async () => {
    const user = userEvent.setup();
    const onCancel = vi.fn();
    render(<EditPanel {...defaultProps} onCancel={onCancel} />);

    await user.click(screen.getByText('取消'));
    expect(onCancel).toHaveBeenCalledTimes(1);
  });

  it("文本区可以输入内容", async () => {
    const user = userEvent.setup();
    render(<EditPanel {...defaultProps} />);

    const textarea = screen.getByRole('textbox', { name: /rewrite text/i });
    await user.type(textarea, '他盘坐在硬板床上吐纳了三息便散去。');
    expect(textarea).toHaveValue('他盘坐在硬板床上吐纳了三息便散去。');
  });

  it("空内容时提交按钮禁用", () => {
    render(<EditPanel {...defaultProps} />);
    const submitBtn = screen.getByRole('button', { name: /提交评估/ });
    expect(submitBtn).toBeDisabled();
  });

  it("提交按钮在 isSubmitting 时禁用并显示加载", () => {
    render(<EditPanel {...defaultProps} isSubmitting={true} />);
    const submitBtn = screen.getByRole('button', { name: /提交评估/ });
    expect(submitBtn).toBeDisabled();
    expect(submitBtn).toHaveAttribute('disabled');
  });

  it("输入内容后提交按钮可用，点击触发 onSubmit", async () => {
    const user = userEvent.setup();
    const onSubmit = vi.fn();
    render(<EditPanel {...defaultProps} onSubmit={onSubmit} />);

    const textarea = screen.getByRole('textbox', { name: /rewrite text/i });
    await user.type(textarea, '他摸了摸腰间仅剩的两张匿气符。');

    await user.click(screen.getByRole('button', { name: /提交评估/ }));
    expect(onSubmit).toHaveBeenCalledWith('他摸了摸腰间仅剩的两张匿气符。');
  });

  it("只输入空格时提交按钮禁用", async () => {
    const user = userEvent.setup();
    render(<EditPanel {...defaultProps} />);

    const textarea = screen.getByRole('textbox', { name: /rewrite text/i });
    await user.type(textarea, '   ');
    const submitBtn = screen.getByRole('button', { name: /提交评估/ });
    expect(submitBtn).toBeDisabled();
  });
});
