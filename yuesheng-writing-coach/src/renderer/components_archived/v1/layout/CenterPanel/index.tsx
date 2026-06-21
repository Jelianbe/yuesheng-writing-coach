/**
 * CenterPanel — 中间栏容器组件
 *
 * V6.2 Shell 主对话区域：
 * - 顶部：当前会话标题 + [+][⚙] 操作按钮
 * - 中部：ChatMessages 消息列表
 * - 底部：ChatInput + AttitudeLights
 * - 训练会话时显示训练信息横幅
 *
 * 用法:
 * ```tsx
 * <CenterPanel />
 * ```
 */
import { useEffect, useCallback } from 'react';
import { useSessionStore } from '@/stores/session.store';
import { useChatStore } from '@/stores/chat.store';
import { useDrawerStore } from '@/stores/drawer.store';
import { useUiStore } from '@/stores/ui.store';
import type { TrainingContext } from '@/stores/ui.store';
import { ChatMessages } from '@/components/center/ChatMessages';
import { ChatInput } from '@/components/center/ChatInput';
import { AttitudeLights } from '@/components/center/AttitudeLights';
import styles from './index.module.css';

/** 难度档位 → 中文显示文本和样式类名 */
const DIFFICULTY_MAP: Record<TrainingContext['difficulty'], { label: string; className: string }> = {
  beginner: { label: '入门', className: styles.difficultyBeginner },
  intermediate: { label: '进阶', className: styles.difficultyIntermediate },
  advanced: { label: '高级', className: styles.difficultyAdvanced },
};

/**
 * 训练信息横幅
 */
function TrainingBanner({ ctx }: { ctx: TrainingContext }): JSX.Element {
  const diff = DIFFICULTY_MAP[ctx.difficulty];

  const diffClass = [styles.trainingBadge, styles.badgeDifficulty, diff.className]
    .filter(Boolean)
    .join(' ');

  return (
    <div className={styles.trainingBanner} role="banner" aria-label="训练信息">
      <span className={`${styles.trainingBadge} ${styles.badgeTechnique}`}>
        {ctx.coreName || ctx.techniqueName}
      </span>
      <span className={`${styles.trainingBadge} ${styles.badgeCategory}`}>
        {ctx.category}
      </span>
      <span className={diffClass}>
        {diff.label}
      </span>
      <span className={styles.trainingDesc}>
        {ctx.description}
      </span>
    </div>
  );
}

/**
 * CenterPanel 中间栏容器
 */
export function CenterPanel(): JSX.Element {
  // ── Session 状态 ──
  const sessions = useSessionStore((s) => s.sessions);
  const currentSessionId = useSessionStore((s) => s.currentSessionId);
  const loadMessages = useSessionStore((s) => s.loadMessages);

  // ── Chat 状态 ──
  const messages = useChatStore((s) => s.messages);
  const isLoading = useChatStore((s) => s.isLoading);
  const error = useChatStore((s) => s.error);
  const sendMessage = useChatStore((s) => s.sendMessage);
  const setMessages = useChatStore((s) => s.setMessages);

  // ── UI 状态 ──
  const attitude = useUiStore((s) => s.attitude);
  const trainingContexts = useUiStore((s) => s.trainingContexts);

  // 当前会话信息
  const currentSession = sessions.find((s) => s.id === currentSessionId);
  const sessionTitle = currentSession?.title ?? '';
  const trainingCtx = currentSessionId ? trainingContexts[currentSessionId] : undefined;

  // 当 currentSessionId 变化时，加载该会话的消息
  useEffect(() => {
    if (!currentSessionId) {
      setMessages([]);
      return;
    }

    let cancelled = false;

    loadMessages(currentSessionId).then((msgs) => {
      if (!cancelled && msgs.length > 0) {
        setMessages(msgs as Parameters<typeof setMessages>[0]);
      }
    });

    return () => {
      cancelled = true;
    };
  }, [currentSessionId, loadMessages, setMessages]);

  // 发送消息
  const handleSend = useCallback(
    (text: string) => {
      if (!currentSessionId) return;

      // 构建 studentContext JSON（如果存在训练上下文）
      const studentContext = trainingCtx
        ? JSON.stringify({
            techniqueName: trainingCtx.techniqueName,
            coreName: trainingCtx.coreName,
            difficulty: trainingCtx.difficulty,
            category: trainingCtx.category,
            description: trainingCtx.description,
          })
        : '';

      sendMessage(text, {
        sessionId: currentSessionId,
        attitudeLevel: attitude,
        studentContext,
      });
    },
    [currentSessionId, attitude, trainingCtx, sendMessage],
  );

  // ── 无会话空状态 ──
  if (!currentSessionId || !currentSession) {
    return (
      <div className={styles.panel}>
        <div className={styles.emptySession} role="status">
          <span className={styles.emptyIcon} aria-hidden="true">&#9998;</span>
          <span>选择或创建一个会话开始写作练习</span>
        </div>
      </div>
    );
  }

  return (
    <div className={styles.panel}>
      {/* 顶部标题 */}
      <div className={styles.header}>
        <h1 className={styles.title}>{sessionTitle}</h1>
        <div className={styles.headerActions}>
          <button
            className={styles.headerBtn}
            type="button"
            aria-label="新建会话"
            title="新建会话"
            onClick={() => {
              const store = useSessionStore.getState();
              store.createSession();
            }}
          >
            +
          </button>
          <button
            className={styles.headerBtn}
            type="button"
            aria-label="设置"
            title="设置"
            onClick={() => {
              const drawerStore = useDrawerStore.getState();
              drawerStore.openPanel('__settings__');
            }}
          >
            &#9881;
          </button>
        </div>
      </div>

      {/* 训练信息横幅 */}
      {trainingCtx && <TrainingBanner ctx={trainingCtx} />}

      {/* 消息列表 */}
      <div className={styles.messagesArea}>
        <ChatMessages
          messages={messages}
          isLoading={isLoading}
          error={error}
        />
      </div>

      {/* 底部栏 */}
      <div className={styles.bottomBar}>
        <div className={styles.inputRow}>
          <ChatInput onSubmit={handleSend} isLoading={isLoading} />
        </div>
        <div className={styles.attitudeRow}>
          <AttitudeLights />
        </div>
      </div>
    </div>
  );
}
