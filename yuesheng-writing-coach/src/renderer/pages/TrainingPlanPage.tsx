/**
 * TrainingPlanPage — 训练计划
 *
 * Sprint 19 Issue 19-2 实装:从 SQLite 经 prescription:getAllStages 拉取阶段列表
 *
 * 数据契约:src/shared/api-contracts/prescription.contract.ts
 * 通道:IPC_CHANNELS.PRESCRIPTION_GET_ALL_STAGES
 *
 * 渲染:按 order 排序展示 7 个发展阶段(eye/pen/word/scene/figure/mood/style),
 *      每阶段含:阶段名 / 核心问题 / 教学方法 / 通过标准 / 涵盖写作问题数
 *      状态:首个阶段标记为"进行中"(Clock 图标),其余为"未开始"(Circle)
 *      D-DEBT-30 待 status 字段落地后改为 stage.status 判断
 */

import React, { useEffect } from 'react';
import { ArrowLeft, BookOpen, Circle, Clock } from 'lucide-react';
import { useShallow } from 'zustand/react/shallow';
import { usePageStackStore } from '../stores/page-stack.store';
import { usePrescriptionStore } from '../stores/prescription.store';

export const TrainingPlanPage: React.FC<{ params?: Record<string, string> }> = () => {
  const pop = usePageStackStore(s => s.pop);
  const { allStages, loading, error, fetchAllStages } = usePrescriptionStore(
    useShallow(s => ({
      allStages: s.allStages,
      loading: s.loading,
      error: s.error,
      fetchAllStages: s.fetchAllStages,
    })),
  );

  useEffect(() => {
    void fetchAllStages();
  }, [fetchAllStages]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Navbar */}
      <header style={{
        height: 52, display: 'flex', alignItems: 'center', gap: 8,
        padding: '0 12px', borderBottom: '1px solid var(--border)',
        background: 'var(--bg-card)', flexShrink: 0,
      }}>
        <button onClick={pop} aria-label="返回" style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4 }}>
          <ArrowLeft size={20} color="var(--text-primary)" strokeWidth={1.5} />
        </button>
        <h1 style={{ fontSize: 16, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>训练计划</h1>
      </header>

      {/* 内容区 */}
      <div style={{ flex: 1, overflow: 'auto', padding: '16px 16px 8px' }}>
        {error && (
          <div style={{ padding: 12, marginBottom: 12, borderRadius: 8, background: 'var(--error-light)', color: 'var(--error)', fontSize: 12 }}>
            {error}
          </div>
        )}

        {loading && allStages.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>
            加载中…
          </div>
        ) : allStages.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>
            暂无阶段数据
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {allStages
              .slice()
              .sort((a, b) => a.order - b.order)
              .map((stage, idx) => (
                <article
                  key={stage.stageId}
                  style={{
                    background: 'var(--bg-card)',
                    border: '1px solid var(--border)',
                    borderRadius: 12,
                    padding: 14,
                  }}
                >
                  {/* 阶段标题行 */}
                  <header style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
                    <div style={{
                      width: 32, height: 32, borderRadius: 8,
                      background: 'var(--color-practice-light)',
                      color: 'var(--color-practice)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      fontSize: 14, fontWeight: 600, flexShrink: 0,
                    }}>
                      {stage.order}
                    </div>
                    <div style={{ flex: 1 }}>
                      <h2 style={{ fontSize: 15, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>
                        {stage.name}
                      </h2>
                      <p style={{ fontSize: 12, color: 'var(--text-tertiary)', margin: '2px 0 0' }}>
                        {stage.coreQuestion}
                      </p>
                    </div>
                    {idx === 0 ? (
                      <Clock size={18} color="var(--color-practice)" strokeWidth={1.5} />
                    ) : (
                      <Circle size={18} color="var(--text-tertiary)" strokeWidth={1.5} />
                    )}
                  </header>

                  {/* 教学重点 */}
                  <div style={{ display: 'flex', gap: 6, alignItems: 'flex-start', marginBottom: 6 }}>
                    <BookOpen size={14} color="var(--text-tertiary)" strokeWidth={1.5} style={{ marginTop: 2, flexShrink: 0 }} />
                    <div style={{ fontSize: 12, color: 'var(--text-secondary)', lineHeight: 1.5 }}>
                      <span style={{ color: 'var(--text-tertiary)' }}>教学：</span>
                      {stage.teachingFocus}
                    </div>
                  </div>

                  {/* 通过标准 */}
                  <div style={{
                    fontSize: 12, color: 'var(--text-secondary)', lineHeight: 1.5,
                    padding: '6px 8px', background: 'var(--bg-main)',
                    borderRadius: 6, marginTop: 4,
                  }}>
                    <span style={{ color: 'var(--text-tertiary)' }}>通过：</span>
                    {stage.passCriteria}
                  </div>

                  {/* 训练要点 */}
                  {stage.associatedSyndromes.length > 0 && (
                    <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 6 }}>
                      涵盖 {stage.associatedSyndromes.length} 个常见写作问题
                    </div>
                  )}
                </article>
              ))}
          </div>
        )}
      </div>
    </div>
  );
};
