/** MessageInput 组件测试
 * 覆盖：渲染、输入、发送、禁用状态
 * 可以拦截：collapsed prop 传递错误、disabled 逻辑错误
 */
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MessageInput } from './MessageInput';

describe('MessageInput', () => {
  const defaultProps = {
    onSend: vi.fn(),
    onStop: vi.fn(),
    isStreaming: false,
    disabled: false,
  };

  it('应该渲染输入框和发送按钮', () => {
    render(<MessageInput {...defaultProps} />);

    const textarea = screen.getByRole('textbox', { name: /message text/i });
    expect(textarea).toBeInTheDocument();

    const sendButton = screen.getByRole('button', { name: /send message/i });
    expect(sendButton).toBeInTheDocument();
  });

  it('输入内容后点击发送应触发 onSend 并清空输入框', async () => {
    const user = userEvent.setup();
    const onSend = vi.fn();
    render(<MessageInput {...defaultProps} onSend={onSend} />);

    const textarea = screen.getByRole('textbox', { name: /message text/i });
    await user.type(textarea, '测试消息');
    expect(textarea).toHaveValue('测试消息');

    await user.click(screen.getByRole('button', { name: /send message/i }));
    expect(onSend).toHaveBeenCalledWith('测试消息');
    expect(textarea).toHaveValue('');
  });

  it('空内容时点击发送不应触发 onSend', async () => {
    const user = userEvent.setup();
    const onSend = vi.fn();
    render(<MessageInput {...defaultProps} onSend={onSend} />);

    await user.click(screen.getByRole('button', { name: /send message/i }));
    expect(onSend).not.toHaveBeenCalled();
  });

  it('disabled 时输入框和按钮应被禁用', () => {
    render(<MessageInput {...defaultProps} disabled={true} />);

    const textarea = screen.getByRole('textbox', { name: /message text/i });
    expect(textarea).toBeDisabled();

    const sendButton = screen.getByRole('button', { name: /send message/i });
    expect(sendButton).toBeDisabled();
  });

  it('isStreaming 时应显示停止按钮', () => {
    render(<MessageInput {...defaultProps} isStreaming={true} />);

    const stopButton = screen.getByRole('button', { name: /stop generation/i });
    expect(stopButton).toBeInTheDocument();
  });

  it('点击停止按钮应调用 onStop', async () => {
    const user = userEvent.setup();
    const onStop = vi.fn();
    render(<MessageInput {...defaultProps} isStreaming={true} onStop={onStop} />);

    await user.click(screen.getByRole('button', { name: /stop generation/i }));
    expect(onStop).toHaveBeenCalled();
  });

  it('按 Enter 发送消息', async () => {
    const user = userEvent.setup();
    const onSend = vi.fn();
    render(<MessageInput {...defaultProps} onSend={onSend} />);

    const textarea = screen.getByRole('textbox', { name: /message text/i });
    await user.type(textarea, 'Enter 发送{Enter}');
    expect(onSend).toHaveBeenCalledWith('Enter 发送');
  });

  it('按 Shift+Enter 不应发送消息', async () => {
    const user = userEvent.setup();
    const onSend = vi.fn();
    render(<MessageInput {...defaultProps} onSend={onSend} />);

    const textarea = screen.getByRole('textbox', { name: /message text/i });
    await user.type(textarea, '多行{Shift>}{Enter}{/Shift}文本');
    expect(onSend).not.toHaveBeenCalled();
  });
});
