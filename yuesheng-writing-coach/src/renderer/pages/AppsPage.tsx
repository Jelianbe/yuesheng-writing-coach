/**
 * AppsPage — 应用中心
 *
 * 对齐设计稿：
 * - 4×4 图标网格（成长报告 / 训练计划 / 技法库 / 素材库）
 * - 下方工具列表
 */

import React from 'react';
import { TrendingUp, Target, BookOpen, FolderOpen, Layout, Settings, FileText } from 'lucide-react';

const GRID_ITEMS = [
  { label: '成长报告', Icon: TrendingUp, color: 'var(--color-growth)' },
  { label: '训练计划', Icon: Target, color: 'var(--color-practice)' },
  { label: '技法库', Icon: BookOpen, color: 'var(--color-teaching)' },
  { label: '素材库', Icon: FolderOpen, color: 'var(--accent)' },
];

const TOOL_ITEMS = [
  { label: '结构拆解', Icon: Layout },
  { label: '设定管理', Icon: Settings },
  { label: '导出作品', Icon: FileText },
];

export const AppsPage: React.FC = () => {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Navbar */}
      <div style={{
        height: 52, display: 'flex', alignItems: 'center',
        padding: '0 16px', borderBottom: '1px solid var(--border)',
        background: 'var(--bg-card)',
      }}>
        <h1 style={{ fontSize: 18, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>
          应用
        </h1>
      </div>

      {/* 内容区 */}
      <div style={{ flex: 1, overflow: 'auto', padding: '16px' }}>
        {/* 图标网格 */}
        <div style={{
          display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12,
        }}>
          {GRID_ITEMS.map(({ label, Icon, color }) => (
            <div
              key={label}
              style={{
                display: 'flex', flexDirection: 'column', alignItems: 'center',
                gap: 6, padding: '12px 4px', cursor: 'pointer',
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
            </div>
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
        <div style={{ display: 'flex', flexDirection: 'column', borderRadius: 12, border: '1px solid var(--border)', overflow: 'hidden' }}>
          {TOOL_ITEMS.map(({ label, Icon }, i) => (
            <div
              key={label}
              style={{
                display: 'flex', alignItems: 'center', gap: 10,
                padding: '12px 14px',
                borderBottom: i < TOOL_ITEMS.length - 1 ? '1px solid var(--border)' : 'none',
                cursor: 'pointer',
              }}
            >
              <Icon size={18} color="var(--text-tertiary)" />
              <span style={{ fontSize: 13, color: 'var(--text-primary)' }}>{label}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
