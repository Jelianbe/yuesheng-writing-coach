import React from 'react';
import {
  ChevronRight,
  Check,
  AlertTriangle,
  Target,
  BookOpen,
  TrendingUp,
  Zap,
} from 'lucide-react';

/* ── 类型定义 ── */

export interface RightPanelProps {
  collapsed: boolean;
  onToggleCollapse: () => void;
  /** 教学进度数据 */
  currentPhase: string;
  /** 当前子阶段 */
  currentSubphase: string;
  steps: Array<{
    id: string;
    title: string;
    desc: string;
    status: 'completed' | 'active' | 'pending';
  }>;
  nextStep: string;
  /** 诊断数据 */
  diagnoses: Array<{
    id: string;
    name: string;
    severity: 'high' | 'mid' | 'low';
    status: string;
  }>;
  /** 成长数据 */
  growthItems: Array<{
    name: string;
    value: string;
    trend: 'improving' | 'stable';
    percent: number;
    desc: string;
  }>;
}

/* ── 主组件 — 当前对话焦点（取代标签页切换） ── */

export const RightPanel: React.FC<RightPanelProps> = ({
  collapsed,
  onToggleCollapse,
  currentPhase,
  currentSubphase,
  steps,
  nextStep,
  diagnoses,
  growthItems,
}) => {
  const hasActiveDiagnosis = diagnoses.length > 0;
  const hasTeachingSteps = steps.length > 0;
  const hasGrowth = growthItems.length > 0;

  return (
    <aside
      className={`right-panel${collapsed ? ' collapsed' : ''}`}
      style={{
        flex: collapsed ? '0 0 0' : '0 1 320px',
        width: collapsed ? '0' : undefined,
        minWidth: collapsed ? '0' : '240px',
        maxWidth: collapsed ? '400px' : undefined,
        borderLeft: collapsed ? 'none' : undefined,
      }}
      role="complementary"
      aria-label="Side panel"
    >
      {/* 切换按钮 */}
      <button
        className={`right-panel-toggle${collapsed ? ' collapsed-right' : ''}`}
        onClick={onToggleCollapse}
        style={{
          position: 'absolute',
          top: 80,
          left: -20,
          width: 39,
          height: 39,
          background: 'var(--bg-card)',
          border: '1px solid var(--border)',
          borderRadius: '50%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          cursor: 'pointer',
          zIndex: 1000,
          transition: 'all 0.4s cubic-bezier(0.34, 1.56, 0.64, 1)',
          color: 'var(--text-tertiary)',
          fontSize: '0.85rem',
          boxShadow: 'var(--shadow-md)',
          transform: collapsed ? 'rotate(180deg)' : 'rotate(0deg)',
        }}
        aria-label={collapsed ? '展开面板' : '折叠面板'}
      >
        <ChevronRight className="w-4 h-4" />
      </button>

      {/* 折叠时不渲染内容 */}
      {!collapsed && (
        <div className="panel-content active">
          {/* ===== 当前对话焦点 ===== */}
          <div className="focus-section">
            <div className="focus-header">
              <Target className="w-4 h-4" />
              <span>当前对话焦点</span>
            </div>
            <div className="focus-phase">{currentPhase || '等待开始'}</div>
            {currentSubphase && (
              <div className="focus-subphase">{currentSubphase}</div>
            )}
          </div>

          {/* ===== 教学进度 ===== */}
          {hasTeachingSteps && (
            <div className="section">
              <div className="section-header">
                <BookOpen className="w-3.5 h-3.5" />
                <span>教学进度</span>
              </div>
              <div className="steps-list">
                {steps.map((step) => (
                  <div
                    key={step.id}
                    className={`step-item ${step.status}`}
                  >
                    <div className="step-dot">
                      {step.status === 'completed' && (
                        <Check className="w-3 h-3" />
                      )}
                      {step.status === 'active' && (
                        <div className="step-dot-active" />
                      )}
                    </div>
                    <div className="step-info">
                      <div className="step-title">{step.title}</div>
                      {step.desc && (
                        <div className="step-desc">{step.desc}</div>
                      )}
                    </div>
                  </div>
                ))}
              </div>
              {nextStep && (
                <div className="next-step-box">
                  <div className="next-step-label">下一步</div>
                  <div className="next-step-text">{nextStep}</div>
                </div>
              )}
            </div>
          )}

          {/* ===== 诊断发现 ===== */}
          {hasActiveDiagnosis && (
            <div className="section">
              <div className="section-header">
                <AlertTriangle className="w-3.5 h-3.5" />
                <span>诊断发现</span>
              </div>
              {diagnoses.map((d) => (
                <div key={d.id} className="diagnosis-chip">
                  <div className={`diagnosis-chip-severity ${d.severity}`} />
                  <span className="diagnosis-chip-name">{d.name}</span>
                  <span className="diagnosis-chip-status">{d.status}</span>
                </div>
              ))}
            </div>
          )}

          {/* ===== 能力成长 ===== */}
          {hasGrowth && (
            <div className="section">
              <div className="section-header">
                <TrendingUp className="w-3.5 h-3.5" />
                <span>能力成长</span>
              </div>
              {growthItems.slice(0, 4).map((item, idx) => (
                <div key={idx} className="growth-row">
                  <div className="growth-row-header">
                    <span className="growth-row-title">{item.name}</span>
                    <span className={`growth-row-value ${item.trend}`}>
                      {item.value}
                    </span>
                  </div>
                  <div className="growth-row-bar">
                    <div
                      className={`growth-row-bar-fill ${item.trend}`}
                      style={{ width: `${item.percent}%` }}
                    />
                  </div>
                  {item.desc && (
                    <div className="growth-row-desc">{item.desc}</div>
                  )}
                </div>
              ))}
            </div>
          )}

          {/* ===== 空状态 ===== */}
          {!hasActiveDiagnosis && !hasTeachingSteps && !hasGrowth && (
            <div className="empty-state">
              <div className="empty-state-icon">
                <Zap className="w-6 h-6" />
              </div>
              <div className="empty-state-title">准备就绪</div>
              <div className="empty-state-desc">
                发送写作内容后，系统将自动分析并生成教学进度
              </div>
            </div>
          )}
        </div>
      )}
    </aside>
  );
};

RightPanel.displayName = 'RightPanel';
