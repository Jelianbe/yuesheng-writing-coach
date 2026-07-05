/**
 * SettingsPage 交互测试
 *
 * 覆盖：API 配置字段渲染、返回导航、输入更新→保存、显示/隐藏 Key、
 *       测试连接、态度档位切换、三字段批量保存、初始加载状态。
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom/vitest';
import { SettingsPage } from '../SettingsPage';

// --- spies ---
const mockSetApiKey = vi.fn().mockResolvedValue(undefined);
const mockSetBaseUrl = vi.fn().mockResolvedValue(undefined);
const mockSetModelName = vi.fn().mockResolvedValue(undefined);
const mockSetAttitudeLevel = vi.fn().mockResolvedValue(undefined);
const mockSetMaxTokens = vi.fn().mockResolvedValue(undefined);
const mockTestConnection = vi.fn().mockResolvedValue({ success: true, responseTime: 150 });
const mockLoadConfig = vi.fn().mockResolvedValue(undefined);
const mockPop = vi.fn();

/** 可在各测试中修改的可变 store 状态 */
const storeState = vi.hoisted(() => ({
  apiKey: '',
  baseUrl: 'https://api.deepseek.com',
  modelName: 'deepseek-v4-flash',
  attitudeLevel: 'yuesheng' as const,
  attitudeLocked: false,
  maxTokens: 8192,
  isLoading: false,
  isConfigured: false,
  testStatus: 'idle' as const,
  testError: undefined as string | undefined,
  testResponseTime: undefined as number | undefined,
}));

vi.mock('../../stores/config.store', () => ({
  useConfigStore: (selector: (s: unknown) => unknown) =>
    selector({
      get apiKey() {
        return storeState.apiKey;
      },
      get baseUrl() {
        return storeState.baseUrl;
      },
      get modelName() {
        return storeState.modelName;
      },
      get attitudeLevel() {
        return storeState.attitudeLevel;
      },
      get attitudeLocked() {
        return storeState.attitudeLocked;
      },
      get maxTokens() {
        return storeState.maxTokens;
      },
      get isLoading() {
        return storeState.isLoading;
      },
      get isConfigured() {
        return storeState.isConfigured;
      },
      get testStatus() {
        return storeState.testStatus;
      },
      get testError() {
        return storeState.testError;
      },
      get testResponseTime() {
        return storeState.testResponseTime;
      },
      setApiKey: mockSetApiKey,
      setBaseUrl: mockSetBaseUrl,
      setModelName: mockSetModelName,
      setAttitudeLevel: mockSetAttitudeLevel,
      setMaxTokens: mockSetMaxTokens,
      testConnection: mockTestConnection,
      loadConfig: mockLoadConfig,
    }),
}));

vi.mock('../../stores/page-stack.store', () => ({
  usePageStackStore: (selector: (s: unknown) => unknown) =>
    selector({ pop: mockPop }),
}));

describe('<SettingsPage />', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    storeState.apiKey = '';
    storeState.baseUrl = 'https://api.deepseek.com';
    storeState.modelName = 'deepseek-v4-flash';
    storeState.attitudeLevel = 'yuesheng';
    storeState.isLoading = false;
    storeState.testStatus = 'idle';
  });

  it('渲染所有配置字段（API Key / Base URL / Model / 态度档位 / Max Tokens）', () => {
    render(<SettingsPage />);

    // API 配置输入框
    expect(screen.getByPlaceholderText('sk-...')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('https://api.deepseek.com')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('deepseek-v4-flash')).toBeInTheDocument();

    // 4 个态度档位 radio
    const radios = screen.getAllByRole('radio');
    expect(radios).toHaveLength(4);

    // Max Tokens 滑块
    const slider = screen.getByRole('slider');
    expect(slider).toBeInTheDocument();
    expect(slider).toHaveAttribute('min', '1024');
    expect(slider).toHaveAttribute('max', '32768');

    // 保存 + 测试连接按钮
    expect(screen.getByText('保存配置')).toBeInTheDocument();
    expect(screen.getByText('测试连接')).toBeInTheDocument();
  });

  it('返回按钮 → 调用 pop()', async () => {
    const user = userEvent.setup();
    render(<SettingsPage />);

    await user.click(screen.getByLabelText('返回'));
    expect(mockPop).toHaveBeenCalledOnce();
  });

  it('API Key 输入 onChange 更新本地状态，保存后将值写入 store', async () => {
    const user = userEvent.setup();
    render(<SettingsPage />);

    const input = screen.getByPlaceholderText('sk-...');
    await user.type(input, 'sk-test-key-12345');

    // 保存按钮应已启用（hasChanges === true）
    await user.click(screen.getByText('保存配置'));

    expect(mockSetApiKey).toHaveBeenCalledWith('sk-test-key-12345');
  });

  it('显示/隐藏 Key 切换控制 password 可见性', async () => {
    const user = userEvent.setup();
    render(<SettingsPage />);

    const input = screen.getByPlaceholderText('sk-...');
    expect(input).toHaveAttribute('type', 'password');

    await user.click(screen.getByLabelText('显示'));
    expect(input).toHaveAttribute('type', 'text');

    await user.click(screen.getByLabelText('隐藏'));
    expect(input).toHaveAttribute('type', 'password');
  });

  it('测试连接按钮 → 调用 testConnection()', async () => {
    const user = userEvent.setup();
    render(<SettingsPage />);

    // 先用户输入 API Key（让按钮 enabled）
    await user.type(screen.getByPlaceholderText('sk-...'), 'sk-test');

    await user.click(screen.getByText('测试连接'));
    expect(mockTestConnection).toHaveBeenCalledOnce();
  });

  it('态度档位点击 → 调用 setAttitudeLevel()', async () => {
    const user = userEvent.setup();
    render(<SettingsPage />);

    // 点击「严厉」（value: sensei）
    await user.click(screen.getByRole('radio', { name: /严厉/ }));
    expect(mockSetAttitudeLevel).toHaveBeenCalledWith('sensei');
  });

  it('保存配置按钮 → 依次调用 setApiKey / setBaseUrl / setModelName', async () => {
    const user = userEvent.setup();
    render(<SettingsPage />);

    // 修改三个字段
    await user.type(screen.getByPlaceholderText('sk-...'), 'new-key');
    await user.clear(screen.getByPlaceholderText('https://api.deepseek.com'));
    await user.type(screen.getByPlaceholderText('https://api.deepseek.com'), 'https://custom.api.com');
    await user.clear(screen.getByPlaceholderText('deepseek-v4-flash'));
    await user.type(screen.getByPlaceholderText('deepseek-v4-flash'), 'gpt-4o');

    await user.click(screen.getByText('保存配置'));

    expect(mockSetApiKey).toHaveBeenCalledWith('new-key');
    expect(mockSetBaseUrl).toHaveBeenCalledWith('https://custom.api.com');
    expect(mockSetModelName).toHaveBeenCalledWith('gpt-4o');
  });

  it('初始 isLoading=true 时调用 loadConfig()', () => {
    storeState.isLoading = true;
    render(<SettingsPage />);
    expect(mockLoadConfig).toHaveBeenCalledOnce();
  });
});
