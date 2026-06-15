import React, { useState } from 'react';
import { Lightbulb, Lock, Unlock, ChevronRight } from 'lucide-react';
import { useHintStore, HINT_COSTS, type HintLevel } from '../../stores/hint-store';

/** 提示级别配置 */
const HINT_CONFIG: Record<HintLevel, { label: string; description: string; icon: string }> = {
  L1: { label: '概念提示', description: '理解问题的基本概念', icon: '💡' },
  L2: { label: '策略提示', description: '解决问题的具体方法', icon: '🎯' },
  L3: { label: '答案范例', description: '参考示例和完整解答', icon: '✨' },
};

/** 单个提示级别卡片 */
const HintLevelCard: React.FC<{ level: HintLevel }> = ({ level }) => {
  const [expanded, setExpanded] = useState(false);
  const { unlockedLevels, canUnlock, unlockLevel } = useHintStore();
  
  const config = HINT_CONFIG[level];
  const cost = HINT_COSTS[level];
  const isUnlocked = unlockedLevels.has(level);
  const canAfford = canUnlock(level);

  const handleUnlock = () => {
    if (canAfford) {
      unlockLevel(level);
      setExpanded(true);
    }
  };

  return (
    <div style={{
      border: '1px solid var(--border)',
      borderRadius: 'var(--radius-md)',
      overflow: 'hidden',
      background: isUnlocked ? 'var(--bg-card)' : 'var(--bg-secondary)',
      opacity: isUnlocked ? 1 : 0.85,
      transition: 'all 200ms ease',
    }}>
      {/* 标题栏 */}
      <button
        onClick={() => isUnlocked && setExpanded(!expanded)}
        disabled={!isUnlocked}
        style={{
          width: '100%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '10px 12px',
          border: 'none',
          background: 'transparent',
          cursor: isUnlocked ? 'pointer' : 'default',
          color: 'var(--text-primary)',
          fontSize: '0.82rem',
          fontFamily: 'var(--font-body)',
          textAlign: 'left',
          gap: 8,
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flex: 1 }}>
          <span style={{ fontSize: '1rem' }}>{config.icon}</span>
          <div style={{ flex: 1 }}>
            <div style={{ fontWeight: 500, marginBottom: 2 }}>{config.label}</div>
            <div style={{ fontSize: '0.68rem', color: 'var(--text-tertiary)' }}>
              {config.description}
            </div>
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          {isUnlocked ? (
            <>
              <Unlock size={14} strokeWidth={1.6} color="var(--success)" />
              <span style={{ fontSize: '0.68rem', color: 'var(--success)', fontWeight: 500 }}>
                已解锁
              </span>
            </>
          ) : (
            <>
              <Lock size={14} strokeWidth={1.6} color="var(--text-tertiary)" />
              <span style={{ fontSize: '0.68rem', color: 'var(--text-tertiary)' }}>
                {cost} 点
              </span>
            </>
          )}
          {isUnlocked && (
            expanded ? <ChevronRight size={14} strokeWidth={1.6} style={{ transform: 'rotate(90deg)' }} />
                     : <ChevronRight size={14} strokeWidth={1.6} />
          )}
        </div>
      </button>

      {/* 未解锁状态：显示解锁按钮 */}
      {!isUnlocked && (
        <div style={{ padding: '0 12px 10px' }}>
          <button
            onClick={handleUnlock}
            disabled={!canAfford}
            style={{
              width: '100%',
              padding: '6px 12px',
              border: 'none',
              borderRadius: 'var(--radius-sm)',
              background: canAfford ? 'var(--accent)' : 'var(--bg-hover)',
              color: canAfford ? '#fff' : 'var(--text-tertiary)',
              fontSize: '0.72rem',
              cursor: canAfford ? 'pointer' : 'not-allowed',
              transition: 'all 200ms ease',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 4,
            }}
          >
            <Lightbulb size={12} strokeWidth={1.6} />
            <span>消耗 {cost} 点解锁</span>
          </button>
        </div>
      )}

      {/* 已解锁状态：显示内容 */}
      {isUnlocked && expanded && (
        <div style={{
          padding: '0 12px 10px',
          fontSize: '0.78rem',
          color: 'var(--text-secondary)',
          lineHeight: 1.6,
        }}>
          <div style={{
            padding: '8px',
            background: 'var(--bg-secondary)',
            borderRadius: 'var(--radius-sm)',
            borderLeft: '3px solid var(--accent)',
          }}>
            {level === 'L1' && (
              <p style={{ margin: 0 }}>
                这个症候通常与<strong>叙事节奏</strong>和<strong>信息密度</strong>有关。
                思考一下：你的文字是否在关键情节处给了足够的篇幅？是否在过渡段落过于冗长？
              </p>
            )}
            {level === 'L2' && (
              <div>
                <p style={{ margin: '0 0 6px' }}>具体改进策略：</p>
                <ul style={{ margin: 0, paddingLeft: 18 }}>
                  <li>识别场景转折点，在这些位置增加细节描写</li>
                  <li>压缩过渡性叙述，用对话或动作替代说明</li>
                  <li>检查每个段落是否推动情节或揭示角色</li>
                </ul>
              </div>
            )}
            {level === 'L3' && (
              <div>
                <p style={{ margin: '0 0 6px', fontWeight: 500 }}>参考范例：</p>
                <blockquote style={{
                  margin: '4px 0',
                  padding: '8px',
                  borderLeft: '2px solid var(--accent)',
                  background: 'var(--bg-card)',
                  fontSize: '0.75rem',
                  fontStyle: 'italic',
                }}>
                  "她推开门，看见桌上的信。信封没有封口，信纸露出一角。
                  她走过去，手指悬在信纸上方——然后缩了回来。
                  有些真相，不知道比知道更好。"
                </blockquote>
                <p style={{ margin: '6px 0 0', fontSize: '0.72rem', color: 'var(--text-tertiary)' }}>
                  注意：通过动作和犹豫传达心理，而非直接说明"她害怕知道真相"。
                </p>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

/** 分级提示面板 */
export const HintPanel: React.FC = () => {
  const { points } = useHintStore();

  return (
    <div style={{
      padding: '12px',
      background: 'var(--bg-card)',
      borderRadius: 'var(--radius-md)',
      border: '1px solid var(--border)',
    }}>
      {/* 标题和点数显示 */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        marginBottom: 12,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <Lightbulb size={16} strokeWidth={1.8} color="var(--accent)" />
          <span style={{ fontWeight: 600, fontSize: '0.85rem', color: 'var(--text-primary)' }}>
            分级提示
          </span>
        </div>
        <div style={{
          padding: '4px 10px',
          background: points > 0 ? 'var(--accent-subtle)' : 'var(--bg-secondary)',
          borderRadius: 'var(--radius-full)',
          fontSize: '0.72rem',
          fontWeight: 500,
          color: points > 0 ? 'var(--accent)' : 'var(--text-tertiary)',
        }}>
          {points} / 3 点
        </div>
      </div>

      {/* 提示级别列表 */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <HintLevelCard level="L1" />
        <HintLevelCard level="L2" />
        <HintLevelCard level="L3" />
      </div>

      {/* 底部说明 */}
      <div style={{
        marginTop: 12,
        padding: '8px',
        background: 'var(--bg-secondary)',
        borderRadius: 'var(--radius-sm)',
        fontSize: '0.68rem',
        color: 'var(--text-tertiary)',
        lineHeight: 1.5,
      }}>
        💡 提示点数会在新的诊断周期开始时重置。每级提示消耗不同点数，请根据需要选择解锁。
      </div>
    </div>
  );
};
