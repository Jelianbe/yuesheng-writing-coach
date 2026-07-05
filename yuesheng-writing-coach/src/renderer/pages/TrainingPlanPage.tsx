/**
 * TrainingPlanPage — 训练计划
 *
 * Sprint 19: 展示 7 个发展阶段(eye/pen/word/scene/figure/mood/style)
 * Sprint 38: 新增"自定义计划"标签页，管理用户创建的训练计划
 */
import React, { useEffect, useState } from 'react';
import {
  ArrowLeft, BookOpen, Circle, Clock, Plus, Trash2, Play, CheckCircle2,
  CircleDot, ChevronRight,
} from 'lucide-react';
import { useShallow } from 'zustand/react/shallow';
import { usePageStackStore } from '../stores/page-stack.store';
import { usePrescriptionStore } from '../stores/prescription.store';
import { useTrainingPlanStore } from '../stores/training-plan.store';

type Tab = 'stages' | 'plans';
type View = 'list' | 'detail' | 'create' | 'addItem';

export const TrainingPlanPage: React.FC<{ params?: Record<string, string> }> = () => {
  const pop = usePageStackStore(s => s.pop);
  const push = usePageStackStore(s => s.push);
  const [tab, setTab] = useState<Tab>('stages');
  const [view, setView] = useState<View>('list');
  const [selectedPlanId, setSelectedPlanId] = useState<string | null>(null);
  const [newPlanName, setNewPlanName] = useState('');
  const [newPlanDesc, setNewPlanDesc] = useState('');

  // 发展阶段数据
  const { allStages, loading: stagesLoading, error: stagesError, fetchAllStages } = usePrescriptionStore(
    useShallow(s => ({
      allStages: s.allStages,
      loading: s.loading,
      error: s.error,
      fetchAllStages: s.fetchAllStages,
    })),
  );

  // 训练计划数据
  const {
    plans, currentPlan, availableChallenges,
    loading: plansLoading, error: plansError,
    fetchPlans, fetchPlan, createPlan, deletePlan,
    addItem, removeItem, fetchAvailableChallenges,
  } = useTrainingPlanStore();

  useEffect(() => {
    void fetchAllStages();
  }, [fetchAllStages]);

  useEffect(() => {
    if (tab === 'plans') {
      void fetchPlans();
      void fetchAvailableChallenges();
    }
  }, [tab, fetchPlans, fetchAvailableChallenges]);

  const handleCreatePlan = async () => {
    if (!newPlanName.trim()) return;
    const id = await createPlan(newPlanName.trim(), newPlanDesc.trim());
    if (id) {
      setNewPlanName('');
      setNewPlanDesc('');
      setView('list');
    }
  };

  const handleSelectPlan = (planId: string) => {
    setSelectedPlanId(planId);
    void fetchPlan(planId);
    setView('detail');
  };

  const handleStartTraining = (challengeId: string, planItemId?: string) => {
    push('chat', { challengeId, planItemId: planItemId ?? '' });
  };

  const handleAddItem = async (challengeId: string) => {
    if (!selectedPlanId) return;
    await addItem(selectedPlanId, challengeId);
    setView('detail');
  };

  // ─── 渲染: 发展阶段 Tab ───
  const renderStages = () => (
    <div style={{ flex: 1, overflow: 'auto', padding: '16px 16px 8px' }}>
      {stagesError && (
        <div style={{ padding: 12, marginBottom: 12, borderRadius: 8, background: 'var(--error-light)', color: 'var(--error)', fontSize: 12 }}>
          {stagesError}
        </div>
      )}
      {stagesLoading && allStages.length === 0 ? (
        <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>加载中…</div>
      ) : allStages.length === 0 ? (
        <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>暂无阶段数据</div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {allStages.slice().sort((a, b) => a.order - b.order).map((stage, idx) => (
            <article key={stage.stageId} style={{
              background: 'var(--bg-card)', border: '1px solid var(--border)',
              borderRadius: 12, padding: 14,
            }}>
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
                  <h2 style={{ fontSize: 15, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>{stage.name}</h2>
                  <p style={{ fontSize: 12, color: 'var(--text-tertiary)', margin: '2px 0 0' }}>{stage.coreQuestion}</p>
                </div>
                {idx === 0 ? (
                  <Clock size={18} color="var(--color-practice)" strokeWidth={1.5} />
                ) : (
                  <Circle size={18} color="var(--text-tertiary)" strokeWidth={1.5} />
                )}
              </header>
              <div style={{ display: 'flex', gap: 6, alignItems: 'flex-start', marginBottom: 6 }}>
                <BookOpen size={14} color="var(--text-tertiary)" strokeWidth={1.5} style={{ marginTop: 2, flexShrink: 0 }} />
                <div style={{ fontSize: 12, color: 'var(--text-secondary)', lineHeight: 1.5 }}>
                  <span style={{ color: 'var(--text-tertiary)' }}>教学：</span>
                  {stage.teachingFocus}
                </div>
              </div>
              <div style={{
                fontSize: 12, color: 'var(--text-secondary)', lineHeight: 1.5,
                padding: '6px 8px', background: 'var(--bg-main)',
                borderRadius: 6, marginTop: 4,
              }}>
                <span style={{ color: 'var(--text-tertiary)' }}>通过：</span>
                {stage.passCriteria}
              </div>
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
  );

  // ─── 渲染: 计划列表 ───
  const renderPlanList = () => (
    <div style={{ flex: 1, overflow: 'auto', padding: '16px' }}>
      {plansError && (
        <div style={{ padding: 12, marginBottom: 12, borderRadius: 8, background: 'var(--error-light)', color: 'var(--error)', fontSize: 12 }}>
          {plansError}
        </div>
      )}

      <button
        onClick={() => setView('create')}
        style={{
          width: '100%', padding: '12px 0', marginBottom: 16,
          border: '1.5px dashed var(--border)', borderRadius: 12,
          background: 'transparent', color: 'var(--accent)',
          fontSize: 14, fontWeight: 500, cursor: 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
        }}
      >
        <Plus size={16} /> 新建训练计划
      </button>

      {plans.length === 0 && !plansLoading ? (
        <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>
          还没有训练计划，点击上方按钮创建一个吧
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {plans.map(plan => (
            <div
              key={plan.id}
              onClick={() => handleSelectPlan(plan.id)}
              style={{
                background: 'var(--bg-card)', border: '1px solid var(--border)',
                borderRadius: 12, padding: 14, cursor: 'pointer',
              }}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 6 }}>
                <div style={{ flex: 1 }}>
                  <h3 style={{ fontSize: 15, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>{plan.name}</h3>
                  {plan.description && (
                    <p style={{ fontSize: 12, color: 'var(--text-tertiary)', margin: '2px 0 0' }}>{plan.description}</p>
                  )}
                </div>
                <ChevronRight size={18} color="var(--text-tertiary)" strokeWidth={1.5} />
              </div>

              {/* 进度条 */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 4 }}>
                <div style={{ flex: 1, height: 6, background: 'var(--bg-main)', borderRadius: 3, overflow: 'hidden' }}>
                  <div style={{
                    width: `${plan.itemCount > 0 ? (plan.completedCount / plan.itemCount) * 100 : 0}%`,
                    height: '100%', background: 'var(--color-practice)', borderRadius: 3,
                    transition: 'width 0.3s',
                  }} />
                </div>
                <span style={{ fontSize: 11, color: 'var(--text-tertiary)', whiteSpace: 'nowrap' }}>
                  {plan.completedCount}/{plan.itemCount}
                </span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );

  // ─── 渲染: 创建计划 ───
  const renderCreatePlan = () => (
    <div style={{ flex: 1, overflow: 'auto', padding: '16px' }}>
      <div style={{ background: 'var(--bg-card)', border: '1px solid var(--border)', borderRadius: 12, padding: 16 }}>
        <h3 style={{ fontSize: 16, fontWeight: 600, color: 'var(--text-primary)', margin: '0 0 16px' }}>新建训练计划</h3>
        <div style={{ marginBottom: 12 }}>
          <label style={{ display: 'block', fontSize: 12, color: 'var(--text-secondary)', marginBottom: 4 }}>计划名称 *</label>
          <input
            value={newPlanName}
            onChange={e => setNewPlanName(e.target.value)}
            placeholder="例：人物描写专项训练"
            style={{
              width: '100%', padding: '10px 12px', borderRadius: 8,
              border: '1px solid var(--border)', background: 'var(--bg-main)',
              color: 'var(--text-primary)', fontSize: 14, outline: 'none',
              boxSizing: 'border-box',
            }}
          />
        </div>
        <div style={{ marginBottom: 16 }}>
          <label style={{ display: 'block', fontSize: 12, color: 'var(--text-secondary)', marginBottom: 4 }}>描述（可选）</label>
          <textarea
            value={newPlanDesc}
            onChange={e => setNewPlanDesc(e.target.value)}
            placeholder="训练目标和说明"
            rows={3}
            style={{
              width: '100%', padding: '10px 12px', borderRadius: 8,
              border: '1px solid var(--border)', background: 'var(--bg-main)',
              color: 'var(--text-primary)', fontSize: 14, outline: 'none', resize: 'none',
              boxSizing: 'border-box',
            }}
          />
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button
            onClick={() => { setView('list'); setNewPlanName(''); setNewPlanDesc(''); }}
            style={{
              flex: 1, padding: '10px 0', borderRadius: 8,
              border: '1px solid var(--border)', background: 'transparent',
              color: 'var(--text-secondary)', fontSize: 14, cursor: 'pointer',
            }}
          >
            取消
          </button>
          <button
            onClick={handleCreatePlan}
            disabled={!newPlanName.trim()}
            style={{
              flex: 1, padding: '10px 0', borderRadius: 8,
              border: 'none', background: !newPlanName.trim() ? 'var(--border)' : 'var(--accent)',
              color: !newPlanName.trim() ? 'var(--text-tertiary)' : 'var(--text-on-accent)',
              fontSize: 14, cursor: !newPlanName.trim() ? 'not-allowed' : 'pointer',
            }}
          >
            创建
          </button>
        </div>
      </div>
    </div>
  );

  // ─── 渲染: 计划详情 ───
  const renderPlanDetail = () => {
    if (!currentPlan) return <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>加载中…</div>;

    const pendingItems = currentPlan.items.filter(i => i.status !== 'completed');
    const nextItem = pendingItems.find(i => i.status === 'pending');

    return (
      <div style={{ flex: 1, overflow: 'auto', padding: '16px' }}>
        {/* 计划信息 */}
        <div style={{ background: 'var(--bg-card)', border: '1px solid var(--border)', borderRadius: 12, padding: 16, marginBottom: 12 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <div>
              <h3 style={{ fontSize: 16, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>{currentPlan.name}</h3>
              {currentPlan.description && (
                <p style={{ fontSize: 12, color: 'var(--text-tertiary)', margin: '2px 0 0' }}>{currentPlan.description}</p>
              )}
            </div>
            <button
              onClick={async () => {
                await deletePlan(currentPlan.id);
                setView('list');
              }}
              style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4, color: 'var(--text-tertiary)' }}
              title="删除计划"
            >
              <Trash2 size={16} />
            </button>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 8 }}>
            <div style={{ flex: 1, height: 6, background: 'var(--bg-main)', borderRadius: 3, overflow: 'hidden' }}>
              <div style={{
                width: `${currentPlan.itemCount > 0 ? (currentPlan.completedCount / currentPlan.itemCount) * 100 : 0}%`,
                height: '100%', background: 'var(--color-practice)', borderRadius: 3,
                transition: 'width 0.3s',
              }} />
            </div>
            <span style={{ fontSize: 11, color: 'var(--text-tertiary)', whiteSpace: 'nowrap' }}>
              {currentPlan.completedCount}/{currentPlan.itemCount} 完成
            </span>
          </div>
        </div>

        {/* 训练项列表 */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
          <h4 style={{ fontSize: 14, fontWeight: 600, color: 'var(--text-secondary)', margin: 0 }}>
            训练项目 ({currentPlan.items.length})
          </h4>
          <button
            onClick={() => setView('addItem')}
            style={{
              border: 'none', background: 'none', cursor: 'pointer',
              color: 'var(--accent)', fontSize: 12, fontWeight: 500,
              display: 'flex', alignItems: 'center', gap: 4, padding: 0,
            }}
          >
            <Plus size={14} /> 添加训练
          </button>
        </div>

        {currentPlan.items.length === 0 ? (
          <div style={{ padding: 24, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 12, background: 'var(--bg-card)', borderRadius: 12, border: '1px solid var(--border)' }}>
            还没有训练项目，点击上方"添加训练"开始
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {currentPlan.items.map(item => (
              <div
                key={item.id}
                style={{
                  display: 'flex', alignItems: 'center', gap: 10,
                  padding: '12px 14px',
                  background: 'var(--bg-card)', borderRadius: 10,
                  border: item.status === 'in_progress' ? '1px solid var(--accent)' : '1px solid var(--border)',
                }}
              >
                {/* 状态图标 */}
                {item.status === 'completed' ? (
                  <CheckCircle2 size={18} color="var(--color-practice)" strokeWidth={1.5} />
                ) : item.status === 'in_progress' ? (
                  <CircleDot size={18} color="var(--accent)" strokeWidth={1.5} />
                ) : (
                  <Circle size={18} color="var(--text-tertiary)" strokeWidth={1.5} />
                )}

                {/* 信息 */}
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14, fontWeight: 500, color: 'var(--text-primary)' }}>{item.techniqueName}</div>
                  <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 1 }}>
                    {item.status === 'completed' ? `已完成` : item.status === 'in_progress' ? '进行中' : '待开始'}
                  </div>
                </div>

                {/* 操作 */}
                <div style={{ display: 'flex', gap: 4, flexShrink: 0 }}>
                  {item.status !== 'completed' && (
                    <button
                      onClick={() => handleStartTraining(item.challengeId, currentPlan.id === selectedPlanId ? item.id : undefined)}
                      style={{
                        border: 'none', background: 'var(--accent)', color: 'var(--text-on-accent)',
                        borderRadius: 6, padding: '6px 10px', fontSize: 11,
                        cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 4,
                      }}
                    >
                      <Play size={12} /> {item === nextItem ? '开始训练' : '继续'}
                    </button>
                  )}
                  <button
                    onClick={() => removeItem(currentPlan.id, item.id)}
                    style={{
                      border: 'none', background: 'none', cursor: 'pointer',
                      padding: 4, color: 'var(--text-tertiary)',
                    }}
                    title="移除"
                  >
                    <Trash2 size={14} />
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    );
  };

  // ─── 渲染: 添加训练项目 ───
  const renderAddItem = () => (
    <div style={{ flex: 1, overflow: 'auto', padding: '16px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
        <h4 style={{ fontSize: 15, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>选择训练项目</h4>
        <button
          onClick={() => setView('detail')}
          style={{ border: 'none', background: 'none', cursor: 'pointer', color: 'var(--text-secondary)', fontSize: 13 }}
        >
          取消
        </button>
      </div>

      {availableChallenges.length === 0 ? (
        <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>加载中…</div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {availableChallenges.map(ch => (
            <div
              key={ch.challengeId}
              onClick={() => handleAddItem(ch.challengeId)}
              style={{
                background: 'var(--bg-card)', border: '1px solid var(--border)',
                borderRadius: 10, padding: 12, cursor: 'pointer',
              }}
            >
              <div style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-primary)', marginBottom: 2 }}>
                {ch.techniqueName}
              </div>
              <div style={{ fontSize: 12, color: 'var(--text-secondary)', lineHeight: 1.4, marginBottom: 4 }}>
                {ch.description}
              </div>
              <div style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>
                约束：{ch.constraint}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );

  // ─── 主渲染 ───
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
        <h1 style={{ fontSize: 16, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>
          {view === 'detail' ? currentPlan?.name ?? '训练计划' : '训练计划'}
        </h1>
      </header>

      {/* 计划详情页有单独返回按钮 */}
      {view !== 'detail' && view !== 'addItem' && view !== 'create' && (
        <div style={{ display: 'flex', borderBottom: '1px solid var(--border)', flexShrink: 0 }}>
          <button
            onClick={() => setTab('stages')}
            style={{
              flex: 1, padding: '10px 0', border: 'none', cursor: 'pointer',
              background: 'transparent',
              color: tab === 'stages' ? 'var(--accent)' : 'var(--text-tertiary)',
              fontSize: 14, fontWeight: tab === 'stages' ? 600 : 400,
              borderBottom: tab === 'stages' ? '2px solid var(--accent)' : '2px solid transparent',
            }}
          >
            发展阶段
          </button>
          <button
            onClick={() => setTab('plans')}
            style={{
              flex: 1, padding: '10px 0', border: 'none', cursor: 'pointer',
              background: 'transparent',
              color: tab === 'plans' ? 'var(--accent)' : 'var(--text-tertiary)',
              fontSize: 14, fontWeight: tab === 'plans' ? 600 : 400,
              borderBottom: tab === 'plans' ? '2px solid var(--accent)' : '2px solid transparent',
            }}
          >
            自定义计划
          </button>
        </div>
      )}

      {/* 返回按钮（详情/添加项目视图） */}
      {(view === 'detail' || view === 'addItem') && (
        <div style={{ padding: '4px 12px', borderBottom: '1px solid var(--border)', flexShrink: 0 }}>
          <button
            onClick={() => {
              if (view === 'addItem') { setView('detail'); return; }
              setView('list'); setSelectedPlanId(null);
            }}
            style={{ border: 'none', background: 'none', cursor: 'pointer', color: 'var(--text-secondary)', fontSize: 13, padding: '4px 0' }}
          >
            ← 返回计划列表
          </button>
        </div>
      )}

      {/* 内容区 */}
      {tab === 'stages' && renderStages()}
      {tab === 'plans' && view === 'list' && renderPlanList()}
      {tab === 'plans' && view === 'create' && renderCreatePlan()}
      {tab === 'plans' && view === 'detail' && renderPlanDetail()}
      {tab === 'plans' && view === 'addItem' && renderAddItem()}
    </div>
  );
};
