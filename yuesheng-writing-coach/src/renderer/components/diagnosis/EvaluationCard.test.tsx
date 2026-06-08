/**
 * EvaluationCard 组件测试
 * 覆盖：三种改善状态展示、分析/建议文本、改前改后对比、操作按钮
 */
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { EvaluationCard } from './EvaluationCard';
import { createRewriteEvaluation } from '../../../test/fixtures';

describe('EvaluationCard', () => {
  it("'明显改善'时显示'这个改法有效'", () => {
    const evaluation = createRewriteEvaluation({ improvement: '明显改善' });
    render(<EvaluationCard evaluation={evaluation} />);
    expect(screen.getByText('这个改法有效')).toBeInTheDocument();
  });

  it("'略有改善'时显示'部分改善'", () => {
    const evaluation = createRewriteEvaluation({ improvement: '略有改善' });
    render(<EvaluationCard evaluation={evaluation} />);
    expect(screen.getByText('部分改善')).toBeInTheDocument();
  });

  it("'无明显改善'时显示'需要调整'", () => {
    const evaluation = createRewriteEvaluation({ improvement: '无明显改善' });
    render(<EvaluationCard evaluation={evaluation} />);
    expect(screen.getByText('需要调整')).toBeInTheDocument();
  });

  it("显示分析文本", () => {
    const evaluation = createRewriteEvaluation({
      analysis: '你的修改用动作替代了旁白说明。',
    });
    render(<EvaluationCard evaluation={evaluation} />);
    expect(screen.getByText('你的修改用动作替代了旁白说明。')).toBeInTheDocument();
  });

  it("有 suggestion 时显示建议内容", () => {
    const evaluation = createRewriteEvaluation({
      suggestion: '继续——下一步是加一个环境细节。',
    });
    render(<EvaluationCard evaluation={evaluation} />);
    expect(screen.getByText(/继续——下一步是加一个环境细节。/)).toBeInTheDocument();
  });

  it("无 suggestion 时不显示建议区块", () => {
    const evaluation = createRewriteEvaluation({ suggestion: '' });
    const { container } = render(<EvaluationCard evaluation={evaluation} />);
    // 没有建议：建议前的分隔线和"建议："标签都不应出现
    expect(container.querySelector('.border-t')).toBeNull();
  });

  it("显示改前改后对比", () => {
    const evaluation = createRewriteEvaluation();
    render(
      <EvaluationCard
        evaluation={evaluation}
        originalText="他资质平平，只是一个普通的散修。"
        rewrittenText="他盘坐在硬板床上吐纳了三息便散去。"
      />
    );
    expect(screen.getByText('他资质平平，只是一个普通的散修。')).toBeInTheDocument();
    expect(screen.getByText('他盘坐在硬板床上吐纳了三息便散去。')).toBeInTheDocument();
  });

  it("未提供原文时不显示对比区域", () => {
    const evaluation = createRewriteEvaluation();
    const { container } = render(<EvaluationCard evaluation={evaluation} />);
    expect(container.textContent).not.toContain('对比之前');
  });

  it("显示自定义 actions", () => {
    const evaluation = createRewriteEvaluation();
    render(
      <EvaluationCard
        evaluation={evaluation}
        actions={<button>继续练习</button>}
      />
    );
    expect(screen.getByText('继续练习')).toBeInTheDocument();
  });
});
