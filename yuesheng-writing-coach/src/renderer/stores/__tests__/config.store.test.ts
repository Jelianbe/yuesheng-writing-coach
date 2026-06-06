// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { useConfigStore } from '../config.store';
import { IPC_CHANNELS } from '../../shared/constants';

function mockElectronAPI() {
  window.electronAPI = {
    invoke: vi.fn().mockResolvedValue(undefined) as (...args: unknown[]) => Promise<unknown>,
    on: vi.fn() as (channel: string, callback: (...args: unknown[]) => void) => () => void,
  };
}

function clearMock() {
  delete window.electronAPI;
}

describe('ConfigStore - attitudeLevel', () => {
  beforeEach(() => {
    useConfigStore.setState({
      apiKey: '',
      baseUrl: 'https://api.deepseek.com/v1',
      modelName: 'deepseek-v4-pro',
      temperature: 0.7,
      attitudeLevel: 'yuesheng',
      isConfigured: false,
      isLoading: false,
      testStatus: 'idle',
      testError: undefined,
      testResponseTime: undefined,
      validation: { isValid: false, errors: ['尚未加载配置'] },
    });
    clearMock();
    vi.restoreAllMocks();
  });

  it('默认 attitudeLevel 为 yuesheng', () => {
    const state = useConfigStore.getState();
    expect(state.attitudeLevel).toBe('yuesheng');
  });

  it('setAttitudeLevel 更新状态并通过 IPC 持久化', async () => {
    mockElectronAPI();

    await useConfigStore.getState().setAttitudeLevel('doubao');

    const invoke = window.electronAPI!.invoke;
    expect(invoke).toHaveBeenCalledWith(
      IPC_CHANNELS.CONFIG_SET,
      { key: 'attitudeLevel', value: 'doubao' },
    );
    expect(useConfigStore.getState().attitudeLevel).toBe('doubao');
  });

  it('setAttitudeLevel 可切换回 yuesheng', async () => {
    mockElectronAPI();

    await useConfigStore.getState().setAttitudeLevel('doubao');
    expect(useConfigStore.getState().attitudeLevel).toBe('doubao');

    await useConfigStore.getState().setAttitudeLevel('yuesheng');
    expect(useConfigStore.getState().attitudeLevel).toBe('yuesheng');
  });
});
