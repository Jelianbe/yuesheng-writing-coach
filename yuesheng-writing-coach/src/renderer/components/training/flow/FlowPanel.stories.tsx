import type { Meta, StoryObj } from '@storybook/react-vite';
import { FlowPanel } from './FlowPanel';
import { MemoryRouter } from 'react-router-dom';

// Mock ActiveTrainingSession 数据
const mockActive = {
  challengeId: 'ch-test',
  challengeName: '专项训练：描写技法',
  challengeDescription: '原文示例：他高兴地走进房间。',
  mode: 'flow5' as const,
  steps: [
    { id: 's1', title: '理解技法', description: '阅读技法说明', status: 'active' as const },
    { id: 's2', title: '观察例证', description: '观看例证', status: 'pending' as const },
    { id: 's3', title: '确认理解', description: '复述要点', status: 'pending' as const },
    { id: 's4', title: '尝试改写', description: '应用技法改写', status: 'pending' as const },
    { id: 's5', title: '获得反馈', description: '查看评估', status: 'pending' as const },
  ],
  currentStepIndex: 0,
  originalQuote: '他高兴地走进房间，对大家说："大家好。"',
  constraint: '保持第一人称视角，增加感官描写细节',
  userDraft: '',
  trainingFlow: {
    syndromeId: 'P001',
    techniqueName: '描写课程',
    category: 'technique' as const,
    steps: [
      { stepId: 1, name: '解说技法', instruction: '描写是通过感官细节让读者身临其境的写作技巧。', userAction: '阅读并理解技法', estimatedMinutes: 3 },
      { stepId: 2, name: '例证展示', instruction: '例证：将"他高兴地走进房间"改为"他推开门，脚步轻盈，嘴角挂着笑"。', userAction: '观察并分析例证', estimatedMinutes: 5 },
      { stepId: 3, name: '确认理解', instruction: '请用自己的话复述描写的核心要点，不少于30字。', userAction: '用自己的话复述', estimatedMinutes: 3 },
      { stepId: 4, name: '尝试改写', instruction: '运用描写技法改写给定原文片段，注意保持原意。', userAction: '改写原文', estimatedMinutes: 10 },
      { stepId: 5, name: '获得反馈', instruction: 'AI 将评估你的改写质量并提供改进建议。', userAction: '查看评估反馈', estimatedMinutes: 3 },
    ],
    estimatedTotalMinutes: 24,
  },
};

const meta = {
  title: 'Training/FlowPanel',
  component: FlowPanel,
  decorators: [
    (Story) => (
      <MemoryRouter>
        <div style={{ width: '420px', padding: '16px', border: '1px solid #e5e7eb', borderRadius: '8px' }}>
          <Story />
        </div>
      </MemoryRouter>
    ),
  ],
  parameters: {
    layout: 'centered',
    a11y: { test: 'todo' },
  },
} satisfies Meta<typeof FlowPanel>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {
  args: {
    active: mockActive,
    onReturnToChat: () => alert('返回对话'),
  },
};

export const Step3Confirm: Story = {
  args: {
    active: { ...mockActive, currentStepIndex: 2 },
    onReturnToChat: () => alert('返回对话'),
  },
};

export const Step4Practice: Story = {
  args: {
    active: { ...mockActive, currentStepIndex: 3 },
    onReturnToChat: () => alert('返回对话'),
  },
};
