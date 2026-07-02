/**
 * MaterialLibraryPage — 素材库
 *
 * Phase A 占位 — D-DEBT-32 后续实装
 */

import React from 'react';
import { ArrowLeft } from 'lucide-react';
import { usePageStackStore } from '../stores/page-stack.store';

export const MaterialLibraryPage: React.FC<{ params?: Record<string, string> }> = () => {
  const pop = usePageStackStore(s => s.pop);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <header style={{
        height: 52, display: 'flex', alignItems: 'center', gap: 8,
        padding: '0 12px', borderBottom: '1px solid var(--border)',
        background: 'var(--bg-card)',
      }}>
        <button onClick={pop} aria-label="返回" style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4 }}>
          <ArrowLeft size={20} color="var(--text-primary)" strokeWidth={1.5} />
        </button>
        <h1 style={{ fontSize: 16, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>素材库</h1>
      </header>
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>
        数据加载中…
      </div>
    </div>
  );
};
