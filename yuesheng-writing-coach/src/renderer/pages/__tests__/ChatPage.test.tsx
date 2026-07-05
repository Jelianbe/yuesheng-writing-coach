/**
 * ChatPage 交互测试
 *
 * 验证:
 * - 无消息时渲染欢迎引导区和返回按钮
 * - 发送消息动作
 * - 空输入保护
 * - ActionSheet 开关与动作
 * - MoreMenu 跳转
 * - 返回按钮
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor, act } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom/vitest';
import { ChatPage } from '../ChatPage';

// ---------------------------------------------------------------------------
// mocks — 使用 vi.hoisted 避免 vi.mock 提升导致变量未初始化
// ---------------------------------------------------------------------------

const mockPush = vi.fn();
const mockPop = vi.fn();

vi.mock('../../stores/page-stack.store', () => ({
  usePageStackStore: (selector: (s: unknown) => unknown) =>
    selector({ push: mockPush, pop: mockPop }),
}));

const mockSessionStore = {
  currentSessionId: 'session-1',
  sessions: [] as Array<{ id: string; title: string }>,
  loadMessages: vi.fn(),
  switchSession: vi.fn(),
};

vi.mock('../../stores/session.store', () => ({
  useSessionStore: (selector: (s: unknown) => unknown) =>
    selector(mockSessionStore),
}));

const mockSend = vi.fn();
const mockSubscribe = vi.fn<(cb: (envelope: unknown) => void) => () => void>(() => () => {});
const mockFinishStream = vi.fn();

vi.mock('../../hooks/useOrchestrator', () => ({
  useOrchestrator: () => ({
    send: mockSend,
    subscribe: mockSubscribe,
    finishStream: mockFinishStream,
    streaming: false,
  }),
  isTokenEvent: (e: { type: string }) => e.type === 'token',
  isErrorEvent: (e: { type: string }) => e.type === 'error',
  isDoneEvent: (e: { type: string }) => e.type === 'done',
}));

const { mockActiveTrainingCreate, mockMountActiveTraining } = vi.hoisted(() => ({
  mockActiveTrainingCreate: vi.fn<() => Promise<null | Record<string, unknown>>>(() => Promise.resolve(null)),
  mockMountActiveTraining: vi.fn(),
}));

vi.mock('../../services/active-training.service', () => ({
  activeTrainingService: { create: mockActiveTrainingCreate },
}));

vi.mock('../../stores/training.store', () => ({
  useTrainingStore: (selector: (s: unknown) => unknown) =>
    selector({
      evaluationResult: null,
      mountActiveTraining: mockMountActiveTraining,
    }),
}));

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/**
 * 设置 subscribe mock 并返回捕获回调数组。
 * 调用方通过 push 到该数组的回调手动触发 orchestrator 事件。
 */
function setupSubscribeCapture(): Array<(envelope: unknown) => void> {
  const captured: Array<(envelope: unknown) => void> = [];
  mockSubscribe.mockImplementation((fn: (envelope: unknown) => void) => {
    captured.push(fn);
    return () => {};
  });
  return captured;
}

/**
 * 生成逼近真实数据的 mock create 结果，含完整 5 步训练流数据。
 */
function makeMockCreateResult(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    challengeId: 'ch-t1',
    challengeName: '专项训练',
    originalQuote: '原文示例：他高兴地走进房间，对大家说："大家好。"',
    mode: 'flow5',
    steps: [
      { id: 's1', title: '理解技法', description: '阅读技法说明', status: 'active' as const },
      { id: 's2', title: '观察例证', description: '观看例证', status: 'pending' as const },
      { id: 's3', title: '确认理解', description: '复述要点', status: 'pending' as const },
      { id: 's4', title: '尝试改写', description: '应用技法改写', status: 'pending' as const },
      { id: 's5', title: '获得反馈', description: '查看评估', status: 'pending' as const },
    ],
    currentStepIndex: 0,
    constraint: '保持第一人称视角，增加感官描写细节',
    userDraft: '',
    trainingFlow: {
      syndromeId: 'P001',
      techniqueName: '描写课程',
      category: 'technique',
      steps: [
        { stepId: 1, name: '解说技法', instruction: '描写是通过感官细节让读者身临其境的写作技巧。', userAction: '阅读并理解技法', estimatedMinutes: 3 },
        { stepId: 2, name: '例证展示', instruction: '例证：将"他高兴地走进房间"改为"他推开门，脚步轻盈，嘴角挂着笑"。', userAction: '观察并分析例证', estimatedMinutes: 5 },
        { stepId: 3, name: '确认理解', instruction: '请用自己的话复述描写的核心要点，不少于30字。', userAction: '用自己的话复述', estimatedMinutes: 3 },
        { stepId: 4, name: '尝试改写', instruction: '运用描写技法改写给定原文片段，注意保持原意。', userAction: '改写原文', estimatedMinutes: 10 },
        { stepId: 5, name: '获得反馈', instruction: 'AI 将评估你的改写质量并提供改进建议。', userAction: '查看评估反馈', estimatedMinutes: 3 },
      ],
      estimatedTotalMinutes: 24,
    },
    ...overrides,
  };
}

/** 等待 ChatPage 初始渲染完成（欢迎区出现） */
async function waitForReady() {
  await waitFor(() => {
    expect(screen.getByText('分析一下作品')).toBeInTheDocument();
  });
}

/**
 * 在 act() 内触发 subscribe callback，避免 React state update 产生的 act warning。
 */
function fireCallback(
  capturedCbs: Array<(envelope: unknown) => void>,
  envelope: unknown,
): void {
  act(() => {
    const cb = capturedCbs[0];
    cb(envelope);
  });
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

describe('<ChatPage />', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockSessionStore.currentSessionId = 'session-1';
    mockSessionStore.sessions = [];
    mockSessionStore.loadMessages.mockResolvedValue([]);
    mockSessionStore.switchSession.mockReset();
  });

  // ---- 1. 渲染 ----
  it('无消息时显示欢迎引导区和返回按钮', async () => {
    render(<ChatPage />);

    // 返回按钮始终存在
    expect(screen.getByLabelText('返回')).toBeInTheDocument();

    // 等待 loadMessages 完成后显示欢迎引导区
    await waitFor(() => {
      expect(screen.getByText('嘿,今天想从哪里开始?')).toBeInTheDocument();
    });
    expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    expect(screen.getByText('学点描写技法')).toBeInTheDocument();
    expect(screen.getByText('出个题目练练')).toBeInTheDocument();
  });

  // ---- 2. 发送消息 ----
  it('输入文本后点击发送按钮调用 orchestrator.send', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    // 等待欢迎引导区加载完毕
    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    const input = screen.getByPlaceholderText('输入你的问题和作品…');
    await user.type(input, '如何提升文笔');

    await user.click(screen.getByLabelText('发送'));

    await waitFor(() => {
      expect(mockSend).toHaveBeenCalledWith({
        userMessage: '如何提升文笔',
        sessionId: 'session-1',
        phase: 'requirement',
      });
    });
  });

  // ---- 3. 空输入保护 ----
  it('输入为空时发送按钮禁用,点击不触发 send', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    const sendBtn = screen.getByLabelText('发送');
    // 空输入时按钮应为 disabled
    expect(sendBtn).toBeDisabled();

    await user.click(sendBtn);
    expect(mockSend).not.toHaveBeenCalled();
  });

  // ---- 4. ActionSheet 开关 ----
  it('点击「+」按钮切换 ActionSheet 可见性', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    // 初始: ActionSheet 隐藏
    expect(screen.queryByRole('dialog', { name: '工具' })).not.toBeInTheDocument();

    // 点击「+」按钮 → 显示
    await user.click(screen.getByLabelText('添加工具'));
    expect(screen.getByRole('dialog', { name: '工具' })).toBeInTheDocument();

    // 点击「纯文字」选项(handleClick 会调用 onClose) → 隐藏
    await user.click(screen.getByText('纯文字'));
    expect(screen.queryByRole('dialog', { name: '工具' })).not.toBeInTheDocument();
  });

  // ---- 5. ActionSheet: "设定" → 跳转设置 ----
  it('ActionSheet 中点击「设定」导航到 settings 页面', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    await user.click(screen.getByLabelText('添加工具'));
    await user.click(screen.getByText('设定'));

    expect(mockPush).toHaveBeenCalledWith('settings', { label: '对话配置' });
  });

  // ---- 6. ActionSheet: "图片/文档" → 显示错误 ----
  it('ActionSheet 中点击「图片」显示暂不支持提示', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    await user.click(screen.getByLabelText('添加工具'));
    await user.click(screen.getByText('图片'));

    expect(screen.getByRole('alert')).toHaveTextContent('暂不支持文件上传');
  });

  it('ActionSheet 中点击「文档」同样显示暂不支持提示', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    await user.click(screen.getByLabelText('添加工具'));
    await user.click(screen.getByText('文档'));

    expect(screen.getByRole('alert')).toHaveTextContent('暂不支持文件上传');
  });

  // ---- 7. MoreMenu: "对话配置" → 跳转设置 ----
  it('MoreMenu 中点击「对话配置」导航到 settings 页面', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    // 打开 MoreMenu
    await user.click(screen.getByLabelText('更多操作'));

    // 点击「对话配置」
    const configItem = screen.getByRole('menuitem', { name: '对话配置' });
    await user.click(configItem);

    expect(mockPush).toHaveBeenCalledWith('settings', { label: '对话配置' });
  });

  // ---- 8. 返回按钮 ----
  it('点击返回按钮调用 pop()', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    await user.click(screen.getByLabelText('返回'));
    expect(mockPop).toHaveBeenCalledOnce();
  });

  // ---- Sprint 37: 训练入口交互 ----

  it('ActionSheet 中点击「训练」调用 activeTrainingService.create', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    await user.click(screen.getByLabelText('添加工具'));
    await user.click(screen.getByText('训练'));

    await waitFor(() => {
      expect(mockActiveTrainingCreate).toHaveBeenCalledWith('session-1', 'training');
    });
  });

  it('ActionSheet 中点击「训练」创建失败时显示错误', async () => {
    mockActiveTrainingCreate.mockRejectedValueOnce(new Error('create failed'));
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    await user.click(screen.getByLabelText('添加工具'));
    await user.click(screen.getByText('训练'));

    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent('创建训练失败');
    });
  });

  it('training_triggered 事件插入系统消息', async () => {
    const capturedCbs = setupSubscribeCapture();
    render(<ChatPage />);
    await waitForReady();

    // streamId 需匹配 activeStreamIdRef.current 初始值 null
    fireCallback(capturedCbs, {
      streamId: null,
      event: {
        type: 'training_triggered',
        payload: {
          sessionId: 'session-1',
          syndromeId: 'P001',
          reason: 'user_request',
        },
      },
    });

    // 训练建议按钮应出现
    await waitFor(() => {
      expect(screen.getByText('开始训练')).toBeInTheDocument();
    });
  });

  it('训练创建成功时挂载 mountActiveTraining', async () => {
    mockMountActiveTraining.mockReset();
    mockActiveTrainingCreate.mockResolvedValue(makeMockCreateResult());

    const user = userEvent.setup();
    render(<ChatPage />);
    await waitForReady();

    await user.click(screen.getByLabelText('添加工具'));
    await user.click(screen.getByText('训练'));

    await waitFor(() => {
      expect(mockMountActiveTraining).toHaveBeenCalledWith('session-1');
    });
  });

  // ======================================================================
  // Sprint 41: 综合功能测试 — 对话/数据流/训练/UI
  // ======================================================================

  describe('对话功能测试 (发送"你好"并验证响应)', () => {
    it('发送"你好"并验证完整流式响应', async () => {
      mockSend.mockResolvedValue({ streamId: 'stream-c1' });
      const capturedCbs = setupSubscribeCapture();

      const user = userEvent.setup();
      render(<ChatPage />);
      await waitForReady();

      const input = screen.getByPlaceholderText('输入你的问题和作品…');
      await user.type(input, '你好');
      await user.click(screen.getByLabelText('发送'));

      // 用户消息"你好"出现
      await waitFor(() => {
        expect(screen.getByText('你好')).toBeInTheDocument();
      });
      expect(mockSend).toHaveBeenCalledWith({
        userMessage: '你好',
        sessionId: 'session-1',
        phase: 'requirement',
      });

      // 模拟 token 事件
      fireCallback(capturedCbs, { streamId: 'stream-c1', event: { type: 'token', content: '你好！' } });
      await waitFor(() => {
        expect(screen.getByText(/你好！/)).toBeInTheDocument();
      });

      fireCallback(capturedCbs, { streamId: 'stream-c1', event: { type: 'token', content: '我是月笙写作教练' } });
      await waitFor(() => {
        expect(screen.getByText(/月笙写作教练/)).toBeInTheDocument();
      });

      // done 事件
      fireCallback(capturedCbs, { streamId: 'stream-c1', event: { type: 'done', fullResponse: '你好！我是月笙写作教练' } });

      // 输入框被清空
      await waitFor(() => {
        expect(input).toHaveValue('');
      });
    });

    it('发送"你好"时 send 失败显示错误信息', async () => {
      mockSend.mockImplementationOnce(() => Promise.resolve(null));

      const user = userEvent.setup();
      render(<ChatPage />);
      await waitForReady();

      await user.type(screen.getByPlaceholderText('输入你的问题和作品…'), '你好');
      await user.click(screen.getByLabelText('发送'));

      // 确保 send 确实被调用了
      await waitFor(() => {
        expect(mockSend).toHaveBeenCalled();
      });

      // 确认错误提示出现
      const alert = await screen.findByRole('alert', undefined, { timeout: 2000 });
      expect(alert).toHaveTextContent('发送失败,主进程未响应');
      expect(screen.getByText('你好')).toBeInTheDocument();
    });

    it('发送"你好"时 stream 事件报错显示错误信息', async () => {
      mockSend.mockResolvedValue({ streamId: 'stream-c3' });
      const capturedCbs = setupSubscribeCapture();

      const user = userEvent.setup();
      render(<ChatPage />);
      await waitForReady();

      await user.type(screen.getByPlaceholderText('输入你的问题和作品…'), '你好');
      await user.click(screen.getByLabelText('发送'));

      await waitFor(() => {
        expect(capturedCbs.length).toBeGreaterThan(0);
      });
      fireCallback(capturedCbs, { streamId: 'stream-c3', event: { type: 'error', payload: { code: 'E001', message: 'API 超时' } } });

      await waitFor(() => {
        expect(screen.getByRole('alert')).toHaveTextContent('E001: API 超时');
      });
    });
  });

  describe('数据流验证 (事件驱动)', () => {
    it('phase_transition 事件插入阶段变更系统消息', async () => {
      const capturedCbs = setupSubscribeCapture();

      render(<ChatPage />);
      await waitForReady();

      // activeStreamIdRef.current 初始为 null，需 streamId: null 才能通过过滤器
      fireCallback(capturedCbs, { streamId: null, event: { type: 'phase_transition', payload: { phase: 'diagnosis', summary: '诊断分析中' } } });

      await waitFor(() => {
        expect(screen.getByText(/进入诊断分析阶段/)).toBeInTheDocument();
      });
    });

    it('diagnosis_extracted 事件插入诊断系统消息', async () => {
      const capturedCbs = setupSubscribeCapture();

      render(<ChatPage />);
      await waitForReady();

      fireCallback(capturedCbs, { streamId: null, event: { type: 'diagnosis_extracted', payload: { syndromes: [{ id: 'P001' }, { id: 'P002' }], summary: '已识别 2 个症候' } } });

      await waitFor(() => {
        expect(screen.getByText(/已识别 2 个写作症候/)).toBeInTheDocument();
      });
    });

    it('模拟完整事件链: token → phase → diagnosis → done', async () => {
      mockSend.mockResolvedValue({ streamId: 'stream-d3' });
      const capturedCbs = setupSubscribeCapture();

      const user = userEvent.setup();
      render(<ChatPage />);
      await waitForReady();

      await user.type(screen.getByPlaceholderText('输入你的问题和作品…'), '请分析我的作品');
      await user.click(screen.getByLabelText('发送'));

      await waitFor(() => {
        expect(screen.getByText('请分析我的作品')).toBeInTheDocument();
      });

      // token: 发送后 activeStreamIdRef.current === 'stream-d3'
      fireCallback(capturedCbs, { streamId: 'stream-d3', event: { type: 'token', content: '好的，让我分析' } });
      await waitFor(() => {
        expect(screen.getByText(/好的，让我分析/)).toBeInTheDocument();
      });

      // phase_transition
      fireCallback(capturedCbs, { streamId: 'stream-d3', event: { type: 'phase_transition', payload: { phase: 'diagnosis' } } });
      await waitFor(() => {
        expect(screen.getByText(/进入诊断分析阶段/)).toBeInTheDocument();
      });

      // diagnosis_extracted — ChatPage 忽略 summary,自行构造 "🔍 已识别 X 个写作症候"
      fireCallback(capturedCbs, { streamId: 'stream-d3', event: { type: 'diagnosis_extracted', payload: { syndromes: [{ id: 'P001' }], summary: '发现描写不足' } } });
      await waitFor(() => {
        expect(screen.getByText(/已识别 1 个写作症候/)).toBeInTheDocument();
      });

      // done
      fireCallback(capturedCbs, { streamId: 'stream-d3', event: { type: 'done', fullResponse: '好的，让我分析。你的作品中描写不足…' } });
    });
  });

  describe('用户训练场景测试', () => {
    it('training_triggered 事件后点击"开始训练"弹出训练覆盖层', async () => {
      mockActiveTrainingCreate.mockReset();
      mockMountActiveTraining.mockReset();
      mockActiveTrainingCreate.mockResolvedValue(makeMockCreateResult());

      const capturedCbs = setupSubscribeCapture();

      const user = userEvent.setup();
      render(<ChatPage />);
      await waitForReady();

      fireCallback(capturedCbs, { streamId: null, event: { type: 'training_triggered', payload: { sessionId: 'session-1', syndromeId: 'P001', reason: '描写能力待提升' } } });

      await waitFor(() => {
        expect(screen.getByText('开始训练')).toBeInTheDocument();
      });
      expect(screen.getByText(/世界观膨胀/)).toBeInTheDocument();

      await user.click(screen.getByText('开始训练'));

      await waitFor(() => {
        expect(mockActiveTrainingCreate).toHaveBeenCalledWith('session-1', 'training');
      });
      // 验证 overlay 出现(「返回对话」按钮仅在 overlay header 中)
      await waitFor(() => {
        expect(screen.getByText('返回对话')).toBeInTheDocument();
      });
    });

    it('训练覆盖层有「返回对话」按钮可退出', async () => {
      mockActiveTrainingCreate.mockReset();
      mockMountActiveTraining.mockReset();
      mockActiveTrainingCreate.mockResolvedValue(makeMockCreateResult());

      const capturedCbs = setupSubscribeCapture();

      const user = userEvent.setup();
      render(<ChatPage />);
      await waitForReady();

      fireCallback(capturedCbs, { streamId: null, event: { type: 'training_triggered', payload: { sessionId: 'session-1', syndromeId: 'P001' } } });
      await waitFor(() => {
        expect(screen.getByText('开始训练')).toBeInTheDocument();
      });
      await user.click(screen.getByText('开始训练'));
      // 验证 overlay 出现（「返回对话」按钮唯一属于 overlay header）
      await waitFor(() => {
        expect(screen.getByText('返回对话')).toBeInTheDocument();
      });
      const backBtn = screen.getByText('返回对话');
      expect(backBtn).toBeInTheDocument();
      await user.click(backBtn);

      // 点击「返回对话」后 overlay 消失——「返回对话」按钮不再存在
      await waitFor(() => {
        expect(screen.queryByText('返回对话')).not.toBeInTheDocument();
      });
    });
  });

  describe('界面显示验证', () => {
    it('发送消息后消息列表正确渲染用户和 AI 气泡', async () => {
      mockSend.mockResolvedValue({ streamId: 'stream-u1' });
      const capturedCbs = setupSubscribeCapture();

      const user = userEvent.setup();
      render(<ChatPage />);
      await waitForReady();

      await user.type(screen.getByPlaceholderText('输入你的问题和作品…'), '如何提升文笔');
      await user.click(screen.getByLabelText('发送'));

      await waitFor(() => {
        expect(screen.getByText('如何提升文笔')).toBeInTheDocument();
      });

      fireCallback(capturedCbs, { streamId: 'stream-u1', event: { type: 'token', content: '多读多写是基础' } });
      await waitFor(() => {
        expect(screen.getByText(/多读多写是基础/)).toBeInTheDocument();
      });
    });

    it('system 系统消息正常显示 (phase/diagnosis/training)', async () => {
      const capturedCbs = setupSubscribeCapture();

      render(<ChatPage />);
      await waitForReady();

      // activeStreamIdRef.current 为 null，需 streamId: null 通过过滤器
      fireCallback(capturedCbs, { streamId: null, event: { type: 'phase_transition', payload: { phase: 'requirement' } } });
      await waitFor(() => {
        expect(screen.getByText(/进入需求了解阶段/)).toBeInTheDocument();
      });

      fireCallback(capturedCbs, { streamId: null, event: { type: 'diagnosis_extracted', payload: { syndromes: [{ id: 'P001' }], summary: '发现描写不足' } } });
      await waitFor(() => {
        expect(screen.getByText(/已识别 1 个写作症候/)).toBeInTheDocument();
      });

      fireCallback(capturedCbs, { streamId: null, event: { type: 'training_triggered', payload: { syndromeId: 'P001', reason: '检测到症候' } } });
      await waitFor(() => {
        expect(screen.getByText(/检测到.*症候/)).toBeInTheDocument();
      });
      expect(screen.getByText('开始训练')).toBeInTheDocument();
    });

    it('错误提示条可手动关闭', async () => {
      const capturedCbs = setupSubscribeCapture();

      const user = userEvent.setup();
      render(<ChatPage />);
      await waitForReady();

      // activeStreamIdRef.current 为 null，需 streamId: null 通过过滤器
      fireCallback(capturedCbs, { streamId: null, event: { type: 'error', payload: { code: 'ERR', message: '网络错误' } } });

      await waitFor(() => {
        expect(screen.getByRole('alert')).toHaveTextContent('ERR: 网络错误');
      });

      await user.click(screen.getByLabelText('关闭'));
      expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    });
  });
});
