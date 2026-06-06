/**
 * GrowthCard 组件测试
 * 覆盖：加载骨架屏、有历史/无历史文案
 */
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { GrowthCard } from './GrowthCard';

describe('GrowthCard', () => {
  it("加载状态显示骨架屏且不显示成长记录标题", () => {
    const { container } = render(
      <GrowthCard summary="" hasHistory={false} isLoading={true} />
    );
    // 骨架屏有 animate-pulse-custom 类
    expect(container.querySelector('.animate-pulse-custom')).toBeInTheDocument();
    // 加载时不应显示"成长记录"标题
    expect(container.querySelector('.text-text-tertiary')).toBeNull();
  });

  it("有历史记录时显示成长摘要", () => {
    render(
      <GrowthCard
        summary="这次你试了'用动作替代设定旁白'，比上次进步了。"
        hasHistory={true}
      />
    );
    expect(
      screen.getByText("这次你试了'用动作替代设定旁白'，比上次进步了。")
    ).toBeInTheDocument();
  });

  it("无历史记录时显示提示文案", () => {
    render(
      <GrowthCard
        summary=""
        hasHistory={false}
      />
    );
    expect(
      screen.getByText('这是你的第一次诊断，还没有对比数据。')
    ).toBeInTheDocument();
  });

  it("始终显示'成长记录'标题", () => {
    render(<GrowthCard summary="" hasHistory={false} />);
    expect(screen.getByText('成长记录')).toBeInTheDocument();
  });
});
