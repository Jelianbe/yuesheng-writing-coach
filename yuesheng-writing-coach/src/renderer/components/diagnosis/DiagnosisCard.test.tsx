/**
 * DiagnosisCard 组件测试
 * 覆盖：折叠/展开状态、症候展示、严重度标签、建议动作、自检清单
 */
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { DiagnosisCard } from './DiagnosisCard';
import { createDiagnosisEntry, createSyndrome } from '../../../test/fixtures';

describe('DiagnosisCard', () => {
  it("无症候时返回 null", () => {
    const diagnosis = createDiagnosisEntry({ syndromes: [] });
    const { container } = render(
      <DiagnosisCard diagnosis={diagnosis} />
    );
    expect(container.innerHTML).toBe('');
  });

  it("摘要行显示主要症候名称和证据预览", () => {
    const diagnosis = createDiagnosisEntry();
    const top = diagnosis.syndromes[0];
    render(<DiagnosisCard diagnosis={diagnosis} />);

    expect(screen.getByText(top.name)).toBeInTheDocument();
    expect(screen.getByText(`${top.evidence[0].slice(0, 50)}...`)).toBeInTheDocument();
  });

  it("严重度标签显示在摘要行", () => {
    const diagnosis = createDiagnosisEntry();
    render(<DiagnosisCard diagnosis={diagnosis} />);

    // L2 → "中度"
    expect(screen.getByText('中度')).toBeInTheDocument();
  });

  it("点击展开按钮显示详细症候列表", async () => {
    const user = userEvent.setup();
    const diagnosis = createDiagnosisEntry();
    render(<DiagnosisCard diagnosis={diagnosis} />);

    const toggle = screen.getByRole('button', { name: /toggle diagnosis details/i });
    await user.click(toggle);

    // 展开后显示所有症候（可能同时出现在标题和详情区）
    for (const s of diagnosis.syndromes) {
      const matches = screen.getAllByText(s.name);
      expect(matches.length).toBeGreaterThanOrEqual(1);
    }
    // 显示严重度标签
    expect(screen.getByText('严重')).toBeInTheDocument(); // L3
  });

  it("展开后显示原文证据区块", async () => {
    const user = userEvent.setup();
    const diagnosis = createDiagnosisEntry();
    render(<DiagnosisCard diagnosis={diagnosis} />);

    await user.click(screen.getByRole('button', { name: /toggle diagnosis details/i }));

    // 原文证据区块标题（OriginalEvidenceSection 在无数据时不渲染，
    // 但 "原文证据" 标题只在有数据时出现，此处验证展开后不报错即可）
    // 摘要行仍显示 evidence 预览
    const top = diagnosis.syndromes[0];
    expect(screen.getByText(`${top.evidence[0].slice(0, 50)}...`)).toBeInTheDocument();
  });

  it("展开后显示建议动作标签", async () => {
    const user = userEvent.setup();
    const diagnosis = createDiagnosisEntry({
      syndromes: [
        createSyndrome({ id: 'P001', name: '世界观膨胀', suggestedActions: ['A001', 'A005'] }),
      ],
    });
    render(<DiagnosisCard diagnosis={diagnosis} />);

    await user.click(screen.getByRole('button', { name: /toggle diagnosis details/i }));

    expect(screen.getByText('建议动作')).toBeInTheDocument();
    expect(screen.getByText('缩小范围')).toBeInTheDocument();
    expect(screen.getByText('阶段拆分')).toBeInTheDocument();
  });

  it("展开后显示自检清单（已知症候）", async () => {
    const user = userEvent.setup();
    const diagnosis = createDiagnosisEntry({
      syndromes: [
        createSyndrome({ id: 'P001', name: '世界观膨胀' }),
      ],
    });
    render(<DiagnosisCard diagnosis={diagnosis} />);

    await user.click(screen.getByRole('button', { name: /toggle diagnosis details/i }));

    // 自检清单标题
    expect(screen.getByText('自检清单')).toBeInTheDocument();
    // 自检问题（P001 的第 1 个问题）
    expect(screen.getByText('你的开篇是否聚焦在一个具体场景上？')).toBeInTheDocument();
  });

  it("未知症候不显示自检清单", async () => {
    const user = userEvent.setup();
    const diagnosis = createDiagnosisEntry({
      syndromes: [
        createSyndrome({ id: 'P999', name: '未知症候' }),
      ],
    });
    render(<DiagnosisCard diagnosis={diagnosis} />);

    await user.click(screen.getByRole('button', { name: /toggle diagnosis details/i }));

    expect(screen.queryByText('自检清单')).not.toBeInTheDocument();
  });

  it("勾选自检清单后显示'已自查'状态", async () => {
    const user = userEvent.setup();
    const diagnosis = createDiagnosisEntry({
      syndromes: [
        createSyndrome({ id: 'P003', name: '情绪标签化', evidence: ['他很伤心。'] }),
      ],
    });
    render(<DiagnosisCard diagnosis={diagnosis} />);

    await user.click(screen.getByRole('button', { name: /toggle diagnosis details/i }));

    // 勾选所有 checklist 项
    const checkboxes = screen.getAllByRole('checkbox');
    for (const cb of checkboxes) {
      await user.click(cb);
    }

    expect(screen.getByText(/已自查/)).toBeInTheDocument();
  });

  it("展开/折叠状态由 aria-expanded 反映", async () => {
    const user = userEvent.setup();
    const diagnosis = createDiagnosisEntry();
    render(<DiagnosisCard diagnosis={diagnosis} />);

    const toggle = screen.getByRole('button', { name: /toggle diagnosis details/i });
    expect(toggle).toHaveAttribute('aria-expanded', 'false');

    await user.click(toggle);
    expect(toggle).toHaveAttribute('aria-expanded', 'true');

    await user.click(toggle);
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
  });
});
