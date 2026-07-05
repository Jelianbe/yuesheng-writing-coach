/**
 * PageStackRouter — 移动端页面栈路由
 *
 * 架构：
 * - 桌面端 (>=431px): 居中显示手机外观(圆角 + 边框 + 阴影)
 * - 移动端 (<=430px): 铺满全屏,纯手机模式
 * - 顶部 24px 模拟状态栏(9:41 + 信号/电量)
 * - TabBar 3 tab:书架 | 对话 | 应用
 * - 子页面(project-space / chat / growth-report / training-plan) push 进入,TabBar 隐藏
 */

import React from 'react';
import { Battery, Signal, Wifi } from 'lucide-react';
import { usePageStackStore } from '../stores/page-stack.store';
import { TabBar } from '../components/navigation/TabBar';
import { BookshelfPage } from '../pages/BookshelfPage';
import { ConversationsPage } from '../pages/ConversationsPage';
import { AppsPage } from '../pages/AppsPage';
import { ProjectSpacePage } from '../pages/ProjectSpacePage';
import { ChatPage } from '../pages/ChatPage';
import { GrowthReportPage } from '../pages/GrowthReportPage';
import { TrainingPlanPage } from '../pages/TrainingPlanPage';
import styles from './PageStackRouter.module.css';

const PAGE_MAP: Record<string, React.FC<{ params?: Record<string, string> }>> = {
  bookshelf: BookshelfPage,
  conversations: ConversationsPage,
  apps: AppsPage,
  'project-space': ProjectSpacePage,
  chat: ChatPage,
  'growth-report': GrowthReportPage,
  'training-plan': TrainingPlanPage,
};

const StatusBar: React.FC = () => (
  <div className={styles.statusBar}>
    <span className={styles.statusTime}>9:41</span>
    <div className={styles.statusIcons}>
      <Signal size={12} strokeWidth={2} />
      <Wifi size={12} strokeWidth={2} />
      <Battery size={14} strokeWidth={1.5} />
    </div>
  </div>
);

const HomeIndicator: React.FC = () => (
  <div className={styles.homeIndicator} aria-hidden>
    <div className={styles.homeBar} />
  </div>
);

export const PageStackRouter: React.FC = () => {
  const stack = usePageStackStore(s => s.stack);
  const tabBarVisible = usePageStackStore(s => s.tabBarVisible);
  const current = stack[stack.length - 1];
  const PageComponent = PAGE_MAP[current.name];

  if (!PageComponent) {
    return <div style={{ padding: 20, color: 'var(--text-tertiary)' }}>页面未找到</div>;
  }

  return (
    <div className={styles.outer}>
      <div className={styles.phone}>
        <StatusBar />
        <div className={styles.content}>
          <PageComponent params={current.params} />
        </div>
        {tabBarVisible && (
          <>
            <TabBar />
            <HomeIndicator />
          </>
        )}
      </div>
    </div>
  );
};
