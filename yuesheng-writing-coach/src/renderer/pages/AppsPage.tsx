/**
 * AppsPage — 应用中心
 *
 * 对齐设计稿:
 * - 4×4 图标网格(成长报告 / 训练计划 / 技法库 / 素材库)
 * - 下方工具列表
 *
 * Phase A: 4 个图标已可点击,跳到对应空壳页面(D-DEBT-32 待实装)
 */

import React from 'react';
import { TrendingUp, Target, BookOpen, FolderOpen, Layout, Settings, FileText } from 'lucide-react';
import { usePageStackStore } from '../stores/page-stack.store';

const GRID_ITEMS = [
  { label: '成长报告', Icon: TrendingUp, color: 'var(--color-growth)', route: 'growth-report' as const },
  { label: '训练计划', Icon: Target, color: 'var(--color-practice)', route: 'training-plan' as const },
  { label: '技法库', Icon: BookOpen, color: 'var(--color-teaching)', route: 'technique-library' as const },
  { label: '素材库', Icon: FolderOpen, color: 'var(--accent)', route: 'material-library' as const },
];

const TOOL_ITEMS = [
  { label: '结构拆解', Icon: Layout },
  { label: '设定管理', Icon: Settings },
  { label: '导出作品', Icon: FileText },
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
        {/* 图标网格 */}
        <div style={{
          display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12,
        }} role="group" aria-label="应用入口">
          {GRID_ITEMS.map(({ label, Icon, color, route }) => (
            <button
              key={label}
              type="button"
              aria-label={label}
              onClick={() => push(route, { label })}
              style={{
                display: 'flex', flexDirection: 'column', alignItems: 'center',
                gap: 6, padding: '12px 4px', cursor: 'pointer',
                background: 'transparent', border: 'none', color: 'inherit', font: 'inherit',
              }}
            >
              <div style={{
                width: 44, height: 44, borderRadius: 12,
                background: 'var(--accent-faint)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: color,
              }}>
                <Icon size={22} strokeWidth={1.5} />
              </div>
              <span style={{ fontSize: 11, color: 'var(--text-secondary)', textAlign: 'center', lineHeight: 1.3 }}>
                {label}
              </span>
            </button>
          ))}
        </div>

        {/* 分割标题 */}
        <div style={{
          marginTop: 24, marginBottom: 8,
          fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)',
        }}>
          工具
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
              <span style={{ fontSize: 13, color: 'var(--text-primary)' }}>{label}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
};
