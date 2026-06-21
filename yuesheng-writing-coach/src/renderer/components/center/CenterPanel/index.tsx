import React, { useCallback, useEffect } from 'react';
import { useSessionStore } from '../../../stores/session.store';
import { useChatStore } from '../../../stores/chat.store';
import { useTeachingStateStore } from '../../../stores/teaching-state.store';
import { useRightToolsStore } from '../../../stores/right-tools.store';
import { useUiStore } from '../../../stores/ui.store';
import { Footer } from '../Footer';
import { ChatMessages } from '../ChatMessages';
import styles from './index.module.css';

interface CenterPanelProps {
  collapsedLeft: boolean;
  setCollapsedLeft: (v: boolean) => void;
}

const SUBPHASE_LABELS: Record<string, string> = {
  S1: '待诊断',
  S2: '诊断中',
  S3: '待训练',
  S4: '训练中',
  S5: '待回顾',
  S6: '回顾中',
  S7: '已完成',
};

// 讨论要点预览数据（与 HTML MOCK_PREVIEW_POINTS 一致）
const MOCK_PREVIEW_POINTS = [
  { id: 'n1', label: '主角设定', content: '陈远，17岁，普通山村少年，性格倔强不服输，核心驱动力是"不信命"。母亲临终前留下一封神秘信件。' },
  { id: 'n2', label: '世界观基调', content: '修仙世界，境界体系：练气→筑基→金丹→元婴→化神→大乘→渡劫。宗门：凌霄殿统领五堂。' },
  { id: 'n3', label: '开篇方案', content: '以绝壁路登山作为开篇意象，用行动展示主角性格，替代背景旁白式交代世界观。' },
  { id: 'n4', label: '待定事项', content: '师尊沈渊的身世秘密（莲花印记）何时揭示，需在第5章前埋好伏笔。' },
];

export const CenterPanel: React.FC<CenterPanelProps> = ({
  collapsedLeft, setCollapsedLeft,
}) => {
  const { sessions, currentSessionId, loadSessions, switchSession } = useSessionStore();
  const { messages } = useChatStore();
  const { currentState } = useTeachingStateStore();
  const { openTool } = useRightToolsStore();
  const { trainingContexts } = useUiStore();

  const [templatePreviewVisible, setTemplatePreviewVisible] = React.useState(false);

  useEffect(() => {
    loadSessions();
  }, [loadSessions]);

  // Auto-select first session
  useEffect(() => {
    if (!currentSessionId && sessions.length > 0) {
      switchSession(sessions[0].id);
    }
  }, [sessions, currentSessionId, switchSession]);

  // 切换会话时加载消息
  useEffect(() => {
    if (currentSessionId) {
      (async () => {
        const msgs = await useSessionStore.getState().loadMessages(currentSessionId);
        useChatStore.getState().setMessages(msgs as import('../../../shared/types').ChatMessage[]);
      })();
    } else {
      useChatStore.getState().setMessages([]);
    }
  }, [currentSessionId]);

  const currentSession = sessions.find(s => s.id === currentSessionId);
  const isTrain = currentSession?.title.startsWith('训练:') ?? false;
  const trainingCtx = currentSessionId ? trainingContexts[currentSessionId] : undefined;

  // Status text
  const statusText = currentState?.currentSubphase
    ? (SUBPHASE_LABELS[currentState.currentSubphase] ?? currentState.currentSubphase)
    : '教学中';

  const handleNewSession = async () => {
    const { createSession } = useSessionStore.getState();
    const s = await createSession();
    if (s) switchSession(s.id);
  };

  // [模板] 按钮
  const handleToggleTemplate = useCallback(() => {
    setTemplatePreviewVisible(prev => !prev);
  }, []);

  // 记录到教学笔记
  const handleRecordToTeachingNotes = useCallback(() => {
    setTemplatePreviewVisible(false);
    // 打开教学笔记工具
    openTool('training');
  }, [openTool]);

  const previewPanel = templatePreviewVisible ? (
    <div className={styles.templatePreview}>
      <div className={styles.templatePreviewInner}>
        <div className={styles.templatePreviewHdr}>
          <span className={styles.templatePreviewDot} />
          <span className={styles.templatePreviewTitle}>讨论要点汇总</span>
          <span className={styles.templatePreviewTag}>预览</span>
        </div>
        <div>
          {MOCK_PREVIEW_POINTS.map(p => (
            <div key={p.id} className={styles.templateItem}>
              <span className={styles.templateItemArrow}>↘</span>
              <div>
                <span className={styles.templateItemLabel}>{p.label}</span>
                <p className={styles.templateItemContent}>{p.content}</p>
              </div>
            </div>
          ))}
        </div>
        <div className={styles.templatePreviewActions}>
          <button
            className={styles.templateCancelBtn}
            onClick={() => setTemplatePreviewVisible(false)}
          >取消</button>
          <button
            className={styles.templateRecordBtn}
            onClick={handleRecordToTeachingNotes}
          >记录到教学笔记</button>
        </div>
      </div>
    </div>
  ) : null;

  return (
    <>
      {/* Header */}
      <header className={styles.header}>
        <div className={styles.headerLeft}>
          {collapsedLeft && (
            <div className={styles.collapsedBar}>
              <div className="w-[26px] h-[26px] rounded bg-[#7A6040] text-white flex items-center justify-center text-[13px] font-bold font-serif flex-shrink-0">月</div>
              <button className={styles.expandBtn} onClick={() => setCollapsedLeft(false)} title="展开">☰</button>
            </div>
          )}
          <button className={styles.projectBtn}>
            <span className={styles.projectBtnArrow}>▼</span>
            <span>我的第一本小说</span>
            <span className={styles.projectBtnArrow}>▾</span>
          </button>
          <span className={styles.statusBadge}>
            <span className={styles.statusDot} />
            <span>{statusText}</span>
          </span>
          {currentSession && (
            <span className={styles.sessionBadge}>{currentSession.title}</span>
          )}
          {isTrain && (
            <span className={styles.trainBadge}>
              <span className={styles.trainBadgeDot} />训练
            </span>
          )}
        </div>
        <div className={styles.headerActions}>
          <button className={styles.headerBtn} onClick={handleNewSession} title="新建会话">＋</button>
          <button className={styles.headerBtn} onClick={() => openTool('__settings__')} title="设置">⚙</button>
        </div>
      </header>

      {/* Chat Area */}
      <div className={styles.chatArea}>
        {!currentSessionId ? (
          <div className={styles.empty}>
            <h2 className={styles.emptyTitle}>开始你的写作之旅</h2>
            <div className={styles.emptyOptions}>
              <button className={styles.emptyOption} onClick={() => handleNewSession()}>
                <span className={styles.emptyOptionIcon}>📝</span>
                <div>
                  <div className={styles.emptyOptionLabel}>我有作品</div>
                  <div className={styles.emptyOptionHint}>直接进入聊天，我会帮你分析</div>
                </div>
              </button>
              <button className={styles.emptyOption} onClick={() => handleNewSession()}>
                <span className={styles.emptyOptionIcon}>🌱</span>
                <div>
                  <div className={styles.emptyOptionLabel}>从头学习</div>
                  <div className={styles.emptyOptionHint}>我引导你搭建世界观和人物</div>
                </div>
              </button>
              <button className={styles.emptyOption} onClick={() => handleNewSession()}>
                <span className={styles.emptyOptionIcon}>💬</span>
                <div>
                  <div className={styles.emptyOptionLabel}>先聊聊</div>
                  <div className={styles.emptyOptionHint}>正常聊天，我在对话中自然引导</div>
                </div>
              </button>
            </div>
          </div>
        ) : messages.length === 0 ? (
          <div className={styles.empty}>
            <div className={styles.emptyIcon}>✍️</div>
            <div>开始一段新的教学对话</div>
          </div>
        ) : (
          <>
            <ChatMessages messages={messages} trainingCtx={trainingCtx} />
            {previewPanel}
          </>
        )}
      </div>

      {/* Footer */}
      <Footer chatSessionId={currentSessionId} onToggleTemplate={handleToggleTemplate} />
    </>
  );
};
