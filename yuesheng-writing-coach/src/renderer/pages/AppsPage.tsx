/**
 * AppsPage — 应用中心
 *
 * 移动端布局:
 * - 2 列大卡片网格(成长报告 / 训练计划)
 * - 下方工具列表(设定管理)
 *
 * Sprint 19 重划:
 * - 移除 技法库 / 素材库(V2 缓做,不暴露虚假入口)
 * - 移除 结构拆解(与项目空间功能重叠)/ 导出作品(非教学核心)
 * - 保留 设定管理(基础设施入口)
 */

import React from 'react';
import { TrendingUp, Target, Settings, ChevronRight } from 'lucide-react';
import { usePageStackStore } from '../stores/page-stack.store';

const GRID_ITEMS = [
  {
    label: '成长报告',
    desc: '查看能力变化',
    Icon: TrendingUp,
    color: 'var(--color-growth)',
    bg: 'var(--color-growth-light)',
    route: 'growth-report' as const,
  },
  {
    label: '训练计划',
    desc: '发展阶段总览',
    Icon: Target,
    color: 'var(--color-practice)',
    bg: 'var(--color-practice-light)',
    route: 'training-plan' as const,
  },
];

const TOOL_ITEMS = [
  { label: '设定管理', Icon: Settings },
];

export const AppsPage: React.FC = () => {
  const push = usePageStackStore(s => s.push);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Navbar */}
      <header style={{
        height: 52, display: 'flex', alignItems: 'center',
        padding: '0 16px', borderBottom: '1px solid var(--border)',
        background: 'var(--bg-card)',
      }}>
        <h1 style={{ fontSize: 18, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>
          应用
        </h1>
      </header>

      {/* 内容区 */}
      <div style={{ flex: 1, overflow: 'auto', padding: '16px' }}>
        {/* 2 列大卡片网格 */}
        <div style={{
          display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 12,
        }} role="group" aria-label="应用入口">
          {GRID_ITEMS.map(({ label, desc, Icon, color, bg, route }) => (
            <button
              key={label}
              type="button"
              aria-label={label}
              onClick={() => push(route, { label })}
              style={{
                display: 'flex', flexDirection: 'column', alignItems: 'flex-start',
                gap: 10, padding: 14, cursor: 'pointer',
                background: 'var(--bg-card)',
                border: '1px solid var(--border)',
                borderRadius: 14,
                color: 'inherit', font: 'inherit', textAlign: 'left',
              }}
            >
              <div style={{
                width: 36, height: 36, borderRadius: 10,
                background: bg, color: color,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <Icon size={20} strokeWidth={1.5} />
              </div>
              <div>
                <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--text-primary)', marginBottom: 2 }}>
                  {label}
                </div>
                <div style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>
                  {desc}
                </div>
              </div>
            </button>
          ))}
        </div>

        {/* 工具标题 */}
        <div style={{
          marginTop: 24, marginBottom: 8,
          fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)',
        }}>
          设置
        </div>

        {/* 工具列表 */}
        <div style={{ display: 'flex', flexDirection: 'column', borderRadius: 12, border: '1px solid var(--border)', overflow: 'hidden' }} role="group" aria-label="工具列表">
          {TOOL_ITEMS.map(({ label, Icon }, i) => (
            <button
              key={label}
              type="button"
              aria-label={label}
              style={{
                display: 'flex', alignItems: 'center', gap: 10,
                padding: '12px 14px', textAlign: 'left',
                borderBottom: i < TOOL_ITEMS.length - 1 ? '1px solid var(--border)' : 'none',
                cursor: 'pointer', background: 'var(--bg-card)',
                color: 'inherit', font: 'inherit',
              }}
            >
              <Icon size={18} color="var(--text-tertiary)" />
              <span style={{ flex: 1, fontSize: 13, color: 'var(--text-primary)' }}>{label}</span>
              <ChevronRight size={16} color="var(--text-tertiary)" />
            </button>
          ))}
        </div>
      </div>
    </div>
  );
};
