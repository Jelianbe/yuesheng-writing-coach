/**
 * TrainingWorkshop 组件测试
 * 覆盖：加载中 / 错误 / 活跃训练 / 三区块布局 / 空状态
 */
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { TrainingWorkshop } from './TrainingWorkshop';
import type { ErrorCard, TrainingRecommendation, ActiveTrainingSession, TrainingRecord } from '../../shared/types';

// ===== 工厂数据 =====

const defaultProps = {
  errorCards: [] as ErrorCard[],
  recommendations: [] as TrainingRecommendation[],
  activeTraining: null as ActiveTrainingSession | null,
  history: [] as TrainingRecord[],
  submissionResult: null as { passed: boolean; feedback: string } | null,
  evaluationResult: null as { score: number; feedback: string; improved: boolean; nextStep: string } | null,
  isLoading: false,
  error: null as string | null,
  onStartTraining: vi.fn(),
  onBackToChat: vi.fn(),
  onSubmitStep: vi.fn(),
  onSkipTraining: vi.fn(),
  onUpdateDraft: vi.fn(),
};

const mockActiveSession: ActiveTrainingSession = {
  challengeId: 'CH-001',
  challengeName: '信息硬塞训练',
  challengeDescription: '请用动作替代旁白',
  mode: 'generic',
  steps: [
    { id: 'review', title: '阅读原文', description: '回顾你的写作', status: 'active' },
    { id: 'rewrite', title: '约束改写', description: '动手改写', status: 'pending' },
    { id: 'submit', title: '提交评估', description: '接收反馈', status: 'pending' },
  ],
  currentStepIndex: 0,
  originalQuote: '他资质平平，只是一个普通的散修。',
  constraint: '不直接交代设定',
  userDraft: '',
};

describe('TrainingWorkshop', () => {
  // ===== 状态视图 =====

  // ===== 状态视图 =====

  describe('状态视图', () => {
    it('加载中显示 loading 状态', () => {
      render(<TrainingWorkshop {...defaultProps} isLoading={true} />);
      expect(screen.getByText('加载中...')).toBeInTheDocument();
    });

    it('错误时显示错误信息和返回按钮', () => {
      render(<TrainingWorkshop {...defaultProps} error="获取数据失败" />);
      expect(screen.getByText('获取数据失败')).toBeInTheDocument();
      expect(screen.getByText('返回对话')).toBeInTheDocument();
    });

    it('有 activeTraining 时渲染 ActiveTrainingView', () => {
      render(
        <TrainingWorkshop
          {...defaultProps}
          activeTraining={mockActiveSession}
        />
      );
      // ActiveTrainingView 显示挑战名称和步骤信息
      expect(screen.getByText('信息硬塞训练')).toBeInTheDocument();
      expect(screen.getByText(/步骤 1\/3/)).toBeInTheDocument();
      expect(screen.getByText('阅读原文')).toBeInTheDocument();
    });

    it('默认显示预训练引导问题（PE-004 五步引导链）', () => {
      render(<TrainingWorkshop {...defaultProps} />);
      // 欢迎画面：引导问题 + 选项
      expect(screen.getByText(/训练工坊/)).toBeInTheDocument();
      expect(screen.getByText('开始训练前，先告诉我：')).toBeInTheDocument();
      expect(screen.getByText('你想优先练什么？')).toBeInTheDocument();
      // 聚焦选项
      expect(screen.getByText('节奏控制')).toBeInTheDocument();
      expect(screen.getByText('角色塑造')).toBeInTheDocument();
      expect(screen.getByText('返回对话')).toBeInTheDocument();
      // 底部提示
      expect(screen.getByText('选择后即可查看推荐训练任务')).toBeInTheDocument();
    });
  });

  // ===== 辅助：导航到主面板 =====

  /** 在欢迎画面点击聚焦和卡点选项，到达三区块主面板 */
  async function navigateToMainPanel() {
    const user = userEvent.setup();
    await user.click(screen.getByText('节奏控制'));
    await user.click(screen.getByText('不知道怎么开始'));
  }

  // ===== ErrorCardsSection =====

  describe('ErrorCardsSection', () => {
    it('空错误卡显示空状态提示', async () => {
      render(<TrainingWorkshop {...defaultProps} />);
      await navigateToMainPanel();
      expect(
        screen.getByText(/发送写作内容后，AI 会自动分析/)
      ).toBeInTheDocument();
    });

    it('有错误卡时显示症候名称和开始练习按钮', async () => {
      const errorCards: ErrorCard[] = [
        {
          syndromeId: 'P004',
          syndromeName: '信息硬塞',
          severity: 'L2',
          diagnosisCount: 3,
          lastQuote: '他资质平平，只是一个普通的散修。',
          lastDiagnosedAt: new Date().toISOString(),
          matchedChallengeId: 'CH-001',
        },
        {
          syndromeId: 'P002',
          syndromeName: '角色工具化',
          severity: 'L3',
          diagnosisCount: 2,
          lastQuote: '散修是最底层的存在。',
          lastDiagnosedAt: new Date().toISOString(),
          matchedChallengeId: 'CH-002',
        },
      ];
      render(<TrainingWorkshop {...defaultProps} errorCards={errorCards} />);
      await navigateToMainPanel();
      expect(screen.getByText('信息硬塞')).toBeInTheDocument();
      expect(screen.getByText('角色工具化')).toBeInTheDocument();
      // 严重度标签
      expect(screen.getByText(/严重/)).toBeInTheDocument(); // L3
      expect(screen.getByText(/中等/)).toBeInTheDocument(); // L2
      // 诊断计数
      expect(screen.getByText('3 次诊断')).toBeInTheDocument();
      expect(screen.getByText('2 次诊断')).toBeInTheDocument();
      // 引用原文
      expect(screen.getByText(/他资质平平/)).toBeInTheDocument();
      // 按钮
      const buttons = screen.getAllByText('开始练习');
      expect(buttons).toHaveLength(2);
    });

    it('无 matchedChallengeId 时不显示开始练习按钮', async () => {
      const cards: ErrorCard[] = [{
        syndromeId: 'P001',
        syndromeName: '世界观膨胀',
        severity: 'L1',
        diagnosisCount: 1,
        lastQuote: '',
        lastDiagnosedAt: new Date().toISOString(),
      }];
      render(<TrainingWorkshop {...defaultProps} errorCards={cards} />);
      await navigateToMainPanel();
      expect(screen.queryByText('开始练习')).toBeNull();
    });
  });

  // ===== RecommendationsSection =====

  describe('RecommendationsSection', () => {
    it('空推荐显示空状态提示', async () => {
      render(<TrainingWorkshop {...defaultProps} />);
      await navigateToMainPanel();
      expect(
        screen.getByText(/暂无推荐/)
      ).toBeInTheDocument();
    });

    it('有推荐时显示任务列表和层级标签', async () => {
      const recommendations: TrainingRecommendation[] = [{
        challengeId: 'CH-001',
        challengeName: '信息硬塞',
        description: '请改写这段文字',
        syndromeId: 'P004',
        severity: 'L2',
        tier: 'structural',
        constraint: '不直接交代信息',
        expectedOutcome: '改善设定释放',
        mode: 'generic',
      }];
      render(<TrainingWorkshop {...defaultProps} recommendations={recommendations} />);
      await navigateToMainPanel();
      expect(screen.getByText('信息硬塞')).toBeInTheDocument();
      expect(screen.getByText(/结构性问题/)).toBeInTheDocument();
      expect(screen.getByText(/约束：不直接交代信息/)).toBeInTheDocument();
    });

    it('无约束条件时不显示约束标签', async () => {
      const recommendations: TrainingRecommendation[] = [{
        challengeId: 'CH-002',
        challengeName: '角色工具化',
        description: '描述',
        syndromeId: 'P002',
        severity: 'L3',
        tier: 'surface',
        constraint: '',
        expectedOutcome: '改善',
        mode: 'generic',
      }];
      render(<TrainingWorkshop {...defaultProps} recommendations={recommendations} />);
      await navigateToMainPanel();
      expect(screen.queryByText(/约束：/)).toBeNull();
    });
  });

  // ===== HistorySection =====

  describe('HistorySection', () => {
    it('空历史显示空状态提示', async () => {
      render(<TrainingWorkshop {...defaultProps} />);
      await navigateToMainPanel();
      expect(
        screen.getByText(/暂无训练记录/)
      ).toBeInTheDocument();
    });

    it('加载中显示 loading 文本', () => {
      render(<TrainingWorkshop {...defaultProps} isLoading={true} />);
      expect(screen.getByText('加载中...')).toBeInTheDocument();
    });

    it('有历史记录时显示记录列表', async () => {
      const history: TrainingRecord[] = [
        {
          id: 'r1',
          sessionId: 's1',
          taskId: 'CH-001',
          syndromeId: 'P004',
          userResponse: '改写稿',
          status: 'completed',
          effectiveness: 0.85,
          aiFeedback: '做得不错',
          assignedAt: new Date().toISOString(),
          completedAt: new Date().toISOString(),
        },
        {
          id: 'r2',
          sessionId: 's1',
          taskId: 'CH-002',
          syndromeId: 'P002',
          userResponse: '',
          status: 'skipped',
          effectiveness: 0,
          aiFeedback: '',
          assignedAt: new Date().toISOString(),
        },
      ];
      render(<TrainingWorkshop {...defaultProps} history={history} />);
      await navigateToMainPanel();
      expect(screen.getByText('CH-001')).toBeInTheDocument();
      expect(screen.getByText('CH-002')).toBeInTheDocument();
      // 有效率标签
      expect(screen.getByText('85% 有效')).toBeInTheDocument();
    });
  });
});
